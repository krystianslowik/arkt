import AppKit
import EngineAPI
import Testing
@testable import ShellUI

/// The download row (design/downloads): the buttons each state shows, its words, its VoiceOver label, the progress bar's
/// tween and the layout of a very long name. No window and no clock: the bar reads a number the test steps by hand.
@MainActor
struct DownloadRowViewTests {
  private let url = URL(string: "https://files.example/data/file.zip")!

  private func item(_ name: String = "Field-survey.zip", total: Int64? = 1_000, received: Int64 = 130,
                    state: DownloadState = .inProgress, danger: DownloadDangerType = .notDangerous) -> DownloadItem {
    DownloadItem(url: url, filename: name, totalBytes: total, receivedBytes: received, state: state,
                 dangerType: danger, bytesPerSecond: 100)
  }

  private func row(_ item: DownloadItem, style: DownloadRowView.Style = .popover, width: CGFloat = 304) -> DownloadRowView {
    let row = DownloadRowView(style: style, item: item)
    row.frame = NSRect(x: 0, y: 0, width: width, height: row.rowHeight)
    row.layoutSubtreeIfNeeded()
    return row
  }

  // MARK: Controls per state

  @Test func `an active row shows Cancel and the bar`() {
    let row = row(item())
    #expect(row.visibleControls == [.cancel] && row.showsBar && !row.bar.isHidden)
    #expect(!row.cancelButton.isHidden && row.showButton.isHidden && row.retryPill.isHidden)
  }

  @Test func `a finished popover row shows Show in Finder and opens on a click`() {
    let row = row(item(state: .complete))
    #expect(row.visibleControls == [.show] && !row.showsBar && row.bar.isHidden)
  }

  @Test func `a finished library row keeps its buttons until hover or selection`() {
    let row = row(item(state: .complete), style: .library)
    #expect(row.visibleControls.isEmpty)
    row.setHovered(true)
    #expect(row.visibleControls == [.show, .open] && !row.openPill.isHidden && row.primaryOpenPill.isHidden)
    row.setHovered(false)
    row.isSelected = true
    #expect(row.openPill.isHidden && !row.primaryOpenPill.isHidden, "the selected row's Open is the one primary")
  }

  @Test func `failed and cancelled rows offer Retry and Remove`() {
    #expect(row(item(state: .interrupted(.networkFailed))).visibleControls == [.retry, .remove])
    #expect(row(item(state: .cancelled)).visibleControls == [.retry, .remove])
  }

  @Test func `a held file offers Review, never Open`() {
    let held = row(item(state: .complete, danger: .dangerousFile), style: .library)
    held.isSelected = true
    #expect(held.visibleControls == [.review, .remove])
    #expect(held.openPill.isHidden && held.primaryOpenPill.isHidden)
    #expect(held.tile.isBlocked)
  }

  @Test func `an uncommon file gets Keep or Delete on its row, with no sheet`() {
    let uncommon = row(item(state: .complete, danger: .uncommonContent), style: .library)
    #expect(uncommon.visibleControls == [.keep, .delete])
    #expect(!uncommon.tile.isBlocked)
  }

  @Test func `a state change swaps the controls`() {
    let row = row(item())
    row.update(item(received: 1_000, state: .complete))
    #expect(row.visibleControls == [.show] && row.cancelButton.isHidden && row.bar.isHidden)
  }

  // MARK: Actions

  @Test func `each button reports its action with the download's id`() {
    let download = item(state: .interrupted(.networkFailed))
    let row = row(download)
    var log: [(DownloadRowAction, DownloadID)] = []
    row.onAction = { log.append(($0, $1)) }
    row.retryPill.performClick(nil)
    row.removeButton.performClick(nil)
    row.update(item())
    row.cancelButton.performClick(nil)
    row.update(item(state: .complete, danger: .dangerousFile))
    row.reviewPill.performClick(nil)
    #expect(log.map(\.0) == [.retry, .remove, .cancel, .review])
    #expect(log.allSatisfy { $0.1 == row.item.id } == false, "a new item replaced it in update")
  }

  // MARK: Words and VoiceOver

  @Test func `the row speaks its state`() {
    let row = row(item(total: 1_000, received: 130))
    #expect(row.accessibilityLabel() == "Downloading Field-survey.zip, 13 percent")
    #expect(row.accessibilityRole() == .group && row.isAccessibilityElement())
    #expect(row.bar.accessibilityRole() == .progressIndicator)
    #expect(row.bar.accessibilityMinValue() as? Double == 0 && row.bar.accessibilityMaxValue() as? Double == 1)
    #expect(abs((row.bar.accessibilityValue() as? Double ?? -1) - 0.13) < 1e-9)
    row.update(item(state: .complete))
    #expect(row.accessibilityLabel() == "Field-survey.zip, finished")
    row.update(item(state: .interrupted(.networkFailed)))
    #expect(row.accessibilityLabel() == "Field-survey.zip, failed")
    row.update(item(state: .complete, danger: .dangerousFile))
    #expect(row.accessibilityLabel() == "Field-survey.zip, blocked")
  }

