import AppKit

/// Edits a local draft; the caller receives a value only when Save is pressed.
@MainActor
final class SettingsRouteSheet: NSWindowController {
  var onFinish: (@MainActor (SettingsLinkRoute?) -> Void)?
  private let literal = NSTextField(frame: .zero)
  private let condition: SettingsPopUpButton
  private let destination: SettingsPopUpButton
  private var conditionIndex: Int
  private var destinationIndex: Int
  private let destinations: [SettingsLinkDestination]
  private let save = ArchivePillButton(style: .primary, title: "Save", metrics: .dialog)
  private let cancel = ArchivePillButton(style: .neutral, title: "Cancel", metrics: .dialog)

  init(route: SettingsLinkRoute?, spaces: [SettingsSpaceSummary]) {
    let text: String
    let initialCondition: Int
    switch route?.condition {
    case .contains(let value): text = value; initialCondition = 0
    case .matches(let value): text = value; initialCondition = 1
    case nil: text = ""; initialCondition = 0
    }
    let selected = route?.destination ?? .littleArkt
    var choices: [(String, SettingsLinkDestination)] = [("Little Arkt", .littleArkt),
                                                         ("Most Recent Space", .mostRecentSpace)]
    choices += spaces.map { ($0.title, .space($0.id)) }
    if !choices.contains(where: { $0.1 == selected }) { choices.append(("Unavailable Space", selected)) }
    let values = choices.map(\.1)
    let initialDestination = values.firstIndex(of: selected) ?? 0
    destinations = values
    conditionIndex = initialCondition
    destinationIndex = initialDestination
    condition = SettingsPopUpButton(items: ["Contains", "Matches"], selected: initialCondition == 0 ? "Contains" : "Matches")
    destination = SettingsPopUpButton(items: choices.map(\.0), selected: choices[initialDestination].0)
    let window = DialogWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 260),
                              styleMask: [.titled], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.setAccessibilitySubrole(.dialog)
    window.setAccessibilityLabel(route == nil ? "Add Route" : "Edit Route")
    let root = ImportSheetRootView(frame: NSRect(x: 0, y: 0, width: 500, height: 260))
    root.wantsLayer = true
    window.contentView = root
    let heading = settingsLabel(route == nil ? "Add Route" : "Edit Route", size: 16, weight: .semibold)
    heading.frame = NSRect(x: 24, y: 20, width: 452, height: 24)
    root.addSubview(heading)
    func label(_ title: String, y: CGFloat) {
      let view = settingsLabel(title, size: 13, weight: .medium)
      view.frame = NSRect(x: 24, y: y, width: 110, height: 22)
      root.addSubview(view)
    }
    label("Match", y: 59)
    label("Link text", y: 99)
    label("Open in", y: 139)
    condition.frame = NSRect(x: 140, y: 56, width: 160, height: 28)
    condition.setAccessibilityIdentifierWithCell("settings.route.condition")
    condition.setAccessibilityLabel("Match condition")
    condition.showIndex(conditionIndex)
    condition.onIndexChange = { [weak self] in self?.conditionIndex = $0 }
    root.addSubview(condition)
    literal.frame = NSRect(x: 140, y: 96, width: 336, height: 24)
    literal.stringValue = text
    literal.setAccessibilityIdentifierWithCell("settings.route.literal")
    literal.setAccessibilityLabel("Link text")
    root.addSubview(literal)
    destination.frame = NSRect(x: 140, y: 136, width: 250, height: 28)
    destination.setAccessibilityIdentifierWithCell("settings.route.destination")
    destination.setAccessibilityLabel("Route destination")
    destination.showIndex(destinationIndex)
    destination.onIndexChange = { [weak self] in self?.destinationIndex = $0 }
    root.addSubview(destination)
    cancel.frame = NSRect(x: 304, y: 202, width: 76, height: 28)
    save.frame = NSRect(x: 400, y: 202, width: 76, height: 28)
    cancel.setAccessibilityIdentifierWithCell("settings.route.cancel")
    save.setAccessibilityIdentifierWithCell("settings.route.save")
    cancel.setAccessibilityLabel("Cancel")
    save.setAccessibilityLabel("Save")
    cancel.target = self; cancel.action = #selector(cancelPressed(_:))
    save.target = self; save.action = #selector(savePressed(_:)); save.keyEquivalent = "\r"
    root.addSubview(cancel); root.addSubview(save)
    literal.nextKeyView = condition; condition.nextKeyView = destination
    destination.nextKeyView = cancel; cancel.nextKeyView = save; save.nextKeyView = literal
    window.initialFirstResponder = literal
    window.onEscape = { [weak self] in self?.finish(nil); return true }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func begin(on parent: NSWindow) {
    guard let window else { return }
    parent.beginSheet(window) { [weak self] _ in self?.finish(nil) }
    window.makeFirstResponder(literal)
  }

  func dismiss() { finish(nil) }

  @objc private func cancelPressed(_ sender: Any?) { finish(nil) }
  @objc private func savePressed(_ sender: Any?) {
    window?.makeFirstResponder(nil)
    let value: SettingsLinkRoute.Condition = conditionIndex == 0 ? .contains(literal.stringValue) : .matches(literal.stringValue)
    finish(SettingsLinkRoute(condition: value, destination: destinations[destinationIndex]))
  }
  private func finish(_ result: SettingsLinkRoute?) {
    guard let callback = onFinish else { return }
    onFinish = nil
    if let window { window.sheetParent?.endSheet(window); window.orderOut(nil) }
    callback(result)
  }
}
