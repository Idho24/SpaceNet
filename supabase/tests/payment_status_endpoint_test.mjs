import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { createContext, SourceTextModule, SyntheticModule } from 'node:vm';
import * as statusHelpers from '../functions/_shared/midtrans_status.ts';

// Execute the actual Edge Function with isolated Supabase and HTTP boundaries.
// No credentials, network requests, or database writes are used by these tests.
const source = stripTypeScriptTypes(await readFile(
  new URL('../functions/get-midtrans-payment-status/index.ts', import.meta.url), 'utf8',
));
const basePayment = {
  order_id: 'SPN-test', invoice_id: 'INV-test', user_id: 'user-test',
  amount: 170000, status: 'pending', transaction_id: null, payment_type: null,
  redirect_url: 'https://app.sandbox.midtrans.com/snap/v2/vtweb/test',
  updated_at: '2026-11-17T10:00:00Z',
};
const missing = { status_code: '404', status_message: 'The requested resource is not found' };
const settlement = {
  status_code: '200', order_id: 'SPN-test', gross_amount: '170000.00',
  transaction_status: 'settlement', transaction_id: 'tx-1', payment_type: 'qris',
};

async function invoke({ payment = basePayment, responses = [], user = { id: 'user-test' }, method = 'POST', body = { orderId: 'SPN-test' } } = {}) {
  let handler;
  const calls = { fetch: [], headers: [], apply: [], filters: [] };
  const query = {
    select() { return this; },
    eq(...args) { calls.filters.push(args); return this; },
    async maybeSingle() { return { data: payment, error: null }; },
    async single() { return { data: { transaction_id: 'tx-1', payment_type: 'qris', updated_at: basePayment.updated_at }, error: null }; },
  };
  const shared = {
    authenticatedUser: async () => user,
    createAdminClient: () => ({ from: () => query }),
    corsHeaders: { 'Access-Control-Allow-Origin': '*' },
    isRecord: value => value !== null && typeof value === 'object' && !Array.isArray(value),
    jsonResponse: (status, value) => new Response(JSON.stringify(value), { status }),
    midtransAuthorization: () => 'Basic test-only',
    requiredEnv: () => 'test-only',
    sandboxApiUrl: 'https://api.sandbox.midtrans.com',
    applyMidtransStatus: async (_admin, notification) => {
      calls.apply.push(notification);
      return notification.transaction_status === 'settlement' ? 'paid' : 'pending';
    },
  };
  const context = createContext({
    Request, Response, AbortSignal, Error, console: { warn() {}, error() {} },
    Deno: { serve: callback => { handler = callback; } },
    fetch: async (url, options) => {
      calls.headers.push(options.headers);
      calls.fetch.push(url);
      const reply = responses[calls.fetch.length - 1];
      assert.ok(reply, 'Unexpected Midtrans lookup');
      return new Response(JSON.stringify(reply.body), { status: reply.status });
    },
  });
  const module = new SourceTextModule(source, { context });
  await module.link(specifier => {
    const values = specifier.endsWith('/midtrans_status.ts') ? statusHelpers : shared;
    return new SyntheticModule(Object.keys(values), function () {
      for (const [name, value] of Object.entries(values)) this.setExport(name, value);
    }, { context });
  });
  await module.evaluate();
  const response = await handler(new Request('https://test.local/status', {
    method, ...(method === 'POST' ? { body: JSON.stringify(body) } : {}),
  }));
  return { status: response.status, body: await response.json(), calls };
}

for (const status of [200, 404]) {
  test(`endpoint returns pending, not 502, for unstarted Snap (HTTP ${status})`, async () => {
    const result = await invoke({ responses: [{ status, body: missing }] });
    assert.equal(result.status, 200);
    assert.equal(result.body.status, 'pending');
    assert.match(result.body.statusMessage, /jangan bayar ulang/);
    assert.equal(result.calls.apply.length, 0, 'Must not mutate invoice or payment');
    assert.deepEqual(result.calls.filters, [['order_id', 'SPN-test'], ['user_id', 'user-test']]);
  });
}

test('endpoint applies verified settlement and returns receipt metadata', async () => {
  const result = await invoke({ responses: [{ status: 200, body: settlement }] });
  assert.equal(result.status, 200);
  assert.equal(result.body.status, 'paid');
  assert.equal(result.body.transactionId, 'tx-1');
  assert.equal(result.calls.apply.length, 1);
});

test('endpoint retries missing transaction ID by order ID', async () => {
  const result = await invoke({
    payment: { ...basePayment, transaction_id: 'old-tx' },
    responses: [{ status: 404, body: missing }, { status: 200, body: settlement }],
  });
  assert.equal(result.status, 200);
  assert.match(result.calls.fetch[0], /old-tx\/status$/);
  assert.match(result.calls.fetch[1], /SPN-test\/status$/);
  assert.equal(result.body.status, 'paid');
});

test('endpoint rejects mismatched settlement without applying it', async () => {
  for (const changes of [{ order_id: 'wrong' }, { gross_amount: undefined }, { gross_amount: '170000.4' }]) {
    const result = await invoke({ responses: [{ status: 200, body: { ...settlement, ...changes } }] });
    assert.equal(result.status, 502);
    assert.equal(result.calls.apply.length, 0);
  }
});

test('authentication, ownership, and request validation stop before Midtrans', async () => {
  for (const [options, status] of [[{ user: null }, 401], [{ payment: null }, 404], [{ body: {} }, 400], [{ method: 'GET' }, 405]]) {
    const result = await invoke(options);
    assert.equal(result.status, status);
    assert.equal(result.calls.fetch.length, 0);
    assert.equal(result.calls.apply.length, 0);
  }
});

test('already-paid orders do not issue another Midtrans request', async () => {
  const result = await invoke({ payment: { ...basePayment, status: 'paid' } });
  assert.equal(result.body.status, 'paid');
  assert.equal(result.calls.fetch.length, 0);
});

test('endpoint keeps access failures visible', async () => {
  const result = await invoke({ responses: [{ status: 401, body: { status_code: '401' } }] });
  assert.equal(result.status, 502);
  assert.match(result.body.error, /Akses status Midtrans ditolak/);
  assert.equal(result.calls.apply.length, 0);
});

test('DANA uses transaction ID and SNAP_API header', async () => {
  const result = await invoke({
    payment: { ...basePayment, payment_type: 'dana', transaction_id: 'tx-1' },
    responses: [{ status: 200, body: { ...settlement, payment_type: 'dana' } }],
  });
  assert.equal(result.body.status, 'paid');
  assert.match(result.calls.fetch[0], /tx-1\/status$/);
  assert.equal(result.calls.headers[0]['transaction-source'], 'SNAP_API');
});
test('missing DANA transaction does not fall back to unsupported order lookup', async () => {
  const result = await invoke({
    payment: { ...basePayment, payment_type: 'dana', transaction_id: 'tx-1' },
    responses: [{ status: 404, body: missing }],
  });
  assert.equal(result.status, 502);
  assert.equal(result.calls.fetch.length, 1);
  assert.equal(result.calls.apply.length, 0);
});
