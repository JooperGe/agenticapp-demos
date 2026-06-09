/* ═══════════════════════════════════
   Restage · ideas.js
   Ideas strip dot-indicator sync
   ═══════════════════════════════════ */
(function () {
  const strip = document.getElementById('ideasStrip');
  const dots  = document.querySelectorAll('#ideaDots span');
  if (!strip || !dots.length) return;
  strip.addEventListener('scroll', () => {
    const idx = Math.round(strip.scrollLeft / strip.clientWidth);
    dots.forEach((d, i) => d.classList.toggle('active', i === idx));
  });
})();
