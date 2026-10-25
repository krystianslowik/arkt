// The stage: one field of motes for the whole first run, the same system as arkt.dev's world.
// Every mote is a spring toward a target, so a new formation can arrive at any moment and the motion picks up from
// where each mote is, with its velocity. Motes keep drifting inside a formation. Rendered as WebGL2 point sprites
// with the website's soft disc (smoothstep 0.5 -> 0.18).

export const hex = (h) => { const n = parseInt(h.slice(1), 16); return [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255]; };
export const BRAND = { mustard: hex('#e9b520'), highlight: hex('#f3ca3d'), shade: hex('#dca319'), fold: hex('#a96e12') };

// Spring presets from Motion/SpringPreset.swift: damping ratio, response in seconds.
export const SPRING = { firm: [0.9, 0.25], firmSlow: [0.9, 0.35], gather: [0.86, 0.9], drift: [0.9, 1.25] };

export function seeded(seed = 7) {
  let s = seed >>> 0 || 1;
  return () => { s ^= s << 13; s ^= s >>> 17; s ^= s << 5; return ((s >>> 0) % 1e9) / 1e9; };
}

export function createField(canvas, { count = 16000, still = false, reduced = false } = {}) {
  const gl = canvas.getContext('webgl2', { alpha: true, premultipliedAlpha: false, antialias: false, preserveDrawingBuffer: true });
  if (!gl) throw new Error('WebGL2 needed');
  const N = count;
  const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s)); return s; };
  const prog = gl.createProgram();
  gl.attachShader(prog, sh(gl.VERTEX_SHADER, `#version 300 es
    in vec2 aPos; in float aSize; in vec4 aCol;
    uniform vec2 uView; uniform float uDpr;
    out vec4 vCol;
    void main() {
      vec2 p = aPos / uView * 2.0 - 1.0;
      gl_Position = vec4(p.x, -p.y, 0.0, 1.0);
      gl_PointSize = aSize * uDpr;
      vCol = aCol;
    }`));
  gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, `#version 300 es
    precision mediump float;
    in vec4 vCol; out vec4 o;
    void main() {
      float d = length(gl_PointCoord - 0.5);
      if (d > 0.5) discard;
      o = vec4(vCol.rgb, vCol.a * smoothstep(0.5, 0.18, d));
    }`));
  gl.linkProgram(prog);
  gl.useProgram(prog);
  const STRIDE = 7;
  const buf = new Float32Array(N * STRIDE);
  const vbo = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
  gl.bufferData(gl.ARRAY_BUFFER, buf.byteLength, gl.DYNAMIC_DRAW);
  const attr = (name, size, off) => { const l = gl.getAttribLocation(prog, name); gl.enableVertexAttribArray(l); gl.vertexAttribPointer(l, size, gl.FLOAT, false, STRIDE * 4, off * 4); };
  attr('aPos', 2, 0); attr('aSize', 1, 2); attr('aCol', 4, 3);
  const uView = gl.getUniformLocation(prog, 'uView'), uDpr = gl.getUniformLocation(prog, 'uDpr');
  gl.enable(gl.BLEND);
  gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);

  // State, one slot per mote
  const x = new Float32Array(N), y = new Float32Array(N), vx = new Float32Array(N), vy = new Float32Array(N);
  const tx = new Float32Array(N), ty = new Float32Array(N), drift = new Float32Array(N), start = new Float32Array(N);
  const k = new Float32Array(N), c = new Float32Array(N);
  const col = new Float32Array(N * 4), tcol = new Float32Array(N * 4), size = new Float32Array(N), tsize = new Float32Array(N);
  const seed = new Float32Array(N);
  const r0 = seeded(11);
  let W = 0, H = 0, dpr = 1;
  for (let i = 0; i < N; i++) { seed[i] = r0(); }

  const field = { N, ink: [0.125, 0.137, 0.129], dark: false, time: 0, onFrame: null };

  function resize() {
    dpr = Math.min(2, devicePixelRatio || 1);
    W = canvas.clientWidth; H = canvas.clientHeight;
    canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.uniform2f(uView, W, H); gl.uniform1f(uDpr, dpr);
  }
  resize();
  field.size = () => ({ W, H });
  addEventListener('resize', () => { resize(); field.relayout?.(); });

  // Scatter everything as an ambient cloud before the first formation
  for (let i = 0; i < N; i++) {
    x[i] = r0() * W; y[i] = r0() * H; tx[i] = x[i]; ty[i] = y[i];
    size[i] = tsize[i] = 1 + r0() * 2; col.set([...field.ink, 0], i * 4); tcol.set([...field.ink, 0], i * 4);
  }

  // form(fn): fn(i, rnd) returns { x, y, a, c ('ink' | 'accent' | [r,g,b]), s, drift, delay (s), spring [zeta, resp] }
  field.form = (fn, { at = 0, only = null, retarget = false } = {}) => {
    const rnd = seeded(97);
    const now = field.time;
    for (let i = 0; i < N; i++) {
      if (only && !only(i)) continue;
      const p = fn(i, rnd);
      tx[i] = p.x; ty[i] = p.y;
      const cc = p.c === 'accent' ? BRAND.mustard : p.c === 'ink' || !p.c ? field.ink : p.c;
      tcol[i * 4] = cc[0]; tcol[i * 4 + 1] = cc[1]; tcol[i * 4 + 2] = cc[2]; tcol[i * 4 + 3] = p.a ?? 0.3;
      tsize[i] = p.s ?? 1.6;
      drift[i] = p.drift ?? 1.2;
      // A retarget (a live number changing) only moves the target; each mote keeps its place in the stagger
      if (!retarget) start[i] = now + at + (p.delay ?? 0);
      const [z, resp] = p.spring || SPRING.gather;
      const w = 2 * Math.PI / resp;
      k[i] = w * w; c[i] = 2 * z * w;
    }
    if (reduced || still) field.settle(reduced && !still, only);
  };

  // Jump to the formation. Under Reduce Motion nothing travels: motes fade out, move, and fade back in.
  field.settle = (fade = false, only = null) => {
    for (let i = 0; i < N; i++) {
      if (only && !only(i)) continue;
      x[i] = tx[i]; y[i] = ty[i]; vx[i] = vy[i] = 0; size[i] = tsize[i]; start[i] = 0;
      for (let j = 0; j < 3; j++) col[i * 4 + j] = tcol[i * 4 + j];
      col[i * 4 + 3] = fade ? 0 : tcol[i * 4 + 3];
    }
  };

  // A kick: motes near (px, py) get pushed outward, then their springs bring them home
  field.kick = (px, py, strength = 900, radius = 260) => {
    if (reduced) return;
    for (let i = 0; i < N; i++) {
      const dx = x[i] - px, dy = y[i] - py, d = Math.hypot(dx, dy) + 1;
      if (d > radius) continue;
      const f = strength * (1 - d / radius) / d;
      vx[i] += dx * f; vy[i] += dy * f;
    }
  };

  function step(dt, t) {
    const ca = 1 - Math.exp(-dt * (reduced ? 5 : 3.2));
    for (let i = 0; i < N; i++) {
      const s = seed[i];
      const dr = drift[i];
      const ox = dr * Math.sin(t * (0.35 + s * 0.5) + s * 40), oy = dr * Math.cos(t * (0.3 + s * 0.45) + s * 23);
      if (t >= start[i]) {
        const ax = k[i] * (tx[i] + ox - x[i]) - c[i] * vx[i];
        const ay = k[i] * (ty[i] + oy - y[i]) - c[i] * vy[i];
        vx[i] += ax * dt; vy[i] += ay * dt;
        for (let j = 0; j < 4; j++) col[i * 4 + j] += (tcol[i * 4 + j] - col[i * 4 + j]) * ca;
        size[i] += (tsize[i] - size[i]) * ca;
      } else { vx[i] *= 0.96; vy[i] *= 0.96; }
      x[i] += vx[i] * dt; y[i] += vy[i] * dt;
    }
  }

  function draw() {
    for (let i = 0; i < N; i++) {
      const o = i * STRIDE;
      buf[o] = x[i]; buf[o + 1] = y[i]; buf[o + 2] = size[i];
      buf[o + 3] = col[i * 4]; buf[o + 4] = col[i * 4 + 1]; buf[o + 5] = col[i * 4 + 2]; buf[o + 6] = col[i * 4 + 3];
    }
    gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT);
    gl.bufferSubData(gl.ARRAY_BUFFER, 0, buf);
    gl.drawArrays(gl.POINTS, 0, N);
  }

  let last = performance.now();
  function frame(now) {
    const dt = Math.min(0.05, (now - last) / 1000); last = now;
    if (!still) {
      // Sub-step at 240 Hz or finer so stiff springs stay stable on a 120 Hz display
      const n = Math.max(1, Math.ceil(dt / (1 / 240)));
      for (let s = 0; s < n; s++) { field.time += dt / n; step(dt / n, field.time); }
    }
    field.onFrame?.(field.time);
    draw();
    if (!still) requestAnimationFrame(frame);
  }
  field.start = () => requestAnimationFrame(frame);
  field.renderStill = (t = 4) => { field.time = t; step(0, t); draw(); };
  return field;
}

