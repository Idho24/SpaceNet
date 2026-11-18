import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export const sandboxSnapUrl =
  "https://app.sandbox.midtrans.com/snap/v1/transactions";
export const sandboxApiUrl = "https://api.sandbox.midtrans.com";

export function jsonResponse(
  status: number,
  body: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

export function createAdminClient() {
  return createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}

export async function authenticatedUser(request: Request) {
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return null;
  const accessToken = authorization.slice("Bearer ".length).trim();
  if (!accessToken) return null;

  const authClient = createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_ANON_KEY"),
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
  const { data, error } = await authClient.auth.getUser(accessToken);
  if (error || !data.user) return null;
  return data.user;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function midtransAuthorization(serverKey: string): string {
  return `Basic ${btoa(`${serverKey}:`)}`;
}

export function verifyNotificationSignature(
  orderId: string,
  statusCode: string,
  grossAmount: string,
  signature: string,
  serverKey: string,
): Promise<boolean> {
  return crypto.subtle.digest(
    "SHA-512",
    new TextEncoder().encode(
      `${orderId}${statusCode}${grossAmount}${serverKey}`,
    ),
  ).then((digest) => {
    const expected = Array.from(new Uint8Array(digest))
      .map((byte) => byte.toString(16).padStart(2, "0"))
      .join("");
    if (expected.length !== signature.length) return false;

    let difference = 0;
    for (let index = 0; index < expected.length; index++) {
      difference |= expected.charCodeAt(index) ^ signature.charCodeAt(index);
    }
    return difference === 0;
  });
}

export async function applyMidtransStatus(
  admin: ReturnType<typeof createAdminClient>,
  notification: Record<string, unknown>,
): Promise<string> {
  const orderId = notification.order_id;
  const grossAmount = notification.gross_amount;
  const rawTransactionStatus = notification.transaction_status;
  if (
    typeof orderId !== "string" ||
    (typeof grossAmount !== "string" && typeof grossAmount !== "number") ||
    typeof rawTransactionStatus !== "string"
  ) {
    throw new Error("Midtrans notification is missing transaction details.");
  }
  if (notification.currency !== undefined && notification.currency !== "IDR") {
    throw new Error("Midtrans notification currency does not match the invoice.");
  }
  const transactionStatus = rawTransactionStatus.toLowerCase();

  const { data: payment, error: paymentError } = await admin
    .from("midtrans_payments")
    .select("order_id, invoice_id, amount, status")
    .eq("order_id", orderId)
    .maybeSingle();
  if (paymentError) throw paymentError;
  if (!payment) throw new Error("Payment order was not found.");

  const receivedAmount = Number(grossAmount);
  if (
    !Number.isFinite(receivedAmount) ||
    receivedAmount !== payment.amount
  ) {
    throw new Error("Midtrans notification amount does not match the invoice.");
  }

  const fraudStatus = typeof notification.fraud_status === "string"
    ? notification.fraud_status.toLowerCase() : notification.fraud_status;
  let status: string | null = null;
  if (transactionStatus === "settlement") {
    status = "paid";
  } else if (transactionStatus === "capture" && fraudStatus === "accept") {
    status = "paid";
  } else if (transactionStatus === "pending") {
    status = "pending";
  } else if (transactionStatus === "expire") {
    status = "expired";
  } else if (transactionStatus === "cancel") {
    status = "cancelled";
  } else if (transactionStatus === "deny") {
    status = "failed";
  }

  if (status === null) return payment.status;

  // One database transaction keeps the receipt and invoice consistent.
  const { data: appliedStatus, error: applyError } = await admin.rpc(
    "apply_verified_midtrans_status",
    {
      p_order_id: orderId,
      p_amount: receivedAmount,
      p_status: status,
      p_transaction_id: typeof notification.transaction_id === "string"
        ? notification.transaction_id : null,
      p_payment_type: typeof notification.payment_type === "string"
        ? notification.payment_type.toLowerCase() : null,
    },
  );
  if (applyError) throw applyError;
  if (typeof appliedStatus !== "string") throw new Error("Payment status was not returned.");
  return appliedStatus;
}
