import { test } from "node:test";
import assert from "node:assert/strict";
import { interpretMidtransStatus } from "../functions/_shared/midtrans_status.ts";

const payment = {
  order_id: "SPN-test", amount: 170000, status: "pending",
  transaction_id: null, payment_type: null,
};
const notFound = { status_code: "404", status_message: "The requested resource is not found" };
const settlement = {
  status_code: "200", order_id: payment.order_id, gross_amount: "170000.00",
  transaction_status: "settlement", currency: "IDR",
};

for (const httpStatus of [200, 404]) {
  test(`Snap before choosing a method stays pending (HTTP ${httpStatus})`, () => {
    assert.deepEqual(interpretMidtransStatus(httpStatus, notFound, payment), {
      awaitingPaymentMethod: true,
    });
  });
}

test("404 after a transaction was started remains an error", () => {
  for (const changes of [{ transaction_id: "tx-1" }, { payment_type: "qris" }, { status: "expired" }]) {
    assert.throws(() => interpretMidtransStatus(200, notFound, { ...payment, ...changes }));
  }
});

test("access, server, malformed, and rate limit errors are not treated as pending", () => {
  for (const httpStatus of [401, 403, 429, 500, 502]) {
    assert.throws(() => interpretMidtransStatus(httpStatus, notFound, payment));
  }
  for (const payload of [null, "not JSON", { status_code: "401" }, { status_code: "500" }]) {
    assert.throws(() => interpretMidtransStatus(200, payload, payment));
  }
  assert.throws(() => interpretMidtransStatus(404, null, payment));
});

test("verified settlement and pending statuses keep their actual status", () => {
  for (const transaction_status of ["settlement", "pending", "expire", "cancel", "deny", "capture"]) {
    const notification = { ...settlement, transaction_status };
    assert.deepEqual(interpretMidtransStatus(200, notification, payment), {
      awaitingPaymentMethod: false, notification,
    });
  }
});

test("missing or mismatched identity cannot mark an invoice paid", () => {
  for (const changes of [
    { order_id: undefined }, { order_id: "another-order" },
    { gross_amount: undefined }, { gross_amount: "170000.40" },
    { gross_amount: "NaN" }, { gross_amount: "100.00" },
    { currency: "USD" }, { transaction_status: undefined },
  ]) {
    assert.throws(() => interpretMidtransStatus(200, { ...settlement, ...changes }, payment));
  }
});
