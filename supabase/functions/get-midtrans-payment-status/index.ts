import {
  applyMidtransStatus,
  authenticatedUser,
  createAdminClient,
  corsHeaders,
  isRecord,
  jsonResponse,
  requiredEnv,
} from "../_shared/midtrans.ts";
import {
  fetchMidtransStatus,
  interpretMidtransStatus,
  isMidtransNotFound,
} from "../_shared/midtrans_status.ts";

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "Metode request tidak didukung." });
  }

  const user = await authenticatedUser(request);
  if (!user) {
    return jsonResponse(401, { error: "Silakan masuk kembali ke akun." });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return jsonResponse(400, { error: "Data pembayaran tidak valid." });
  }
  if (!isRecord(body) || typeof body.orderId !== "string") {
    return jsonResponse(400, { error: "ID transaksi wajib diisi." });
  }

  try {
    const admin = createAdminClient();
    const { data: payment, error: paymentError } = await admin
      .from("midtrans_payments")
      .select(
        "order_id, invoice_id, user_id, amount, status, redirect_url, transaction_id, payment_type, updated_at",
      )
      .eq("order_id", body.orderId)
      .eq("user_id", user.id)
      .maybeSingle();
    if (paymentError) throw paymentError;
    if (!payment) {
      return jsonResponse(404, { error: "Transaksi tidak ditemukan." });
    }
    if (payment.status === "paid") {
      return jsonResponse(200, {
        orderId: payment.order_id,
        invoiceId: payment.invoice_id,
        amount: payment.amount,
        status: payment.status,
        redirectUrl: payment.redirect_url,
        paymentType: payment.payment_type,
        transactionId: payment.transaction_id,
        updatedAt: payment.updated_at,
      });
    }
    if (payment.status === "creating" || !payment.redirect_url) {
      return jsonResponse(409, {
        error: "Checkout masih disiapkan. Coba periksa kembali sebentar lagi.",
      });
    }

    const serverKey = requiredEnv("MIDTRANS_SERVER_KEY").trim();
    const statusLookupId =
      typeof payment.transaction_id === "string"
        ? payment.transaction_id
        : payment.order_id;
    const fetchStatus = (lookupId: string) =>
      fetchMidtransStatus(lookupId, serverKey, payment.payment_type, fetch);

    let lookupId = statusLookupId;
    let statusResult = await fetchStatus(lookupId);
    const isNotFound = (result: typeof statusResult) =>
      isMidtransNotFound(result.response.status, result.payload);

    if (payment.payment_type?.toLowerCase() !== "dana" &&
      lookupId !== payment.order_id && isNotFound(statusResult)) {
      console.warn("Midtrans transaction ID lookup was not found; retrying by order ID.");
      lookupId = payment.order_id;
      statusResult = await fetchStatus(lookupId);
    }

    let result: ReturnType<typeof interpretMidtransStatus>;
    try {
      result = interpretMidtransStatus(
        statusResult.response.status,
        statusResult.payload,
        payment,
      );
    } catch (error) {
      return jsonResponse(502, {
        error: error instanceof Error
          ? error.message
          : "Status transaksi belum dapat diperiksa.",
      });
    }
    if (result.awaitingPaymentMethod) {
      return jsonResponse(200, {
        orderId: payment.order_id,
        invoiceId: payment.invoice_id,
        amount: payment.amount,
        status: "pending",
        redirectUrl: payment.redirect_url,
        paymentType: payment.payment_type,
        transactionId: payment.transaction_id,
        updatedAt: payment.updated_at,
        statusMessage:
          "Konfirmasi pembayaran belum diterima. Buka checkout untuk melihat statusnya. Jika sudah membayar, jangan bayar ulang; status akan diperbarui setelah dikonfirmasi oleh Midtrans.",
      });
    }

    const status = await applyMidtransStatus(admin, result.notification);
    const { data: updatedPayment, error: updatedPaymentError } = await admin
      .from("midtrans_payments")
      .select("payment_type, transaction_id, updated_at")
      .eq("order_id", payment.order_id)
      .single();
    if (updatedPaymentError) throw updatedPaymentError;
    return jsonResponse(200, {
      orderId: payment.order_id,
      invoiceId: payment.invoice_id,
      amount: payment.amount,
      status,
      redirectUrl: payment.redirect_url,
      paymentType: updatedPayment.payment_type,
      transactionId: updatedPayment.transaction_id,
      updatedAt: updatedPayment.updated_at,
    });
  } catch (error) {
    console.error("Could not check Midtrans payment status", error);
    return jsonResponse(500, {
      error: "Status pembayaran belum dapat diperiksa.",
    });
  }
});
