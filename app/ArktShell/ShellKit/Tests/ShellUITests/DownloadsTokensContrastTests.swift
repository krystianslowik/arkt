import Testing
@testable import ShellUI

/// The Downloads UI's colors on its surfaces: white on every file tile, and the graphite progress fill against its
/// track (design/downloads, Light and dark).
@MainActor
struct DownloadsTokensContrastTests {
  nonisolated static let flavors: [ThemeFlavor] = [.light, .dark]

  @Test func `white reads on every file tile`() {
    for ext in ["zip", "pdf", "mp4", "dmg", "csv", "txt", "pkg", "unknown"] {
      let fill = RGBA.srgb(hex: UInt32(DownloadsFormat.kind(of: "a.\(ext)").fillHex))
      let ratio = Contrast.ratio(.white(1), fill)
      #expect(ratio >= 4.5, "\(ext) \(ratio):1")
    }
  }

  @Test(arguments: flavors)
  func `the graphite fill is distinct from its track`(flavor: ThemeFlavor) {
    let surface = BrandTokens.surfaceBrand.resolve(flavor)
    let track = ShellContrastProbe.over(DownloadsTokens.progressTrack.resolve(flavor), surface)
    let fill = ShellContrastProbe.over(DownloadsTokens.progressFill.resolve(flavor), surface)
    let ratio = ShellContrastProbe.ratio(fill, track)
    #expect(ratio >= Contrast.minimumNonText, "\(flavor) \(ratio):1")
  }

  @Test(arguments: flavors)
  func `the progress fill is the text colour, graphite in light`(flavor: ThemeFlavor) {
    #expect(DownloadsTokens.progressFill == ShellTokens.primaryText)
    #expect(DownloadsTokens.progressFill.resolve(.light).alpha > 0.8)
    _ = flavor
  }
}
