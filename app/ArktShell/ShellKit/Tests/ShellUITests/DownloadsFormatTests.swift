import EngineAPI
import Foundation
import Testing
@testable import ShellUI

/// The words and numbers of the Downloads UI (design/downloads, Behavior and VoiceOver): sizes, time left, the lines
/// under a name, the kind tile and the VoiceOver labels.
struct DownloadsFormatTests {
  private let url = URL(string: "https://files.example/data/Field-survey.zip")!
  private let english = Locale(identifier: "en_US")

  private func item(name: String = "Field-survey.zip", total: Int64? = 310_000_000, received: Int64 = 42_000_000,
                    state: DownloadState = .inProgress, speed: Int64 = 1_000_000,
                    danger: DownloadDangerType = .notDangerous) -> DownloadItem {
    DownloadItem(url: url, filename: name, totalBytes: total, receivedBytes: received, state: state,
                 dangerType: danger, bytesPerSecond: speed)
  }

  // MARK: Sizes

  @Test(arguments: [
    (Int64(0), "0 B"), (999, "999 B"), (1_000, "1 KB"), (96_000, "96 KB"), (1_800_000, "1.8 MB"),
    (42_000_000, "42 MB"), (212_000_000, "212 MB"), (310_000_000, "310 MB"), (2_400_000_000, "2.4 GB"),
    (1_000_000_000_000, "1 TB"),
  ])
  func `sizes use decimal units with at most one decimal`(_ bytes: Int64, _ text: String) {
    #expect(DownloadsFormat.size(bytes, locale: english) == text)
  }

  // MARK: Time left

  @Test(arguments: [
    (0, "Almost done"), (2, "Almost done"), (3, "3 s"), (20, "20 s"), (59, "59 s"), (60, "1 min"), (100, "2 min"),
    (3_540, "59 min"), (3_600, "1 h 00 min"), (3_900, "1 h 05 min"), (7_260, "2 h 01 min"),
  ])
  func `time left reads seconds, minutes and hours`(_ seconds: Int, _ text: String) {
    #expect(DownloadsFormat.timeLeft(seconds: seconds) == text)
  }

  // MARK: Lines

