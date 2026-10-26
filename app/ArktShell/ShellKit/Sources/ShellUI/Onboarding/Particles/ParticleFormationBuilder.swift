import CoreText
import Motion
import Synchronization
import Foundation
import simd

/// Builds a formation's targets (onboarding spec, section 7.2) from the live layout, the way the prototype's
/// formations do: lanes of the particle index (index mod 20) split each formation into its parts; shapes come from
/// the artwork's pixels, real type and real geometry. Pure and nonisolated, so it runs off the main thread.
struct ParticleFormationBuilder: Sendable {
  struct MarkSample: Sendable {
    var position: SIMD2<Float>
    var color: SIMD3<Float>
  }

  /// What the build needs besides the formation.
  struct Input: Sendable {
    var size: SIMD2<Float>
    var count: Int
    /// Field time now (seconds): start times are `now` + the mote's delay.
    var now: Float
    var epoch: Float
    var dark: Bool
    var reduceTransparency = false
    var increaseContrast = false
    var reduceMotion = false
    var mark: [MarkSample]
    /// When tip 3 appeared (the rooms' pan clock).
    var tipStart: Float = 0
  }

  /// A target before colour resolution and alpha floors.
  private struct Spec {
    enum Tint { case ink, accent, rgb(SIMD3<Float>) }
    var position = SIMD2<Float>.zero
    var path = ParticlePath.rest
    var tint = Tint.ink
    var alpha: Float = 0.3
    var size: Float = 1.6
    var drift: Float = 1.2
    var delay: Float = 0
    var spring = SpringPreset.gather
    var ambient = false
    var rate: Float = 0
    var phase: Float?
    var fades = false
  }

  let input: Input

  private var width: Float { input.size.x }
  private var height: Float { input.size.y }
  private var ink: SIMD3<Float> { input.dark ? ParticleColors.porcelain : ParticleColors.graphite }

  static func lane(_ index: Int) -> Int { index % 20 }

  // MARK: - Build

  /// Every mote's target for `formation`. `previous` keeps start times for a retarget (P4: a changing count never
  /// restarts motes already in flight).
  func build(_ formation: OnboardingFormation, previous: [ParticleTarget]? = nil) -> [ParticleTarget] {
    var random = SeededRandom(seed: 97)
    var targets = [ParticleTarget](repeating: .zero, count: input.count)
    for index in 0..<input.count {
      let spec = self.spec(for: formation, index: index, random: &random)
      targets[index] = resolve(spec, index: index, keepStart: previous?[index])
    }
    return targets
  }

  /// P9: the content card's edge, sparse mustard on it, a faint fill; the rest fades.
  func buildCard(_ card: CGRect) -> [ParticleTarget] {
    var random = SeededRandom(seed: 131)
    let rect = Self.rect(card)
    var targets = [ParticleTarget](repeating: .zero, count: input.count)
    for index in 0..<input.count {
      let lane = Self.lane(index)
      var spec: Spec
      if lane < 12 {
        let p = ParticleGeometry.roundRect(&random, width: rect.width, height: rect.height, radius: 10, edge: true)
        spec = Spec(position: rect.centre + p, tint: random.next() > 0.8 ? .accent : .ink, alpha: 0.85,
                    size: 1.1 + random.next() * 1.2, drift: 0.6, delay: random.next() * 0.3)
      } else if lane < 15 {
        let p = ParticleGeometry.roundRect(&random, width: rect.width, height: rect.height, radius: 10, edge: false)
        spec = Spec(position: rect.centre + p, alpha: 0.12, size: 1.2, delay: random.next() * 0.3)
      } else {
        spec = ambient(&random, tint: nil)
        spec.alpha = 0
      }
      targets[index] = resolve(spec, index: index, keepStart: nil)
    }
    return targets
  }

