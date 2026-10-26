import AppKit
import CoreBridge
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// The Space theme creator popover (#410): opening from the Space header, layout, live re-tint, the writes, the
/// haptic gating of real drags, keyboard, accessibility and the session's undo step.
@MainActor
final class ThemeCreatorTests: XCTestCase {
  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let controller: ShellWindowController
    let ids: [SpaceID]
    let performer = RecordingPerformer()

    /// Two Spaces; the first has a two-colour sand theme at 80 % ("Studio"), the second the default theme.
    init(appearance: NSAppearance.Name = .aqua) {
      var sidebar = SidebarModel.Sidebar()
      let blue = ThemePad.color(ThemePadPoint(hue: 216, tone: 0.74))
      let copper = ThemePad.color(ThemePadPoint(hue: 27, tone: 0.34))
      let theme = SidebarModel.SpaceTheme(
        baseColors: [blue, copper].map { SidebarModel.RGBA(red: $0.red, green: $0.green, blue: $0.blue) },
        texture: "sand", noiseFactor: 0.4, opacity: 0.8, isDark: true)
      ids = [sidebar.addSpace(title: "Studio", theme: theme), sidebar.addSpace(title: "Plain")]
      source = ModelSidebarSource(sidebar: sidebar)
      controller = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
      controller.window?.appearance = NSAppearance(named: appearance)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.orderFront(nil)
      let performer = performer
      controller.sidebarController.makeThemeHaptics = { ThemeHaptics(performer: performer) }
      controller.sidebarController.themeCreatorReducesMotion = { true }
      controller.rootView.layoutSubtreeIfNeeded()
    }

    var sidebarController: SidebarController { controller.sidebarController }
    var creator: ThemeCreatorController? { sidebarController.themeCreator }
    var popover: ThemeCreatorView? { creator?.view }
    var stored: SpaceThemeInfo? { source.space(ids[0])?.theme }

    func page(_ id: SpaceID) -> SpacePageView? {
      controller.pager.pages.lazy.compactMap { $0 as? SpacePageView }.first { $0.spaceID == id }
    }

    /// Opens the creator through Theme > Edit Theme... of `id`'s header menu.
    func open(_ id: SpaceID? = nil) throws -> ThemeCreatorView {
      let page = try XCTUnwrap(self.page(id ?? ids[0]))
      let theme = try XCTUnwrap(page.makeOptionsMenu().item(withTitle: "Theme")?.submenu)
      let edit = try XCTUnwrap(theme.item(withTitle: "Edit Theme\u{2026}"))
      XCTAssertTrue(edit.isEnabled)
      XCTAssertTrue(theme.items[theme.index(of: edit) - 1].isSeparatorItem)
      page.editTheme(edit)
      let popover = try XCTUnwrap(self.popover)
      popover.layoutSubtreeIfNeeded()
      return popover
    }

    func event(_ type: NSEvent.EventType, at point: NSPoint, in view: NSView, clicks: Int = 1) throws -> NSEvent {
      try XCTUnwrap(NSEvent.mouseEvent(
        with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
        windowNumber: controller.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: clicks,
        pressure: 1))
    }

