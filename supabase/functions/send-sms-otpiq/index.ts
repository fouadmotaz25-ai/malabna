import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

type SendSmsPayload = {
  user: { phone?: string };
  sms: { otp?: string };
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const apiKey = Deno.env.get("OTPIQ_API_KEY");
  const hookSecret = Deno.env.get("SEND_SMS_HOOK_SECRET");
  if (!apiKey || !hookSecret) return json({ error: "Server is not configured" }, 500);

  try {
    const rawBody = await req.text();
    const secret = hookSecret.replace(/^v1,whsec_/, "");
    const payload = new Webhook(secret).verify(
      rawBody,
      Object.fromEntries(req.headers),
    ) as SendSmsPayload;

    const phoneNumber = (payload.user.phone ?? "").replace(/^\+/, "");
    const verificationCode = payload.sms.otp ?? "";
    if (!/^9647\d{9}$/.test(phoneNumber) || !/^\d{6}$/.test(verificationCode)) {
      return json({ error: "Invalid Iraqi phone number or OTP" }, 400);
    }

    const response = await fetch("https://api.otpiq.com/api/sms", {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        phoneNumber,
        smsType: "verification",
        verificationCode,
        provider: "auto",
      }),
    });

    if (!response.ok) {
      const providerMessage = await response.text();
      console.error("OTPIQ delivery failed", response.status, providerMessage);
      return json({ error: "OTP delivery failed" }, 502);
    }

    return json({});
  } catch (error) {
    console.error("Invalid Send SMS hook request", error);
    return json({ error: "Unauthorized hook request" }, 401);
  }
});