  private func resolve(_ spec: Spec, index: Int, keepStart: ParticleTarget?) -> ParticleTarget {
    let rgb: SIMD3<Float> = switch spec.tint {
    case .ink: ink
    case .accent: input.increaseContrast && !input.dark ? ParticleColors.fold : ParticleColors.mustard
    case .rgb(let color): color
    }
    var alpha = spec.alpha
    if input.reduceTransparency && spec.ambient { alpha = 0 }
    if input.increaseContrast && !spec.ambient && alpha > 0 { alpha = max(alpha, 0.8) }
    if input.reduceTransparency && !spec.ambient && alpha > 0 { alpha = max(alpha, 0.6) }
    let size = spec.size * (input.reduceTransparency && !spec.ambient ? 1.15 : 1)
    let parameters = spec.spring.parameters
    let w = Float(2 * Double.pi / parameters.response)
    let k = w * w, c = 2 * Float(parameters.dampingRatio) * w
    let seed = Self.seed(index)
    let phase = spec.phase ?? seed
    var position = spec.position
    if spec.path != .rest {
      position = spec.path.point(phase: phase, clock: input.now, settled: input.reduceMotion)
    }
    let (a, b) = spec.path.parameters
    // Reduce Motion: shapes cross-dissolve in place, staggered by seed x 0.3 s (section 9).
    let start = keepStart?.motion.y ?? (input.now + (input.reduceMotion ? seed * 0.3 : spec.delay))
    return ParticleTarget(
      target: SIMD4(position.x, position.y, input.reduceMotion ? 0 : spec.drift, spec.path.kind.rawValue),
      pathA: a, pathB: b, color: SIMD4(rgb, alpha), motion: SIMD4(size, start, k, c),
      extra: SIMD4(input.reduceMotion ? 0 : spec.rate, phase, spec.fades ? 1 : 0, input.epoch))
  }

  /// A mote's own seed in 0...1, the same every build (the kernel stores it in the state).
  static func seed(_ index: Int) -> Float {
    var random = SeededRandom(seed: UInt32(truncatingIfNeeded: index &* 2_654_435_761 &+ 11))
    return random.next()
  }

  // MARK: - Formations

  private func spec(for formation: OnboardingFormation, index: Int, random: inout SeededRandom) -> Spec {
    let lane = Self.lane(index)
    switch formation {
    case .none:
      return ambient(&random, tint: nil)
    case .welcome(let rect):
      let r = Self.rect(rect)
      if lane < 11 { return mark(&random, centre: r.centre, height: r.height) }
      if lane < 14 { return fold(&random) }
      return ambient(&random, tint: nil)
    case .counts(let counts):
      if lane < 11 { return digit(index: index, counts: counts, random: &random) }
      if lane < 14 { return fold(&random) }
      return ambient(&random, tint: nil)
    case .theme(let preview, let theme, let origin):
      return themeSpec(lane: lane, preview: Self.rect(preview), theme: theme, origin: origin.map(Self.point),
                       random: &random)
    case .defaultBrowser(let rect):
      let r = Self.rect(rect)
      if lane < 7 { return mark(&random, centre: r.centre, height: 150) }
      if lane < 10 {
        let y0 = r.centre.y + random.gauss() * 140
        var spec = Spec(path: .curve(x0: -20, y0: y0, x1: r.centre.x - 70, y1: r.centre.y + random.gauss() * 30,
                                     bend: -40 * random.next()),
                        tint: random.next() > 0.15 ? .accent : .ink, alpha: 0.9, size: 1 + random.next() * 1.5,
                        spring: .firm, rate: 0.18 + random.next() * 0.12, fades: true)
        spec.delay = random.next() * 0.55
        return spec
      }
      return ambient(&random, tint: nil)
    case .extensions(let markRect, _):
      let c = Self.rect(markRect).centre
      if lane < 4 { return mark(&random, centre: c, height: 104) }
      if lane < 12 {
        let ring = min(2, Int(random.next() * 3)), cluster = min(17, Int(random.next() * 18))
        let tilt: [Float] = [-0.28, 0, 0.28], rx: [Float] = [250, 205, 160], ry: [Float] = [62, 48, 36]
        let phase = (Float(cluster) / 18 + Float(ring) * 0.11 + random.gauss() * 0.012 + 1)
          .truncatingRemainder(dividingBy: 1)
        let mustard = (cluster + ring) % 3 == 0
        return Spec(path: .ellipse(cx: c.x, cy: c.y, rx: rx[ring], ry: ry[ring], tilt: tilt[ring],
                                   offsetX: random.gauss() * 3, offsetY: random.gauss() * 3),
                    tint: mustard ? .accent : .ink, alpha: 0.9, size: 1.2 + random.next() * 1.3,
                    delay: random.next() * 0.55, spring: .firm, rate: 0.025 * (ring % 2 == 1 ? -1 : 1),
                    phase: phase)
      }
      return ambient(&random, tint: nil)
    case .tour(let tip, let stage):
      return tourSpec(tip: tip, centre: Self.rect(stage).centre, lane: lane, random: &random)
    case .done(let rect):
      let c = Self.rect(rect).centre
      if lane < 9 { return mark(&random, centre: c, height: 168) }
      if lane < 10 {
        let radius = 130 + random.gauss() * 10
        return Spec(path: .ellipse(cx: c.x, cy: c.y, rx: radius, ry: radius * 0.42, tilt: 0, offsetX: 0, offsetY: 0),
                    tint: .accent, alpha: random.next() > 0.4 ? 0.9 : 0, size: 1 + random.next() * 1.6,
                    delay: random.next() * 0.55, spring: .firm, rate: 0.04)
      }
      if lane < 13 { return fold(&random) }
      return ambient(&random, tint: nil)
    }
  }

