(function () {
  "use strict";
  const client = window.supabase.createClient(
    "https://onyideifalwoyxbvwhwl.supabase.co",
    "sb_publishable_K_8YUNMGO4UAOUTxBc9z8Q_5mOKLC46",
    { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } },
  );
  const fallbackImages = [
    "https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?auto=format&fit=crop&w=900&q=85",
    "https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?auto=format&fit=crop&w=900&q=85",
    "https://images.unsplash.com/photo-1517466787929-bc90951d0974?auto=format&fit=crop&w=900&q=85"
  ];
  programs.online = [];
  programs.inperson = [];

  document.querySelector(".how-training").insertAdjacentHTML("beforebegin", `
    <section class="coach-chat-section" id="onlineCoaching"><div class="shell">
      <div class="section-head coach-chat-head"><div><span class="eyebrow">متابعة خاصة وآمنة</span><h2>شات الكابتن والمتدرب</h2><p>بعد تفعيل اشتراكك يمكنك إرسال الاستفسارات والصور ومتابعة خطتك مباشرة مع الكابتن.</p></div><div class="chat-head-actions"><a href="coach.html">واجهة الكابتن</a><span class="secure-chat-badge">🔒 للمشتركين فقط</span></div></div>
      <div class="chat-loading" id="chatGate">جاري التحقق من اشتراكك…</div>
      <div class="coach-chat-workspace" id="chatWorkspace" hidden>
        <aside class="chat-subscriptions"><div class="chat-side-title"><b>اشتراكات التدريب</b><small>اختر المحادثة</small></div><div id="subscriptionList"></div></aside>
        <div class="chat-panel"><div class="chat-panel-head"><div class="coach-avatar" id="chatAvatar">NM</div><div><b id="chatTitle">اختر اشتراكاً</b><small id="chatStatus">الشات يفتح بعد تفعيل الاشتراك</small></div><span class="online-dot" id="chatOnline" hidden>متاح</span></div>
          <div class="chat-empty" id="chatEmpty"><span>💬</span><h3>متابعة حقيقية مع مدربك</h3><p>اختر اشتراكاً فعالاً من القائمة لعرض الرسائل والاستفسارات.</p></div>
          <div class="chat-conversation" id="chatConversation" hidden>
            <div class="question-shortcuts"><button type="button" data-question="هل يمكن مراجعة أدائي في هذا التمرين؟">مراجعة الأداء</button><button type="button" data-question="أشعر بألم أثناء التمرين، ما التعديل المناسب؟">تعديل التمرين</button><button type="button" data-question="هل أزيد الوزن أو عدد التكرارات هذا الأسبوع؟">تقدم الأوزان</button></div>
            <div class="chat-messages" id="chatMessages" aria-live="polite"></div>
            <div class="image-preview" id="imagePreview" hidden><span></span><button type="button" aria-label="إلغاء الصورة">×</button></div>
            <form class="chat-composer" id="chatComposer"><label class="attach-button" for="chatImage" title="إرسال صورة">📎<input id="chatImage" type="file" accept="image/jpeg,image/png,image/webp" hidden></label><textarea id="chatText" maxlength="2000" rows="1" placeholder="اكتب استفسارك للكابتن…" aria-label="نص الرسالة"></textarea><button class="send-message" type="submit">إرسال</button></form>
            <small class="chat-note">الصور خاصة بطرفي الاشتراك، بحد أقصى 5 ميغابايت.</small>
          </div>
        </div>
      </div>
    </div></section>`);

  const state = { user: null, subscriptions: [], active: null, channel: null, file: null, rendered: new Set() };
  const $ = (selector) => document.querySelector(selector);
  const gate = $("#chatGate"), workspace = $("#chatWorkspace"), list = $("#subscriptionList"), conversation = $("#chatConversation"), empty = $("#chatEmpty"), messagesBox = $("#chatMessages"), chatText = $("#chatText"), imageInput = $("#chatImage"), imagePreview = $("#imagePreview");
  const programInfo = (subscription) => subscription.training_programs || {};
  const coachInfo = (subscription) => subscription.training_coaches || {};
  const isActive = (subscription) => subscription.status === "active" && new Date(subscription.starts_at).getTime() <= Date.now() && new Date(subscription.ends_at).getTime() > Date.now();
  const statusLabel = (subscription) => isActive(subscription) ? "اشتراك فعال" : ({ pending: "قيد تفعيل الاشتراك", paused: "الاشتراك متوقف مؤقتاً", expired: "انتهى الاشتراك", cancelled: "أُلغي الاشتراك" }[subscription.status] || "غير متاح");

  async function stopRealtime() {
    if (state.channel) { await client.removeChannel(state.channel); state.channel = null; }
  }

  async function loadTrainingAccess() {
    const { data: { session } } = await client.auth.getSession();
    state.user = session?.user || null;
    await stopRealtime();
    if (!state.user) {
      workspace.hidden = true; gate.hidden = false;
      gate.innerHTML = '<span>🔐</span><div><b>سجّل الدخول لعرض متابعة التدريب</b><p>بعد تسجيل الدخول سيظهر اشتراكك وشات الكابتن هنا.</p></div><a href="index.html#top">تسجيل الدخول</a>';
      return;
    }
    const userId = state.user.id;
    const { data, error } = await client.from("training_subscriptions").select("id,status,starts_at,ends_at,trainee_id,trainee_name,coach_id,program_id,training_programs(title,coach_name),training_coaches(display_name,avatar_url)").or(`trainee_id.eq.${userId},coach_id.eq.${userId}`).order("created_at", { ascending: false });
    if (error) { workspace.hidden = true; gate.hidden = false; gate.textContent = "تعذر تحميل اشتراكات التدريب حالياً."; return; }
    state.subscriptions = data || [];
    if (!state.subscriptions.length) {
      workspace.hidden = true; gate.hidden = false;
      gate.innerHTML = '<span>🏋️</span><div><b>لا يوجد اشتراك أونلاين بعد</b><p>اختر أحد البرامج وأرسل طلب الاشتراك.</p></div><a href="#programs" onclick="selectMode(\'online\')">عرض البرامج</a>';
      return;
    }
    gate.hidden = true; workspace.hidden = false; renderSubscriptions();
    const first = state.subscriptions.find(isActive) || state.subscriptions[0];
    await openTrainingChat(first.id);
  }

  function renderSubscriptions() {
    list.replaceChildren();
    state.subscriptions.forEach((subscription) => {
      const item = document.createElement("button"); item.type = "button"; item.className = "subscription-item";
      if (state.active?.id === subscription.id) item.classList.add("active");
      if (!isActive(subscription)) item.classList.add("locked");
      const icon = document.createElement("span"); icon.textContent = isActive(subscription) ? "💬" : "🔒";
      const copy = document.createElement("div"), title = document.createElement("b"), status = document.createElement("small");
      title.textContent = programInfo(subscription).title || "تدريب أونلاين"; status.textContent = statusLabel(subscription); copy.append(title, status); item.append(icon, copy);
      item.addEventListener("click", () => openTrainingChat(subscription.id)); list.append(item);
    });
  }

  async function openTrainingChat(subscriptionId) {
    const subscription = state.subscriptions.find((item) => item.id === subscriptionId); if (!subscription) return;
    state.active = subscription; renderSubscriptions(); await stopRealtime();
    const program = programInfo(subscription), coach = coachInfo(subscription), coachName = coach.display_name || program.coach_name || "الكابتن";
    $("#chatTitle").textContent = coachName; $("#chatStatus").textContent = `${program.title || "تدريب أونلاين"} · ${statusLabel(subscription)}`; $("#chatAvatar").textContent = coachName.replace("الكابتن", "").trim().slice(0, 2) || "NM";
    if (!isActive(subscription)) {
      empty.hidden = false; conversation.hidden = true; $("#chatOnline").hidden = true; empty.querySelector("span").textContent = "🔒"; empty.querySelector("h3").textContent = "المحادثة مقفلة مؤقتاً"; empty.querySelector("p").textContent = subscription.status === "pending" ? "طلب الاشتراك قيد التفعيل وربط حساب الكابتن. ستفتح المحادثة تلقائياً بعد التأكيد." : "يتطلب إرسال الرسائل والصور اشتراكاً فعالاً."; return;
    }
    empty.hidden = true; conversation.hidden = false; $("#chatOnline").hidden = false; messagesBox.replaceChildren(); state.rendered.clear();
    const { data, error } = await client.from("training_messages").select("id,subscription_id,sender_id,body,image_path,message_type,created_at").eq("subscription_id", subscription.id).order("created_at", { ascending: true }).limit(200);
    if (error) { const notice = document.createElement("p"); notice.className = "chat-system-message"; notice.textContent = "تعذر تحميل الرسائل."; messagesBox.append(notice); return; }
    for (const message of data || []) await appendMessage(message);
    if (!data?.length) { const welcome = document.createElement("p"); welcome.className = "chat-system-message"; welcome.textContent = "بدأت المتابعة. أرسل استفسارك الأول أو صورة للكابتن."; messagesBox.append(welcome); }
    scrollMessages();
    state.channel = client.channel(`training-chat-${subscription.id}`).on("postgres_changes", { event: "INSERT", schema: "public", table: "training_messages", filter: `subscription_id=eq.${subscription.id}` }, ({ new: message }) => appendMessage(message)).subscribe();
  }

  async function appendMessage(message) {
    if (state.rendered.has(message.id)) return; state.rendered.add(message.id); messagesBox.querySelector(".chat-system-message")?.remove();
    const bubble = document.createElement("article"); bubble.className = message.sender_id === state.user.id ? "chat-message mine" : "chat-message theirs";
    if (message.body) { const text = document.createElement("p"); text.textContent = message.body; bubble.append(text); }
    if (message.image_path) {
      const { data } = await client.storage.from("training-chat").createSignedUrl(message.image_path, 3600);
      if (data?.signedUrl) { const link = document.createElement("a"); link.href = data.signedUrl; link.target = "_blank"; link.rel = "noopener noreferrer"; const image = document.createElement("img"); image.src = data.signedUrl; image.alt = "صورة مرسلة في المحادثة"; image.loading = "lazy"; link.append(image); bubble.append(link); }
    }
    const meta = document.createElement("small"); meta.textContent = new Intl.DateTimeFormat("ar-IQ", { hour: "numeric", minute: "2-digit" }).format(new Date(message.created_at)); bubble.append(meta); messagesBox.append(bubble); scrollMessages();
  }

  function scrollMessages() { requestAnimationFrame(() => { messagesBox.scrollTop = messagesBox.scrollHeight; }); }
  function resetImage() { state.file = null; imageInput.value = ""; imagePreview.hidden = true; imagePreview.querySelector("span").textContent = ""; }
  imageInput.addEventListener("change", () => {
    const file = imageInput.files?.[0]; if (!file) return resetImage();
    if (!["image/jpeg", "image/png", "image/webp"].includes(file.type) || file.size > 5 * 1024 * 1024) { resetImage(); toast("اختر صورة JPG أو PNG أو WebP بحجم لا يتجاوز 5 ميغابايت"); return; }
    state.file = file; imagePreview.hidden = false; imagePreview.querySelector("span").textContent = `📷 ${file.name}`;
  });
  imagePreview.querySelector("button").addEventListener("click", resetImage);
  document.querySelectorAll("[data-question]").forEach((button) => button.addEventListener("click", () => { chatText.value = button.dataset.question; chatText.focus(); }));

  $("#chatComposer").addEventListener("submit", async (event) => {
    event.preventDefault(); const subscription = state.active, body = chatText.value.trim(), file = state.file;
    if (!subscription || !isActive(subscription) || (!body && !file)) return;
    const submit = event.currentTarget.querySelector(".send-message"); submit.disabled = true; submit.textContent = "جارٍ الإرسال…"; let imagePath = null;
    try {
      if (file) { const extension = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" }[file.type]; imagePath = `${subscription.id}/${state.user.id}/${crypto.randomUUID()}.${extension}`; const { error } = await client.storage.from("training-chat").upload(imagePath, file, { contentType: file.type, upsert: false }); if (error) throw error; }
      const { data, error } = await client.from("training_messages").insert({ subscription_id: subscription.id, sender_id: state.user.id, body: body || null, image_path: imagePath, message_type: body && imagePath ? "mixed" : imagePath ? "image" : "text" }).select("id,subscription_id,sender_id,body,image_path,message_type,created_at").single(); if (error) throw error;
      chatText.value = ""; resetImage(); await appendMessage(data);
    } catch (_) { toast("لم تُرسل الرسالة. تأكد من أن الاشتراك ما زال فعالاً"); }
    finally { submit.disabled = false; submit.textContent = "إرسال"; }
  });

  async function loadPublicPrograms() {
    const { data, error } = await client.from("training_programs").select("id,slug,title,description,coach_name,coach_id,price_iqd,billing_period,sessions_count,max_trainees,is_online,training_coaches(display_name)").eq("is_active", true).not("coach_id", "is", null).order("created_at", { ascending: false });
    if (error) { programs.online = []; programs.inperson = []; renderPrograms(); return; }
    const mapProgram = (item, index) => ({
      icon: item.is_online ? "🏋️" : "⚽", tag: item.is_online ? "تدريب · أونلاين" : "تدريب · حضوري", title: item.title,
      coach: item.training_coaches?.display_name || item.coach_name || "كابتن NextMove", rating: "جديد",
      place: `${item.sessions_count} حصص · حتى ${item.max_trainees} مشتركاً`,
      description: item.description || (item.is_online ? "خطة تدريب أونلاين مع متابعة خاصة عبر الشات والصور." : "برنامج تدريب حضوري مع كابتن معتمد."),
      price: `${Number(item.price_iqd).toLocaleString("ar-IQ")} د.ع / ${{ week: "أسبوع", month: "شهر", session: "حصة" }[item.billing_period] || "اشتراك"}`,
      image: fallbackImages[index % fallbackImages.length], slug: item.slug
    });
    programs.online = (data || []).filter(item => item.is_online).map(mapProgram);
    programs.inperson = (data || []).filter(item => !item.is_online).map(mapProgram);
    renderPrograms();
  }

  renderPrograms = function () {
    const items = programs[currentMode];
    $("#trainingGrid").innerHTML = items.length ? items.map((program, index) => `<article class="training-card"><div class="training-image"><img src="${program.image}" alt="${program.title}" loading="lazy"><span>${program.icon} ${program.tag}</span></div><div class="training-copy"><div class="coach-line"><small>${program.coach}</small><b>★ ${program.rating}</b></div><h3>${program.title}</h3><p>${program.description}</p><div class="program-meta"><span>⌖ ${program.place}</span><strong>${program.price}</strong></div><button onclick="openBooking(${index})">${currentMode === "online" ? "اشترك وابدأ المتابعة" : "احجز مع المدرب"}</button>${currentMode === "online" ? '<small class="chat-included">✓ يشمل الشات والصور بعد التفعيل</small>' : ""}</div></article>`).join("") : '<div class="chat-loading"><span>✓</span><div><b>لا توجد برامج معتمدة في هذا القسم حاليًا</b><p>تظهر البرامج هنا فور نشرها من كابتن مفعّل رسميًا.</p></div></div>';
  };

  submitBooking = async function (event) {
    event.preventDefault(); const mode = $("#selectedMode").value;
    if (mode !== "online") {
      const { data: { session } } = await client.auth.getSession();
      if (!session?.user) { toast("سجّل الدخول أولاً لإرسال طلب الحجز رسميًا"); setTimeout(() => { location.href = "index.html#top"; }, 1400); return; }
      const submit = event.submitter || event.currentTarget.querySelector("button:not(.close)"); submit.disabled = true; submit.textContent = "جارٍ تسجيل الحجز…";
      try {
        const phone = $("#traineePhone").value.trim().replace(/[\s()-]/g, "");
        const { error } = await client.from("training_booking_requests").insert({
          trainee_id: session.user.id,
          program_title: $("#selectedProgram").value,
          trainee_name: $("#traineeName").value.trim(),
          trainee_phone: phone,
          training_date: $("#trainingDate").value,
          training_time: $("#trainingTime").value,
          notes: $("#trainingNotes").value.trim(),
        });
        if (error) throw error;
        closeBooking(); event.target.reset(); toast("تم تسجيل طلب التدريب رسميًا وربطه بحسابك");
      } catch (_) { toast("تعذر تسجيل الحجز. تحقق من البيانات وحاول مرة أخرى"); }
      finally { submit.disabled = false; submit.textContent = "إرسال طلب التدريب"; }
      return;
    }
    const { data: { session } } = await client.auth.getSession();
    if (!session?.user) { toast("سجّل الدخول أولاً لإرسال طلب الاشتراك وفتح الشات"); setTimeout(() => { location.href = "index.html#top"; }, 1400); return; }
    const selected = programs.online.find((item) => item.title === $("#selectedProgram").value), submit = event.submitter || event.currentTarget.querySelector("button:not(.close)"); submit.disabled = true; submit.textContent = "جارٍ إرسال الطلب…";
    try {
      const { data: program, error: programError } = await client.from("training_programs").select("id,coach_id").eq("slug", selected.slug).single(); if (programError) throw programError;
      const { error } = await client.from("training_subscriptions").insert({ trainee_id: session.user.id, trainee_name: $("#traineeName").value.trim(), program_id: program.id, coach_id: program.coach_id });
      if (error?.code === "23505") { closeBooking(); toast("لديك طلب أو اشتراك قائم بالفعل لهذا البرنامج"); await loadTrainingAccess(); return; }
      if (error) throw error; closeBooking(); event.target.reset(); toast("تم إرسال طلب الاشتراك. سيُفتح شات الكابتن بعد التفعيل"); await loadTrainingAccess(); $("#onlineCoaching").scrollIntoView({ behavior: "smooth" });
    } catch (_) { toast("تعذر إرسال طلب الاشتراك حالياً. حاول مرة أخرى"); }
    finally { submit.disabled = false; submit.textContent = "إرسال طلب التدريب"; }
  };

  client.auth.onAuthStateChange(() => setTimeout(loadTrainingAccess, 0));
  window.addEventListener("beforeunload", stopRealtime);
  renderPrograms(); loadPublicPrograms(); loadTrainingAccess();
})();
