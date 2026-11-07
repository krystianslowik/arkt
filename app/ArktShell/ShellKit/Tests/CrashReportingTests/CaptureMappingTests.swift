import Foundation
import Testing
@testable import CrashReporting

/// What the two capture sources hand over, mapped to raw crashes without MetricKit or a live exception.
struct CaptureMappingTests {
  private let tree = """
    {"callStackPerThread":true,"callStacks":[
      {"threadAttributed":false,"callStackRootFrames":[
        {"binaryUUID":"00000000-0000-0000-0000-00000000000A","offsetIntoBinaryTextSegment":10,"binaryName":"other","address":1}]},
      {"threadAttributed":true,"callStackRootFrames":[
        {"binaryUUID":"11111111-1111-1111-1111-111111111111","offsetIntoBinaryTextSegment":100,"binaryName":"dyld","address":1,
         "subFrames":[
           {"binaryUUID":"22222222-2222-2222-2222-222222222222","offsetIntoBinaryTextSegment":200,"binaryName":"ArktShell","address":2,
            "subFrames":[
              {"binaryUUID":"33333333-3333-3333-3333-333333333333","offsetIntoBinaryTextSegment":300,"binaryName":"AppKit","address":3}]}]}]}]}
    """

  @Test func theAttributedThreadComesOutTopFrameFirst() {
    let frames = MetricKitMapping.frames(fromCallStackTree: Data(tree.utf8))
    #expect(frames.map(\.image) == ["AppKit", "ArktShell", "dyld"])
    #expect(frames.map(\.offset) == [300, 200, 100])
    #expect(frames.first?.uuid == "33333333-3333-3333-3333-333333333333")
    #expect(frames.allSatisfy { $0.symbol == nil })
  }

  @Test func withoutAnAttributedThreadTheFirstStackIsUsed() {
    let json = #"{"callStacks":[{"callStackRootFrames":[{"binaryName":"only","offsetIntoBinaryTextSegment":5}]}]}"#
    #expect(MetricKitMapping.frames(fromCallStackTree: Data(json.utf8)).map(\.image) == ["only"])
  }

  @Test func garbageGivesNoFramesNotACrash() {
    #expect(MetricKitMapping.frames(fromCallStackTree: Data("not json".utf8)).isEmpty)
    #expect(MetricKitMapping.frames(fromCallStackTree: Data("{}".utf8)).isEmpty)
  }

  @Test func aVeryDeepTreeIsBounded() {
    var json = #"{"binaryName":"leaf","offsetIntoBinaryTextSegment":0}"#
    for index in 0..<5_000 { json = #"{"binaryName":"f\#(index)","offsetIntoBinaryTextSegment":1,"subFrames":[\#(json)]}"# }
    let frames = MetricKitMapping.frames(fromCallStackTree:
      Data(#"{"callStacks":[{"threadAttributed":true,"callStackRootFrames":[\#(json)]}]}"#.utf8))
    #expect(frames.count <= CrashReportStripper.maximumFrames * 4)
  }

  @Test func exceptionNamesCombineTheMachTypeAndTheSignal() {
    #expect(MetricKitMapping.exceptionName(type: 1, signal: 11) == "EXC_BAD_ACCESS (SIGSEGV)")
    #expect(MetricKitMapping.exceptionName(type: 10, signal: 6) == "EXC_CRASH (SIGABRT)")
    #expect(MetricKitMapping.exceptionName(type: 6, signal: nil) == "EXC_BREAKPOINT")
    #expect(MetricKitMapping.exceptionName(type: 99, signal: 99) == "EXC_UNKNOWN (SIG99)")
    #expect(MetricKitMapping.exceptionName(type: nil, signal: nil) == "EXC_UNKNOWN")
  }

  @Test func onlySIGABRTIsAnAbort() {
    #expect(MetricKitMapping.isAbort(signal: 6))
    #expect(!MetricKitMapping.isAbort(signal: 11))
    #expect(!MetricKitMapping.isAbort(signal: nil))
  }

  @Test func aSymbolicatedStackLineSplitsIntoImageAndSymbol() {
    let line = "3   AppKit                               0x00000001a3b4c5d0 -[NSApplication run] + 480"
    #expect(RawFrame.parse(callStackSymbol: line) == RawFrame(image: "AppKit", offset: nil, symbol: "-[NSApplication run] + 480"))
    let spaced = "12  Google Chrome Framework  0x000000010a0b0c0d 0x10a000000 + 721933"
    #expect(RawFrame.parse(callStackSymbol: spaced)?.image == "Google Chrome Framework")
    #expect(RawFrame.parse(callStackSymbol: "nonsense") == nil)
  }

  @Test func theUUIDIsKeptOnlyWhenItLooksLikeOne() {
    let raw = [RawFrame(image: "A", offset: 1, symbol: nil, uuid: "11111111-1111-1111-1111-111111111111"),
               RawFrame(image: "B", offset: 1, symbol: nil, uuid: "/Users/seedname/x")]
    let report = CrashFixtures.stripper.report(from: CrashFixtures.raw(frames: raw), id: "x")
    #expect(report.frames[0].uuid == "11111111-1111-1111-1111-111111111111")
    #expect(report.frames[1].uuid == nil)
  }

  @Test func theIssueBodyListsEachImageOnceWithItsUUID() throws {
    let raw = [RawFrame(image: "ArktShell", offset: 1, symbol: nil, uuid: "11111111-1111-1111-1111-111111111111"),
               RawFrame(image: "ArktShell", offset: 2, symbol: nil, uuid: "11111111-1111-1111-1111-111111111111"),
               RawFrame(image: "AppKit", offset: 3, symbol: nil, uuid: "22222222-2222-2222-2222-222222222222")]
    let report = CrashFixtures.stripper.report(from: CrashFixtures.raw(frames: raw), id: "x")
    let body = GitHubIssueLink.body(for: report, shownFrames: 3)
    #expect(body.components(separatedBy: "ArktShell 11111111-1111-1111-1111-111111111111").count == 2)
    #expect(body.contains("AppKit 22222222-2222-2222-2222-222222222222"))
  }
}
