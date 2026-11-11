Warning: p was declared with const; use let for reassignable variables.
import { json, serviceClient, swiftpay, userClient } from "../_shared/swiftpay.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: { ...corsHeaders, "Access-Control-Allow-Origin": "*" } });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const partnerKey = Deno.env.get("SWIFTPAY_PARTNER_API_KEY");
    if (!partnerKey) return json({ error: "swiftpay_partner_key_not_configured" }, 503);
    const auth = userClient(req);
    const { data: { user }, error: authError } = await auth.auth.getUser();
    if (authError || !user) return json({ error: "authentication_required" }, 401);

    const body = await req.json().catch(() => ({}));
    const action = body?.action;
    const admin = serviceClient();
    const { data: partner } = await admin.from("partner_profiles")
      .select("user_id,business_name,partner_role,status").eq("user_id", user.id).maybeSingle();
    if (!partner || partner.status !== "approved") return json({ error: "approved_partner_required" }, 403);

    if (action === "start") {
      const phone = String(body?.phone ?? "").replace(/[\s()-]/g, "");
      if (!/^\+964[0-9]{8,10}$/.test(phone)) return json({ error: "valid_iraqi_phone_required" }, 400);
      const result = await swiftpay("/partner/onboarding-sessions", partnerKey, {
        phone,
        prefill: { tradeName: partner.business_name },
      });
      const onboardingUrl = result?.onboardingUrl ?? result?.url ?? result?.setupUrl;
      if (typeof onboardingUrl !== "string" || !onboardingUrl.startsWith("https://swiftpayiq.com/")) {
        return json({ error: "swiftpay_onboarding_url_missing" }, 502);
      }
      return json({ ok: true, onboardingUrl });
    }

    if (action === "exchange") {
      const code = String(body?.code ?? "").trim();
      if (code.length < 8 || code.length > 512) return json({ error: "invalid_connection_code" }, 400);
      const result = await swiftpay("/partner/connections/exchange", partnerKey, { code });
      const record = result?.connection ?? result;
      if (typeof record?.apiKey !== "string" || typeof record?.businessId !== "string") {
        return json({ error: "invalid_swiftpay_connection_response" }, 502);
      }
      const { error } = await admin.rpc("swiftpay_store_merchant_key", {
        p_partner_user_id: user.id,
        p_api_key: record.apiKey,
        p_business_id: record.businessId,
        p_business_name: record.businessName ?? partner.business_name,
        p_scopes: Array.isArray(record.scopes) ? record.scopes : [],
      });
      if (error) {
        console.error("SwiftPay key could not be persisted", error.message);
        return json({ error: "could_not_securely_save_connection" }, 500);
      }
      return json({ ok: true, businessName: record.businessName ?? partner.business_name });
    }

    if (action === "status") {
      const { data, error } = await admin.rpc("swiftpay_get_connection_status", { p_partner_user_id: user.id });
      if (error) throw error;
      const connection = Array.isArray(data) ? data[0] ?? null : data ?? null;
      return json({ connected: Boolean(connection), connection });
    }
    return json({ error: "unsupported_action" }, 400);
  } catch (error) {
    console.error("SwiftPay connection error", error);
    const message = error instanceof Error ? error.message : "connection_failed";
    if (message.includes("partner.link_already_pending_review")) return json({ error: "waiting_for_swiftpay_review" }, 409);
    return json({ error: "swiftpay_connection_failed" }, 502);
  }
});

const corsHeaders = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
