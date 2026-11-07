/// What ends a find with Esc leave behind (`EngineClient.stopFinding(_:action:)`, #134).
public enum FindStopAction: Equatable, Sendable {
  /// Removes the highlight and the selection of the active match.
  case clear
  /// Keeps the active match as the page's selection.
  case keep
  /// Keeps the active match as the selection and clicks it when it is a link.
  case activate
}
