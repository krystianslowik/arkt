import AppKit
import Testing
@testable import ShellUI

@MainActor
struct SpaceHeaderDragTests {
  @Test func slotDeltaRoundsToWholeSlots() {
    let pitch = SidebarMetrics.spaceDotSize + SidebarMetrics.spaceDotSpacing
    #expect(SpaceHeaderDrag.slotDelta(translation: pitch, pitch: pitch) == 1)
    #expect(SpaceHeaderDrag.slotDelta(translation: -pitch, pitch: pitch) == -1)
    #expect(SpaceHeaderDrag.slotDelta(translation: pitch / 2, pitch: pitch) == 1)
    #expect(SpaceHeaderDrag.slotDelta(translation: SidebarMetrics.spaceHeaderDragThreshold, pitch: pitch) == nil)
    #expect(SpaceHeaderDrag.slotDelta(translation: 0, pitch: pitch) == nil)
    #expect(SpaceHeaderDrag.slotDelta(translation: 10, pitch: 0) == nil)
  }

  /// One slot is one header width, the header's own geometry (not the dock's 21.5 pt dot pitch).
  @Test func pitchIsTheHeaderWidth() {
    #expect(SpaceHeaderDrag.pitch(headerWidth: 240) == 240)
    #expect(SpaceHeaderDrag.slotDelta(translation: 119, pitch: SpaceHeaderDrag.pitch(headerWidth: 240)) == nil)
    #expect(SpaceHeaderDrag.slotDelta(translation: 120, pitch: SpaceHeaderDrag.pitch(headerWidth: 240)) == 1)
    #expect(SpaceHeaderDrag.pitch(headerWidth: -1) == 0)
  }

  /// The title tracks 1:1 while a slot is reachable and resists past the last one, never stopping dead.
  @Test func displayedOffsetTracksThenRubberBands() {
    let pitch: CGFloat = 200
    #expect(SpaceHeaderDrag.displayedOffset(150, slotsBefore: 0, slotsAfter: 1, pitch: pitch) == 150)
    #expect(SpaceHeaderDrag.displayedOffset(-150, slotsBefore: 1, slotsAfter: 0, pitch: pitch) == -150)
    let past = SpaceHeaderDrag.displayedOffset(300, slotsBefore: 0, slotsAfter: 1, pitch: pitch)
    #expect(past > 200 && past < 300)
    let alone = SpaceHeaderDrag.displayedOffset(-80, slotsBefore: 0, slotsAfter: 0, pitch: pitch)
    #expect(alone < 0 && alone > -80)
    #expect(SpaceHeaderDrag.displayedOffset(-90, slotsBefore: 0, slotsAfter: 0, pitch: pitch) < alone)
  }

  @Test func moveIndexUsesTheFullOrderAndSkipsOtherProfiles() {
    let a = UUID(), b = UUID(), c = UUID(), other = UUID()
    #expect(SpaceHeaderDrag.moveIndex(id: a, order: [a, b, c], visible: [a, b, c], delta: 1) == 2)
    #expect(SpaceHeaderDrag.moveIndex(id: c, order: [a, b, c], visible: [a, b, c], delta: -2) == 0)
    #expect(SpaceHeaderDrag.moveIndex(id: b, order: [a, b, c], visible: [a, b, c], delta: 0) == nil)
    #expect(SpaceHeaderDrag.moveIndex(id: UUID(), order: [a, b, c], visible: [a, b, c], delta: 1) == nil)
    #expect(SpaceHeaderDrag.moveIndex(id: a, order: [a, b, c], visible: [a, b, c], delta: 9) == 3)
    // other stays put: dragging A onto B lands A after B, and dragging B onto A lands B before A.
    #expect(SpaceHeaderDrag.moveIndex(id: a, order: [a, other, b], visible: [a, b], delta: 1) == 3)
    #expect(SpaceHeaderDrag.moveIndex(id: b, order: [a, other, b], visible: [a, b], delta: -1) == 0)
    #expect(SpaceHeaderDrag.moveIndex(id: a, order: [a, other, b], visible: [a, b], delta: -1) == nil)
  }
}

