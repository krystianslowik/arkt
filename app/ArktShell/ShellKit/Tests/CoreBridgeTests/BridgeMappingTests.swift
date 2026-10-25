import AppKit
import ShellUI
import SidebarModel
import Testing
@testable import CoreBridge

/// `BridgeMapping.modelColor` (#296): a failed Display P3 to sRGB conversion must never crash the write of a
/// Space theme; the components are clamped and copied instead, and the fault is logged.
struct BridgeMappingColorTests {
  @Test func anSRGBColorPassesThroughUnconverted() {
    let color = ShellUI.RGBA(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5, space: .sRGB)
    #expect(BridgeMapping.modelColor(color) == SidebarModel.RGBA(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5))
  }

  @Test func aDisplayP3ColorConvertsToExtendedSRGBComponents() {
    // P3 red sits outside the sRGB gamut; extended sRGB keeps it as components outside 0...1 (Arc's stored form).
    let converted = BridgeMapping.modelColor(ShellUI.RGBA(red: 1, green: 0, blue: 0, alpha: 1, space: .displayP3))
    #expect(converted.red > 1)
    #expect(converted.green < 0)
    #expect(converted.blue < 0)
    #expect(converted.alpha == 1)
  }

  @Test func aColorThatCannotConvertIsStoredClampedAndDoesNotCrash() {
    let color = ShellUI.RGBA(red: 1.2, green: -0.3, blue: 0.5, alpha: 2, space: .displayP3)
    let converted = BridgeMapping.modelColor(color, convert: { _ in nil })
    #expect(converted == SidebarModel.RGBA(red: 1, green: 0, blue: 0.5, alpha: 1))
  }

  @Test func aConverterReturningTooFewComponentsFallsBackToClamped() {
    let color = ShellUI.RGBA(red: 1.2, green: -0.3, blue: 0.5, alpha: 2, space: .displayP3)
    let converted = BridgeMapping.modelColor(color, convert: { _ in [0.5] })
    #expect(converted == SidebarModel.RGBA(red: 1, green: 0, blue: 0.5, alpha: 1))
  }
}