  // MARK: Parts

  /// The website's background field: ink motes at 20 %, mustard sparks at 65 % for about one in seven.
  private func ambient(_ random: inout SeededRandom, tint: ((Float) -> SIMD3<Float>)?) -> Spec {
    let spark = random.next() > 0.86
    let x = random.next() * width, y = random.next() * height
    let color: Spec.Tint = spark ? .accent : (tint.map { .rgb($0(random.next())) } ?? .ink)
    return Spec(position: SIMD2(x, y), tint: color, alpha: spark ? 0.65 : 0.2, size: 1 + random.next() * 1.7,
                drift: 12 + random.next() * 12, delay: random.next() * 0.55, spring: .firmExtraSlow, ambient: true)
  }

  /// A pixel of the mark artwork at `height`, with sub-pixel jitter.
  private func mark(_ random: inout SeededRandom, centre: SIMD2<Float>, height h: Float) -> Spec {
    guard !input.mark.isEmpty else { return ambient(&random, tint: nil) }
    let sample = input.mark[min(input.mark.count - 1, Int(random.next() * Float(input.mark.count)))]
    let jitter = h / 130
    let x = centre.x + sample.position.x * h + (random.next() - 0.5) * jitter * 1.6
    let y = centre.y + sample.position.y * h + (random.next() - 0.5) * jitter * 1.6
    return Spec(position: SIMD2(x, y), tint: .rgb(sample.color), alpha: 1,
                size: 1.3 + random.next() * 1.3 * min(1, h / 150), drift: 0.8, delay: random.next() * 0.55)
  }

  /// The brand fold along the bottom of the window.
  private func fold(_ random: inout SeededRandom) -> Spec {
    let (point, color) = ParticleGeometry.foldPoint(&random, widthScale: 0.42)
    let projected = ParticleGeometry.project(point, cx: width / 2, cy: height / 2, scale: height / 12.6)
    return Spec(position: SIMD2(projected.x, projected.y), tint: .rgb(color), alpha: 0.95,
                size: (1.2 + random.next() * 1.8) * projected.z, drift: 1.6, delay: random.next() * 0.55)
  }

