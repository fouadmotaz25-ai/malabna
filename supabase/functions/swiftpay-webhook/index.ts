Warning: p was declared with const; use let for reassignable variables.
import { json, serviceClient } from "../_shared/swiftpay.ts";

function hex(bytes: Uint8Array) {
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function constantTimeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return mismatch === 0;
}

async function verify(rawBody: string, signature: string, secret: string) {
  const parts = Object.fromEntries(signature.split(",").map((part) => part.split("=")));
  const timestamp = Number(parts.t);
  if (!Number.isFinite(timestamp) || Math.abs(Date.now() / 1000 - timestamp) > 300 || !parts.v1) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${parts.t}.${rawBody}`));
  return constantTimeEqual(hex(new Uint8Array(mac)), parts.v1.toLowerCase());
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const secret = Deno.env.get("SWIFTPAY_WEBHOOK_SECRET");
  if (!secret) return json({ error: "webhook_not_configured" }, 503);
  const rawBody = await req.text();
  const signature = req.headers.get("X-SwiftPay-Signature") ?? "";
  if (!await verify(rawBody, signature, secret)) return json({ error: "invalid_signature" }, 401);
  try {
    const payload = JSON.parse(rawBody);
    const event = String(payload?.event ?? "");
    const data = payload?.data ?? {};
    if (!["payment.succeeded", "payment.failed", "payment.refunded", "invoice.paid", "payment_link.paid"].includes(event)) {
      return json({ ok: true, ignored: true });
    }
    const paymentLinkId = String(data.paymentLinkId ?? "");
    const amount = Number(data.amount);
    const businessId = String(data.businessId ?? "");
    if (!paymentLinkId || !Number.isSafeInteger(amount) || !businessId) return json({ error: "invalid_event_payload" }, 400);
    const admin = serviceClient();
    const { data: applied, error } = await admin.rpc("swiftpay_apply_payment_event", {
      p_payment_link_id: paymentLinkId,
      p_payment_id: String(data.paymentId ?? ""),
      p_gateway_txn_id: data.gatewayTxnId ? String(data.gatewayTxnId) : null,
      p_event: event,
      p_amount_iqd: amount,
      p_business_id: businessId,
    });
    if (error) {
      console.error("SwiftPay event could not be applied", error.message);
      return json({ error: "event_application_failed" }, 503);
    }
    if (!applied) return json({ error: "payment_intent_not_found" }, 503);
    return json({ ok: true });
  } catch (error) {
    console.error("SwiftPay webhook failed", error);
    return json({ error: "webhook_processing_failed" }, 503);
  }
});
