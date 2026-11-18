import {test} from 'node:test';
import assert from 'node:assert/strict';
import {paymentReturnUrl} from '../functions/_shared/payment_return.ts';
test('localhost callback points to the current app with an explicit order in query and hash',()=>{
  const result=new URL(paymentReturnUrl('http://localhost:56136/','http://localhost:56136','SPN-123'));
  assert.equal(result.origin,'http://localhost:56136');
  assert.equal(result.searchParams.get('order_id'),'SPN-123');
  assert.equal(result.hash,'#/payment-result?order_id=SPN-123');
});
test('HTTPS callback preserves a deployed app subpath',()=>{
  assert.equal(new URL(paymentReturnUrl('https://app.example.id/customer/','https://app.example.id','SPN-123')).pathname,'/customer/');
});
test('callback rejects a foreign origin, insecure public HTTP and credentials',()=>{
  for(const url of ['https://other.example/','http://app.example.id/','https://user:pass@app.example.id/','javascript:alert(1)','https://app.example.id/?secret=value']){
    assert.throws(()=>paymentReturnUrl(url,'https://app.example.id','SPN-123'));
  }
});
test('missing native callback remains optional and cannot imply paid',()=>{
  assert.equal(paymentReturnUrl(undefined,null,'SPN-123'),null);
});
