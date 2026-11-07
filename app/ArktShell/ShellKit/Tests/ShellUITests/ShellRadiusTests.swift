import CoreGraphics
import Foundation
import Testing
@testable import ShellUI

/// The chrome's corner radius scale (#620). The values are the ones the surfaces used before the scale existed, so a
/// change here is a visible change and needs screenshots.
@MainActor
struct ShellRadiusTests {
  @Test func scaleValuesArePinned() {
    #expect(ShellRadius.row == 9)
    #expect(ShellRadius.control == 8)
    #expect(ShellRadius.field == 10)
    #expect(ShellRadius.tile == 12)
    #expect(ShellRadius.card == 10)
    #expect(ShellRadius.popover == 12)
    #expect(ShellRadius.sheet == 14)
    #expect(ShellRadius.pill(height: 36) == 18)
    #expect(ShellRadius.pill(height: 28) == 14)
    #expect(ShellRadius.pill(height: 24) == 12)
  }

  @Test func rowShapedFillsFollowTheRowToken() {
    #expect(SidebarMetrics.rowCornerRadius == ShellRadius.row)
    #expect(SidebarDropCanvas.slotCornerRadius == ShellRadius.row)
    #expect(SettingsMetrics.rowRadius == ShellRadius.row)
    #expect(SettingsMetrics.paneItemRadius == ShellRadius.row)
    #expect(CommandBarGeometry.selectedRowRadius == ShellRadius.row)
  }

  @Test func smallControlsFollowTheControlToken() {
    #expect(SettingsMetrics.popUpRadius == ShellRadius.control)
    #expect(DialogMetrics.inputRadius == ShellRadius.control)
    #expect(LittleArktSegmentButton.cornerRadius == ShellRadius.control)
    #expect(CommandBarGeometry.previewButtonRadius == ShellRadius.control)
    #expect(ArchiveMetrics.chipRemoveRadius == ShellRadius.control)
  }

  @Test func recessedFieldsFollowTheFieldToken() {
    #expect(SettingsMetrics.groupRadius == ShellRadius.field)
    #expect(ArchiveMetrics.listRadius == ShellRadius.field)
  }

  @Test func cardsTilesPopoversAndSheetsFollowTheirTokens() {
    #expect(ShellMetrics.standard.cardCornerRadius == ShellRadius.card)
    #expect(CommandBarGeometry.previewThumbnailRadius == ShellRadius.card)
    #expect(LittleArktGeometry.cornerRadius == ShellRadius.popover)
    #expect(LittleArktLayout.cornerRadius == ShellRadius.popover)
    #expect(TabSwitcherView.cornerRadius == ShellRadius.popover)
    #expect(EditPinMetrics.cornerRadius == ShellRadius.popover)
    #expect(DialogMetrics.panelCornerRadius == ShellRadius.popover)
    #expect(ToastView.multiLineRadius == ShellRadius.popover)
    #expect(DialogMetrics.sheetCornerRadius == ShellRadius.sheet)
    #expect(DialogMetrics.alertCornerRadius == ShellRadius.sheet)
  }

  @Test func pillRadiiArePinned() {
    #expect(ZoomPillLayout.cornerRadius == 18)
    #expect(FindBarLayout.cornerRadius == 18)
    #expect(SettingsMetrics.capsuleHeight == 24)
    #expect(ToastView.dismissSize == 24)
  }

  /// Radii that fit no role keep their own names; their values are the literals they replaced (#620).
  @Test func surfaceRadiiArePinned() {
    #expect(SettingsMetrics.segmentedRadius == 9)
    #expect(SettingsMetrics.segmentedPlateRadius == 7)
    #expect(SettingsMetrics.keycapRadius == 6)
    #expect(SettingsMetrics.swatchRadius == 6)
    #expect(ArchiveMetrics.bannerRadius == 12)
    #expect(PeekLayout.grabberRadius == 3)
    #expect(CommandBarGeometry.scopeChipRadius == 6)
    #expect(ExtensionsPanelMetrics.dotRadius == 4)
    #expect(ExtensionsPanelMetrics.insertionLineRadius == 1)
    #expect(PrivatePageRowView.buttonRadius == 4)
    #expect(LittleArktIconButton.cornerRadius == 7)
    #expect(ImportCheckbox.cornerRadius == 4.5)
  }
}

/// A regression guard (#620): ShellUI sets a corner radius from a named constant (the `ShellRadius` scale or a
/// surface's metric enum), never from a number written at the assignment. `cornerRadius = 0` (square) is let through.
struct CornerRadiusLintTests {
  /// app/ArktShell/ShellKit/Sources/ShellUI, derived from this file's location:
  /// app/ArktShell/ShellKit/Tests/ShellUITests/ShellRadiusTests.swift
  static let root = URL(fileURLWithPath: #filePath).standardizedFileURL
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Sources/ShellUI")

  static let pattern = #"cornerRadius\s*=\s*(?!0(?![0-9.]))[0-9.]"#
  /// Onboarding artwork: fixed-scale miniatures whose every frame and radius is part of the drawing, not chrome.
  static let exempt = ["Onboarding/OnboardingStage.swift", "Onboarding/OnboardingThemeViews.swift"]

  static func literalAssignments(in source: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    return source.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
      let text = String(line)
      let range = NSRange(text.startIndex..., in: text)
      return regex.firstMatch(in: text, range: range) != nil ? text.trimmingCharacters(in: .whitespaces) : nil
    }
  }

  static func offendingLines() throws -> [String: [String]] {
    var result: [String: [String]] = [:]
    let prefix = root.path + "/"
    guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [:] }
    for case let url as URL in walker where url.pathExtension == "swift" {
      let path = url.standardizedFileURL.path.replacingOccurrences(of: prefix, with: "")
      guard !exempt.contains(path) else { continue }
      let lines = literalAssignments(in: try String(contentsOf: url, encoding: .utf8))
      guard !lines.isEmpty else { continue }
      result[path] = lines
    }
    return result
  }

  @Test func matcherSeesLiteralAssignments() {
    #expect(Self.literalAssignments(in: "layer?.cornerRadius = 12").count == 1)
    #expect(Self.literalAssignments(in: "tile.cornerRadius=4.5").count == 1)
    #expect(Self.literalAssignments(in: "gradient.cornerRadius = 14 * s").count == 1)
    #expect(Self.literalAssignments(in: "dot.cornerRadius = 0").isEmpty)
    #expect(Self.literalAssignments(in: "dot.cornerRadius = 0.5").count == 1)
    #expect(Self.literalAssignments(in: "layer?.cornerRadius = ShellRadius.row").isEmpty)
    #expect(Self.literalAssignments(in: "static let cornerRadius: CGFloat = 12").isEmpty)
    #expect(Self.literalAssignments(in: "mask.cornerRadius = cornerRadius").isEmpty)
  }

  @Test func sourcesAreFound() {
    #expect(FileManager.default.fileExists(atPath: Self.root.appending(path: "Theme/ShellTokens.swift").path))
    for path in Self.exempt {
      #expect(FileManager.default.fileExists(atPath: Self.root.appending(path: path).path), "\(path)")
    }
  }

  @Test func noCornerRadiusIsALiteral() throws {
    let offending = try Self.offendingLines()
    #expect(offending.isEmpty, "use ShellRadius or a metric enum constant: \(offending)")
  }
}
