import {
  applyMidtransStatus,
  createAdminClient,
  corsHeaders,
  isRecord,
  jsonResponse,
  requiredEnv,
  verifyNotificationSignature,
} from "../_shared/midtrans.ts";

import { fetchMidtransStatus, interpretMidtransStatus } from "../_shared/midtrans_status.ts";

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "Metode request tidak didukung." });
  }

  let notification: unknown;
  try {
    notification = await request.json();
  } catch {
    return jsonResponse(400, { error: "Notifikasi Midtrans tidak valid." });
  }
  if (!isRecord(notification)) {
    return jsonResponse(400, { error: "Notifikasi Midtrans tidak valid." });
  }

  const orderId = notification.order_id;
  const statusCode = notification.status_code;
  const grossAmount = notification.gross_amount;
  const signature = notification.signature_key;
  if (
    typeof orderId !== "string" ||
    typeof statusCode !== "string" ||
    typeof grossAmount !== "string" ||
    typeof signature !== "string"
  ) {
    return jsonResponse(400, {
      error: "Notifikasi Midtrans tidak memiliki signature yang diperlukan.",
    });
  }

  try {
    const serverKey = requiredEnv("MIDTRANS_SERVER_KEY").trim();
    const validSignature = await verifyNotificationSignature(
      orderId,
      statusCode,
      grossAmount,
      signature,
      serverKey,
    );
    const admin = createAdminClient();
    let verifiedNotification = notification;
    if (!validSignature) {
      // A callback can only trigger a lookup. Its status is never trusted.
      // https://docs.midtrans.com/reference/handle-notifications
      const transactionId = notification.transaction_id;
      if (typeof transactionId !== "string" || !transactionId || transactionId.length > 200) {
        return jsonResponse(401, { error: "Signature Midtrans tidak valid." });
      }
      const { data: payment, error } = await admin
        .from("midtrans_payments")
        .select("order_id, amount, status, transaction_id, payment_type")
        .eq("order_id", orderId)
        .maybeSingle();
      if (error) throw error;
      if (!payment) return jsonResponse(404, { error: "Transaksi tidak ditemukan." });
      let lookup;
      try {
        lookup = await fetchMidtransStatus(
          transactionId, serverKey, payment.payment_type ?? notification.payment_type, fetch,
        );
      } catch {
        return jsonResponse(503, { error: "Verifikasi Midtrans belum tersedia. Coba kembali." });
      }
      if (lookup.response.status >= 500 || lookup.response.status === 429) {
        return jsonResponse(503, { error: "Verifikasi Midtrans belum tersedia. Coba kembali." });
      }
      try {
        const result = interpretMidtransStatus(lookup.response.status, lookup.payload, payment);
        if (result.awaitingPaymentMethod ||
          result.notification.transaction_id !== transactionId) {
          return jsonResponse(401, { error: "Notifikasi belum dapat diverifikasi oleh Midtrans." });
        }
        verifiedNotification = result.notification;
      } catch {
        return jsonResponse(401, { error: "Notifikasi belum dapat diverifikasi oleh Midtrans." });
      }
    }

    const status = await applyMidtransStatus(admin, verifiedNotification);
    return jsonResponse(200, { received: true, orderId, status });
  } catch (error) {
    console.error("Could not process Midtrans notification", error);
    return jsonResponse(500, {
      error: "Notifikasi pembayaran belum dapat diproses.",
    });
  }
});