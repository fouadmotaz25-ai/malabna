(function () {
  "use strict";
  const client = window.supabase.createClient("https://onyideifalwoyxbvwhwl.supabase.co", "sb_publishable_K_8YUNMGO4UAOUTxBc9z8Q_5mOKLC46", { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } });
  const $ = selector => document.querySelector(selector), gate = $("#joinGate"), form = $("#coachJoinForm"), result = $("#joinResult"), codeInput = $("#coachJoinCode");
  function toast(message) { const el = $("#joinToast"); el.textContent = message; el.style.display = "block"; setTimeout(() => el.style.display = "none", 3800); }
  async function loadAccess() {
    const { data: { session } } = await client.auth.getSession();
    if (!session?.user) { gate.innerHTML = '<div><b>سجّل الدخول أولاً</b><p>يجب ربط التفعيل بحساب مستخدم حقيقي.</p><a href="index.html#top">تسجيل الدخول</a></div>'; return; }
    const { data: coach } = await client.from("training_coaches").select("display_name,is_active").eq("user_id", session.user.id).maybeSingle();
    if (coach?.is_active) { gate.hidden = true; result.hidden = false; result.innerHTML = '<span>✓</span><h3>حسابك مفعّل ككابتن</h3><p>يمكنك الدخول إلى واجهة الكابتن وإضافة اشتراكاتك.</p><a href="coach.html">فتح واجهة الكابتن</a>'; return; }
    gate.hidden = true; form.hidden = false;
  }
  codeInput.addEventListener("input", () => { codeInput.value = codeInput.value.toUpperCase().replace(/[^A-Z0-9-]/g, ""); });
  form.addEventListener("submit", async event => {
    event.preventDefault(); const button = $("#activateCoachButton"); button.disabled = true; button.textContent = "جارٍ التفعيل…";
    try {
      const { data, error } = await client.rpc("activate_training_coach", { p_name: $("#coachJoinName").value.trim(), p_phone: $("#coachJoinPhone").value.trim(), p_code: codeInput.value.trim() });
      if (error) throw error;
      if (!data?.ok) { toast(data?.message || "تعذر استخدام كود التفعيل"); return; }
      form.hidden = true; result.hidden = false; result.innerHTML = '<span>✓</span><h3>تم تفعيل حساب الكابتن</h3><p>أصبح بإمكانك إنشاء اشتراكاتك ومتابعة المتدربين بصورة رسمية.</p><a href="coach.html">فتح واجهة الكابتن</a>';
    } catch (_) { toast("تعذر التفعيل حالياً. تأكد من تسجيل الدخول والبيانات"); }
    finally { button.disabled = false; button.textContent = "تفعيل حساب الكابتن"; }
  });
  client.auth.onAuthStateChange(() => setTimeout(loadAccess, 0)); loadAccess();
})();
