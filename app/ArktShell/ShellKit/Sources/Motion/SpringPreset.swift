/// Named spring presets: response (s) and damping ratio.
public enum SpringPreset: String, CaseIterable, Sendable {
  case firm, firmSlow, firmExtraSlow, firmFast, springy, springyFast, springyExtraFast

  public var parameters: SpringParameters {
    switch self {
    case .firm:             SpringParameters(dampingRatio: 0.90, response: 0.25)
    case .firmSlow:         SpringParameters(dampingRatio: 0.90, response: 0.35)
    case .firmExtraSlow:    SpringParameters(dampingRatio: 0.90, response: 1.25)
    case .firmFast:         SpringParameters(dampingRatio: 0.95, response: 0.15)
    case .springy:          SpringParameters(dampingRatio: 0.63, response: 0.28)
    case .springyFast:      SpringParameters(dampingRatio: 0.80, response: 0.18)
    case .springyExtraFast: SpringParameters(dampingRatio: 0.80, response: 0.08)
    }
  }
}
