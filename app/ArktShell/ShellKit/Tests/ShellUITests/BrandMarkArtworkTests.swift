import Testing
@testable import ShellUI

/// The mark comes from the approved artwork only (onboarding spec, sections 7.2 and 7.4).
@MainActor
struct BrandMarkArtworkTests {
  @Test func theRuleKeepsSaturatedOpaquePixels() {
    #expect(BrandMarkArtwork.isMark(red: 0xE9, green: 0xB5, blue: 0x20, alpha: 255))
    #expect(!BrandMarkArtwork.isMark(red: 0xE9, green: 0xB5, blue: 0x20, alpha: 200))
    #expect(!BrandMarkArtwork.isMark(red: 0xFA, green: 0xF9, blue: 0xF5, alpha: 255), "the porcelain plate")
    #expect(!BrandMarkArtwork.isMark(red: 0, green: 0, blue: 0, alpha: 255))
  }

  @Test func imageIsTheCroppedMark() throws {
    let image = try #require(BrandMarkArtwork.image)
    #expect(image.width < 456 && image.height < 456)
    #expect(BrandMarkArtwork.aspectRatio > 0.5 && BrandMarkArtwork.aspectRatio < 1.5)
  }

  /// The spec counts 6,622 samples at 140 px; resampling may differ by a few percent.
  @Test func samplesAt140Pixels() {
    let samples = BrandMarkArtwork.samples(width: 140)
    #expect(abs(samples.count - 6_622) < 300, "\(samples.count)")
    #expect(samples.allSatisfy { abs($0.y) <= 0.5 + 1e-3 })
  }
}