// Samplers. Shapes come from real things: the approved logo pixels, real type, the sidebar's real geometry.

const loadImage = async (src) => { const img = new Image(); img.src = src; await img.decode(); return img; };

// Points from an image, centred, scaled to a height of 1. Each keeps its own pixel colour.
export async function imagePoints(src, width, keep = (r, g, b, a) => a > 128) {
  const img = await loadImage(src);
  const cv = document.createElement('canvas');
  cv.width = width; cv.height = Math.round(width * img.naturalHeight / img.naturalWidth);
  const cx = cv.getContext('2d', { willReadFrequently: true });
  cx.drawImage(img, 0, 0, cv.width, cv.height);
  const d = cx.getImageData(0, 0, cv.width, cv.height).data;
  const pts = []; let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
  for (let yy = 0; yy < cv.height; yy++) for (let xx = 0; xx < cv.width; xx++) {
    const o = (yy * cv.width + xx) * 4;
    if (!keep(d[o], d[o + 1], d[o + 2], d[o + 3])) continue;
    pts.push([xx, yy, d[o] / 255, d[o + 1] / 255, d[o + 2] / 255]);
    x0 = Math.min(x0, xx); x1 = Math.max(x1, xx); y0 = Math.min(y0, yy); y1 = Math.max(y1, yy);
  }
  const h = Math.max(1, y1 - y0), cxm = (x0 + x1) / 2, cym = (y0 + y1) / 2;
  return pts.map(([a, b, r, g, bl]) => ({ x: (a - cxm) / h, y: (b - cym) / h, c: [r, g, bl], aspect: (x1 - x0) / h }));
}

