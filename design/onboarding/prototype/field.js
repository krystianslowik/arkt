// The stage: one field of motes for the whole first run, the same system as arkt.dev's world. This is the web
// stand-in for the native Metal layer (spec: "Particle field").
//
// Every mote is a spring toward a target. A new formation retargets from where each mote is, with its velocity, so
// any step change can be interrupted. Targets can rest (with a small drift) or ride a path (streams, orbits, paging).
// Rendered as WebGL2 point sprites with the website's soft disc (smoothstep 0.5 -> 0.18).

const hex = (h) => { const n = parseInt(h.slice(1), 16); return [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255]; };
const mix = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const BRAND = { mustard: hex('#e9b520'), highlight: hex('#f3ca3d'), shade: hex('#dca319'), fold: hex('#a96e12'), porcelain: hex('#faf9f5'), graphite: hex('#202321') };

// SpringPreset values: [damping ratio, response in seconds]
const SPRING = { firmFast: [0.95, 0.15], firm: [0.9, 0.25], firmSlow: [0.9, 0.35], gather: [0.88, 0.8], firmExtraSlow: [0.9, 1.25] };

function seeded(seed = 7) {
  let s = seed >>> 0 || 1;
  return () => { s ^= s << 13; s ^= s >>> 17; s ^= s << 5; return ((s >>> 0) % 1e9) / 1e9; };
}

