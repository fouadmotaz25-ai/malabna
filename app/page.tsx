"use client";

import { FormEvent, useMemo, useState } from "react";

const stadiums = [
  { id: 1, name: "ملعب النخيل الرياضي", area: "المنصور، بغداد", price: 45000, rating: 4.9, size: "خماسي", image: "https://images.unsplash.com/photo-1574629810360-7efbbe195018?auto=format&fit=crop&w=1200&q=85", features: ["عشب احترافي", "إنارة ليلية", "مواقف"] },
  { id: 2, name: "أرينا الجادرية", area: "الجادرية، بغداد", price: 60000, rating: 4.8, size: "سباعي", image: "https://images.unsplash.com/photo-1551958219-acbc608c6377?auto=format&fit=crop&w=1200&q=85", features: ["مكيّف", "غرف تبديل", "كافتيريا"] },
  { id: 3, name: "ملعب الأبطال", area: "زيونة، بغداد", price: 35000, rating: 4.7, size: "خماسي", image: "https://images.unsplash.com/photo-1459865264687-595d652de67e?auto=format&fit=crop&w=1200&q=85", features: ["عشب جديد", "تصوير", "كرة مجانية"] },
];

const times = ["05:00 م", "06:00 م", "07:00 م", "08:00 م", "09:00 م"];