  @Test func `an active row reads amount of total and time left`() {
    #expect(DownloadsFormat.activeLine(item(speed: 2_000_000), locale: english) == "42 MB of 310 MB \u{00B7} 2 min left")
    #expect(DownloadsFormat.activeLine(item(received: 308_000_000, speed: 1_000_000), locale: english)
              == "308 MB of 310 MB \u{00B7} Almost done")
  }

  @Test func `an unknown total shows the amount only and a stalled one shows no time`() {
    #expect(DownloadsFormat.activeLine(item(total: nil), locale: english) == "42 MB")
    #expect(DownloadsFormat.activeLine(item(speed: 0), locale: english) == "42 MB of 310 MB")
  }

  @Test func `a paused row says so`() {
    #expect(DownloadsFormat.activeLine(item(state: .paused), locale: english) == "Paused \u{00B7} 42 MB of 310 MB")
  }

  @Test func `the library line adds the speed`() {
    #expect(DownloadsFormat.libraryLine(item(speed: 4_100_000), locale: english)
              == "42 MB of 310 MB \u{00B7} 1 min left \u{00B7} 4.1 MB/s")
  }

  @Test func `finished, failed, cancelled and blocked rows`() {
    let done = item(received: 212_000_000, state: .complete)
    #expect(DownloadsFormat.popoverLine(done, locale: english) == "Done, 212 MB")
    #expect(DownloadsFormat.libraryLine(done, locale: english) == "ZIP \u{00B7} 212 MB \u{00B7} files.example")
    let failed = item(state: .interrupted(.networkDisconnected))
    #expect(DownloadsFormat.popoverLine(failed, locale: english) == "Failed, Connection lost")
    #expect(DownloadsFormat.libraryLine(failed, locale: english) == "Failed \u{00B7} Connection lost \u{00B7} files.example")
    #expect(DownloadsFormat.libraryLine(item(state: .cancelled), locale: english) == "Cancelled \u{00B7} files.example")
    let blocked = item(state: .complete, danger: .dangerousFile)
    #expect(DownloadsFormat.popoverLine(blocked, locale: english) == "Unsafe file")
    #expect(DownloadsFormat.libraryLine(blocked, locale: english)
              == "Blocked \u{00B7} may be harmful \u{00B7} files.example")
    let uncommon = item(received: 4_000, state: .complete, danger: .uncommonContent)
    #expect(DownloadsFormat.libraryLine(uncommon, locale: english)
              == "ZIP \u{00B7} 4 KB \u{00B7} files.example \u{00B7} Not commonly downloaded")
  }

  // MARK: Kind tile

  @Test(arguments: [
    ("Field-survey.zip", "ZIP", 0x4A6A96), ("deck.PDF", "PDF", 0xB84A36), ("clip.mp4", "MP4", 0x6B4FB0),
    ("tool.dmg", "DMG", 0x4A5A4E), ("data.csv", "CSV", 0x3C7A52), ("notes.txt", "TXT", 0x6A6F76),
    ("installer.pkg", "PKG", 0x8A5A2E), ("README", "FILE", 0x6A6F76), ("archive.tar.gz", "GZ", 0x4A6A96),
    ("weird.abcdefgh", "ABCD", 0x6A6F76),
  ])
  func `the tile shows the extension on a fixed fill`(_ name: String, _ label: String, _ hex: Int) {
    let kind = DownloadsFormat.kind(of: name)
    #expect(kind.label == label)
    #expect(kind.fillHex == hex)
  }

  // MARK: VoiceOver

  @Test func `accessibility labels follow the design`() {
    #expect(DownloadsFormat.accessibilityLabel(item(total: 100, received: 13)) == "Downloading Field-survey.zip, 13 percent")
    #expect(DownloadsFormat.accessibilityLabel(item(total: nil)) == "Downloading Field-survey.zip")
    #expect(DownloadsFormat.accessibilityLabel(item(state: .complete)) == "Field-survey.zip, finished")
    #expect(DownloadsFormat.accessibilityLabel(item(state: .interrupted(.networkFailed))) == "Field-survey.zip, failed")
    #expect(DownloadsFormat.accessibilityLabel(item(state: .cancelled)) == "Field-survey.zip, cancelled")
    #expect(DownloadsFormat.accessibilityLabel(item(state: .complete, danger: .dangerousFile))
              == "Field-survey.zip, blocked")
    #expect(DownloadsFormat.accessibilityLabel(item(total: 100, received: 40, state: .paused))
              == "Field-survey.zip, paused, 40 percent")
  }

  @Test func `the library button label reports the state`() {
    #expect(DownloadsFormat.libraryButtonLabel(.idle) == "Library")
    #expect(DownloadsFormat.libraryButtonLabel(.active(fraction: 0.13)) == "Library, downloading 13 percent")
    #expect(DownloadsFormat.libraryButtonLabel(.active(fraction: nil)) == "Library, downloading")
    #expect(DownloadsFormat.libraryButtonLabel(.done) == "Library, downloads finished")
    #expect(DownloadsFormat.libraryButtonLabel(.attention) == "Library, a download needs attention")
  }

  @Test func `progress announces at 25, 50 and 75 percent only`() {
    #expect(DownloadsFormat.announcementBucket(fraction: nil) == 0)
    #expect(DownloadsFormat.announcementBucket(fraction: 0.24) == 0)
    #expect(DownloadsFormat.announcementBucket(fraction: 0.25) == 25)
    #expect(DownloadsFormat.announcementBucket(fraction: 0.74) == 50)
    #expect(DownloadsFormat.announcementBucket(fraction: 0.99) == 75)
    #expect(DownloadsFormat.announcementBucket(fraction: 1) == 75)
  }

  // MARK: Hosts and groups

  @Test func `the host is the url's host without a leading www`() {
    #expect(DownloadsFormat.host(of: URL(string: "https://www.files.example/a")!) == "files.example")
    #expect(DownloadsFormat.host(of: URL(string: "https://cdn.example.org/a")!) == "cdn.example.org")
    #expect(DownloadsFormat.host(of: URL(string: "file:///tmp/a")!) == "")
  }

  @Test func `downloads group into Today, Yesterday and Earlier, newest first`() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_800_000_000)                 // a fixed noon-ish instant
    func make(_ name: String, daysAgo: Int, hours: Double = 0) -> DownloadItem {
      DownloadItem(url: url, filename: name, startTime: now.addingTimeInterval(-Double(daysAgo) * 86_400 - hours * 3_600))
    }
    let items = [make("old", daysAgo: 5), make("y", daysAgo: 1), make("a", daysAgo: 0), make("b", daysAgo: 0, hours: 0.5)]
    let sections = DownloadsFormat.sections(items, now: now, calendar: calendar)
    #expect(sections.map(\.title) == ["Today", "Yesterday", "Earlier"])
    #expect(sections[0].items.map(\.filename) == ["a", "b"])
    #expect(sections[1].items.map(\.filename) == ["y"] && sections[2].items.map(\.filename) == ["old"])
    #expect(DownloadsFormat.sections([], now: now, calendar: calendar).isEmpty)
  }
}
