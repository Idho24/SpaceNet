// The return destination never determines whether an invoice is paid.
export function paymentReturnUrl(
  returnBase: unknown,
  requestOrigin: string | null,
  orderId: string,
): string | null {
  if (returnBase === undefined || returnBase === null || returnBase === "") return null;
  if (typeof returnBase !== "string") throw new Error("Alamat kembali tidak valid.");
  const base = new URL(returnBase);
  const loopback = ["localhost", "127.0.0.1", "[::1]"].includes(base.hostname);
  if (base.username || base.password || base.search || base.hash ||
      !(base.protocol === "https:" || (base.protocol === "http:" && loopback)) ||
      (requestOrigin !== null && base.origin !== requestOrigin)) {
    throw new Error("Alamat kembali harus memakai alamat aplikasi yang sama.");
  }
  base.searchParams.set("order_id", orderId);
  base.hash = "/payment-result?order_id=" + encodeURIComponent(orderId);
  if (base.toString().length > 255) throw new Error("Alamat kembali terlalu panjang.");
  return base.toString();
}