  /// The counts: each number's share of the digit motes (pinned tabs 46 %, the others 18 % each), sampled from
  /// the number set in Avenir Next DemiBold at its laid-out size.
  private func digit(index: Int, counts: OnboardingCountFormation, random: inout SeededRandom) -> Spec {
    let numbers = counts.numbers
    guard !numbers.isEmpty else { return ambient(&random, tint: nil) }
    if counts.state == .failed {
      let box = numbers.map(\.frame).reduce(numbers[0].frame) { $0.union($1) }
      let c = Self.rect(box).centre
      return Spec(position: SIMD2(c.x + random.gauss() * 300, c.y + random.gauss() * 90), alpha: 0.3,
                  size: 1 + random.next(), drift: 10, delay: random.next() * 0.4, spring: .firmExtraSlow)
    }
    let u = (Float(index) * 0.618_033_9).truncatingRemainder(dividingBy: 1)
    var accumulated: Float = 0
    var number = numbers[0]
    for candidate in numbers {
      accumulated += candidate.kind == .pinnedTabs ? 0.46 : 0.18
      if u < accumulated { number = candidate; break }
    }
    let glyph = GlyphCache.shared.points(number.text, size: number.fontSize)
    let point = glyph.points.isEmpty ? .zero
      : glyph.points[min(glyph.points.count - 1, Int(random.next() * Float(glyph.points.count)))]
    let centre = Self.inkCentre(of: number)
    let landed: Bool = if case .importing(let kinds) = counts.state { kinds.contains(number.kind) } else { false }
    let spark = random.next() > (counts.state == .imported ? 0.8 : 0.88)
    let tint: Spec.Tint = landed || spark ? .accent : .ink
    return Spec(position: SIMD2(centre.x + point.x + (random.next() - 0.5) * 1.2,
                                centre.y + point.y + (random.next() - 0.5) * 1.2),
                tint: tint, alpha: counts.state == .counting ? 0.55 : 0.92, size: 1.2 + random.next() * 1.6,
                drift: 0.8, delay: (point.x / 400 + 0.5) * 0.35, spring: .firmSlow)
  }

