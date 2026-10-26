/// Named spring presets: response (s) and damping ratio. Arc's seven come first, in Arc's tag order; Arkt's own
/// follow.
public enum SpringPreset: String, CaseIterable, Sendable {
  case firm, firmSlow, firmExtraSlow, firmFast, springy, springyFast, springyExtraFast
  /// Particle formations of the first run (onboarding spec, section 7.3): a shape gathers without overshooting
  /// visibly and reads as settled at about 1.2 s.
  case gather

  /// Arc's presets, in Arc's tag order.
  public static let arcPresets: [SpringPreset] = [
    .firm, .firmSlow, .firmExtraSlow, .firmFast, .springy, .springyFast, .springyExtraFast,
  ]

  public var parameters: SpringParameters {
    switch self {
    case .firm:             SpringParameters(dampingRatio: 0.90, response: 0.25)
    case .firmSlow:         SpringParameters(dampingRatio: 0.90, response: 0.35)
    case .firmExtraSlow:    SpringParameters(dampingRatio: 0.90, response: 1.25)
    case .firmFast:         SpringParameters(dampingRatio: 0.95, response: 0.15)
    case .springy:          SpringParameters(dampingRatio: 0.63, response: 0.28)
    case .springyFast:      SpringParameters(dampingRatio: 0.80, response: 0.18)
    case .springyExtraFast: SpringParameters(dampingRatio: 0.80, response: 0.08)
    case .gather:           SpringParameters(dampingRatio: 0.88, response: 0.80)
    }
  }
}
