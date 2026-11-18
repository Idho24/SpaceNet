
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { createContext, SourceTextModule, SyntheticModule } from 'node:vm';
import * as helpers from '../functions/_shared/midtrans_status.ts';
const source = stripTypeScriptTypes(await readFile(
  new URL('../functions/midtrans-webhook/index.ts', import.meta.url), 'utf8'));
const payment = {order_id:'order-1', amount:170000, status:'pending', transaction_id:null, payment_type:null};
const callback = {
  order_id:'order-1', status_code:'200', gross_amount:'170000.00',
  transaction_id:'DANA-1', payment_type:'dana', transaction_status:'settlement',
  signature_key:'unverified', currency:'IDR',
};
async function invoke({signed=false, record=payment, body=callback, reply=callback, http=200, networkError=false}={}) {
  let handler;
  const calls={fetch:[], apply:[]};
  const query={select(){return this;},eq(){return this;},async maybeSingle(){return {data:record,error:null};}};
  const shared={
    applyMidtransStatus:async(_admin,n)=>{calls.apply.push(n);return n.transaction_status.toLowerCase()==='settlement'?'paid':'pending';},
    createAdminClient:()=>({from:()=>query}),corsHeaders:{},
    isRecord:v=>!!v&&typeof v==='object'&&!Array.isArray(v),
    jsonResponse:(status,body)=>new Response(JSON.stringify(body),{status}),
    requiredEnv:()=>'test-server-key',
    verifyNotificationSignature:async()=>signed,
  };
  const context=createContext({Request,Response,Error,console:{error(){}},
    Deno:{serve:fn=>{handler=fn;}},
    fetch:async(url,options)=>{
      calls.fetch.push({url,options});
      if(networkError)throw Error('offline');
      return new Response(JSON.stringify(reply),{status:http});
    },
  });
  const mod=new SourceTextModule(source,{context});
  await mod.link(specifier=>{
    const exports=specifier.endsWith('/midtrans_status.ts')?helpers:shared;
    return new SyntheticModule(Object.keys(exports),function(){
      for(const [k,v] of Object.entries(exports))this.setExport(k,v);
    },{context});
  });
  await mod.evaluate();
  const response=await handler(new Request('https://test.local/webhook',{method:'POST',body:JSON.stringify(body)}));
  return {status:response.status,body:await response.json(),calls};
}
test('valid signature applies notification without extra network request',async()=>{
  const r=await invoke({signed:true});
  assert.equal(r.body.status,'paid');assert.equal(r.calls.fetch.length,0);
});
test('DANA callback with rejected signature is verified through authenticated status API',async()=>{
  const r=await invoke();
  assert.equal(r.body.status,'paid');
  assert.equal(r.calls.fetch[0].options.headers['transaction-source'],'SNAP_API');
  assert.match(r.calls.fetch[0].url,/DANA-1\/status$/);
  assert.equal(r.calls.fetch[0].options.headers.Authorization,'Basic '+btoa('test-server-key:'));
  assert.equal(r.calls.fetch[0].options.redirect,'error');
});
test('forged settlement cannot override authoritative pending status',async()=>{
  const r=await invoke({reply:{...callback,transaction_status:'PENDING'}});
  assert.equal(r.body.status,'pending');
  assert.equal(r.calls.apply[0].transaction_status,'PENDING');
});
test('challenge rejects wrong order, amount, transaction ID, currency, missing status',async()=>{
  for(const change of [{order_id:'another'},{gross_amount:'170000.4'},{transaction_id:'another'},{currency:'USD'},{transaction_status:undefined}]){
    const r=await invoke({reply:{...callback,...change}});
    assert.equal(r.status,401);assert.equal(r.calls.apply.length,0);
  }
});
test('missing or unauthorized Midtrans record cannot mark an invoice paid',async()=>{
  for(const http of [401,403,404]){
    const r=await invoke({http,reply:{status_code:String(http)}});
    assert.equal(r.status,401);assert.equal(r.calls.apply.length,0);
  }
});
test('temporary Midtrans failures request webhook retry without mutation',async()=>{
  for(const options of [{http:503},{http:429},{networkError:true}]){
    const r=await invoke(options);
    assert.equal(r.status,503);assert.equal(r.calls.apply.length,0);
  }
});
test('unknown orders and missing IDs stop before upstream request',async()=>{
  for(const [options,status] of [[{record:null},404],[{body:{...callback,transaction_id:undefined}},401]]){
    const r=await invoke(options);
    assert.equal(r.status,status);assert.equal(r.calls.fetch.length,0);assert.equal(r.calls.apply.length,0);
  }
});
