// Static particle frames for the install DMG backgrounds: the Arkt mote language (sparse dust, the mustard mark, the
// wave), drawn once with a seeded generator. No animation. Canvas 2D, 660 x 420 pt.
const MODE = location.hash === "#dark" ? "dark" : "light";
const DARK = MODE === "dark";
const BRAND = { mustard: [233, 181, 32], highlight: [243, 202, 61], shade: [220, 163, 25], fold: [169, 110, 18], porcelain: [250, 249, 245], graphite: [32, 35, 33] };
const FIELD = DARK ? BRAND.graphite : BRAND.porcelain;
const INK = DARK ? BRAND.porcelain : BRAND.graphite;
const W = 660, H = 420;

function rng(seed) { let s = seed >>> 0 || 1; return () => { s ^= s << 13; s ^= s >>> 17; s ^= s << 5; return ((s >>> 0) % 1e9) / 1e9; }; }
const rand = rng(20260);
const rgba = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;

const cv = document.createElement("canvas");
cv.style.cssText = "position:absolute;left:0;top:0;width:660px;height:420px";
document.body.prepend(cv);
const dpr = Math.min(2, window.devicePixelRatio || 1);
cv.width = W * dpr; cv.height = H * dpr;
const g = cv.getContext("2d");
g.scale(dpr, dpr);
g.fillStyle = rgba(FIELD, 1); g.fillRect(0, 0, W, H);

function dot(x, y, r, c, a) { g.fillStyle = rgba(c, a); g.beginPath(); g.arc(x, y, r, 0, 6.2832); g.fill(); }

// Calm zones: rectangles where dust is thinned out so labels and text stay quiet.
function calm(x, y, zones) { let k = 1; for (const [x0, y0, x1, y1, keep] of zones) if (x > x0 && x < x1 && y > y0 && y < y1) k = Math.min(k, keep); return k; }

// Sparse dust across the whole window, like Welcome's field. A few specks carry mustard.
function dust(n, zones = []) {
  for (let i = 0; i < n; i++) {
    const x = rand() * W, y = rand() * H, r = 0.3 + rand() * rand() * 0.9;
    const keep = calm(x, y, zones);
    if (rand() > keep) continue;
    if (rand() < 0.12) dot(x, y, r * 1.05, DARK ? BRAND.mustard : BRAND.fold, DARK ? 0.5 : 0.55);
    else dot(x, y, r, INK, (DARK ? 0.10 : 0.12) + rand() * (DARK ? 0.22 : 0.28));
  }
}

// A band of mustard motes along y = f(x), thickest in the middle of x range [x0, x1].
function wave(f, x0, x1, n, spread, env, zones = []) {
  for (let i = 0; i < n; i++) {
    const x = x0 + rand() * (x1 - x0), u = (x - x0) / (x1 - x0), e = env(u);
    if (rand() > e) continue;
    const gauss = (rand() + rand() + rand() - 1.5) * 2;
    const y = f(x) + gauss * spread * (0.4 + e);
    if (rand() > calm(x, y, zones)) continue;
    const c = [BRAND.mustard, BRAND.highlight, BRAND.shade, BRAND.fold][(rand() * (DARK ? 3 : 4)) | 0];
    dot(x, y, 0.3 + rand() * rand() * 1.0, c, (DARK ? 0.55 : 0.7) * (0.35 + 0.65 * e));
  }
}
