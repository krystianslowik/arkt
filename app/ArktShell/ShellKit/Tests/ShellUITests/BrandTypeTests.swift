import AppKit
import Testing
@testable import ShellUI

/// Onboarding spec, section 3: Avenir Next by PostScript name, the system font when a face is missing, tracking
/// per size and a fixed line height on display lines.
@MainActor
struct BrandTypeTests {
  @Test func facesArePostScriptNames() {
    #expect(BrandType.Weight.regular.postScriptName == "AvenirNext-Regular")
    #expect(BrandType.Weight.medium.postScriptName == "AvenirNext-Medium")
    #expect(BrandType.Weight.demiBold.postScriptName == "AvenirNext-DemiBold")
  }

  @Test func resolvesAvenirNextWhenInstalled() {
    // Avenir Next ships with macOS; the fallback path is covered below with a lookup that finds nothing.
    let font = BrandType.font(.demiBold, size: 64)
    #expect(font.pointSize == 64)
    #expect(font.fontName == "AvenirNext-DemiBold")
  }

  @Test(arguments: [BrandType.Weight.regular, .medium, .demiBold])
  func fallsBackToTheSystemFontAtTheSameSizeAndWeight(weight: BrandType.Weight) {
    let font = BrandType.font(weight, size: 18) { _, _ in nil }
    let system = NSFont.systemFont(ofSize: 18, weight: weight.systemWeight)
    #expect(font.pointSize == 18)
    #expect(font.fontName == system.fontName)
  }

  @Test func trackingIsEmTimesSize() {
    #expect(abs(BrandType.kern(em: -0.055, size: 64) - -3.52) < 1e-9)
    #expect(abs(BrandType.kern(em: 0.16, size: 12) - 1.92) < 1e-9)
  }

  /// The type table, regular and compact (section 4: below 700 pt tall).
  @Test func roleTableMatchesTheSpec() {
    typealias R = BrandType.Role
    func check(_ role: R, _ weight: BrandType.Weight, _ size: CGFloat, _ leading: CGFloat?, _ tracking: CGFloat,
               compact: Bool = false) {
      let style = role.style(compact: compact)
      #expect(style.weight == weight, "\(role)")
      #expect(style.size == size, "\(role) compact \(compact)")
      #expect(style.leading == leading, "\(role)")
      #expect(style.trackingEm == tracking, "\(role)")
    }
    check(.welcomeTitle, .demiBold, 80, 0.92, -0.055)
    check(.stepTitle, .demiBold, 64, 0.92, -0.055)
    check(.importTitle, .demiBold, 54, 0.92, -0.055)
    check(.nameField, .demiBold, 64, 1.02, -0.055)
    check(.countLarge, .demiBold, 210, 0.86, -0.04)
    check(.countRow, .demiBold, 64, 0.86, -0.04)
    check(.lede, .regular, 18, 1.5, 0)
    check(.welcomeLede, .regular, 20, 1.5, 0)
    check(.eyebrow, .demiBold, 12, nil, 0.16)
    check(.countLabel, .demiBold, 11, nil, 0.16)
    check(.countLabelLarge, .demiBold, 13, nil, 0.16)
    check(.button, .demiBold, 15, nil, 0.005)
    check(.quiet, .medium, 14, nil, 0)
    check(.progress, .regular, 13, nil, 0.01)
    check(.option, .medium, 15, nil, 0)
    check(.themeName, .regular, 13, nil, 0)
    check(.welcomeTitle, .demiBold, 72, 0.92, -0.055, compact: true)
    check(.stepTitle, .demiBold, 56, 0.92, -0.055, compact: true)
    check(.nameField, .demiBold, 56, 1.02, -0.055, compact: true)
    check(.countLarge, .demiBold, 176, 0.86, -0.04, compact: true)
    check(.countRow, .demiBold, 56, 0.86, -0.04, compact: true)
    check(.importTitle, .demiBold, 54, 0.92, -0.055, compact: true)
  }

  @Test func uppercaseRolesAreUppercased() {
    #expect(BrandType.Role.eyebrow.style(compact: false).uppercase)
    #expect(BrandType.Role.countLabel.style(compact: false).uppercase)
    #expect(!BrandType.Role.stepTitle.style(compact: false).uppercase)
  }

  @Test func attributedStringCarriesKernAndFixedLineHeight() throws {
    let text = BrandType.attributed("Open a tab.", role: .stepTitle, color: .black)
    var range = NSRange()
    let kern = try #require(text.attribute(.kern, at: 0, effectiveRange: &range) as? CGFloat)
    #expect(abs(kern - -3.52) < 1e-6)
    let paragraph = try #require(text.attribute(.paragraphStyle, at: 0, effectiveRange: &range) as? NSParagraphStyle)
    #expect(abs(paragraph.minimumLineHeight - 58.88) < 1e-6)
    #expect(abs(paragraph.maximumLineHeight - 58.88) < 1e-6)
    #expect(paragraph.alignment == .center)
  }

  @Test func uppercaseIsAppliedToTheString() {
    #expect(BrandType.attributed("Tip 1 of 5", role: .eyebrow, color: .black).string == "TIP 1 OF 5")
  }
}
