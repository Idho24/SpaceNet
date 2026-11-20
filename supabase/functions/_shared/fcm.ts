export interface ServiceAccount { project_id: string; client_email: string; private_key: string }
export interface PushJob { job_id:string; lease_id:string; token:string; announcement_id:string; version:number; title:string; message:string; area:string; status:string }
export function parseServiceAccount(raw:string):ServiceAccount {
  const a=JSON.parse(raw);
  if(!a || typeof a.project_id!=='string' || !/^[a-z][a-z0-9-]{4,62}$/.test(a.project_id)
    || typeof a.client_email!=='string' || !a.client_email.endsWith('.gserviceaccount.com')
    || typeof a.private_key!=='string' || !a.private_key.includes('BEGIN PRIVATE KEY')) throw new Error('Invalid Firebase service account');
  return a;
}
const encoder=new TextEncoder();
function b64url(bytes:Uint8Array):string {
  return btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
}
export async function serviceAccountAssertion(account:ServiceAccount,nowSeconds=Math.floor(Date.now()/1000)):Promise<string> {
  const pem=account.private_key.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g,'');
  const key=await crypto.subtle.importKey('pkcs8',Uint8Array.from(atob(pem),c=>c.charCodeAt(0)),
    {name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
  const header=b64url(encoder.encode(JSON.stringify({alg:'RS256',typ:'JWT'})));
  const claims=b64url(encoder.encode(JSON.stringify({iss:account.client_email,
    scope:'https://www.googleapis.com/auth/firebase.messaging',aud:'https://oauth2.googleapis.com/token',
    iat:nowSeconds,exp:nowSeconds+3600})));
  const input=`${header}.${claims}`;
  const signature=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,encoder.encode(input));
  return `${input}.${b64url(new Uint8Array(signature))}`;
}
let cached:{email:string;token:string;until:number}|undefined;
export async function accessToken(account:ServiceAccount,fetcher:typeof fetch=fetch):Promise<string> {
  if(cached?.email===account.client_email && cached.until>Date.now()) return cached.token;
  const assertion=await serviceAccountAssertion(account);
  const response=await fetcher('https://oauth2.googleapis.com/token',{method:'POST',
    headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion}),
    signal:AbortSignal.timeout(10000)});
  const data=await response.json();
  if(!response.ok || typeof data.access_token!=='string') throw new Error('Firebase OAuth authorization failed');
  cached={email:account.client_email,token:data.access_token,until:Date.now()+(Math.min(Number(data.expires_in)||3600,3600)-60)*1000};
  return cached.token;
}
export function notificationPayload(job:PushJob) {
  const body=Array.from(`${job.area}: ${job.message}`).slice(0,240).join('');
  return {message:{token:job.token,
    notification:{title:job.status==='resolved'?`Selesai: ${job.title}`:job.title,body},
    data:{type:'service_announcement',announcement_id:job.announcement_id,version:String(job.version),status:job.status},
    android:{priority:'HIGH',ttl:'3600s',collapse_key:job.announcement_id,
      notification:{channel_id:'spacenet_service',icon:'ic_service_notification',sound:'default',tag:job.announcement_id}},
  }};
}
export function classifyFcmResponse(status:number,data:any):{result:'sent'|'retry'|'failed'|'invalid_token';code:string|null} {
  if(status>=200 && status<300 && typeof data?.name==='string') return {result:'sent',code:null};
  const details=Array.isArray(data?.error?.details)?data.error.details:[];
  if(details.some((item:any)=>item?.['@type']==='type.googleapis.com/google.firebase.fcm.v1.FcmError' && item.errorCode==='UNREGISTERED')) {
    return {result:'invalid_token',code:'UNREGISTERED'};
  }
  const code=typeof data?.error?.status==='string'?data.error.status:`HTTP_${status}`;
  return {result:status===429||status>=500||status===401||status===403||status<300?'retry':'failed',code};
}
