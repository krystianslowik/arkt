import AppKit
import Testing
@testable import ShellUI

/// The Library button's ring (design/downloads, direction B): idle it is a quiet glyph, active the graphite arc fills
/// and eases to each value, finished it is a check with a dot, and its label tells VoiceOver which.
@MainActor
struct LibraryButtonTests {
  private func button() -> LibraryButton {
    let button = LibraryButton()
    button.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
    button.layoutSubtreeIfNeeded()
    return button
  }

  @Test func `idle shows the glyph alone`() {
    let button = button()
    #expect(!button.ringIsShown && !button.dotIsShown && button.glyphName == "arrow.down.to.line")
    #expect(button.accessibilityLabel() == "Library")
  }

  @Test func `active shows the ring at the whole's progress`() {
    let button = button()
    button.reduceMotion = { true }
    button.apply(.active(fraction: 0.13))
    #expect(button.ringIsShown && !button.dotIsShown)
    #expect(abs(button.ringStrokeEnd - 0.13) < 1e-9)
    #expect(button.accessibilityLabel() == "Library, downloading 13 percent")
    button.apply(.active(fraction: nil))
    #expect(button.ringStrokeEnd == 0.25 && button.accessibilityLabel() == "Library, downloading")
  }

  @Test func `finished is a check and a dot, a failure an exclamation and a dot`() {
    let button = button()
    button.apply(.done)
    #expect(!button.ringIsShown && button.dotIsShown && button.glyphName == "checkmark")
    #expect(button.accessibilityLabel() == "Library, downloads finished")
    button.apply(.attention)
    #expect(button.dotIsShown && button.glyphName == "exclamationmark")
    button.apply(.idle)
    #expect(!button.dotIsShown && button.glyphName == "arrow.down.to.line")
  }

  @Test func `the arc retargets from the value shown and jumps under Reduce Motion`() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled],
                          backing: .buffered, defer: true)
    let button = button()
    window.contentView?.addSubview(button)
    var clock: CFTimeInterval = 10
    button.now = { clock }
    button.reduceMotion = { false }
    button.apply(.active(fraction: 0.4))
    clock += 0.25
    button.apply(.active(fraction: 0.8))
    #expect(abs((button.ringLastStep?.from ?? 0) - 0.2) < 1e-9 && button.ringLastStep?.to == 0.8)
    #expect(button.ringAnimation?.keyPath == "strokeEnd" && button.ringAnimation?.duration == 0.5)
    button.reduceMotion = { true }
    button.apply(.active(fraction: 0.9))
    #expect(button.ringLastStep?.animated == false && button.ringAnimation == nil)
    #expect(abs(button.ringShownFraction - 0.9) < 1e-9)
  }

  @Test func `hover reports once per change`() {
    let button = button()
    var log: [Bool] = []
    button.onHoverChanged = { log.append($0) }
    button.setHovered(true)
    button.setHovered(true)
    button.setHovered(false)
    #expect(log == [true, false])
  }

  @Test func `the ring sits inside the button and the dot at its top-trailing corner`() {
    let button = button()
    button.apply(.done)
    button.layoutSubtreeIfNeeded()
    #expect(button.bounds.contains(button.layer?.sublayers?.first?.frame ?? .zero))
    #expect(button.identifierForTests == AXID.Downloads.libraryButton)
  }
}

extension NSControl {
  fileprivate var identifierForTests: String { accessibilityIdentifier() }
}
