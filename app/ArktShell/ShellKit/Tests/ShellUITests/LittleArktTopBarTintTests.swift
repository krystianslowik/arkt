import AppKit
import Testing
@testable import ShellUI

/// The split button's glyphs take the segment's text tone (#734): graphite (`onAccent`) on the mustard fill in both
/// appearances, `primaryText` on the quiet fill. The chooser has no title, so its chevron depends on the tint alone.
@MainActor
struct LittleArktTopBarTintTests {
  private func bar(accent: Bool, appearance: NSAppearance.Name) -> LittleArktTopBar {
    let bar = LittleArktTopBar(frame: NSRect(x: 0, y: 0, width: 420, height: 40))
    bar.appearance = NSAppearance(named: appearance)
    bar.configure(host: "example.com", fullURL: "https://example.com/", secure: true,
                  openLabel: accent ? "Open in Studio" : "Open as Tab", openHelp: "", accent: accent,
                  swatch: accent ? [.srgb(hex: 0x3366CC)] : [])
    bar.updateLayer()
    return bar
  }

  private func sRGB(_ color: NSColor?) -> [CGFloat]? {
    guard let color = color?.usingColorSpace(.sRGB) else { return nil }
    return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
  }

  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func `the chooser chevron is graphite on the mustard fill`(appearance: NSAppearance.Name) {
    let bar = bar(accent: true, appearance: appearance)
    let flavor = ThemeFlavor(appearance: NSAppearance(named: appearance)!)
    let expected = sRGB(BrandTokens.onAccent.resolve(flavor).littleArktColor)
    #expect(expected != nil)
    #expect(sRGB(bar.chooserButton.contentTintColor) == expected)
    #expect(sRGB(bar.chooserButton.contentTintColor) == sRGB(bar.openButton.contentTintColor))
  }

  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func `the chooser chevron follows the window on the quiet fill`(appearance: NSAppearance.Name) {
    let bar = bar(accent: false, appearance: appearance)
    let flavor = ThemeFlavor(appearance: NSAppearance(named: appearance)!)
    let expected = sRGB(ShellTokens.primaryText.resolve(flavor).littleArktColor)
    #expect(expected != nil)
    #expect(sRGB(bar.chooserButton.contentTintColor) == expected)
    #expect(sRGB(bar.chooserButton.contentTintColor) == sRGB(bar.openButton.contentTintColor))
  }

  @Test func `graphite on mustard is the same in light and dark`() {
    let light = bar(accent: true, appearance: .aqua)
    let dark = bar(accent: true, appearance: .darkAqua)
    #expect(sRGB(light.chooserButton.contentTintColor) != nil)
    #expect(sRGB(light.chooserButton.contentTintColor) == sRGB(dark.chooserButton.contentTintColor))
  }
}
