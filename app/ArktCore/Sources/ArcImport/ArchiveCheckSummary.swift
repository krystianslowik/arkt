/// Counts-only text for the archive part of `arkt-import-check`. Never includes titles, URLs, ids or Space names:
/// only numbers and enum case names. Values stay lowercase so every line passes the import check's allowlist.
public enum ArchiveCheckSummary {
  public static func lines(report: ArchiveImportReport) -> [String] {
    var out = [
      "archive entries: \(report.entries)",
      "archive imported: \(report.imported) (manual \(report.manual), auto \(report.auto))",
      "archive sources: space \(report.fromSpace), little arc \(report.fromLittleArc), unknown \(report.fromUnknown)",
      "archive skipped: \(report.skipped.count)",
    ]
    let breakdown = Dictionary(report.decodeFailures.map { ($0.label, 1) }, uniquingKeysWith: +)
      .sorted { $0.key < $1.key }
      .map { "    \($0.key): \($0.value)" }
    for line in ImportCheckSummary.grouped(report.skipped.map { ImportCheckSummary.caseName($0.reason) }) {
      out.append(line)
      if line.hasPrefix("  decodeFailed:") { out += breakdown }
    }
    out.append("archive warnings: \(report.warnings.count)")
    out += ImportCheckSummary.grouped(report.warnings.map { ImportCheckSummary.caseName($0) })
    return out
  }
}