    func key(_ code: UInt16, shift: Bool = false) throws -> NSEvent {
      try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: 0,
        windowNumber: controller.window?.windowNumber ?? 0, context: nil, characters: "", charactersIgnoringModifiers: "",
        isARepeat: false, keyCode: code))
    }

    /// Drags dot `index` through `points` (pad coordinates) and leaves the button down.
    func drag(dot index: Int, through points: [CGPoint], in pad: ThemePadView) throws {
      let start = pad.dots[index].center
      pad.mouseDown(with: try event(.leftMouseDown, at: start, in: pad))
      for point in points { pad.mouseDragged(with: try event(.leftMouseDragged, at: point, in: pad)) }
    }

    func release(at point: CGPoint, in pad: ThemePadView) throws {
      pad.mouseUp(with: try event(.leftMouseUp, at: point, in: pad))
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  // MARK: - Opening and layout

  func testEditThemeOpensThePopoverBesideTheSpaceName() throws {
    let harness = Harness()
    let popover = try harness.open()
    XCTAssertTrue(popover.isDescendant(of: harness.controller.rootView))
    XCTAssertEqual(popover.frame.size, NSSize(width: 300, height: ThemeCreatorMetrics.height))
    // The arrow is level with the Space name, and the body clears the sidebar.
    let title = try XCTUnwrap(harness.page(harness.ids[0])?.titleLabel)
    let root = harness.controller.rootView
    let titleMid = title.convert(NSPoint(x: title.bounds.midX, y: title.bounds.midY), to: root)
    let arrowY = root.isFlipped ? popover.frame.minY + ThemeCreatorMetrics.arrowCenterY
      : popover.frame.maxY - ThemeCreatorMetrics.arrowCenterY
    XCTAssertEqual(arrowY, titleMid.y, accuracy: 0.5)
    let sidebarEdge = harness.sidebarController.view.convert(harness.sidebarController.view.bounds, to: root).maxX
    XCTAssertEqual(popover.frame.minX, sidebarEdge + 12, accuracy: 0.5)
    XCTAssertEqual(popover.titleLabel.stringValue, "Studio")
    // Focus starts on the first dot.
    XCTAssertTrue(harness.controller.window?.firstResponder === popover.pad.dots.first)
    harness.controller.close()
  }

  func testLayoutMatchesTheDesign() throws {
    let harness = Harness()
    let popover = try harness.open()
    XCTAssertEqual(popover.pad.frame.size, NSSize(width: 272, height: 212))
    XCTAssertEqual(popover.pad.frame.minX, 14)
    XCTAssertEqual(popover.countButton.frame.size, NSSize(width: 30, height: 22))
    XCTAssertEqual(popover.amountSlider.frame.height, 24)
    XCTAssertEqual(popover.opacitySlider.frame.width, 264)
    XCTAssertEqual(ThemeTextureSwatchesView.width, 5 * 18 + 4 * 6)
    XCTAssertEqual(popover.swatches.frame.maxX, popover.opacitySlider.frame.maxX)
    XCTAssertEqual(popover.pad.dots.count, 2)
    XCTAssertEqual(popover.pad.dots[0].frame.size, NSSize(width: 34, height: 34))
    XCTAssertEqual(ThemeCreatorMetrics.dot, 26)
    XCTAssertEqual(ThemeCreatorMetrics.track, 10)
    XCTAssertEqual(ThemeCreatorMetrics.knob, 24)
    XCTAssertEqual(ThemeCreatorMetrics.cornerRadius, 18)
    // The opacity knob sits at 80 %.
    XCTAssertEqual(popover.opacitySlider.value, 0.8, accuracy: 1e-9)
    XCTAssertEqual(popover.amountSlider.value, 0.4, accuracy: 1e-9)
    harness.controller.close()
  }

  // MARK: - Live re-tint and writes

  /// A dot drag re-tints the window on every event with no animation and stores nothing until it ends; the end
  /// stores the theme and the window does not crossfade.
  func testADotDragPreviewsLiveAndStoresOnRelease() throws {
    let harness = Harness()
    let background = harness.controller.themeBackground
    background.reducesMotion = { false }
    let popover = try harness.open()
    let before = harness.stored
    let pad = popover.pad
    let target = ThemePad.location(of: ThemePadPoint(hue: 120, tone: 0.9), in: pad.bounds.size)
    try harness.drag(dot: 0, through: [target], in: pad)
    XCTAssertEqual(harness.stored, before, "nothing is stored mid-drag")
    let drawn = try XCTUnwrap(harness.creator?.model.theme)
    let expected = ThemeContrast.drawn(drawn, in: harness.sidebarController.themeContext)
    XCTAssertEqual(background.themes.first, expected)
    XCTAssertNil(background.crossfadeAnimationForTesting)
    try harness.release(at: target, in: pad)
    XCTAssertEqual(harness.stored, drawn)
    XCTAssertNil(background.crossfadeAnimationForTesting, "the stored theme matches the preview")
    harness.controller.close()
  }

  /// The sidebar text follows the drag: a pale colour in light mode draws dark text; a deep one light text.
  func testSidebarTextToneFollowsTheDrag() throws {
    let harness = Harness(appearance: .aqua)
    let popover = try harness.open()
    let pad = popover.pad
    harness.sidebarController.themeContext = ThemeContext(appearance: .light)
    try harness.drag(dot: 0, through: [ThemePad.location(of: ThemePadPoint(hue: 200, tone: 0.1), in: pad.bounds.size)],
                     in: pad)
    try harness.drag(dot: 1, through: [ThemePad.location(of: ThemePadPoint(hue: 60, tone: 0.1), in: pad.bounds.size)],
                     in: pad)
    XCTAssertEqual(harness.sidebarController.view.flavor, .light)
    let deep = ThemePad.location(of: ThemePadPoint(hue: 240, tone: 0.94), in: pad.bounds.size)
    try harness.drag(dot: 0, through: [deep], in: pad)
    try harness.drag(dot: 1, through: [deep], in: pad)
    XCTAssertEqual(harness.sidebarController.view.flavor, .dark)
    harness.controller.close()
  }

  func testTheColourCountButtonAddsAndRemovesTheSecondColour() throws {
    let harness = Harness()
    let popover = try harness.open()
    XCTAssertEqual(popover.countButton.accessibilityLabel(), "Use one colour")
    popover.countButton.onPress?()
    XCTAssertEqual(harness.stored?.baseColors.count, 1)
    XCTAssertEqual(popover.pad.dots.count, 1)
    XCTAssertEqual(popover.countButton.accessibilityLabel(), "Add a second colour")
    popover.countButton.onPress?()
    XCTAssertEqual(harness.stored?.baseColors.count, 2)
    XCTAssertEqual(popover.pad.dots.count, 2)
    harness.controller.close()
  }

  /// Dragged more than 24 pt off the pad and let go, a dot is removed; the last one cannot be.
  func testDraggingADotOffThePadRemovesIt() throws {
    let harness = Harness()
    let popover = try harness.open()
    let pad = popover.pad
    let outside = CGPoint(x: pad.bounds.maxX + 40, y: 20)
    try harness.drag(dot: 1, through: [outside], in: pad)
    XCTAssertEqual(pad.dots[1].alphaValue, 0.35, accuracy: 0.01)
    try harness.release(at: outside, in: pad)
    XCTAssertEqual(harness.stored?.baseColors.count, 1)
    XCTAssertEqual(pad.dots.count, 1)
    try harness.drag(dot: 0, through: [outside], in: pad)
    try harness.release(at: outside, in: pad)
    XCTAssertEqual(harness.stored?.baseColors.count, 1, "the last colour stays")
    harness.controller.close()
  }

  func testADoubleClickOnThePadAddsTheSecondColourThere() throws {
    let harness = Harness()
    let popover = try harness.open()
    popover.countButton.onPress?()
    let spot = ThemePad.location(of: ThemePadPoint(hue: 90, tone: 0.5), in: popover.pad.bounds.size)
    popover.pad.mouseDown(with: try harness.event(.leftMouseDown, at: spot, in: popover.pad, clicks: 2))
    XCTAssertEqual(harness.stored?.baseColors.count, 2)
    XCTAssertEqual(harness.stored?.baseColors.last, ThemePad.color(ThemePad.point(at: spot,
                                                                                 in: popover.pad.bounds.size)))
    harness.controller.close()
  }

  /// None disables the amount slider and keeps its value; a texture chosen again draws at it.
  func testTextureNoneKeepsTheAmount() throws {
    let harness = Harness()
    let popover = try harness.open()
    popover.swatches.select(0, byPointer: true)
    XCTAssertNil(harness.stored?.texture)
    XCTAssertEqual(harness.stored?.noiseFactor, 0.4)
    XCTAssertFalse(popover.amountSlider.isEnabled)
    XCTAssertEqual(popover.amountSlider.alphaValue, 0.4, accuracy: 1e-6)
    XCTAssertEqual(harness.controller.themeBackground.grainOpacityForTesting, 0)
    popover.swatches.select(4, byPointer: true)
    XCTAssertEqual(harness.stored?.texture, "tweed")
    XCTAssertEqual(harness.stored?.noiseFactor, 0.4)
    XCTAssertTrue(popover.amountSlider.isEnabled)
    harness.controller.close()
  }

  func testSlidersStoreOnReleaseAndKeysStepFivePercent() throws {
    let harness = Harness()
    let popover = try harness.open()
    let slider = popover.opacitySlider
    let quarter = CGPoint(x: slider.bounds.width * 0.25, y: slider.bounds.midY)
    slider.mouseDown(with: try harness.event(.leftMouseDown, at: quarter, in: slider))
    XCTAssertEqual(harness.stored?.opacity, 0.8, "a slider drag stores on release")
    slider.mouseUp(with: try harness.event(.leftMouseUp, at: quarter, in: slider))
    XCTAssertEqual(harness.stored?.opacity ?? 0, 0.25, accuracy: 1e-9)
    harness.controller.window?.makeFirstResponder(slider)
    slider.keyDown(with: try harness.key(124))
    XCTAssertEqual(harness.stored?.opacity ?? 0, 0.30, accuracy: 1e-9)
    XCTAssertEqual(slider.accessibilityValue() as? String, "30 percent")
    harness.controller.close()
  }

  /// A preset picked from the header while the creator is open moves the dots to its colours.
  func testAPresetPickedWhileOpenMovesTheDots() throws {
    let harness = Harness()
    let popover = try harness.open()
    harness.source.setTheme(harness.ids[0], to: SpaceThemeCatalog.paper)
    XCTAssertEqual(harness.creator?.model.theme, SpaceThemeCatalog.paper)
    let expected = ThemePad.nearestPoint(to: SpaceThemeCatalog.paper.baseColors[0])
    XCTAssertEqual(popover.pad.dots.first?.point, expected)
    harness.controller.close()
  }

  // MARK: - Keyboard, haptics, accessibility, undo

  /// Arrows move the focused dot (2 degrees, 2 %; Shift 10), Delete removes it; keyboard changes play no haptics.
  func testDotKeysMoveAndDeleteWithoutHaptics() throws {
    let harness = Harness()
    let popover = try harness.open()
    let dot = try XCTUnwrap(popover.pad.dots.first)
    let start = dot.point
    dot.keyDown(with: try harness.key(124, shift: true))
    XCTAssertEqual(popover.pad.dots[0].point.hue, start.hue + 10, accuracy: 1e-6)
    dot.keyDown(with: try harness.key(126))
    XCTAssertEqual(popover.pad.dots[0].point.tone, start.tone - 0.02, accuracy: 1e-6)
    XCTAssertEqual(harness.stored?.baseColors.first, ThemePad.color(popover.pad.dots[0].point))
    dot.keyDown(with: try harness.key(51))
    XCTAssertEqual(harness.stored?.baseColors.count, 1)
    XCTAssertTrue(harness.performer.patterns.isEmpty)
    harness.controller.close()
  }

  /// A pointer drag across a preset hue plays `.alignment`; onto the tone limit `.levelChange`; a texture click
  /// `.alignment`.
  func testPointerDragsPlayTheHapticMap() throws {
    let harness = Harness()
    let popover = try harness.open()
    let pad = popover.pad
    let size = pad.bounds.size
    let start = pad.dots[0].point
    // Across Sage (107) in small steps.
    let path = stride(from: 96.0, through: 118.0, by: 4.0).map {
      ThemePad.location(of: ThemePadPoint(hue: $0, tone: start.tone), in: size)
    }
    try harness.drag(dot: 0, through: [ThemePad.location(of: ThemePadPoint(hue: 96, tone: 0.5), in: size)], in: pad)
    try harness.release(at: path[0], in: pad)
    harness.performer.patterns.removeAll()
    try harness.drag(dot: 0, through: path, in: pad)
    try harness.release(at: path[path.count - 1], in: pad)
    XCTAssertEqual(harness.performer.patterns, [.alignment])
    // Straight up onto the top limit, crossing no preset hue.
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.06))
    let top = CGPoint(x: path[path.count - 1].x, y: -20)
    try harness.drag(dot: 0, through: [top], in: pad)
    try harness.release(at: top, in: pad)
    XCTAssertEqual(harness.performer.patterns.last, .levelChange)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.06))
    popover.swatches.select(1, byPointer: true)
    XCTAssertEqual(harness.performer.patterns.last, .alignment)
    harness.controller.close()
  }

  func testAccessibilityRolesLabelsAndValues() throws {
    let harness = Harness()
    let popover = try harness.open()
    XCTAssertEqual(popover.accessibilityRole(), .group)
    XCTAssertEqual(popover.accessibilitySubrole(), .dialog)
    XCTAssertEqual(popover.accessibilityLabel(), "Space Theme")
    XCTAssertEqual(popover.accessibilityTitle(), "Studio")
    XCTAssertEqual(popover.accessibilityIdentifier(), AXID.ThemeCreator.popover)
    XCTAssertEqual(popover.pad.accessibilityLabel(), "Colour")
    XCTAssertEqual(popover.pad.accessibilityIdentifier(), AXID.ThemeCreator.pad)
    let dots = popover.pad.dots
    XCTAssertEqual(dots.map { $0.accessibilityLabel() }, ["Colour 1", "Colour 2"])
    XCTAssertEqual(dots[0].accessibilityRole(), .slider)
    XCTAssertEqual(dots[0].accessibilityValue() as? String, "blue, light 26 percent")
    XCTAssertEqual(dots[1].accessibilityValue() as? String, "orange, light 66 percent")
    XCTAssertTrue(dots[0].accessibilityPerformIncrement())
    XCTAssertEqual(dots[0].accessibilityValue() as? String, "blue, light 28 percent")
    XCTAssertEqual(popover.swatches.accessibilityRole(), .radioGroup)
    let radios = try XCTUnwrap(popover.swatches.accessibilityChildren() as? [NSAccessibilityElement])
    XCTAssertEqual(radios.map { $0.accessibilityLabel() }, ["None", "Grain", "Sand", "Denim", "Tweed"])
    XCTAssertEqual(radios.map { $0.accessibilityValue() as? Int }, [0, 0, 1, 0, 0])
    XCTAssertEqual(popover.amountSlider.accessibilityLabel(), "Texture amount")
    XCTAssertEqual(popover.amountSlider.accessibilityValue() as? String, "40 percent")
    XCTAssertEqual(popover.opacitySlider.accessibilityValue() as? String, "80 percent")
    XCTAssertEqual(popover.countButton.accessibilityRole(), .button)
    // Tab order: colour-count button, dots, swatches, amount, opacity.
    XCTAssertTrue(popover.countButton.nextKeyView === dots[0])
    XCTAssertTrue(dots[1].nextKeyView === popover.swatches)
    XCTAssertTrue(popover.swatches.nextKeyView === popover.amountSlider)
    XCTAssertTrue(popover.amountSlider.nextKeyView === popover.opacitySlider)
    harness.controller.close()
  }

  /// Escape closes; every change stays applied, and Edit > Undo reverts the whole session in one step.
  func testEscapeClosesAndOneUndoRevertsTheSession() throws {
    let harness = Harness()
    let window = try XCTUnwrap(harness.controller.window)
    let before = harness.stored
    let popover = try harness.open()
    popover.countButton.onPress?()
    popover.swatches.select(1, byPointer: true)
    let after = harness.stored
    XCTAssertNotEqual(after, before)
    let dot = try XCTUnwrap(popover.pad.dots.first)
    dot.keyDown(with: try harness.key(53))
    XCTAssertNil(harness.creator)
    XCTAssertEqual(harness.stored, after)
    let undo = try XCTUnwrap(window.undoManager)
    XCTAssertTrue(undo.canUndo)
    undo.undo()
    XCTAssertEqual(harness.stored, before)
    XCTAssertTrue(undo.canRedo)
    undo.redo()
    XCTAssertEqual(harness.stored, after)
    harness.controller.close()
  }

  /// A Space on the default theme starts at 80 % and stores nothing until something changes.
  func testANewThemeStartsAtEightyPercentAndStoresOnlyAChange() throws {
    let harness = Harness()
    let popover = try harness.open(harness.ids[1])
    XCTAssertEqual(popover.opacitySlider.value, 0.8, accuracy: 1e-9)
    XCTAssertEqual(harness.source.space(harness.ids[1])?.usesDefaultTheme, true)
    popover.swatches.select(1, byPointer: true)
    XCTAssertEqual(harness.source.space(harness.ids[1])?.usesDefaultTheme, false)
    XCTAssertEqual(harness.source.space(harness.ids[1])?.theme.opacity, 0.8)
    harness.controller.close()
  }

  /// The window draws through the automatic contrast rule in its own appearance.
  func testTheWindowAppearanceDrivesTheContrastRule() throws {
    let harness = Harness(appearance: .darkAqua)
    XCTAssertEqual(harness.sidebarController.themeContext.appearance, .dark)
    harness.controller.window?.appearance = NSAppearance(named: .aqua)
    waitUntil("the light appearance reaches the sidebar") {
      harness.sidebarController.themeContext.appearance == .light
    }
    let stored = try XCTUnwrap(harness.stored)
    XCTAssertEqual(harness.controller.themeBackground.themes.first,
                   ThemeContrast.drawn(stored, in: ThemeContext(appearance: .light)))
    harness.controller.close()
  }
}

/// Records what the creator plays, in place of `NSHapticFeedbackManager.defaultPerformer`.
final class RecordingPerformer: NSObject, NSHapticFeedbackPerformer {
  var patterns: [NSHapticFeedbackManager.FeedbackPattern] = []

  func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern,
               performanceTime: NSHapticFeedbackManager.PerformanceTime) {
    patterns.append(pattern)
  }
}
