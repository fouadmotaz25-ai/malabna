import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.95.0";

const allowedOrigins = new Set([
  "https://nextmove-fouad.fouadmotaz25.chatgpt.site",
  "https://fouadmotaz25-ai.github.io",
]);

function responseHeaders(req: Request) {
  const origin = req.headers.get("Origin") ?? "";
  return {
    "Access-Control-Allow-Origin": allowedOrigins.has(origin)
      ? origin
      : "https://nextmove-fouad.fouadmotaz25.chatgpt.site",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json",
    "Vary": "Origin",
  };
}

Deno.serve(async (req: Request) => {
  const headers = responseHeaders(req);
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers });

  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);

  const origin = req.headers.get("Origin") ?? "";
  if (origin && !allowedOrigins.has(origin)) return json({ error: "ORIGIN_NOT_ALLOWED" }, 403);

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json({ error: "AUTH_REQUIRED" }, 401);

  const url = Deno.env.get("SUPABASE_URL")!;
  const token = authorization.slice(7);
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: userError } = await userClient.auth.getUser(token);
  if (userError || !user) return json({ error: "AUTH_REQUIRED" }, 401);

  const body = await req.json().catch(() => ({}));
  const code = String(body.code ?? "").trim().toUpperCase();
  const businessName = String(body.business_name ?? "").trim();
  const role = String(body.partner_role ?? "");

  const validRole = ["merchant", "stadium_owner", "restaurant", "gym_owner"].includes(role);
  const validCode = /^MALABNA-(SHOP|FIELD)-[A-F0-9]{8}$/.test(code);
  const prefixMatchesRole =
    ((role === "merchant" || role === "restaurant") && code.startsWith("MALABNA-SHOP-")) ||
    ((role === "stadium_owner" || role === "gym_owner") && code.startsWith("MALABNA-FIELD-"));

  if (!validRole || !validCode || !prefixMatchesRole || businessName.length < 2 || businessName.length > 120) {
    return json({ error: "INVALID_INPUT" }, 400);
  }

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await admin.rpc("redeem_partner_code_internal", {
    p_user_id: user.id,
    p_code: code,
    p_business_name: businessName,
    p_partner_role: role,
  });

  if (error) {
    const errorCode = error.message.includes("ALREADY_PARTNER") ? "ALREADY_PARTNER"
      : error.message.includes("INVALID_OR_USED_CODE") ? "INVALID_OR_USED_CODE"
      : "REDEMPTION_FAILED";
    return json({ error: errorCode }, 400);
  }

  return json(data);
});