// Points from real type: text drawn in the brand face, sampled on a grid. Returns points in CSS px around the
// text's centre, plus its measured width and cap height.
export function textPoints(text, px, weight = 600, family = '"Avenir Next"', tracking = -0.04) {
  const cv = document.createElement('canvas');
  const cx = cv.getContext('2d', { willReadFrequently: true });
  const font = `${weight} ${px}px ${family}`;
  cx.font = font; cx.letterSpacing = `${tracking * px}px`;
  const w = Math.ceil(cx.measureText(text).width) + 8, h = Math.ceil(px * 1.2);
  cv.width = w; cv.height = h;
  cx.font = font; cx.letterSpacing = `${tracking * px}px`; cx.textBaseline = 'alphabetic'; cx.fillStyle = '#000';
  cx.fillText(text, 4, Math.round(px * 0.95));
  const d = cx.getImageData(0, 0, w, h).data;
  const pts = []; let y0 = 1e9, y1 = -1e9, x0 = 1e9, x1 = -1e9;
  const stepPx = Math.max(1, Math.round(px / 120));
  for (let yy = 0; yy < h; yy += stepPx) for (let xx = 0; xx < w; xx += stepPx) {
    if (d[(yy * w + xx) * 4 + 3] < 140) continue;
    pts.push([xx, yy]); x0 = Math.min(x0, xx); x1 = Math.max(x1, xx); y0 = Math.min(y0, yy); y1 = Math.max(y1, yy);
  }
  const mx = (x0 + x1) / 2, my = (y0 + y1) / 2;
  return { pts: pts.map(([a, b]) => ({ x: a - mx, y: b - my })), w: x1 - x0, h: y1 - y0 };
}

