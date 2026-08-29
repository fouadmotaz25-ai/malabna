import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigins = new Set(["https://nextmove-fouad.fouadmotaz25.chatgpt.site", "https://fouadmotaz25-ai.github.io"]);
function responseHeaders(req: Request) {
  const origin = req.headers.get("Origin") ?? "";
  return { "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : "https://nextmove-fouad.fouadmotaz25.chatgpt.site", "Vary": "Origin", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", "Content-Type": "application/json" };
}

Deno.serve(async (req: Request) => {
  const headers = responseHeaders(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return new Response(JSON.stringify({ error: "METHOD_NOT_ALLOWED" }), { status: 405, headers });
  try {
    const origin = req.headers.get("Origin") ?? "";
    if (origin && !allowedOrigins.has(origin)) return new Response(JSON.stringify({ error: "ORIGIN_NOT_ALLOWED" }), { status: 403, headers });
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) return new Response(JSON.stringify({ error: "LOGIN_REQUIRED" }), { status: 401, headers });

    const url = Deno.env.get("SUPABASE_URL")!;
    const authClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: { user }, error: authError } = await authClient.auth.getUser(token);
    if (authError || !user) return new Response(JSON.stringify({ error: "INVALID_SESSION" }), { status: 401, headers });

    const body = await req.json();
    const slotId = Number(body?.slot_id);
    const paymentMethod = body?.payment_method === "split" ? "split" : body?.payment_method === "cash" ? "cash" : "";
    const players = Array.isArray(body?.players) ? body.players.map((player: unknown) => {
      const value = player && typeof player === "object" ? player as Record<string, unknown> : {};
      return { name: String(value.name ?? "").trim().slice(0, 80), phone: String(value.phone ?? "").replace(/[\s()-]/g, "").slice(0, 16) };
    }) : [];
    if (!Number.isSafeInteger(slotId) || slotId <= 0) return new Response(JSON.stringify({ error: "INVALID_SLOT" }), { status: 400, headers });
    if (!paymentMethod || (paymentMethod === "split" && (players.length < 2 || players.length > 22))) return new Response(JSON.stringify({ error: "INVALID_PAYMENT_DETAILS" }), { status: 400, headers });

    // Cash bookings are confirmed only by a trusted payment-provider webhook
    // after the fixed IQD 5,000 deposit has been verified. Until a gateway is
    // configured, never create or reserve a booking from a browser request.
    if (paymentMethod === "cash") {
      return new Response(JSON.stringify({
        error: "DEPOSIT_GATEWAY_REQUIRED",
        deposit_iqd: 5000,
      }), { status: 409, headers });
    }

    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data, error } = await admin.rpc("book_stadium_slot_internal", { p_user_id: user.id, p_slot_id: slotId, p_payment_method: paymentMethod, p_players: players });
    if (error) {
      const message = error.message || "";
      const known = ["SLOT_NOT_FOUND","SLOT_ALREADY_BOOKED","PAST_SLOT","INVALID_PLAYER_DATA","INVALID_PLAYER_COUNT","INVALID_STADIUM_PRICE"].find(item => message.includes(item));
      return new Response(JSON.stringify({ error: known ?? "BOOKING_FAILED" }), { status: known === "SLOT_ALREADY_BOOKED" ? 409 : 400, headers });
    }
    return new Response(JSON.stringify({ ok: true, booking: data }), { status: 200, headers });
  } catch {
    return new Response(JSON.stringify({ error: "BOOKING_FAILED" }), { status: 500, headers });
  }
});
