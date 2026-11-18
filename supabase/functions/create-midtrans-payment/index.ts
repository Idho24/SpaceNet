import { paymentReturnUrl } from "../_shared/payment_return.ts";
import {
  authenticatedUser,
  createAdminClient,
  corsHeaders,
  isRecord,
  jsonResponse,
  midtransAuthorization,
  requiredEnv,
  sandboxSnapUrl,
} from "../_shared/midtrans.ts";

async function markPaymentFailed(
  admin: ReturnType<typeof createAdminClient>,
  orderId: string,
): Promise<void> {
  const { error } = await admin
    .from("midtrans_payments")
    .update({ status: "failed", updated_at: new Date().toISOString() })
    .eq("order_id", orderId);
  if (error) throw error;
}

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
  if (!isRecord(body) || typeof body.invoiceId !== "string") {
    return jsonResponse(400, { error: "ID invoice wajib diisi." });
  }

  try {
    const admin = createAdminClient();
    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("customer_id")
      .eq("id", user.id)
      .maybeSingle();
    if (profileError) throw profileError;
    if (typeof profile?.customer_id !== "string") {
      return jsonResponse(403, {
        error: "Akun belum terhubung ke ID pelanggan.",
      });
    }

    const { data: invoice, error: invoiceError } = await admin
      .from("invoices")
      .select("id, customer_id, period, amount, status")
      .eq("id", body.invoiceId)
      .eq("customer_id", profile.customer_id)
      .maybeSingle();
    if (invoiceError) throw invoiceError;
    if (!invoice) {
      return jsonResponse(404, {
        error: "Invoice tidak ditemukan untuk akun ini.",
      });
    }
    if (invoice.status !== "unpaid") {
      return jsonResponse(409, { error: "Invoice ini tidak lagi menunggu pembayaran." });
    }

    const now = new Date();
    const nowIso = now.toISOString();
    const { error: staleCreationError } = await admin
      .from("midtrans_payments")
      .update({ status: "failed", updated_at: nowIso })
      .eq("invoice_id", invoice.id)
      .eq("status", "creating")
      .lte("expires_at", nowIso);
    if (staleCreationError) throw staleCreationError;

    const { data: existingPayment, error: existingError } = await admin
      .from("midtrans_payments")
      .select("order_id, invoice_id, amount, status, redirect_url")
      .eq("invoice_id", invoice.id)
      .eq("user_id", user.id)
      .in("status", ["creating", "pending"])
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (existingError) throw existingError;
    if (existingPayment) {
      if (
        existingPayment.status === "pending" &&
        typeof existingPayment.redirect_url === "string"
      ) {
        return jsonResponse(200, {
          orderId: existingPayment.order_id,
          invoiceId: existingPayment.invoice_id,
          amount: existingPayment.amount,
          status: existingPayment.status,
          redirectUrl: existingPayment.redirect_url,
        });
      }
      return jsonResponse(409, {
        error: "Pembayaran sedang disiapkan. Periksa status beberapa saat lagi.",
      });
    }

    const { data: customer, error: customerError } = await admin
      .from("customers")
      .select("name, email, phone")
      .eq("customer_id", invoice.customer_id)
      .single();
    if (customerError) throw customerError;

    const serverKey = requiredEnv("MIDTRANS_SERVER_KEY").trim();
    if (!serverKey.startsWith("SB-Mid-server-")) {
      return jsonResponse(500, {
        error:
          "MIDTRANS_SERVER_KEY harus berupa Server Key Sandbox (berawalan SB-Mid-server-), bukan Client Key atau key Production.",
      });
    }
    const orderId = `SPN-${crypto.randomUUID()}`;
    let finishUrl: string | null;
    try {
      finishUrl = paymentReturnUrl(body.returnUrl ?? Deno.env.get("MIDTRANS_FINISH_URL"), request.headers.get("origin"), orderId);
    } catch {
      return jsonResponse(400, { error: "Alamat kembali pembayaran tidak valid." });
    }
    const creatingExpiresAt = new Date(now.getTime() + 5 * 60 * 1000);
    const pendingExpiresAt = new Date(now.getTime() + 24 * 60 * 60 * 1000);
    const { error: insertError } = await admin
      .from("midtrans_payments")
      .insert({
        order_id: orderId,
        invoice_id: invoice.id,
        user_id: user.id,
        amount: invoice.amount,
        status: "creating",
        expires_at: creatingExpiresAt.toISOString(),
      });
    if (insertError) {
      if (insertError.code === "23505") {
        return jsonResponse(409, {
          error: "Pembayaran untuk invoice ini sedang diproses.",
        });
      }
      throw insertError;
    }

    const nameParts = customer.name.trim().split(/\s+/);
    const startTime = new Date(now.getTime() + 7 * 60 * 60 * 1000)
      .toISOString()
      .replace("T", " ")
      .slice(0, 19);
    let midtransResponse: unknown;
    try {
      const response = await fetch(sandboxSnapUrl, {
        method: "POST",
        signal: AbortSignal.timeout(15000),
        headers: {
          Accept: "application/json",
          Authorization: midtransAuthorization(serverKey),
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          transaction_details: {
            order_id: orderId,
            gross_amount: invoice.amount,
          },
          ...(finishUrl ? {
            callbacks: { finish: finishUrl, error: finishUrl },
            dana: { callback_url: finishUrl },
            gopay: { callback_url: finishUrl },
            shopeepay: { callback_url: finishUrl },
          } : {}),
          credit_card: { secure: true },
          customer_details: {
            first_name: nameParts[0] ?? customer.name,
            last_name: nameParts.slice(1).join(" "),
            email: customer.email,
            phone: customer.phone,
          },
          item_details: [
            {
              id: invoice.id,
              price: invoice.amount,
              quantity: 1,
              name: `Tagihan SpaceNet ${invoice.period}`.slice(0, 50),
            },
          ],
          expiry: {
            start_time: `${startTime} +0700`,
            unit: "hours",
            duration: 24,
          },
        }),
      });
      const responseText = await response.text();
      if (!response.ok) {
        console.error("Midtrans Snap request failed", response.status);
        await markPaymentFailed(admin, orderId);
        const errorMessage = response.status === 403
          ? "Midtrans menolak akses (HTTP 403). Periksa secret MIDTRANS_SERVER_KEY: gunakan Server Key Sandbox dari akun yang sama, bukan Client Key atau key Production."
          : `Midtrans menolak transaksi (HTTP ${response.status}). Periksa konfigurasi akun Sandbox dan log Edge Function.`;
        return jsonResponse(502, {
          error: errorMessage,
        });
      }
      midtransResponse = JSON.parse(responseText);
    } catch (error) {
      console.error("Midtrans Snap request failed", error);
      await markPaymentFailed(admin, orderId);
      return jsonResponse(502, {
        error: "Tidak dapat menghubungi Midtrans Sandbox.",
      });
    }

    if (
      !isRecord(midtransResponse) ||
      typeof midtransResponse.token !== "string" ||
      typeof midtransResponse.redirect_url !== "string"
    ) {
      await markPaymentFailed(admin, orderId);
      return jsonResponse(502, {
        error: "Respons checkout Midtrans tidak valid.",
      });
    }

    let redirectUrl: URL;
    try {
      redirectUrl = new URL(midtransResponse.redirect_url);
    } catch {
      await markPaymentFailed(admin, orderId);
      return jsonResponse(502, {
        error: "Midtrans mengembalikan alamat checkout yang tidak valid.",
      });
    }
    if (
      redirectUrl.protocol !== "https:" ||
      redirectUrl.hostname !== "app.sandbox.midtrans.com"
    ) {
      await markPaymentFailed(admin, orderId);
      return jsonResponse(502, {
        error: "Midtrans mengembalikan alamat checkout yang tidak aman.",
      });
    }

    const { error: updateError } = await admin
      .from("midtrans_payments")
      .update({
        status: "pending",
        snap_token: midtransResponse.token,
        redirect_url: redirectUrl.toString(),
        expires_at: pendingExpiresAt.toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("order_id", orderId);
    if (updateError) throw updateError;

    return jsonResponse(200, {
      orderId,
      invoiceId: invoice.id,
      amount: invoice.amount,
      status: "pending",
      redirectUrl: redirectUrl.toString(),
    });
  } catch (error) {
    console.error("Could not create Midtrans payment", error);
    return jsonResponse(500, {
      error: "Pembayaran belum dapat diproses. Periksa konfigurasi Supabase.",
    });
  }
});