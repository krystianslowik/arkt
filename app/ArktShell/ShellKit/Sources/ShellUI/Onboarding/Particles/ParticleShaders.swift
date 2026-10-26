/// The particle field's Metal source (onboarding spec, section 7.4), compiled at run time with
/// `MTLDevice.makeLibrary(source:options:)`, so the package needs no Metal build step. One compute kernel springs each
/// mote toward its target (sub-stepped to 1/240 s) and eases colour and size; one draw renders the motes as point
/// sprites with the website's soft disc (smoothstep 0.5 to 0.18), premultiplied for the layer.
enum ParticleShaders {
  static let source = #"""
  #include <metal_stdlib>
  using namespace metal;

  struct Target { float4 target; float4 pathA; float4 pathB; float4 color; float4 motion; float4 extra; };
  struct State { float4 pv; float4 color; float4 sizeSeed; };
  struct Uniforms { float4 time; float4 view; float4 config; };

  static float panPage(float t) {
    if (t < 1.4) return 0.0;
    if (t < 3.0) return 1.0 - exp(-4.0 * (t - 1.4));
    if (t < 4.6) return 1.0 + (1.0 - exp(-4.0 * (t - 3.0)));
    return 2.0 - (1.0 - exp(-4.0 * (t - 4.6)));
  }

  static float2 pathPoint(int kind, float4 a, float4 b, float u, float clock, bool settled) {
    if (kind == 1) {
      float mx = (a.x + a.z) * 0.5, my = (a.y + a.w) * 0.5 + b.x;
      float p = (1.0 - u) * (1.0 - u), q = 2.0 * (1.0 - u) * u, r = u * u;
      return float2(p * a.x + q * mx + r * a.z, p * a.y + q * my + r * a.w);
    }
    if (kind == 2) {
      float angle = u * 6.28318530718;
      float ex = cos(angle) * a.z, ey = sin(angle) * a.w;
      float ct = cos(b.x), st = sin(b.x);
      return float2(a.x + ex * ct - ey * st + b.y, a.y + ex * st + ey * ct + b.z);
    }
    if (kind == 3) {
      return float2(a.x + sin(u * 9.0 + a.x) * 6.0, a.y + 20.0 - u * (a.y + 40.0));
    }
    if (kind == 4) {
      float page = settled ? 1.0 : panPage(clock - a.w);
      return float2(a.x + (a.z - page) * 168.0, a.y);
    }
    return float2(0.0);
  }

  kernel void stepParticles(device const Target *targets [[buffer(0)]],
                            device State *states [[buffer(1)]],
                            constant Uniforms &u [[buffer(2)]],
                            uint id [[thread_position_in_grid]]) {
    if (id >= uint(u.config.x)) return;
    Target T = targets[id];
    State S = states[id];
    float now = u.time.x, dt = u.time.y;
    int steps = max(1, int(u.time.z));
    bool reduced = u.time.w > 0.5;
    float2 p = S.pv.xy, v = S.pv.zw;
    float4 col = S.color;
    float size = S.sizeSeed.x, seed = S.sizeSeed.y, epoch = S.sizeSeed.z;
    float start = T.motion.y, k = T.motion.z, c = T.motion.w;
    int kind = int(T.target.w);
    float rate = T.extra.x, phase = T.extra.y, targetEpoch = T.extra.w;
    bool fades = T.extra.z > 0.5;
    float h = dt / float(steps);
    for (int s = 0; s < steps; s++) {
      float ts = now - dt + h * float(s + 1);
      if (ts < start) { v *= 0.97; p += v * h; continue; }
      float2 target = T.target.xy;
      float alpha = T.color.a;
      float clock = reduced ? u.config.z : ts;
      if (kind != 0) {
        float w = fract(phase + clock * rate);
        target = pathPoint(kind, T.pathA, T.pathB, w, clock, reduced);
        if (fades) alpha = T.color.a * pow(max(sin(3.14159265 * w), 0.0), 0.6);
      }
      if (reduced) {
        // Nothing travels: a mote fades out of the old shape and appears in place in the new one.
        if (epoch != targetEpoch) {
          col.a -= col.a * (1.0 - exp(-h * 9.0)) + h * 0.4;
          if (col.a <= 0.01) {
            col = float4(T.color.rgb, 0.0); p = target; v = float2(0.0); size = T.motion.x; epoch = targetEpoch;
          }
          continue;
        }
        p = target; v = float2(0.0); size = T.motion.x; col.rgb = T.color.rgb;
        col.a += (alpha - col.a) * (1.0 - exp(-h * 9.0));
        continue;
      }
      epoch = targetEpoch;
      float drift = T.target.z;
      float2 wobble = drift * float2(sin(ts * (0.35 + seed * 0.5) + seed * 40.0),
                                     cos(ts * (0.3 + seed * 0.45) + seed * 23.0));
      float2 acc = k * (target + wobble - p) - c * v;
      v += acc * h;
      p += v * h;
      float ease = 1.0 - exp(-h * u.config.y);
      col += (float4(T.color.rgb, alpha) - col) * ease;
      size += (T.motion.x - size) * ease;
    }
    states[id].pv = float4(p, v);
    states[id].color = col;
    states[id].sizeSeed = float4(size, seed, epoch, 0.0);
  }

  struct Vertex { float4 position [[position]]; float size [[point_size]]; float4 color; };

  vertex Vertex particleVertex(device const State *states [[buffer(0)]],
                               constant Uniforms &u [[buffer(1)]],
                               uint id [[vertex_id]]) {
    State S = states[id];
    Vertex out;
    float2 ndc = S.pv.xy / u.view.xy * 2.0 - 1.0;
    out.position = float4(ndc.x, -ndc.y, 0.0, 1.0);
    out.size = max(S.sizeSeed.x * u.view.z, 1.0);
    out.color = float4(S.color.rgb, S.color.a * u.view.w);
    return out;
  }

  fragment float4 particleFragment(Vertex in [[stage_in]], float2 coord [[point_coord]]) {
    float d = length(coord - 0.5);
    if (d > 0.5) discard_fragment();
    float a = in.color.a * smoothstep(0.5, 0.18, d);
    return float4(in.color.rgb * a, a);
  }
  """#
}
