import {accessToken,classifyFcmResponse,notificationPayload,parseServiceAccount,type PushJob} from '../_shared/fcm.ts';

const json=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json'}});
async function rpc<T>(name:string,params:unknown):Promise<T> {
  const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const response=await fetch(`${Deno.env.get('SUPABASE_URL')}/rest/v1/rpc/${name}`,{
    method:'POST',headers:{apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'},
    body:JSON.stringify(params),signal:AbortSignal.timeout(10000),
  });
  if(!response.ok) throw new Error(`Push database operation failed: ${name}`);
  const body=await response.text();
  return (body?JSON.parse(body):null) as T;
}

Deno.serve(async(request:Request)=>{
  if(request.method!=='POST') return json(405,{error:'Method not allowed'});
  const secret=request.headers.get('x-push-secret')??'';
  if(!/^[a-f0-9]{64}$/.test(secret)) return json(401,{error:'Unauthorized'});
  try {
    if(!await rpc<boolean>('authorize_push_worker',{p_secret:secret})) return json(401,{error:'Unauthorized'});
    const raw=Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
    if(!raw) return json(503,{error:'Firebase push is not configured'});
    const account=parseServiceAccount(raw);
    // Authenticate before claiming jobs, so configuration errors do not consume retries.
    const bearer=await accessToken(account);
    const deadline=Date.now()+40000;
    let sent=0,failed=0,retry=0,removed=0;
    for(let batch=0;batch<5 && Date.now()<deadline;batch++) {
      const jobs=await rpc<PushJob[]>('claim_service_push',{p_limit:40});
      if(!jobs.length) break;
      for(let offset=0;offset<jobs.length;offset+=10) {
        await Promise.all(jobs.slice(offset,offset+10).map(async(job)=>{
          let outcome:{result:'sent'|'retry'|'failed'|'invalid_token';code:string|null};
          try {
            const response=await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,{
              method:'POST',headers:{Authorization:`Bearer ${bearer}`,'Content-Type':'application/json'},
              body:JSON.stringify(notificationPayload(job)),signal:AbortSignal.timeout(8000),
            });
            let data:unknown=null;try{data=await response.json();}catch{/* malformed gateway response */}
            outcome=classifyFcmResponse(response.status,data);
          } catch { outcome={result:'retry',code:'NETWORK_ERROR'}; }
          await rpc('finish_service_push',{p_id:job.job_id,p_lease:job.lease_id,p_result:outcome.result,p_code:outcome.code});
          if(outcome.result==='sent')sent++;
          else if(outcome.result==='retry')retry++;
          else if(outcome.result==='invalid_token')removed++;
          else failed++;
        }));
      }
    }
    return json(200,{accepted_by_fcm:sent,retry,failed,removed});
  } catch {
    // Never emit service keys, OAuth assertions, registration tokens, or upstream bodies.
    return json(503,{error:'Push dispatch unavailable; queued jobs remain retryable'});
  }
});