function createField(canvas, opts = {}) {
  const { count = 16000, still = false, reduced = false, transparency = false, contrast = false, dark = false } = opts;
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
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(gl.ARRAY_BUFFER, buf.byteLength, gl.DYNAMIC_DRAW);
  const attr = (name, size, off) => { const l = gl.getAttribLocation(prog, name); gl.enableVertexAttribArray(l); gl.vertexAttribPointer(l, size, gl.FLOAT, false, STRIDE * 4, off * 4); };
  attr('aPos', 2, 0); attr('aSize', 1, 2); attr('aCol', 4, 3);
  const uView = gl.getUniformLocation(prog, 'uView'), uDpr = gl.getUniformLocation(prog, 'uDpr');
  gl.enable(gl.BLEND);
  // Dark surfaces glow additively, as on the website; Reduce Transparency turns that off
  if (dark && !transparency) gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ONE, gl.ONE);
  else gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);

  const x = new Float32Array(N), y = new Float32Array(N), vx = new Float32Array(N), vy = new Float32Array(N);
  const tx = new Float32Array(N), ty = new Float32Array(N), drift = new Float32Array(N), start = new Float32Array(N);
  const k = new Float32Array(N), c = new Float32Array(N), baseA = new Float32Array(N), pending = new Uint8Array(N);
  const col = new Float32Array(N * 4), tcol = new Float32Array(N * 4), size = new Float32Array(N), tsize = new Float32Array(N);
  const seed = new Float32Array(N), path = new Array(N).fill(null), rate = new Float32Array(N), phase = new Float32Array(N), env = new Uint8Array(N);
  const r0 = seeded(11);
  let W = 0, H = 0, dpr = 1;
  for (let i = 0; i < N; i++) seed[i] = r0();

  const field = { N, ink: dark ? BRAND.porcelain : BRAND.graphite, time: 0, frozenAt: 3.2 };

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

  for (let i = 0; i < N; i++) {
    x[i] = tx[i] = r0() * W; y[i] = ty[i] = r0() * H;
    size[i] = tsize[i] = 1 + r0() * 2; col.set([...field.ink, 0], i * 4); tcol.set([...field.ink, 0], i * 4);
  }

  // Accessibility floors (spec: Reduce Transparency, Increase Contrast)
  const floorA = (a, ambient) => {
    if (transparency && ambient) return 0;
    if (contrast && !ambient) return Math.max(a, 0.8);
    if (transparency && !ambient) return Math.max(a, 0.6);
    return a;
  };
  const resolve = (cc) => {
    if (cc === 'accent') return contrast && !dark ? BRAND.fold : BRAND.mustard;
    if (cc === 'ink' || !cc) return field.ink;
    return cc;
  };

  // form(fn): fn(i, rnd) -> { x, y, a, c, s, drift, delay, spring, ambient, path(u) -> [x, y], rate, phase, env }
  field.form = (fn, { only = null, retarget = false } = {}) => {
    const rnd = seeded(97);
    const now = field.time;
    for (let i = 0; i < N; i++) {
      if (only && !only(i)) continue;
      const p = fn(i, rnd);
      path[i] = p.path || null; rate[i] = p.rate || 0; phase[i] = p.phase ?? seed[i]; env[i] = p.env ? 1 : 0;
      if (p.path) { const [px, py] = p.path(phase[i], now); tx[i] = px; ty[i] = py; } else { tx[i] = p.x; ty[i] = p.y; }
      const cc = resolve(p.c);
      const a = floorA(p.a ?? 0.3, p.ambient);
      tcol[i * 4] = cc[0]; tcol[i * 4 + 1] = cc[1]; tcol[i * 4 + 2] = cc[2]; tcol[i * 4 + 3] = a; baseA[i] = a;
      tsize[i] = (p.s ?? 1.6) * (transparency && !p.ambient ? 1.15 : 1);
      drift[i] = p.drift ?? 1.2;
      if (!retarget) start[i] = now + (p.delay ?? 0);
      const [z, resp] = p.spring || SPRING.gather;
      const w = 2 * Math.PI / resp;
      k[i] = w * w; c[i] = 2 * z * w;
      // Reduce Motion: nothing travels. The mote fades out of the old shape and back in, in place, in the new one.
      if (reduced && !retarget) { pending[i] = 1; start[i] = now + seed[i] * 0.3; }
    }
    if (still) field.settle(only);
  };

  field.settle = (only = null) => {
    for (let i = 0; i < N; i++) {
      if (only && !only(i)) continue;
      if (path[i]) { const [px, py] = path[i](phaseAt(i, field.frozenAt), field.frozenAt); tx[i] = px; ty[i] = py; }
      x[i] = tx[i]; y[i] = ty[i]; vx[i] = vy[i] = 0; size[i] = tsize[i]; start[i] = 0; pending[i] = 0;
      for (let j = 0; j < 4; j++) col[i * 4 + j] = tcol[i * 4 + j];
      if (env[i]) col[i * 4 + 3] = baseA[i] * envelope(phaseAt(i, field.frozenAt));
    }
  };

  const phaseAt = (i, t) => (phase[i] + t * rate[i]) % 1;
  const envelope = (u) => Math.pow(Math.sin(Math.PI * u), 0.6);

  function step(dt, t) {
    const ca = 1 - Math.exp(-dt * 3.4);
    const clock = reduced ? field.frozenAt : t;
    for (let i = 0; i < N; i++) {
      if (t < start[i]) { vx[i] *= 0.97; vy[i] *= 0.97; x[i] += vx[i] * dt; y[i] += vy[i] * dt; continue; }
      if (path[i]) {
        const u = phaseAt(i, clock); const [px, py] = path[i](u, clock); tx[i] = px; ty[i] = py;
        if (env[i]) tcol[i * 4 + 3] = baseA[i] * envelope(u);
      }
      if (pending[i]) {
        col[i * 4 + 3] -= col[i * 4 + 3] * (1 - Math.exp(-dt * 9)) + dt * 0.4;
        if (col[i * 4 + 3] <= 0.01) { col[i * 4 + 3] = 0; x[i] = tx[i]; y[i] = ty[i]; vx[i] = vy[i] = 0; pending[i] = 0; for (let j = 0; j < 3; j++) col[i * 4 + j] = tcol[i * 4 + j]; size[i] = tsize[i]; }
        continue;
      }
      if (reduced) { x[i] = tx[i]; y[i] = ty[i]; col[i * 4 + 3] += (tcol[i * 4 + 3] - col[i * 4 + 3]) * (1 - Math.exp(-dt * 9)); continue; }
      const s = seed[i], dr = drift[i];
      const ox = dr * Math.sin(t * (0.35 + s * 0.5) + s * 40), oy = dr * Math.cos(t * (0.3 + s * 0.45) + s * 23);
      const ax = k[i] * (tx[i] + ox - x[i]) - c[i] * vx[i];
      const ay = k[i] * (ty[i] + oy - y[i]) - c[i] * vy[i];
      vx[i] += ax * dt; vy[i] += ay * dt;
      x[i] += vx[i] * dt; y[i] += vy[i] * dt;
      for (let j = 0; j < 4; j++) col[i * 4 + j] += (tcol[i * 4 + j] - col[i * 4 + j]) * ca;
      size[i] += (tsize[i] - size[i]) * ca;
    }
  }

  function draw() {
    for (let i = 0; i < N; i++) {
      const o = i * STRIDE;
      buf[o] = x[i]; buf[o + 1] = y[i]; buf[o + 2] = size[i];
      buf[o + 3] = col[i * 4]; buf[o + 4] = col[i * 4 + 1]; buf[o + 5] = col[i * 4 + 2]; buf[o + 6] = col[i * 4 + 3] * field.opacity;
    }
    gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT);
    gl.bufferSubData(gl.ARRAY_BUFFER, 0, buf);
    gl.drawArrays(gl.POINTS, 0, N);
  }
  field.opacity = 1;

  let last = performance.now(), running = false;
  function frame(now) {
    const dt = Math.min(1 / 30, (now - last) / 1000); last = now;
    const n = Math.max(1, Math.ceil(dt / (1 / 240)));
    for (let s = 0; s < n; s++) { field.time += dt / n; step(dt / n, field.time); }
    field.onFrame?.(field.time, dt);
    draw();
    if (running) requestAnimationFrame(frame);
  }
  field.start = () => { if (still || running) return; running = true; last = performance.now(); requestAnimationFrame(frame); };
  field.stop = () => { running = false; };
  field.renderStill = () => { field.time = field.frozenAt; draw(); };
  field.redraw = draw;
  return field;
}