@MainActor
struct SpaceOptionsMenuTests {
  @Test func menuOffersIconThemeAndADisabledProfile() throws {
    let stub = StubSidebar()
    let id = stub.addSpace(title: "A", theme: SpaceThemeCatalog.paper)
    stub.setIcon(id, to: .symbol("star"))
    let page = SpacePageView(source: stub, spaceID: id)
    #expect(page.titleLabel.toolTip == SpacePageView.reorderToolTip)

    let menu = page.makeOptionsMenu()
    #expect(menu.accessibilityIdentifier() == AXID.Sidebar.spaceMenu)
    #expect(menu.items.map(\.title) == ["Icon", "Theme", "Profile"])
    let profile = menu.items[2]
    #expect(profile.isEnabled == false)
    #expect(profile.action == nil)

    let icons = try #require(menu.item(withTitle: "Icon")?.submenu)
    #expect(icons.items.filter { !$0.isSeparatorItem }.map(\.title)
      == SpaceIconCatalog.choices.map(\.title) + [SpacePageView.emojiItemTitle])
    #expect(icons.item(withTitle: "Star")?.state == .on)
    #expect(icons.item(withTitle: "None")?.state == .off)
    #expect(icons.item(withTitle: SpacePageView.emojiItemTitle)?.state == .off)
    let themes = try #require(menu.item(withTitle: "Theme")?.submenu)
    #expect(themes.items.map(\.title) == ["Default", "Paper", "Dusk"])
    #expect(themes.item(withTitle: "Paper")?.state == .on)
    #expect(themes.item(withTitle: "Default")?.state == .off)