  /// Where a number's digits sit: the centre of its cap height inside the laid-out line box (the text views place
  /// glyphs the CSS way, `BrandType.cssShift`).
  static func inkCentre(of number: OnboardingCountFormation.Number) -> SIMD2<Float> {
    let font = CTFontCreateWithName("AvenirNext-DemiBold" as CFString, number.fontSize, nil)
    let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font), cap = CTFontGetCapHeight(font)
    let lineHeight = number.frame.height
    let baseline = number.frame.minY + (lineHeight - (ascent + descent)) / 2 + ascent
    return SIMD2(Float(number.frame.midX), Float(baseline - cap / 2))
  }

  // MARK: Make it yours

  private func themeSpec(lane: Int, preview r: Rect, theme: SpaceThemeInfo, origin: SIMD2<Float>?,
                         random: inout SeededRandom) -> Spec {
    let stops = theme.baseColors.map { SIMD3(Float($0.red), Float($0.green), Float($0.blue)) }
    let a = stops.first ?? ink, b = stops.last ?? ink
    let towards: SIMD3<Float> = input.dark ? SIMD3(repeating: 1) : .zero
    let k: Float = input.dark ? 0.45 : 0.38
    let tint: (Float) -> SIMD3<Float> = { u in simd_mix(simd_mix(a, b, SIMD3(repeating: u)), towards, SIMD3(repeating: k)) }
    var spec: Spec
    if lane < 4 {
      let p = ParticleGeometry.roundRect(&random, width: r.width + 14, height: r.height + 14, radius: 20, edge: true)
      spec = Spec(position: r.centre + p, tint: .rgb(tint(random.next())), alpha: 0.7,
                  size: 1 + random.next() * 1.2, drift: 1.5)
    } else if lane < 11 {
      let side: Float = random.next() < 0.5 ? -1 : 1
      let x0 = width / 2 + side * (360 + random.next() * max(0, width / 2 - 360))
      spec = Spec(position: SIMD2(x0, height * random.next()), path: .rising(x: x0, height: height),
                  tint: .rgb(tint(random.next())), alpha: 0.85, size: 1.2 + random.next() * 1.8, spring: .firm,
                  rate: 0.04 + random.next() * 0.08, fades: true)
    } else if lane < 12 {
      let p = ParticleGeometry.roundRect(&random, width: r.width + 40, height: r.height + 40, radius: 30, edge: false)
      spec = Spec(position: r.centre + p, tint: .accent, alpha: random.next() > 0.7 ? 0.8 : 0,
                  size: 1 + random.next() * 1.4, drift: 6)
    } else {
      spec = ambient(&random, tint: tint)
    }
    // P6: the re-tint spreads from the pressed swatch at 900 pt/s.
    if let origin {
      spec.delay = simd_distance(spec.position, origin) / 900
    } else if lane >= 12 {
      // ambient keeps its own delay
    } else {
      spec.delay = random.next() * 0.55
    }
    return spec
  }

  // MARK: Tour

  private func cap(_ random: inout SeededRandom, at c: SIMD2<Float>, text: String) -> Spec {
    let u = random.next()
    if u < 0.42 {
      let p = ParticleGeometry.roundRect(&random, width: 72, height: 72, radius: 16, edge: true)
      return Spec(position: c + p, alpha: 0.8, size: 1.1 + random.next())
    }
    if u < 0.52 {
      return Spec(position: SIMD2(c.x - 30 + random.next() * 60, c.y + 37 + random.next() * 3), alpha: 0.7,
                  size: 1.1 + random.next())
    }
    if u < 0.58 {
      let p = ParticleGeometry.roundRect(&random, width: 70, height: 70, radius: 15, edge: false)
      return Spec(position: c + p, alpha: 0.08, size: 1.4)
    }
    let glyph = text == "\u{2318}" ? GlyphCache.shared.points(text, size: 40, system: true)
      : GlyphCache.shared.points(text, size: 34, tracking: 0)
    let point = glyph.points.isEmpty ? .zero
      : glyph.points[min(glyph.points.count - 1, Int(random.next() * Float(glyph.points.count)))]
    return Spec(position: c + point, alpha: 0.95, size: 1.1 + random.next() * 0.9)
  }

  private func withDelay(_ spec: Spec, _ random: inout SeededRandom) -> Spec {
    var spec = spec
    spec.drift = 0.6
    spec.delay = random.next() * 0.55
    return spec
  }

  private func stream(_ path: ParticlePath, _ random: inout SeededRandom) -> Spec {
    Spec(path: path, tint: .accent, alpha: 0.95, size: 1.2 + random.next() * 1.4, delay: random.next() * 0.55,
         spring: .firm, rate: 0.3 + random.next() * 0.15, fades: true)
  }

  private func tourSpec(tip: Int, centre c: SIMD2<Float>, lane: Int, random: inout SeededRandom) -> Spec {
    switch tip {
    case 1:
      if lane < 11 {
        let pair = random.next() < 0.5 ? 0 : 1, key = random.next() < 0.5 ? 0 : 1
        let x = c.x + (pair == 1 ? 120 : -120) + (key == 1 ? 42 : -42)
        let text = key == 1 ? (pair == 1 ? "L" : "T") : "\u{2318}"
        return withDelay(cap(&random, at: SIMD2(x, c.y), text: text), &random)
      }
      if lane < 12 {
        return withDelay(Spec(position: SIMD2(c.x + random.gauss() * 220, c.y + random.gauss() * 70), tint: .accent,
                              alpha: random.next() > 0.6 ? 0.85 : 0, size: 1 + random.next() * 1.2, drift: 5),
                         &random)
      }
    case 2:
      if lane < 8 {
        let key = random.next() < 0.5 ? 0 : 1
        return withDelay(cap(&random, at: SIMD2(c.x - 170 + (key == 1 ? 42 : -42), c.y), text: key == 1 ? "W" : "\u{2318}"),
                         &random)
      }
      if lane < 10 {
        let u = random.next(), tray = SIMD2(c.x + 170, c.y + 8)
        if u < 0.7 {
          let p = ParticleGeometry.roundRect(&random, width: 92, height: 64, radius: 12, edge: true)
          return withDelay(Spec(position: tray + p, alpha: 0.8, size: 1.2 + random.next()), &random)
        }
        if u < 0.85 {
          return withDelay(Spec(position: SIMD2(tray.x - 46 + random.next() * 92, tray.y - 14), alpha: 0.7,
                                size: 1.1 + random.next()), &random)
        }
        return withDelay(Spec(position: SIMD2(tray.x - 14 + random.next() * 28, tray.y + 4 + (random.next() - 0.5) * 2),
                              alpha: 0.85, size: 1.4), &random)
      }
      if lane < 12 {
        var spec = stream(.curve(x0: c.x - 110, y0: c.y + random.gauss() * 12, x1: c.x + 120,
                                 y1: c.y + 8 + random.gauss() * 10, bend: -60), &random)
        spec.rate = 0.35 + random.next() * 0.2
        spec.alpha = 0.9
        return spec
      }
    case 3:
      if lane < 15 { return room(&random, centre: c) }
    case 4:
      if lane < 10 { return withDelay(window(&random, centre: c, split: true), &random) }
      if lane < 12 { return stream(.curve(x0: c.x - 140, y0: c.y - 34, x1: c.x + 100, y1: c.y, bend: -30), &random) }
    default:
      if lane < 10 { return withDelay(window(&random, centre: c, split: false), &random) }
      if lane < 12 { return stream(.curve(x0: c.x - 150, y0: c.y + 44, x1: c.x - 114, y1: c.y - 70, bend: 10), &random) }
    }
    return ambient(&random, tint: nil)
  }

  /// Tip 3: three Space rooms in Dune, Mist and Blossom's light stops, paging (P8).
  private func room(_ random: inout SeededRandom, centre c: SIMD2<Float>) -> Spec {
    let index = min(2, Int(random.next() * 3))
    let family = [SpaceThemeCatalog.families[0], SpaceThemeCatalog.families[1], SpaceThemeCatalog.families[4]][index]
    let stops = family.light.baseColors.map { SIMD3(Float($0.red), Float($0.green), Float($0.blue)) }
    let a = stops[0], b = stops[stops.count - 1]
    let roomWidth: Float = 128, roomHeight: Float = 208
    let deep: (SIMD3<Float>) -> SIMD3<Float> = { simd_mix($0, .zero, SIMD3(repeating: self.input.dark ? 0.05 : 0.25)) }
    let part = random.next()
    var offset = SIMD2<Float>.zero, color = ink, alpha: Float = 0.9
    if part < 0.3 {
      offset = ParticleGeometry.roundRect(&random, width: roomWidth, height: roomHeight, radius: 14, edge: true)
      color = deep(simd_mix(a, b, SIMD3(repeating: offset.y / roomHeight + 0.5)))
      alpha = 1
    } else if part < 0.74 {
      offset = ParticleGeometry.roundRect(&random, width: roomWidth - 2, height: roomHeight - 2, radius: 13, edge: false)
      color = deep(simd_mix(a, b, SIMD3(repeating: 0.4 + 0.6 * (offset.y / roomHeight + 0.5))))
      alpha = 0.95
    } else if part < 0.82 {
      let k = Float(min(2, Int(random.next() * 3))), tile: Float = 30
      let p = ParticleGeometry.roundRect(&random, width: tile, height: 22, radius: 6, edge: true)
      offset = SIMD2(-roomWidth / 2 + 14 + tile / 2 + k * (tile + 7) + p.x, -roomHeight / 2 + 24 + p.y)
      alpha = 0.6
    } else {
      let k = Float(min(3, Int(random.next() * 4)))
      offset = SIMD2(-roomWidth / 2 + 16 + random.next() * (44 + k * 12),
                     -roomHeight / 2 + 62 + k * 22 + (random.next() - 0.5) * 3)
      alpha = 0.7
    }
    return Spec(path: .pan(x: c.x + offset.x, y: c.y + offset.y, room: Float(index), start: input.tipStart),
                tint: .rgb(color), alpha: alpha, size: 1.6 + random.next() * 1.6, delay: random.next() * 0.55,
                spring: .firmSlow, phase: 0)
  }

  /// Tips 4 and 5: a window with a sidebar strip, rows and Favorites, its page split (tip 4) or a Favorite filled
  /// mustard (tip 5).
  private func window(_ random: inout SeededRandom, centre c: SIMD2<Float>, split: Bool) -> Spec {
    let w: Float = 360, h: Float = 200, sidebarX = c.x - w / 2 + 82, u = random.next()
    if u < 0.3 {
      let p = ParticleGeometry.roundRect(&random, width: w, height: h, radius: 14, edge: true)
      return Spec(position: c + p, alpha: 0.75, size: 1.1 + random.next())
    }
    if u < 0.36 {
      return Spec(position: SIMD2(sidebarX, c.y - h / 2 + 6 + random.next() * (h - 12)), alpha: 0.35, size: 1.1)
    }
    if u < 0.56 {
      let k = Float(min(4, Int(random.next() * 5)))
      return Spec(position: SIMD2(c.x - w / 2 + 14 + random.next() * (34 + (k * 9).truncatingRemainder(dividingBy: 24)),
                                  c.y - h / 2 + 66 + k * 22 + (random.next() - 0.5) * 3),
                  alpha: k == 1 ? 0.95 : 0.6, size: 1.2)
    }
    if u < 0.66 {
      let k = min(2, Int(random.next() * 3))
      let filled = !split && k == 2
      let p = ParticleGeometry.roundRect(&random, width: 18, height: 16, radius: 4, edge: !filled)
      return Spec(position: SIMD2(c.x - w / 2 + 22 + Float(k) * 22 + p.x, c.y - h / 2 + 30 + p.y),
                  tint: filled ? .accent : .ink, alpha: filled ? 1 : 0.6, size: 1.2)
    }
    let pageLeft = sidebarX + 8, pageRight = c.x + w / 2 - 8
    if split {
      let right = random.next() < 0.5
      let paneWidth = (pageRight - pageLeft - 8) / 2
      let p = ParticleGeometry.roundRect(&random, width: paneWidth, height: h - 16, radius: 8, edge: random.next() < 0.8)
      return Spec(position: SIMD2(pageLeft + paneWidth / 2 + (right ? paneWidth + 8 : 0) + p.x, c.y + p.y),
                  tint: right ? .accent : .ink, alpha: right ? 0.8 : 0.5, size: 1.1 + random.next() * 0.6)
    }
    let p = ParticleGeometry.roundRect(&random, width: pageRight - pageLeft, height: h - 16, radius: 8,
                                       edge: random.next() < 0.8)
    return Spec(position: SIMD2((pageLeft + pageRight) / 2 + p.x, c.y + p.y), alpha: 0.4, size: 1.1)
  }

  // MARK: - Geometry helpers

  struct Rect: Sendable {
    var origin: SIMD2<Float>
    var width: Float
    var height: Float
    var centre: SIMD2<Float> { origin + SIMD2(width / 2, height / 2) }
  }

  static func rect(_ rect: CGRect) -> Rect {
    Rect(origin: SIMD2(Float(rect.minX), Float(rect.minY)), width: Float(rect.width), height: Float(rect.height))
  }

  static func point(_ point: CGPoint) -> SIMD2<Float> { SIMD2(Float(point.x), Float(point.y)) }
}

/// Glyph samples are cached for the session (section 7.4).
final class GlyphCache: Sendable {
  static let shared = GlyphCache()
  private let storage = Mutex<[String: GlyphSampler.Points]>([:])

  func points(_ text: String, size: CGFloat, system: Bool = false, tracking: CGFloat = -0.04) -> GlyphSampler.Points {
    let key = "\(text)|\(size)|\(system)|\(tracking)"
    if let cached = storage.withLock({ $0[key] }) { return cached }
    let made = GlyphSampler.points(text, size: size, postScriptName: system ? nil : "AvenirNext-DemiBold",
                                   tracking: tracking)
    storage.withLock { $0[key] = made }
    return made
  }
}