// Samplers. Shapes come from real things: the approved logo pixels, real type, real geometry.

// Points from real type, around the text's centre, in CSS px
function textPoints(text, px, weight = 600, family = '"Avenir Next"', tracking = -0.04) {
  const cv = document.createElement('canvas');
  const cx = cv.getContext('2d', { willReadFrequently: true });
  const font = `${weight} ${px}px ${family}`;
  cx.font = font; cx.letterSpacing = `${tracking * px}px`;
  const w = Math.ceil(cx.measureText(text).width) + 8, h = Math.ceil(px * 1.25);
  cv.width = w; cv.height = h;
  cx.font = font; cx.letterSpacing = `${tracking * px}px`; cx.fillStyle = '#000';
  cx.fillText(text, 4, Math.round(px * 0.98));
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
function roundRect(rnd, w, h, r, edge = false) {
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

// The brand fold: a mustard ribbon that sweeps and flips once, shaded like the fold artwork, projected from 3D
const smooth = (a, b, v) => { const t = Math.min(1, Math.max(0, (v - a) / (b - a))); return t * t * (3 - 2 * t); };
function foldPoint(rnd, centre, wk = 1) {
  const t = rnd();
  const w = rnd() < 0.22 ? (rnd() < 0.5 ? -1 : 1) * (0.92 + rnd() * 0.08) : rnd() * 2 - 1;
  const C = (u) => centre(Math.min(1, Math.max(0, u)));
  const cc = C(t), a = C(t - 0.002), b = C(t + 0.002);
  let T = [b[0] - a[0], b[1] - a[1], b[2] - a[2]]; const tl = Math.hypot(...T); T = T.map((v) => v / tl);
  let D = [-T[2], 0, T[0]]; const dl = Math.hypot(...D) || 1; D = D.map((v) => v / dl);
  const U = [D[1] * T[2] - D[2] * T[1], D[2] * T[0] - D[0] * T[2], D[0] * T[1] - D[1] * T[0]];
  const th = Math.PI * smooth(0.4, 0.8, t);
  const Wv = U.map((u, j) => u * Math.cos(th) + D[j] * Math.sin(th));
  const width = w * (1.25 + 0.6 * t) * wk;
  const p = cc.map((v, j) => v + Wv[j] * width);
  const facing = T[0] * Wv[1] - T[1] * Wv[0];
  const colr = facing < -0.05
    ? mix(BRAND.fold, BRAND.shade, 0.25 * (1 - Math.abs(w)))
    : mix(mix(BRAND.shade, BRAND.mustard, 0.55 + 0.45 * facing), BRAND.highlight, Math.max(0, Math.abs(w) - 0.82) * 4);
  return { p, c: colr };
}
const project = (p, cx, cy, scale, cam = 9) => { const f = cam / (cam - p[2]); return [cx + p[0] * scale * f, cy - p[1] * scale * f, f]; };

window.ArktField = { hex, mix, BRAND, SPRING, seeded, createField, textPoints, roundRect, foldPoint, project };
