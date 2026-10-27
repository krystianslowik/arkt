import AppKit
import EngineAPI

/// The Little Arkt window: titled, with a full-size content view, a hidden transparent titlebar and a clear
/// background, so the rounded brand frame is what shows and the system shadow follows it (docs/design/little-arkt.md,
/// Layout). Reserved keys reach the main menu before the page; the window's own keys (Cmd-O, Cmd-Opt-O) before both.
@MainActor
final class LittleArktWindow: NSWindow {
  /// Where the engine's command selectors go (Back, Forward, Reload from the main menu).
  weak var commandHost: LittleArktEngineHost?
  /// The window's own key equivalents, asked first; true when taken.
  var onKeyEquivalent: (@MainActor (NSEvent) -> Bool)?
  var reservedKeys = ReservedKeys.arkt

  init(contentRect: NSRect) {
    super.init(contentRect: contentRect,
               styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
               backing: .buffered, defer: false)
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isOpaque = false
    backgroundColor = .clear
    isMovableByWindowBackground = false              // the top bar and the frame drag the window
    tabbingMode = .disallowed
    isReleasedWhenClosed = false
    minSize = LittleArktLayout.minimumSize
    animationBehavior = .none                        // the content's own springs are the motion
    setAccessibilityIdentifier(AXID.LittleArkt.window)
    setAccessibilityLabel(LittleArktCopy.windowDescription)
  }

  /// Close, minimize and zoom at x 12, 35 and 58, centered in the 40 pt top bar. The titlebar container is narrowed
  /// to the buttons, so it never takes clicks from the host label or the controls.
  func layoutTrafficLights() {
    guard !styleMask.contains(.fullScreen), let close = standardWindowButton(.closeButton),
          let titlebar = close.superview, let container = titlebar.superview else { return }
    let metrics = ShellMetrics.standard
    let height = LittleArktLayout.topBarHeight
    let width = metrics.trafficLightOrigin.x * 2 + metrics.trafficLightSpacing * 2 + close.frame.width
    let containerFrame = NSRect(x: 0, y: frame.height - height, width: width, height: height)
    if container.frame != containerFrame { container.frame = containerFrame }
    let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    for (index, kind) in kinds.enumerated() {
      guard let button = standardWindowButton(kind) else { continue }
      let x = metrics.trafficLightOrigin.x + CGFloat(index) * metrics.trafficLightSpacing
      let y = ((titlebar.bounds.height - button.frame.height) / 2).rounded()
      let origin = NSPoint(x: x, y: y)
      if button.frame.origin != origin { button.setFrameOrigin(origin) }
    }
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if onKeyEquivalent?(event) == true { return true }
    if reservedKeys.matches(event), NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return true }
    return super.performKeyEquivalent(with: event)
  }

  // MARK: Engine commands

  @objc func commandDispatch(_ sender: Any?) {
    guard let command = Self.command(of: sender) else { return }
    commandHost?.dispatch(command, disposition: .currentTab)
  }

  @objc func commandDispatchUsingKeyModifiers(_ sender: Any?) {
    guard let command = Self.command(of: sender) else { return }
    commandHost?.dispatch(command, disposition: ShellWindow.disposition(for: NSApp.currentEvent?.modifierFlags ?? []))
  }

  override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    switch item.action {
    case #selector(commandDispatch(_:)), #selector(commandDispatchUsingKeyModifiers(_:)):
      return commandHost?.validate(EngineCommand(rawValue: item.tag)) ?? false
    default:
      return super.validateUserInterfaceItem(item)
    }
  }

  private static func command(of sender: Any?) -> EngineCommand? {
    guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag else { return nil }
    return EngineCommand(rawValue: tag)
  }
}

/// The window's content view: the rounded brand frame (`surfaceBrand`, 12 pt corners) with the top bar and the page
/// card. Its layer is what the motion moves: lift and scale as a transform about the top center.
@MainActor
final class LittleArktRootView: NSView {
  let frameView = NSView()
  let topBar = LittleArktTopBar(frame: .zero)
  let card = ContentCardView()

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    frameView.wantsLayer = true
    frameView.layer?.cornerRadius = LittleArktLayout.cornerRadius
    frameView.layer?.cornerCurve = .continuous
    frameView.layer?.masksToBounds = true
    card.setAccessibilityIdentifier(AXID.LittleArkt.card)
    addSubview(frameView)
    frameView.addSubview(LittleArktFrameDragView())
    frameView.addSubview(topBar)
    frameView.addSubview(card)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var wantsUpdateLayer: Bool { true }

  /// Called after each layout pass (the JavaScript dialog panel retries a page view that arrived with it).
  var onLayout: (@MainActor () -> Void)?

  override func layout() {
    super.layout()
    defer { onLayout?() }
    frameView.frame = bounds
    frameView.subviews.first { $0 is LittleArktFrameDragView }?.frame = bounds
    topBar.frame = LittleArktLayout.topBarFrame(in: bounds)
    card.frame = LittleArktLayout.cardFrame(in: bounds)
    (window as? LittleArktWindow)?.layoutTrafficLights()
  }

  override func updateLayer() {
    let flavor = ThemeFlavor(appearance: effectiveAppearance)
    frameView.layer?.backgroundColor = BrandTokens.surfaceBrand.resolve(flavor).cgColor
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}

/// The frame around the card drags the window, like the top bar.
@MainActor
private final class LittleArktFrameDragView: WindowDragView {}

/// The engine's view of a Little Arkt window (`EngineWindowHosting`), separate from the controller because the
/// protocol's `window` is not optional. Holds the controller weakly.
@MainActor
public final class LittleArktEngineHost: EngineWindowHosting {
  public let window: NSWindow
  public let cardView: NSView
  public var forward: EngineCommandForwarding?
  public var onCloseRequested: (@MainActor () -> Void)?
  weak var controller: LittleArktWindowController?

  init(window: NSWindow, cardView: NSView) {
    self.window = window
    self.cardView = cardView
  }

  /// Close Tab and Close Window close the Little Arkt window; New Tab is the main window's.
  public func claim(_ command: EngineCommand) -> CommandClaim? {
    switch command {
    case .closeTab, .closeWindow: CommandClaim(isEnabled: true)
    default: nil
    }
  }

  public func perform(_ command: EngineCommand, disposition: EngineDisposition) -> Bool {
    switch command {
    case .closeTab, .closeWindow:
      window.performClose(nil)
      return true
    default:
      return false
    }
  }

  func dispatch(_ command: EngineCommand, disposition: EngineDisposition) {
    if claim(command) != nil {
      _ = perform(command, disposition: disposition)
    } else {
      forward?.execute(command, disposition)
    }
  }

  func validate(_ command: EngineCommand) -> Bool {
    if let claim = claim(command) { return claim.isEnabled }
    return forward?.validate(command) ?? false
  }
}
