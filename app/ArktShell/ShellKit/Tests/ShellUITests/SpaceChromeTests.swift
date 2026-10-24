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
  @Test func menuOffersIconAndThemeAndADisabledProfile() {
    let stub = StubSidebar()
    let id = stub.addSpace(title: "A", theme: SpaceThemeCatalog.paper)
    stub.setIcon(id, to: SpaceIconInfo(symbol: "star"))
    let page = SpacePageView(source: stub, spaceID: id)
    #expect(page.titleLabel.toolTip == "Drag to Reorder Space")

    let menu = page.makeOptionsMenu()
    #expect(menu.accessibilityIdentifier() == AXID.Sidebar.spaceMenu)
    #expect(menu.items.map(\.title) == ["Icon", "Theme", "Profile"])
    let profile = menu.items[2]
    #expect(profile.isEnabled == false)
    #expect(profile.action == nil)

    let icons = menu.item(withTitle: "Icon")?.submenu
    #expect(icons?.items.map(\.title) == SpaceIconCatalog.choices.map(\.title))
    #expect(icons?.item(withTitle: "Star")?.state == .on)
    #expect(icons?.item(withTitle: "None")?.state == .off)
    let themes = menu.item(withTitle: "Theme")?.submenu
    #expect(themes?.items.map(\.title) == ["Paper", "Dusk"])
    #expect(themes?.item(withTitle: "Paper")?.state == .on)

    page.pickTheme(themes!.item(withTitle: "Dusk")!)
    page.pickIcon(icons!.item(withTitle: "None")!)
    #expect(stub.space(id)?.theme == SpaceThemeCatalog.dusk)
    #expect(stub.space(id)?.icon == nil)

    let again = page.makeOptionsMenu()
    #expect(again.item(withTitle: "Theme")?.submenu?.item(withTitle: "Dusk")?.state == .on)
    #expect(again.item(withTitle: "Icon")?.submenu?.item(withTitle: "None")?.state == .on)
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
    stub.setIcon(a, to: SpaceIconInfo(symbol: "star"))
    #expect(controller.view.spaceDots.icons == ["star", nil])
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
}

@MainActor
struct SpaceDockIconTests {
  private func dots() -> SpaceDotsView {
    let view = SpaceDotsView(frame: NSRect(x: 0, y: 0, width: 120, height: 28))
    view.titles = ["A", "B"]
    _ = view.layer
    view.layoutSubtreeIfNeeded()
    view.updateLayer()
    return view
  }

  @Test func anIconReplacesTheDotAndAnUnknownSymbolDoesNot() {
    let view = dots()
    view.icons = ["star", "not.a.real.symbol"]
    view.updateLayer()
    let icon = view.markForTesting(0)
    let dot = view.markForTesting(1)
    #expect(icon?.hasContents == true)
    #expect(icon?.width == SidebarMetrics.spaceIconSize)
    #expect(icon?.opacity == SpaceDockIconPaint.opacity(1))
    #expect(dot?.hasContents == false)
    #expect(dot?.width == SidebarMetrics.spaceDotSize)
    #expect(dot?.opacity == 1)
    #expect(view.dotFrame(0).width == view.dotFrame(1).width)
  }

  @Test func aSwipeRepaintsOnlyDotsWhoseWeightOrSymbolChanged() {
    let view = dots()
    let before = view.repaintCountForTesting
    view.position = 0.25
    let moved = view.repaintCountForTesting - before
    #expect(moved == 2)
    let painted = view.repaintCountForTesting
    view.icons = [nil, nil]
    #expect(view.repaintCountForTesting == painted)
    view.icons = ["star", nil]
    #expect(view.repaintCountForTesting - painted == 1)
  }
}