// A point inside (or on the edge of) a rounded rectangle centred at 0
export function roundRect(rnd, w, h, r, edge = false) {
  let px, py;
  for (;;) {
    px = (rnd() - 0.5) * w; py = (rnd() - 0.5) * h;
    const qx = Math.abs(px) - (w / 2 - r), qy = Math.abs(py) - (h / 2 - r);
    if (qx > 0 && qy > 0 && qx * qx + qy * qy > r * r) continue;
    break;
  }
  if (edge) {
    if (Math.abs(px) / w > Math.abs(py) / h) px = Math.sign(px) * w / 2; else py = Math.sign(py) * h / 2;
    const qx = Math.abs(px) - (w / 2 - r), qy = Math.abs(py) - (h / 2 - r);
    if (qx > 0 && qy > 0) {
      const ox = Math.sign(px) * (w / 2 - r), oy = Math.sign(py) * (h / 2 - r);
      const dx = px - ox, dy = py - oy, l = Math.hypot(dx, dy) || 1;
      px = ox + dx / l * r; py = oy + dy / l * r;
    }
  }
  return [px, py];
}

// The brand fold: a mustard ribbon that sweeps and flips once, shaded like the fold artwork. Projected from 3D.
const smooth = (a, b, v) => { const t = Math.min(1, Math.max(0, (v - a) / (b - a))); return t * t * (3 - 2 * t); };
const mix = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
export function foldPoint(rnd, centre, wk = 1) {
  const t = rnd();
  const w = rnd() < 0.22 ? (rnd() < 0.5 ? -1 : 1) * (0.92 + rnd() * 0.08) : rnd() * 2 - 1;
  const C = (u) => centre(Math.min(1, Math.max(0, u)));
  const c = C(t), a = C(t - 0.002), b = C(t + 0.002);
  let T = [b[0] - a[0], b[1] - a[1], b[2] - a[2]]; const tl = Math.hypot(...T); T = T.map((v) => v / tl);
  let D = [-T[2], 0, T[0]]; const dl = Math.hypot(...D) || 1; D = D.map((v) => v / dl); // T x up
  const U = [D[1] * T[2] - D[2] * T[1], D[2] * T[0] - D[0] * T[2], D[0] * T[1] - D[1] * T[0]];
  const th = Math.PI * smooth(0.4, 0.8, t);
  const Wv = U.map((u, j) => u * Math.cos(th) + D[j] * Math.sin(th));
  const width = w * (1.25 + 0.6 * t) * wk;
  const p = c.map((v, j) => v + Wv[j] * width);
  const facing = T[0] * Wv[1] - T[1] * Wv[0];
  const colr = facing < -0.05
    ? mix(BRAND.fold, BRAND.shade, 0.25 * (1 - Math.abs(w)))
    : mix(mix(BRAND.shade, BRAND.mustard, 0.55 + 0.45 * facing), BRAND.highlight, Math.max(0, Math.abs(w) - 0.82) * 4);
  return { p, c: colr };
}

// Perspective projection for the 3D shapes: camera at z = cam looking at the origin
export const project = (p, cx, cy, scale, cam = 9) => { const f = cam / (cam - p[2]); return [cx + p[0] * scale * f, cy - p[1] * scale * f, f]; };
