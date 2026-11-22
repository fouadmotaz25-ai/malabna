import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.95.0";

const allowedOrigins = new Set([
  "https://nextmove-north-trial.fouadmotaz25.chatgpt.site",
  "https://fouadmotaz25-ai.github.io",
]);
function response(req: Request, body: unknown, status = 200) {
  const origin = req.headers.get("Origin") ?? "";
  const headers = {
    "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : "https://nextmove-north-trial.fouadmotaz25.chatgpt.site",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json",
    "Vary": "Origin",
  };
  return new Response(JSON.stringify(body), { status, headers });
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin") ?? "";
  if (req.method === "OPTIONS") return new Response("ok", { headers: { "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : "https://nextmove-north-trial.fouadmotaz25.chatgpt.site", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", "Vary": "Origin" } });
  if (req.method !== "POST") return response(req, { error: "METHOD_NOT_ALLOWED" }, 405);
  if (origin && !allowedOrigins.has(origin)) return response(req, { error: "ORIGIN_NOT_ALLOWED" }, 403);
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) return response(req, { error: "LOGIN_REQUIRED" }, 401);
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY")!;
    const auth = createClient(url, anon, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: { user }, error: authError } = await auth.auth.getUser(token);
    if (authError || !user) return response(req, { error: "INVALID_SESSION" }, 401);
    const body = await req.json().catch(() => ({}));
    const slotId = Number(body?.slot_id);
    if (!Number.isSafeInteger(slotId) || slotId <= 0) return response(req, { error: "INVALID_SLOT" }, 400);
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: slot } = await admin.from("stadium_time_slots").select("id,slot_date,stadium_id,status").eq("id", slotId).maybeSingle();
    if (!slot) return response(req, { error: "SLOT_NOT_FOUND" }, 404);
    if (slot.status !== "available") return response(req, { error: "SLOT_ALREADY_BOOKED" }, 409);
    const today = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Baghdad" }).format(new Date());
    if (slot.slot_date < today) return response(req, { error: "PAST_SLOT" }, 400);
    const { data: stadium } = await admin.from("partner_stadiums").select("owner_id,price_iqd,is_active").eq("id", slot.stadium_id).maybeSingle();
    if (!stadium?.is_active || Number(stadium.price_iqd) <= 0) return response(req, { error: "STADIUM_UNAVAILABLE" }, 409);
    const { data: partner } = await admin.from("partner_profiles").select("status").eq("user_id", stadium.owner_id).maybeSingle();
    if (partner?.status !== "approved") return response(req, { error: "PARTNER_NOT_APPROVED" }, 409);
    if (stadium.owner_id === user.id) return response(req, { error: "CANNOT_BOOK_OWN_STADIUM" }, 403);
    const { data: reserved, error: reserveError } = await admin.from("stadium_time_slots").update({ status: "booked" }).eq("id", slotId).eq("status", "available").select("id").maybeSingle();
    if (reserveError || !reserved) return response(req, { error: "SLOT_ALREADY_BOOKED" }, 409);
    const { data: booking, error: bookingError } = await admin.from("stadium_bookings").insert({ slot_id: slotId, customer_id: user.id, status: "pending", total_iqd: Number(stadium.price_iqd), payment_status: "pending" }).select("id").single();
    if (bookingError || !booking) {
      await admin.from("stadium_time_slots").update({ status: "available" }).eq("id", slotId).eq("status", "booked");
      console.error("Booking insert failed", bookingError?.message);
      return response(req, { error: "BOOKING_FAILED" }, 503);
    }
    return response(req, { ok: true, booking_id: booking.id });
  } catch (error) {
    console.error("Booking request failed", error);
    return response(req, { error: "BOOKING_FAILED" }, 500);
  }
});
