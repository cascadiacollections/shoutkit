/* One-time 2026 campaign. Dates are Pacific time; no analytics or requests. */
(() => {
  "use strict";
  const promo = document.querySelector(".halloween-promo");
  if (!promo) return;
  const start = Date.parse("2026-10-25T00:00:00-07:00");
  const end = Date.parse("2026-11-01T00:00:00-07:00");
  let timer;
  const update = () => {
    clearTimeout(timer);
    const now = Date.now();
    promo.hidden = now < start || now >= end;
    const next = now < start ? start : end;
    if (now < next) timer = setTimeout(update, Math.min(next - now, 86400000));
  };
  document.addEventListener("visibilitychange", update);
  update();
})();
