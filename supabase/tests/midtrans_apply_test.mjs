import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
import {createContext,SourceTextModule,SyntheticModule} from 'node:vm';
import {webcrypto,createHash} from 'node:crypto';
const context=createContext({crypto:webcrypto,TextEncoder,Error});
const mod=new SourceTextModule(stripTypeScriptTypes(await readFile(new URL('../functions/_shared/midtrans.ts',import.meta.url),'utf8')),{context});
await mod.link(()=>new SyntheticModule(['createClient'],function(){this.setExport('createClient',()=>{throw Error('Unexpected client construction');});},{context}));
await mod.evaluate();
const {applyMidtransStatus,verifyNotificationSignature}=mod.namespace;
function admin(status='pending',failure=null){
  const calls=[];
  const query={select(){return this;},eq(){return this;},async maybeSingle(){return {data:{amount:170000,status},error:null};}};
  return {calls,from:()=>query,rpc:async(name,args)=>{calls.push({name,args});return {data:status==='paid'?'paid':args.p_status,error:failure};}};
}
const receipt={order_id:'test-order',gross_amount:'170000.00',transaction_status:'settlement',transaction_id:'tx',payment_type:'DANA'};
test('settlement and uppercase capture ACCEPT call atomic database RPC',async()=>{
  for(const change of [{},{transaction_status:'CAPTURE',fraud_status:'ACCEPT'}]){
    const db=admin();
    assert.equal(await applyMidtransStatus(db,{...receipt,...change}),'paid');
    assert.equal(db.calls[0].name,'apply_verified_midtrans_status');
    assert.equal(db.calls[0].args.p_payment_type,'dana');
    assert.equal(db.calls[0].args.p_amount,170000);
  }
});
test('fractional mismatch, missing amount and wrong currency never reach RPC',async()=>{
  for(const change of [{gross_amount:'170000.4'},{gross_amount:undefined},{currency:'USD'}]){
    const db=admin();
    await assert.rejects(applyMidtransStatus(db,{...receipt,...change}));
    assert.equal(db.calls.length,0);
  }
});
test('paid payment retries still invoke atomic invoice reconciliation',async()=>{
  const db=admin('paid');
  assert.equal(await applyMidtransStatus(db,receipt),'paid');
  assert.equal(db.calls.length,1);
});
test('database failures propagate for webhook retry',async()=>{
  await assert.rejects(applyMidtransStatus(admin('pending',Error('DB error')),receipt),/DB error/);
});
test('capture with challenge cannot mark invoice paid',async()=>{
  const db=admin();
  assert.equal(await applyMidtransStatus(db,{...receipt,transaction_status:'capture',fraud_status:'challenge'}),'pending');
  assert.equal(db.calls.length,0);
});
test('signature verifier accepts exact SHA512 and rejects tampering',async()=>{
  const signature=createHash('sha512').update('test-order200170000.00test-key').digest('hex');
  assert.equal(await verifyNotificationSignature('test-order','200','170000.00',signature,'test-key'),true);
  assert.equal(await verifyNotificationSignature('test-order','200','170001.00',signature,'test-key'),false);
});
