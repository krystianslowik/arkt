import CoreGraphics
import Foundation
import Testing
@testable import ShellUI

/// The infobar row height is the engine's (#478): the engine reserves `ArktInfobarRowHeight` (the facade header) per
/// infobar at the top of the tab's container while the shell draws its row over that band, so the shell's rows must be
/// exactly that high. ShellUI may not import the facade module (`EngineABIIsolationTests`), so the test reads the
/// constant from the header's ShellKit copy, which that suite keeps byte-identical to the engine's.
struct InfobarMetricsTests {
  static let header = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appending(path: "../../Sources/ArktEngineABI/include/arkt_engine.h").standardizedFileURL

  /// The value of `enum { ArktInfobarRowHeight = N };` in `source`, nil when the header has no such line.
  static func rowHeight(in source: String) -> Int? {
    source.firstMatch(of: #/enum\s*\{\s*ArktInfobarRowHeight\s*=\s*(\d+)\s*\}\s*;/#).flatMap { Int($0.output.1) }
  }

  @Test func `the row height is the facade's ArktInfobarRowHeight`() throws {
    let source = try String(contentsOf: Self.header, encoding: .utf8)
    let engine = try #require(Self.rowHeight(in: source), "ArktInfobarRowHeight not found in \(Self.header.path)")
    #expect(InfobarMetrics.rowHeight == CGFloat(engine))
  }

  @Test func `the reader finds the constant and nothing else`() {
    #expect(Self.rowHeight(in: "enum { ArktInfobarRowHeight = 40 };") == 40)
    #expect(Self.rowHeight(in: "enum {ArktInfobarRowHeight=44};") == 44)
    #expect(Self.rowHeight(in: "// ArktInfobarRowHeight is 40") == nil)
  }
}
