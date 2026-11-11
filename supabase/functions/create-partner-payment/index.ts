Warning: p was declared with const; use let for reassignable variables.
import { json, serviceClient, swiftpay, userClient } from "../_shared/swiftpay.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: { ...corsHeaders, "Access-Control-Allow-Origin": "*" } });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const auth = userClient(req);
    const { data: { user }, error: authError } = await auth.auth.getUser();
    if (authError || !user) return json({ error: "authentication_required" }, 401);
    const { orderType, orderId } = await req.json();
    if (!["product", "meal", "stadium"].includes(orderType) || !orderId) return json({ error: "invalid_order" }, 400);

    const admin = serviceClient();
    const orderTable = orderType === "product" ? "product_orders" : orderType === "meal" ? "meal_orders" : "stadium_bookings";
    const { data: order, error: orderError } = await admin.from(orderTable).select("*")
      .eq("id", orderId).eq("customer_id", user.id).maybeSingle();
    if (orderError || !order) return json({ error: "order_not_found" }, 404);
    if (["cancelled", "refunded"].includes(String(order.status ?? "").toLowerCase())) return json({ error: "order_not_payable" }, 409);
    if (order.payment_status === "paid") return json({ error: "order_already_paid" }, 409);

    let partnerUserId: string;
    let title: string;
    let amount: number;
    if (orderType === "product") {
      const { data: item } = await admin.from("market_products").select("owner_id,title,price_iqd")
        .eq("id", order.product_id).maybeSingle();
      if (!item) return json({ error: "product_not_found" }, 404);
      partnerUserId = item.owner_id;
      title = `طلب متجر: ${item.title}`;
      amount = Number(order.total_iqd ?? Number(item.price_iqd) * Number(order.quantity ?? 1));
    } else if (orderType === "meal") {
      const { data: meal } = await admin.from("restaurant_meals").select("owner_id,title,price_iqd")
        .eq("id", order.meal_id).maybeSingle();
      if (!meal || meal.owner_id !== order.restaurant_id) return json({ error: "meal_not_found" }, 404);
      partnerUserId = meal.owner_id;
      title = `طلب مطعم: ${meal.title}`;
      amount = Number(order.total_iqd ?? Number(meal.price_iqd) * Number(order.quantity ?? 1));
    } else {
      const { data: slot } = await admin.from("stadium_time_slots").select("stadium_id")
        .eq("id", order.slot_id).maybeSingle();
      if (!slot) return json({ error: "booking_not_found" }, 404);
      const { data: stadium } = await admin.from("partner_stadiums").select("owner_id,name")
        .eq("id", slot.stadium_id).maybeSingle();
      if (!stadium) return json({ error: "stadium_not_found" }, 404);
      partnerUserId = stadium.owner_id;
      title = `حجز ملعب: ${stadium.name}`;
      const required = Number(order.deposit_required_iqd ?? 0);
      const deposited = Number(order.deposit_paid_iqd ?? 0);
      amount = required > deposited ? required - deposited : Number(order.total_iqd ?? 0);
    }

    amount = Math.floor(amount);
    if (!Number.isSafeInteger(amount) || amount <= 0) return json({ error: "invalid_order_amount" }, 409);
    const { data: partner } = await admin.from("partner_profiles").select("status")
      .eq("user_id", partnerUserId).maybeSingle();
    if (partner?.status !== "approved") return json({ error: "partner_not_approved" }, 409);

    const { data: existing } = await admin.rpc("swiftpay_get_pending_payment", {
      p_order_type: orderType, p_order_id: String(orderId),
    });
    const previous = Array.isArray(existing) ? existing[0] : null;
    if (previous?.payment_link_id) {
      // Do not create a second live link while one is still payable.
      const { data: keyRows, error: keyError } = await admin.rpc("swiftpay_get_merchant_key", { p_partner_user_id: partnerUserId });
      if (!keyError && keyRows?.[0]?.api_key) {
        const link = await swiftpay(`/payment-links/${encodeURIComponent(previous.payment_link_id)}`, keyRows[0].api_key, undefined, "GET");
        const payPageUrl = link?.payPageUrl ?? link?.paymentLink?.payPageUrl;
        if (typeof payPageUrl === "string") return json({ ok: true, paymentUrl: payPageUrl, reused: true });
      }
    }

    const { data: keyRows, error: keyError } = await admin.rpc("swiftpay_get_merchant_key", { p_partner_user_id: partnerUserId });
    if (keyError || !keyRows?.[0]?.api_key) return json({ error: "partner_has_not_connected_swiftpay" }, 409);
    const merchant = keyRows[0];
    const customerName = String(user.user_metadata?.full_name ?? user.user_metadata?.name ?? "NextMove customer").slice(0, 100);
    const customerPhone = String(user.phone ?? user.user_metadata?.phone ?? "").replace(/[\s()-]/g, "");
    const created = await swiftpay("/payment-links", merchant.api_key, {
      title: `${title} · ${String(orderId).slice(0, 16)}`.slice(0, 120),
      amount: String(amount),
      isReusable: false,
      ...(customerName ? { customerName } : {}),
      ...(/^\+964[0-9]{8,10}$/.test(customerPhone) ? { customerPhone } : {}),
    });
    const linkRecord = created?.paymentLink ?? created;
    const paymentLinkId = linkRecord?.id;
    const paymentUrl = linkRecord?.payPageUrl ?? created?.payPageUrl;
    if (typeof paymentLinkId !== "string" || typeof paymentUrl !== "string") return json({ error: "payment_link_response_invalid" }, 502);

    const { error: saveError } = await admin.rpc("swiftpay_save_payment_intent", {
      p_order_type: orderType,
      p_order_id: String(orderId),
      p_customer_id: user.id,
      p_partner_user_id: partnerUserId,
      p_business_id: merchant.business_id,
      p_amount_iqd: amount,
      p_payment_link_id: paymentLinkId,
    });
    if (saveError) {
      console.error("Could not persist SwiftPay payment intent", saveError.message);
      return json({ error: "payment_created_but_not_recorded" }, 500);
    }
    return json({ ok: true, paymentUrl });
  } catch (error) {
    console.error("SwiftPay payment link error", error);
    return json({ error: "payment_link_creation_failed" }, 502);
  }
});

const corsHeaders = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
