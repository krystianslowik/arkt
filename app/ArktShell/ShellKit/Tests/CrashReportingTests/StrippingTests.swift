import Foundation
import Testing
@testable import CrashReporting

/// The stripping table (#129): the report keeps an allow-list of fields and scrubs every string in it. A report seeded
/// with each forbidden value must come out with none of them, in any field and in the stored JSON.
struct StrippingTests {
  @Test func noSeededForbiddenValueSurvives() throws {
    let report = CrashFixtures.stripper.report(from: CrashFixtures.raw(), id: "11111111-1111-1111-1111-111111111111")
    let json = try String(decoding: JSONEncoder().encode(report), as: UTF8.self)
    for value in CrashFixtures.forbidden {
      #expect(!json.contains(value), "survived: \(value)")
    }
    for value in CrashFixtures.forbidden {
      #expect(!json.lowercased().contains(value.lowercased()), "survived (any case): \(value)")
    }
  }

  @Test func theAllowedFieldsAreKept() {
    let report = CrashFixtures.stripper.report(from: CrashFixtures.raw(), id: "22222222-2222-2222-2222-222222222222")
    #expect(report.id == "22222222-2222-2222-2222-222222222222")
    #expect(report.osVersion == "15.1 (24B83)")
    #expect(report.architecture == "arm64")
    #expect(report.appVersion == "0.1.0")
    #expect(report.appBuild == "7")
    #expect(report.engineVersion == "142.0.7444.0")
    #expect(report.exceptionType == "EXC_BAD_ACCESS (SIGSEGV)")
    #expect(report.frames.count == 3)
    #expect(report.frames[0].offset == 4096)
    #expect(report.frames[1].image == "AppKit")
    #expect(report.frames[2].image == "libsystem_kernel.dylib")
  }

  @Test func homePathsBecomeATildeAndOtherPathsLoseTheirDirectories() {
    let stripper = CrashReportStripper(homeDirectory: "/Users/seedname", userName: "seedname")
    #expect(stripper.scrub("open /Users/seedname/Documents/Taxes 2025/return.pdf now") == "open ~")
    #expect(stripper.scrub("/Users/seedname") == "~")
    #expect(stripper.scrub("at /Volumes/Disk/secrets/plan.txt") == "at <path>")
    #expect(stripper.scrub("-[NSView layout]") == "-[NSView layout]")
  }

  @Test func urlsAndExtensionIDsAreRemoved() {
    let stripper = CrashReportStripper(homeDirectory: "/Users/seedname", userName: "seedname")
    #expect(!stripper.scrub("fetch https://a.example/x?y=1 done").contains("example"))
    #expect(!stripper.scrub("chrome-extension://abcdefghijklmnopabcdefghijklmnop/p.html").contains("abcdefgh"))
    #expect(!stripper.scrub("id abcdefghijklmnopabcdefghijklmnop end").contains("abcdefgh"))
    #expect(!stripper.scrub("mailto:someone@example.com").contains("someone"))
  }

  @Test func theUserNameIsRemovedWhereverItAppears() {
    let stripper = CrashReportStripper(homeDirectory: "/Users/seedname", userName: "seedname")
    #expect(!stripper.scrub("Seedname's Mac seedname").lowercased().contains("seedname"))
  }

  @Test func shortKnownNamesAreIgnoredSoTextIsNotShredded() {
    let stripper = CrashReportStripper(homeDirectory: "/Users/u", userName: "u", redacting: ["A", "Ab", "Work"])
    #expect(stripper.scrub("A cat") == "A cat")
    #expect(stripper.scrub("a Work item") == "a <redacted> item")
  }

  @Test func theReasonAndAnnotationsNeverEnterTheReport() throws {
    var raw = CrashFixtures.raw()
    raw.exceptionReason = "unique-reason-marker"
    raw.annotations = ["k": "unique-annotation-marker"]
    let json = try String(decoding: JSONEncoder().encode(CrashFixtures.stripper.report(from: raw, id: "x")), as: UTF8.self)
    #expect(!json.contains("unique-reason-marker"))
    #expect(!json.contains("unique-annotation-marker"))
  }

  @Test func oddExceptionTypesAndVersionsAreReplacedNotKept() {
    var raw = CrashFixtures.raw()
    raw.exceptionType = "Not allowed: \(CrashFixtures.title)\nline two"
    raw.osVersion = String(repeating: "9", count: 200)
    let report = CrashFixtures.stripper.report(from: raw, id: "x")
    #expect(report.exceptionType == "unknown")
    #expect(report.osVersion == "unknown")
  }

  @Test func longStacksAndSymbolsAreBounded() {
    let frames = (0..<500).map { RawFrame(image: "Img", offset: $0, symbol: String(repeating: "s", count: 1_000)) }
    let report = CrashFixtures.stripper.report(from: CrashFixtures.raw(frames: frames), id: "x")
    #expect(report.frames.count == CrashReportStripper.maximumFrames)
    #expect(report.frames.allSatisfy { ($0.symbol?.count ?? 0) <= CrashReportStripper.maximumSymbolLength })
  }
}