    page.pickTheme(try #require(themes.item(withTitle: "Dusk")))
    page.pickIcon(try #require(icons.item(withTitle: "None")))
    #expect(stub.space(id)?.theme == SpaceThemeCatalog.dusk)
    #expect(stub.space(id)?.icon == nil)

    let again = page.makeOptionsMenu()
    #expect(again.item(withTitle: "Theme")?.submenu?.item(withTitle: "Dusk")?.state == .on)
    #expect(again.item(withTitle: "Icon")?.submenu?.item(withTitle: "None")?.state == .on)
  }

  /// D2 on #279: "Default" clears the Space's own theme; it is the checked choice exactly while there is none.
  @Test func defaultClearsTheThemeAndIsCheckedOnlyWithoutOne() throws {
    let stub = StubSidebar()
    let id = stub.addSpace(title: "A", theme: SpaceThemeCatalog.dusk)
    let page = SpacePageView(source: stub, spaceID: id)
    var changes: [SidebarChange] = []
    let observation = stub.observe { changes.append($0) }
    let themes = try #require(page.makeOptionsMenu().item(withTitle: "Theme")?.submenu)
    page.pickTheme(try #require(themes.item(withTitle: "Default")))
    #expect(stub.space(id)?.usesDefaultTheme == true)
    #expect(stub.space(id)?.theme == StubSidebar.defaultTheme)
    #expect(changes == [.spaceChanged(id)])

    let after = try #require(page.makeOptionsMenu().item(withTitle: "Theme")?.submenu)
    #expect(after.item(withTitle: "Default")?.state == .on)
    #expect(after.item(withTitle: "Dusk")?.state == .off)
    #expect(after.item(withTitle: "Paper")?.state == .off)
    page.pickTheme(try #require(after.item(withTitle: "Default")))
    #expect(changes.count == 1, "already the default")

    // A Space whose own theme equals the default is not on "Default".
    let own = SpaceThemeCatalog.Choice(title: "Own", theme: StubSidebar.defaultTheme)
    stub.setTheme(id, to: StubSidebar.defaultTheme)
    #expect(SpaceThemeCatalog.isCurrent(own, for: stub.space(id)))
    #expect(!SpaceThemeCatalog.isCurrent(SpaceThemeCatalog.choices[0], for: stub.space(id)))
    _ = observation
  }

  /// D1 on #279: the emoji entry writes exactly one emoji and nothing else.
  @Test func emojiEntryWritesOnlyOneEmoji() throws {
    let stub = StubSidebar()
    let id = stub.addSpace(title: "A")
    let page = SpacePageView(source: stub, spaceID: id)
    for text in ["", "1", "ab", "\u{1F680}\u{1F680}", "\u{2764}"] {
      #expect(page.setEmojiIcon(text) == false, "\(text.unicodeScalars.map(\.value))")
    }
    #expect(stub.space(id)?.icon == nil)
    #expect(page.setEmojiIcon("\u{1F680}"))
    #expect(stub.space(id)?.icon == .emoji("\u{1F680}"))
    let icons = try #require(page.makeOptionsMenu().item(withTitle: "Icon")?.submenu)
    #expect(icons.item(withTitle: SpacePageView.emojiItemTitle)?.state == .on)
    #expect(icons.item(withTitle: "None")?.state == .off)
  }

  /// The header tool tip is installed once for a header rect, not again on every layout.
  @Test func headerToolTipIsNotReinstalledByALayoutThatChangesNothing() {
    let stub = StubSidebar()
    let page = SpacePageView(source: stub, spaceID: stub.addSpace(title: "A"))
    page.frame = NSRect(x: 0, y: 0, width: 240, height: 400)
    page.layout()
    #expect(page.showsHeaderToolTipForTesting)
    let installs = page.headerToolTipInstallsForTesting
    page.layout()
    page.layout()
    #expect(page.headerToolTipInstallsForTesting == installs)
    page.frame.size.width = 260
    page.layout()
    #expect(page.headerToolTipInstallsForTesting == installs + 1)
  }
}

/// D1 on #279: one extended grapheme cluster that presents as an emoji. Emoji are built from scalars (no emoji in
/// sources).
struct SpaceEmojiValidationTests {
  @Test(arguments: [
    "\u{1F680}",                        // emoji presentation by default
    "\u{2764}\u{FE0F}",                 // text-default heart made emoji by VS16
    "1\u{FE0F}\u{20E3}",                // keycap
    "\u{1F1E9}\u{1F1EA}",               // flag
    "\u{1F468}\u{200D}\u{1F4BB}",       // ZWJ sequence
    "\u{1F44D}\u{1F3FD}",               // skin tone modifier
  ])
  func acceptsOneEmoji(text: String) {
    #expect(SpaceIconInfo.validatedEmoji(text) == .emoji(text))
    #expect(SpaceIconInfo.validatedEmoji(" \(text)\n") == .emoji(text), "surrounding whitespace is trimmed")
  }

  @Test(arguments: [
    "", " ", "1", "7", "#", "*", "a", "ab", "\u{2764}", "1\u{20E3}", "\u{00A9}", "\u{1F680}\u{1F680}",
    "\u{1F680}a", "1\u{1F3FB}",
  ])
  func rejectsAnythingElse(text: String) {
    #expect(SpaceIconInfo.validatedEmoji(text) == nil)
  }
}

@MainActor
struct ThemeCrossfadeTests {
  private func background() -> ThemeBackgroundView {
    let view = ThemeBackgroundView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
    view.reducesMotion = { false }
    view.crossfadeDuration = 0.28
    view.themes = [SpaceThemeCatalog.paper, SpaceThemeCatalog.paper]
    view.setPosition(0)
    return view
  }

  @Test func aSettledThemeChangeCrossfadesAndSetPositionSnaps() {
    let view = background()
    view.replaceThemes([SpaceThemeCatalog.dusk, SpaceThemeCatalog.paper], crossfade: true)
    let animation = view.crossfadeAnimationForTesting
    #expect(animation != nil)
    #expect(animation?.duration == 0.28)
    #expect((animation?.fromValue as? NSNumber)?.floatValue == 0)
    #expect((animation?.toValue as? NSNumber)?.floatValue == 1)
    view.setPosition(0)
    #expect(view.crossfadeAnimationForTesting == nil)
    #expect(stops(view.baseColorsForTesting) == stops(SpaceThemeCatalog.dusk.baseColors.map(\.cgColor)))
  }

  /// #296: the crossfade eases in and out, and the settle onto the new theme is tied to the animation's
  /// completion (CATransaction), not a wall-clock timer. A view in no window has no render server pacing, so
  /// the test does not watch the clock: it checks the curve's control points and that the settle happens.
  @Test func theCrossfadeEasesInAndOutAndSettlesOnCompletion() async throws {
    let view = background()
    view.replaceThemes([SpaceThemeCatalog.dusk, SpaceThemeCatalog.paper], crossfade: true)
    let animation = try #require(view.crossfadeAnimationForTesting)
    #expect(controlPoint(animation.timingFunction, at: 1) == (0.42, 0))
    #expect(controlPoint(animation.timingFunction, at: 2) == (0.58, 1))
    #expect(stops(view.baseColorsForTesting) == stops(SpaceThemeCatalog.paper.baseColors.map(\.cgColor)))
    try await Task.sleep(for: .milliseconds(500))
    #expect(view.crossfadeAnimationForTesting == nil)
    #expect(stops(view.baseColorsForTesting) == stops(SpaceThemeCatalog.dusk.baseColors.map(\.cgColor)))
  }

  @Test func reduceMotionAZeroDurationOrASwipeSnaps() {
    let view = background()
    view.reducesMotion = { true }
    view.replaceThemes([SpaceThemeCatalog.dusk, SpaceThemeCatalog.paper], crossfade: true)
    #expect(view.crossfadeAnimationForTesting == nil)
    #expect(stops(view.baseColorsForTesting) == stops(SpaceThemeCatalog.dusk.baseColors.map(\.cgColor)))

    view.reducesMotion = { false }
    view.crossfadeDuration = 0
    view.replaceThemes([SpaceThemeCatalog.paper, SpaceThemeCatalog.paper], crossfade: true)
    #expect(view.crossfadeAnimationForTesting == nil)

    view.crossfadeDuration = 0.28
    view.setPosition(0.4)
    view.replaceThemes([SpaceThemeCatalog.dusk, SpaceThemeCatalog.dusk], crossfade: true)
    #expect(view.crossfadeAnimationForTesting == nil)
    view.replaceThemes([SpaceThemeCatalog.paper], crossfade: true)
    #expect(view.crossfadeAnimationForTesting == nil)
  }

  @Test func onlyTheCurrentSpacesThemeAsksForACrossfade() {
    let stub = StubSidebar()
    let a = stub.addSpace(title: "A", theme: SpaceThemeCatalog.paper)
    let b = stub.addSpace(title: "B", theme: SpaceThemeCatalog.paper)
    let controller = SidebarController(source: stub)
    #expect(controller.consumeThemeCrossfade() == false)

    stub.renameSpace(a, to: "A2")
    stub.setIcon(a, to: .symbol("star"))
    #expect(controller.view.spaceDots.icons == [.symbol("star"), nil])
    #expect(controller.consumeThemeCrossfade() == false)

    stub.setTheme(b, to: SpaceThemeCatalog.dusk)
    stub.moveSpace(b, to: 0)
    #expect(controller.consumeThemeCrossfade() == false)
    #expect(controller.currentSpace == a)

    stub.setTheme(a, to: SpaceThemeCatalog.dusk)
    #expect(controller.consumeThemeCrossfade() == true)
    #expect(controller.consumeThemeCrossfade() == false)
  }

  private func stops(_ colors: [CGColor]) -> [[CGFloat]] {
    colors.map { color in (color.components ?? []).map { ($0 * 1000).rounded() / 1000 } }
  }

  /// CAMediaTimingFunction has no name getter; the curve is identified by its two control points. A missing
  /// function reads as (-1, -1), which matches no real control point.
  private func controlPoint(_ function: CAMediaTimingFunction?, at index: Int) -> (x: Float, y: Float) {
    guard let function else { return (-1, -1) }
    var xy: [Float] = [-1, -1]
    xy.withUnsafeMutableBufferPointer { function.getControlPoint(at: index, values: $0.baseAddress!) }
    return (xy[0], xy[1])
  }
}

@MainActor
struct SpaceDockIconTests {
  private func dots(_ titles: [String] = ["A", "B"]) -> SpaceDotsView {
    let view = SpaceDotsView(frame: NSRect(x: 0, y: 0, width: 120, height: 28))
    view.titles = titles
    _ = view.layer
    view.layoutSubtreeIfNeeded()
    view.updateLayer()
    return view
  }

  private func components(_ color: CGColor?) -> [CGFloat] {
    (color?.components ?? []).map { ($0 * 1000).rounded() / 1000 }
  }

  /// A symbol is the dot's own fill seen through the symbol: the same contrast-tuned tokens as the dots (#72).
  @Test func aSymbolUsesTheDotsFillAndAnUnknownSymbolStaysADot() {
    let view = dots()
    view.icons = [.symbol("star"), .symbol("not.a.real.symbol")]
    view.updateLayer()
    let icon = view.markForTesting(0)
    let dot = view.markForTesting(1)
    #expect(icon?.mark == .symbol("star"))
    #expect(icon?.showsImage == true)
    #expect(icon?.width == SidebarMetrics.spaceIconSize)
    #expect(components(icon?.fill) == components(ShellTokens.primaryText.resolve(.light).cgColor))
    #expect(dot?.mark == .dot)
    #expect(dot?.showsImage == false)
    #expect(dot?.width == SidebarMetrics.spaceDotSize)
    #expect(components(dot?.fill) == components(ShellTokens.sidebarForeground.resolve(.light).cgColor))

    view.position = 1
    #expect(components(view.markForTesting(0)?.fill)
      == components(ShellTokens.sidebarForeground.resolve(.light).cgColor), "idle: the idle dot's token")
    #expect(view.dotFrame(0).width == view.dotFrame(1).width)
  }

  @Test func anEmojiKeepsItsColorsAndDimsByTheIdleDotsRatio() {
    let view = dots()
    view.icons = [nil, .emoji("\u{1F680}")]
    let emoji = view.markForTesting(1)
    #expect(emoji?.mark == .emoji("\u{1F680}"))
    #expect(emoji?.showsImage == true)
    #expect(emoji?.fill == nil)
    #expect(emoji?.width == SidebarMetrics.spaceIconSize)
    #expect(emoji?.opacity == SpaceDockIconPaint.emojiOpacity(0, flavor: .light))
    let idle = ShellTokens.sidebarForeground.light.alpha / ShellTokens.primaryText.light.alpha
    #expect(abs(Double(SpaceDockIconPaint.emojiOpacity(0, flavor: .light)) - idle) < 0.0001)
    #expect(SpaceDockIconPaint.emojiOpacity(1, flavor: .dark) == 1)
  }

  @Test func aSwipeRepaintsOnlyDotsWhoseWeightOrIconChanged() {
    let view = dots()
    let before = view.repaintCountForTesting
    view.position = 0.25
    let moved = view.repaintCountForTesting - before
    #expect(moved == 2)
    let painted = view.repaintCountForTesting
    view.icons = [nil, nil]
    #expect(view.repaintCountForTesting == painted)
    view.icons = [.symbol("star"), nil]
    #expect(view.repaintCountForTesting - painted == 1)
  }

  /// The swipe hot path: every frame moves `position`, and every neighbour's weight changes, but no icon image is
  /// set or made again and no layer is re-placed; only fills and opacities follow.
  @Test func swipeFramesNeverRedrawAnIcon() {
    let view = dots(["A", "B", "C"])
    view.icons = [.symbol("star"), .emoji("\u{1F680}"), nil]
    view.updateLayer()
    let paints = view.iconPaintCountForTesting
    let rasters = view.iconRasterCountForTesting
    let fills = view.repaintCountForTesting
    #expect(paints == 2)
    #expect(rasters == 2)
    let iconFrame = view.markForTesting(0)?.width

    for step in 1...40 { view.position = CGFloat(step) / 20 }

    #expect(view.iconPaintCountForTesting == paints)
    #expect(view.iconRasterCountForTesting == rasters)
    #expect(view.repaintCountForTesting > fills, "the fills and opacities did follow the swipe")
    #expect(view.markForTesting(0)?.width == iconFrame)
    #expect(view.markForTesting(1)?.opacity == SpaceDockIconPaint.emojiOpacity(view.fillWeight(1), flavor: .light))

    view.updateLayer()                                       // a layout re-places, keeps the images
    view.flavor = .dark
    #expect(view.iconPaintCountForTesting == paints)
    #expect(view.iconRasterCountForTesting == rasters)
    view.icons = [.symbol("bolt"), .emoji("\u{1F680}"), nil]
    #expect(view.iconPaintCountForTesting == paints + 1)
  }
}
