// Snap creates a checkout before Core API creates a payment transaction.
// https://docs.midtrans.com/docs/transaction-status-cycle
type PaymentIdentity = {
  order_id: string;
  amount: number;
  status: string;
  transaction_id: string | null;
  payment_type: string | null;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function isMidtransNotFound(httpStatus: number, payload: unknown): boolean {
  // Never hide authentication, rate-limit, or server errors behind a body code.
  return (httpStatus === 200 || httpStatus === 404) &&
    isRecord(payload) && String(payload.status_code) === "404";
}

export function interpretMidtransStatus(
  httpStatus: number,
  payload: unknown,
  payment: PaymentIdentity,
): { awaitingPaymentMethod: true } | {
  awaitingPaymentMethod: false;
  notification: Record<string, unknown>;
} {
  if (isMidtransNotFound(httpStatus, payload)) {
    if (payment.status === "pending" && !payment.transaction_id && !payment.payment_type) {
      return { awaitingPaymentMethod: true };
    }
    throw new Error("Transaksi yang sudah diproses belum ditemukan di Midtrans. Coba periksa kembali; jika berlanjut, periksa konfigurasi akun Sandbox.");
  }
  if (httpStatus === 401 || httpStatus === 403 ||
    (isRecord(payload) && ["401", "403"].includes(String(payload.status_code)))) {
    throw new Error("Akses status Midtrans ditolak. Periksa Server Key Sandbox dan izin Core API Read pada server.");
  }
  if (httpStatus < 200 || httpStatus >= 300 || !isRecord(payload)) {
    throw new Error("Status transaksi belum dapat diambil dari Midtrans. Coba lagi sebentar.");
  }
  if (!["200", "201", "202"].includes(String(payload.status_code))) {
    throw new Error("Midtrans belum mengembalikan status transaksi yang valid.");
  }
  // Do not invent missing identity fields when deciding whether an invoice is paid.
  if (payload.order_id !== payment.order_id ||
    (typeof payload.gross_amount !== "string" && typeof payload.gross_amount !== "number") ||
    !Number.isFinite(Number(payload.gross_amount)) ||
    Number(payload.gross_amount) !== payment.amount ||
    typeof payload.transaction_status !== "string" ||
    (payload.currency !== undefined && payload.currency !== "IDR")) {
    throw new Error("Data status Midtrans tidak cocok dengan transaksi. Tagihan belum diubah.");
  }
  return { awaitingPaymentMethod: false, notification: payload };
}

 
// DANA uses BI SNAP transaction IDs, not the merchant order ID.
// https://docs.midtrans.com/reference/dana
export async function fetchMidtransStatus(
  lookupId: string,
  serverKey: string,
  paymentType: unknown,
  fetcher: typeof fetch = fetch,
) {
  const headers: Record<string, string> = {
    Accept: "application/json",
    "Content-Type": "application/json",
    Authorization: "Basic " + btoa(serverKey + ":"),
  };
  if (typeof paymentType === "string" && paymentType.toLowerCase() === "dana") {
    headers["transaction-source"] = "SNAP_API";
  }
  const response = await fetcher(
    "https://api.sandbox.midtrans.com/v2/" + encodeURIComponent(lookupId) + "/status",
    { headers, signal: AbortSignal.timeout(15000), redirect: "error" },
  );
  let payload: unknown;
  try {
    payload = await response.json();
  } catch {
    payload = null;
  }
  return { response, payload };
}