  @Test func `buttons are labelled for VoiceOver`() {
    let row = row(item())
    #expect(row.cancelButton.accessibilityLabel() == "Cancel download")
    #expect(row.showButton.accessibilityLabel() == "Show in Finder")
    #expect(row.removeButton.accessibilityLabel() == "Remove from list")
    #expect(row.retryPill.accessibilityLabel() == "Retry" && row.reviewPill.accessibilityLabel() == "Review")
    #expect(row.openPill.accessibilityLabel() == "Open")
  }

  @Test func `the second line follows the style`() {
    let download = item(total: 310_000_000, received: 42_000_000)
    #expect(row(download).statusField.stringValue.hasPrefix("42 MB of 310 MB"))
    let done = item(received: 212_000_000, state: .complete)
    #expect(row(done).statusField.stringValue == "Done, 212 MB")
    #expect(row(done, style: .library).statusField.stringValue.hasPrefix("ZIP \u{00B7} 212 MB \u{00B7} files.example"))
  }

  // MARK: Worst cases

  @Test func `a very long name truncates in the middle and never reaches the buttons`() {
    let name = "Field-survey-2026-coastal-lichens-high-resolution-dataset-FINAL-v3-with-an-extremely-long-tail.zip"
    for style in [DownloadRowView.Style.popover, .library] {
      for download in [item(name), item(name, state: .interrupted(.networkFailed)), item(name, state: .complete)] {
        let row = row(download, style: style)
        row.isSelected = true
        row.layoutSubtreeIfNeeded()
        #expect(row.nameField.lineBreakMode == .byTruncatingMiddle, "the extension stays visible")
        #expect(row.nameField.frame.maxX <= row.bounds.width && row.nameField.frame.minX >= row.tile.frame.maxX)
        let buttons = [row.cancelButton, row.showButton, row.removeButton, row.openPill, row.primaryOpenPill,
                       row.retryPill, row.reviewPill].filter { !$0.isHidden }
        for button in buttons {
          #expect(row.nameField.frame.maxX <= button.frame.minX + 0.5, "\(style) \(button)")
          #expect(button.frame.maxX <= row.bounds.width + 0.5)
        }
        #expect(row.statusField.frame.maxX <= (buttons.map(\.frame.minX).min() ?? row.bounds.width) + 0.5)
      }
    }
  }

  @Test func `an unknown size and a huge one stay readable`() {
    let huge = row(item(total: 2_400_000_000, received: 1_100_000_000))
    #expect(huge.statusField.stringValue.hasPrefix(
      "\(DownloadsFormat.size(1_100_000_000)) of \(DownloadsFormat.size(2_400_000_000))"))
    #expect(huge.statusField.stringValue.contains("GB"))
    let unknown = row(item(total: nil, received: 5_000))
    #expect(unknown.statusField.stringValue == DownloadsFormat.size(5_000))
    #expect(unknown.bar.fraction == nil)
  }

  @Test func `the tile is a fixed colour in both appearances`() {
    let row = row(item("deck.pdf"))
    row.appearance = NSAppearance(named: .aqua)
    let light = row.tile.displayedFill
    row.appearance = NSAppearance(named: .darkAqua)
    #expect(row.tile.displayedFill == light && light == .srgb(hex: 0xB84A36))
  }

  // MARK: Progress bar

  @Test func `the bar eases from where it is on every update, and jumps under Reduce Motion`() {
    let bar = ProgressBarView(frame: NSRect(x: 0, y: 0, width: 200, height: 3))
    var clock: CFTimeInterval = 100
    bar.now = { clock }
    bar.reduceMotion = { false }
    bar.setFraction(0.4)
    clock += 0.25
    bar.setFraction(0.8)                                    // half way to 0.4 when the new target arrives
    #expect(bar.lastStep?.to == 0.8)
    #expect(abs((bar.lastStep?.from ?? 0) - 0.2) < 1e-9)
    #expect(abs(bar.shownFraction - 0.2) < 1e-9)
    clock += 0.5
    #expect(bar.shownFraction == 0.8)
    bar.reduceMotion = { true }
    bar.setFraction(0.9)
    #expect(bar.shownFraction == 0.9 && bar.lastStep?.animated == false)
  }

  @Test func `no animation is added without a window, and the model value is always the target`() {
    let bar = ProgressBarView(frame: NSRect(x: 0, y: 0, width: 200, height: 3))
    bar.reduceMotion = { false }
    bar.setFraction(0.5)
    #expect(bar.fillAnimation == nil && bar.tween.target == 0.5)
    bar.setFraction(nil)
    #expect(bar.tween.target == 0 && bar.fraction == nil)
  }

  @Test func `a window gets a 0.5 s linear transform animation on the fill`() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40), styleMask: [.titled],
                          backing: .buffered, defer: true)
    let bar = ProgressBarView(frame: NSRect(x: 0, y: 0, width: 200, height: 3))
    window.contentView?.addSubview(bar)
    bar.reduceMotion = { false }
    bar.setFraction(0.5)
    let animation = bar.fillAnimation
    #expect(animation?.keyPath == "transform.scale.x" && animation?.duration == 0.5)
    #expect(animation?.fromValue as? Double == 0 && animation?.toValue as? Double == 0.5)
    #expect(animation?.timingFunction == CAMediaTimingFunction(name: .linear))
  }
}