export default function Home() {
  const [modal, setModal] = useState<"login" | "signup" | "booking" | null>(null);
  const [selected, setSelected] = useState(stadiums[0]);
  const [time, setTime] = useState("07:00 م");
  const [toast, setToast] = useState("");
  const [query, setQuery] = useState("");

  const filtered = useMemo(() => stadiums.filter(s => `${s.name} ${s.area}`.includes(query)), [query]);
  const showToast = (message: string) => { setToast(message); setTimeout(() => setToast(""), 3200); };
  const submitAuth = (e: FormEvent) => { e.preventDefault(); setModal(null); showToast(modal === "login" ? "أهلًا بعودتك! تم تسجيل الدخول بنجاح" : "تم إنشاء حسابك بنجاح، أهلًا بك في ملعبنا"); };
  const book = (stadium: typeof stadiums[0]) => { setSelected(stadium); setModal("booking"); };

  return (
    <main dir="rtl">
      <nav className="nav shell">
        <a className="brand" href="#top" aria-label="ملعبنا - الرئيسية"><span className="brand-ball">⚽</span><span>ملعبنا</span></a>
        <div className="nav-links"><a href="#stadiums">الملاعب</a><a href="#how">كيف يعمل؟</a><a href="#why">لماذا نحن؟</a></div>
        <div className="nav-actions"><button className="text-btn" onClick={() => setModal("login")}>تسجيل الدخول</button><button className="primary small" onClick={() => setModal("signup")}>أنشئ حسابًا</button></div>
      </nav>

      <section className="hero" id="top">
        <div className="hero-overlay" />
        <div className="shell hero-content">
          <div className="eyebrow"><span /> ألعب أكثر، ابحث أقل</div>
          <h1>ملعبك جاهز.<br/><em>والكرة بانتظارك.</em></h1>
          <p>اكتشف أفضل ملاعب كرة القدم بالقرب منك، اختر الوقت المناسب واحجز خلال أقل من دقيقة.</p>
          <div className="search-box">
            <label><span>⌖</span><div><small>ابحث عن ملعب أو منطقة</small><input value={query} onChange={e => setQuery(e.target.value)} placeholder="مثلاً: المنصور، الجادرية..." /></div></label>
            <label className="date-label"><span>□</span><div><small>التاريخ</small><input type="date" defaultValue="2026-08-12" /></div></label>
            <a className="primary search-button" href="#stadiums">ابحث الآن <b>←</b></a>
          </div>
          <div className="trust-row"><span>✓ حجز فوري ومؤكد</span><span>✓ بدون رسوم خفية</span><span>✓ دعم متواصل</span></div>
        </div>
      </section>

      <section className="stats shell" aria-label="إحصائيات المنصة">
        <div><strong>+120</strong><span>ملعب موثّق</span></div><i/><div><strong>+8,500</strong><span>حجز ناجح</span></div><i/><div><strong>4.9</strong><span>متوسط التقييم</span></div><i/><div><strong>24/7</strong><span>دعم اللاعبين</span></div>
      </section>

      <section className="section shell" id="stadiums">
        <div className="section-head"><div><span className="kicker">ملاعب مختارة</span><h2>الأقرب إليك والأعلى تقييمًا</h2></div><button className="all-btn">عرض كل الملاعب ←</button></div>
        <div className="cards">
          {filtered.map((s, i) => <article className="stadium-card" key={s.id}>
            <div className="card-image"><img src={s.image} alt={s.name}/><span className="available">متاح اليوم</span><button className="heart" aria-label="أضف للمفضلة">♡</button><div className="rating">★ {s.rating}</div></div>
            <div className="card-body"><div className="card-title"><div><h3>{s.name}</h3><p>⌖ {s.area}</p></div><span>{s.size}</span></div><div className="chips">{s.features.map(f => <small key={f}>✓ {f}</small>)}</div><div className="card-footer"><div><small>ابتداءً من</small><strong>{s.price.toLocaleString("ar-IQ")} <em>د.ع / ساعة</em></strong></div><button onClick={() => book(s)}>احجز الآن</button></div></div>
          </article>)}
          {!filtered.length && <div className="empty">لا توجد ملاعب مطابقة. جرّب البحث باسم منطقة أخرى.</div>}
        </div>
      </section>

      <section className="how" id="how"><div className="shell"><div className="center-head"><span className="kicker">ثلاث خطوات فقط</span><h2>من البحث إلى الملعب بسهولة</h2><p>نسهّل عليك كل شيء لتتفرغ للعب والمنافسة.</p></div><div className="steps">
        <div><b>01</b><span className="step-icon">⌕</span><h3>ابحث واختر</h3><p>تصفّح الملاعب حسب المنطقة والسعر والتقييم.</p></div><div className="step-line"/><div><b>02</b><span className="step-icon">▣</span><h3>حدّد موعدك</h3><p>اختر اليوم والساعة المناسبة لفريقك.</p></div><div className="step-line"/><div><b>03</b><span className="step-icon">✓</span><h3>أكد الحجز والعب</h3><p>استلم تأكيدك فورًا وتوجّه إلى الملعب.</p></div>
      </div></div></section>

      <section className="why shell" id="why"><div className="why-copy"><span className="kicker">تجربة صُنعت للاعبين</span><h2>كل ما تحتاجه لمباراتك القادمة</h2><p>منصة واحدة تجمع لك أفضل الملاعب، الأوقات المتاحة والأسعار الواضحة. لا اتصالات طويلة ولا انتظار.</p><ul><li><b>تأكيد فوري</b><span>يصلك تأكيد الحجز وتفاصيل الموقع مباشرة.</span></li><li><b>ملاعب موثّقة</b><span>نراجع جودة الملاعب والخدمات قبل إضافتها.</span></li><li><b>دفع آمن ومرن</b><span>ادفع بالطريقة التي تناسبك بكل أمان.</span></li></ul></div><div className="why-photo"><img src="https://images.unsplash.com/photo-1517466787929-bc90951d0974?auto=format&fit=crop&w=1200&q=90" alt="لاعبو كرة قدم في الملعب"/><div className="quote">“الحجز صار أسرع من تجهيز الفريق!”<span>— أحمد، لاعب أسبوعي</span></div></div></section>

      <section className="cta"><div className="shell"><div><span>⚽</span><h2>جاهز للمباراة القادمة؟</h2><p>اجمع فريقك، اختر ملعبك، والباقي علينا.</p></div><a href="#stadiums" className="light-btn">استكشف الملاعب <b>←</b></a></div></section>
      <footer><div className="shell footer-grid"><div><a className="brand light" href="#top"><span className="brand-ball">⚽</span><span>ملعبنا</span></a><p>أسهل طريقة لحجز ملاعب كرة القدم في مدينتك.</p></div><div><h4>المنصة</h4><a href="#stadiums">اكتشف الملاعب</a><a href="#how">كيف يعمل؟</a><a href="#">أضف ملعبك</a></div><div><h4>المساعدة</h4><a href="#">الأسئلة الشائعة</a><a href="#">تواصل معنا</a><a href="#">سياسة الإلغاء</a></div><div><h4>تابعنا</h4><p>Instagram &nbsp; X &nbsp; Facebook</p></div></div><div className="copyright shell">© 2026 ملعبنا. جميع الحقوق محفوظة. <span>صُنع بشغف للكرة ⚽</span></div></footer>

      {modal && <div className="modal-backdrop" onMouseDown={() => setModal(null)}><section className="modal" onMouseDown={e => e.stopPropagation()} role="dialog" aria-modal="true">
        <button className="close" onClick={() => setModal(null)}>×</button>
        {modal === "booking" ? <><div className="modal-icon">⚽</div><h2>أكّد حجزك</h2><p className="muted">{selected.name} · {selected.area}</p><div className="booking-date"><span>الأربعاء، 12 أغسطس</span><b>{selected.price.toLocaleString("ar-IQ")} د.ع</b></div><label className="field-label">اختر الوقت</label><div className="time-grid">{times.map(t => <button className={time === t ? "active" : ""} onClick={() => setTime(t)} key={t}>{t}</button>)}</div><button className="primary full" onClick={() => { setModal(null); showToast(`تم حجز ${selected.name} الساعة ${time}`); }}>تأكيد الحجز</button></> : <form onSubmit={submitAuth}><div className="modal-icon">⚽</div><h2>{modal === "login" ? "أهلًا بعودتك" : "ابدأ اللعب معنا"}</h2><p className="muted">{modal === "login" ? "سجّل دخولك لإدارة حجوزاتك" : "أنشئ حسابك واحجز ملعبك الأول"}</p>{modal === "signup" && <label>الاسم الكامل<input required placeholder="مثلاً: محمد علي" /></label>}<label>رقم الهاتف<input required type="tel" placeholder="07XX XXX XXXX" /></label><label>كلمة المرور<input required type="password" placeholder="••••••••" /></label>{modal === "signup" && <label className="check"><input type="checkbox" required/> أوافق على الشروط وسياسة الخصوصية</label>}<button className="primary full" type="submit">{modal === "login" ? "تسجيل الدخول" : "إنشاء حساب"}</button><p className="switch">{modal === "login" ? "ليس لديك حساب؟ " : "لديك حساب بالفعل؟ "}<button type="button" onClick={() => setModal(modal === "login" ? "signup" : "login")}>{modal === "login" ? "أنشئ حسابًا" : "سجّل الدخول"}</button></p></form>}
      </section></div>}
      {toast && <div className="toast"><b>✓</b>{toast}</div>}
    </main>
  );
}
