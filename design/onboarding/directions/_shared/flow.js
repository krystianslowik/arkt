// Shared plumbing for the direction prototypes: query parameters for review captures, word splitting for the
// website's word reveal, step switching and the live count.
//   ?step=welcome|import   start on a step
//   ?theme=light|dark      force the appearance (otherwise the system's)
//   ?still=1               settle every formation and freeze time, for screenshots

export const params = new URLSearchParams(location.search);

export function setup() {
  const theme = params.get('theme');
  if (theme) document.documentElement.dataset.theme = theme;
  const still = params.has('still');
  if (still) document.documentElement.classList.add('still');
  const dark = theme ? theme === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  return { still, dark, reduced, step: params.get('step') || 'welcome' };
}

// Wrap each word so it can resolve on its own, 45 ms apart, as on arkt.dev
export function splitWords(root = document) {
  root.querySelectorAll('[data-split]').forEach((el) => {
    const words = el.textContent.trim().split(/\s+/);
    el.setAttribute('aria-label', el.textContent.trim());
    el.innerHTML = words.map((w, i) => `<span class="w" aria-hidden="true" style="--i:${i}">${w}</span>`).join(' ');
  });
}

export function show(name) {
  document.querySelectorAll('.step').forEach((s) => s.classList.toggle('on', s.dataset.step === name));
  document.body.dataset.step = name;
}

// Return runs the step's primary action, the way a default button does on macOS. No focus ring is forced onto it.
addEventListener('keydown', (e) => {
  if (e.key !== 'Enter' || e.target.closest('button, a, input')) return;
  document.querySelector('.step.on [data-autofocus]')?.click();
});

// Captures wait for this flag
export const ready = () => { document.documentElement.dataset.ready = '1'; };

// The read-only counting pass. Numbers rise as Arkt finds items; onValue fires for every change.
export function liveCount(targets, { still, duration = 1600, onValue }) {
  const keys = Object.keys(targets);
  if (still) { keys.forEach((k) => onValue(k, targets[k], true)); return; }
  const t0 = performance.now();
  const cur = Object.fromEntries(keys.map((k) => [k, -1]));
  function tick(now) {
    const p = Math.min(1, (now - t0) / duration);
    const e = 1 - Math.pow(1 - p, 3);
    keys.forEach((k, j) => {
      const local = Math.min(1, Math.max(0, e * 1.25 - j * 0.08));
      const v = Math.round(targets[k] * local);
      if (v !== cur[k]) { cur[k] = v; onValue(k, v, p === 1); }
    });
    if (p < 1) requestAnimationFrame(tick); else keys.forEach((k) => onValue(k, targets[k], true));
  }
  requestAnimationFrame(tick);
}

// The sample Arc profile every direction counts. Counts only, as the importer reports them.
export const ARC = { spaces: 4, pinned: 37, favorites: 12, folders: 9 };
export const ARC_SPACES = [['#f2eae4', '#f29bbb'], ['#e0f2fb', '#c5c6e2'], ['#2d4468', '#120f2e'], ['#f7eed2', '#ebd592']];
