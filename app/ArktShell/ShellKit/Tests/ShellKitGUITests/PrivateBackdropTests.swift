import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@_spi(Smoke) @testable import ShellUI

/// #766: a Blank or Incognito window draws the design's neutral backdrop (design/private-pages, `prototype.html`
/// `--theme-a` and `--theme-b`), light or dark by the window's appearance, never the theme of the Space it opened on.
/// Its chrome takes the backdrop's flavor. Normal windows keep their Space theme. InMemoryEngine; no wall-clock waits.
@MainActor
final class PrivateBackdropTests: XCTestCase {
  private var sets: [ShellWindowSet] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets { for controller in set.controllers { controller.window?.orderOut(nil) } }
    sets = []
  }

  /// Strong Space themes, far from the backdrop: a saturated red light theme and a deep blue dark one.
  static let redLight = SpaceThemeInfo(baseColors: [.srgb(hex: 0xFF3B30), .srgb(hex: 0xFF9500)], isDark: false)
  static let blueDark = SpaceThemeInfo(baseColors: [.srgb(hex: 0x0A1A6B), .srgb(hex: 0x1D1838)],
                                       texture: "grain", noiseFactor: 0.5, isDark: true)

  private struct Fixture {
    let set: ShellWindowSet
    let source: StubSidebar
    let red: SpaceID
    let blue: SpaceID
  }

  private func makeFixture() -> Fixture {
    let engine = InMemoryEngine()
    let source = StubSidebar()
    let red = source.addSpace(title: "Red", theme: Self.redLight)
    let blue = source.addSpace(title: "Blue", theme: Self.blueDark)
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    sets.append(set)
    return Fixture(set: set, source: source, red: red, blue: blue)
  }

  /// Sets the window's appearance, as a system appearance change reaches it, and hands it to the theme drawing.
  private func setAppearance(_ controller: ShellWindowController, dark: Bool) throws {
    let window = try XCTUnwrap(controller.window)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    controller.themeContextObserver?.notify()
  }

  /// A window opened on `space`, then made private.
  private func privateWindow(_ f: Fixture, on space: SpaceID, dark: Bool,
                             incognito: Bool = true) throws -> ShellWindowController {
    let controller = f.set.openWindow(opensFirstTab: false)
    try setAppearance(controller, dark: dark)
    controller.sidebarController.showSpace(space)
    if incognito { controller.makeIncognito() } else { controller.makeBlank() }
    controller.rootView.layoutSubtreeIfNeeded()
    return controller
  }

  private func drawnBackdrop(dark: Bool) -> SpaceThemeInfo {
    ThemeContrast.drawn(PrivateBackdrop.theme(for: dark ? .dark : .light),
                        in: ThemeContext(appearance: dark ? .dark : .light))
  }

  private func assertBackdrop(_ controller: ShellWindowController, dark: Bool,
                              file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(controller.themeBackground.themes, [drawnBackdrop(dark: dark)], file: file, line: line)
    XCTAssertEqual(controller.sidebarController.view.flavor, dark ? .dark : .light, file: file, line: line)
  }

  // MARK: The backdrop

  /// The design's colors, as `prototype.html` gives them.
  func testBackdropColorsAreTheDesignTokens() {
    XCTAssertEqual(PrivateBackdrop.theme(for: .light).baseColors, [.srgb(hex: 0xE7E6EA), .srgb(hex: 0xD6D5DB)])
    XCTAssertEqual(PrivateBackdrop.theme(for: .dark).baseColors, [.srgb(hex: 0x34343B), .srgb(hex: 0x222227)])
    XCTAssertEqual(PrivateBackdrop.theme(for: .light).flavor, .light)
    XCTAssertEqual(PrivateBackdrop.theme(for: .dark).flavor, .dark)
    // The automatic contrast rule leaves them as they are without Increase Contrast.
    XCTAssertEqual(drawnBackdrop(dark: false).baseColors, PrivateBackdrop.theme(for: .light).baseColors)
    XCTAssertEqual(drawnBackdrop(dark: true).baseColors, PrivateBackdrop.theme(for: .dark).baseColors)
  }

  /// Opened from a light or a dark Space theme, in a light or a dark appearance, Blank or Incognito: the window
  /// draws the backdrop of its appearance.
  func testPrivateWindowDrawsTheBackdropWhateverSpaceItOpenedOn() throws {
    let f = makeFixture()
    for (space, dark, incognito) in [(f.red, false, true), (f.red, true, false), (f.blue, false, false),
                                     (f.blue, true, true)] {
      let controller = try privateWindow(f, on: space, dark: dark, incognito: incognito)
      assertBackdrop(controller, dark: dark)
      controller.close()
    }
  }

  /// A window with no Spaces at all made private draws the backdrop too.
  func testPrivateWindowWithoutSpacesDrawsTheBackdrop() throws {
    let engine = InMemoryEngine()
    let set = ShellWindowSet(engine: engine, sidebar: StubSidebar(), hostLookup: { [engine] in engine.host(of: $0) })
    sets.append(set)
    let controller = set.openWindow(opensFirstTab: false)
    try setAppearance(controller, dark: true)
    controller.makeBlank()
    assertBackdrop(controller, dark: true)
  }

  /// The appearance changes while the window is open: the backdrop and the chrome's flavor switch with it.
  func testAppearanceChangeSwitchesTheBackdropLive() throws {
    let f = makeFixture()
    let controller = try privateWindow(f, on: f.blue, dark: false)
    assertBackdrop(controller, dark: false)
    try setAppearance(controller, dark: true)
    assertBackdrop(controller, dark: true)
    XCTAssertEqual(controller.sidebarController.view.privatePages.flavor, .dark)
    try setAppearance(controller, dark: false)
    assertBackdrop(controller, dark: false)
    XCTAssertEqual(controller.sidebarController.view.privatePages.flavor, .light)
  }

  /// Another window switching Spaces, or a Space's theme changing, leaves the private window as it was.
  func testSpaceChangesLeaveThePrivateWindowAlone() throws {
    let f = makeFixture()
    let normal = f.set.openWindow(opensFirstTab: false)
    try setAppearance(normal, dark: false)
    normal.sidebarController.showSpace(f.red)
    let controller = try privateWindow(f, on: f.red, dark: false)
    assertBackdrop(controller, dark: false)

    normal.sidebarController.showSpace(f.blue)
    f.source.setTheme(f.red, to: Self.blueDark)
    f.source.setTheme(f.blue, to: Self.redLight)
    assertBackdrop(controller, dark: false)
    // The normal window still draws its Spaces' themes.
    XCTAssertEqual(normal.themeBackground.themes.count, 2)
    XCTAssertEqual(normal.sidebarController.view.flavor,
                   normal.sidebarController.drawnSpace(f.blue)?.theme.flavor)
  }

  /// The cap toast keeps the untinted toast surface (README "Past the cap") in the backdrop's flavor, and follows
  /// the appearance.
  func testCapToastTakesTheBackdropFlavor() throws {
    let f = makeFixture()
    let controller = try privateWindow(f, on: f.red, dark: true)
    controller.toasts.view?.reduceMotion = { true }
    for index in 0..<PrivatePageOrder.cap {
      controller.openPrivately(URL(string: "https://example.org/\(index)")!, inNewPage: index > 0)
    }
    controller.openPrivately(URL(string: "https://example.org/refused")!, inNewPage: true)
    XCTAssertEqual(controller.toasts.view?.theme, ToastView.plainTheme(.dark))
    try setAppearance(controller, dark: false)
    XCTAssertEqual(controller.toasts.view?.theme, ToastView.plainTheme(.light))
  }

  /// A normal window keeps its Space theme and its flavor.
  func testNormalWindowKeepsItsSpaceTheme() throws {
    let f = makeFixture()
    let controller = f.set.openWindow(opensFirstTab: false)
    try setAppearance(controller, dark: false)
    controller.sidebarController.showSpace(f.blue)
    let drawn = [f.red, f.blue].compactMap { controller.sidebarController.drawnSpace($0)?.theme }
    XCTAssertEqual(controller.themeBackground.themes, drawn)
    XCTAssertEqual(controller.sidebarController.view.flavor, drawn[1].flavor)
  }
}
