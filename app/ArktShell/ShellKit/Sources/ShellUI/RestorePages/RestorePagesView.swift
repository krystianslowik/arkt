import AppKit
import QuartzCore
import Motion

/// The launch window's persistent, top-trailing crash recovery offer.
@MainActor
final class RestorePagesView: NSView {
  let model: RestorePagesModel
  let restoreButton = ArchivePillButton(style: .primary, title: "", metrics: .dialog)
  let dismissButton = ArchivePillButton(style: .neutral, title: "Dismiss", metrics: .dialog)
  private(set) var rowLabels: [NSTextField] = []
  private(set) var overflowLabel: NSTextField?
  private var closing = false
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  var animateClose: @MainActor (@escaping @MainActor () -> Void) -> Void = { completion in
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
    } completionHandler: { MainActor.assumeIsolated { completion() } }
  }

  init(model: RestorePagesModel, pages: [RestorePagesModel.Page]) {
    self.model = model
    let count = min(pages.count, 3)
    let height: CGFloat = 168 + CGFloat(count) * 40 + (pages.count > 3 ? 22 : 0)
    super.init(frame: NSRect(x: 0, y: 0, width: 340, height: height))
    wantsLayer = true
    layer?.cornerRadius = 14
    layer?.shadowOpacity = 0.22
    layer?.shadowRadius = 24
    layer?.shadowOffset = CGSize(width: 0, height: -9)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilitySubrole(.dialog)
    setAccessibilityLabel("Restore pages?")
    let title = label("Restore pages?", size: 15, weight: .semibold)
    title.frame = NSRect(x: 18, y: 18, width: 304, height: 20)
    addSubview(title)
    let body = label("Arkt quit unexpectedly. Your Spaces and tabs are back. These were open outside the sidebar:", size: 13)
    body.maximumNumberOfLines = 3
    body.lineBreakMode = .byWordWrapping
    body.frame = NSRect(x: 18, y: 44, width: 304, height: 56)
    addSubview(body)
    let list = NSView(frame: NSRect(x: 18, y: 104, width: 304, height: CGFloat(count) * 40 + (pages.count > 3 ? 22 : 0) + 8))
    list.wantsLayer = true
    list.layer?.cornerRadius = 10
    addSubview(list)
    for (index, page) in pages.prefix(3).enumerated() {
      let kind = page.kind == .peek ? "Peek" : "Little Arkt window"
      let tile = NSImageView(frame: NSRect(x: 26, y: 113 + CGFloat(index) * 40, width: 18, height: 18))
      tile.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
      tile.setAccessibilityElement(false)
      addSubview(tile)
      let row = label(page.title, size: 13, weight: .medium)
      row.lineBreakMode = .byTruncatingTail
      row.frame = NSRect(x: 52, y: 108 + CGFloat(index) * 40, width: 256, height: 19)
      row.setAccessibilityLabel("\(page.title), \(kind)")
      addSubview(row)
      rowLabels.append(row)
      let subtitle = label(kind, size: 11)
      subtitle.frame = NSRect(x: 52, y: 127 + CGFloat(index) * 40, width: 256, height: 16)
      subtitle.setAccessibilityElement(false)
      addSubview(subtitle)
    }
    if pages.count > 3 {
      let extra = pages.count - 3
      let overflow = label("and \(extra) more", size: 12)
      overflow.frame = NSRect(x: 30, y: 108 + CGFloat(count) * 40, width: 278, height: 20)
      overflow.setAccessibilityLabel("and \(extra) more pages")
      addSubview(overflow)
      overflowLabel = overflow
    }
    dismissButton.target = self
    dismissButton.action = #selector(dismissPressed)
    dismissButton.keyEquivalent = "\u{1b}"
    dismissButton.keyEquivalentModifierMask = []
    dismissButton.frame = NSRect(x: 143, y: height - 42, width: 78, height: 26)
    addSubview(dismissButton)
    restoreButton.title = "Restore \(pages.count)"
    restoreButton.setArchiveAccessibilityLabel("Restore \(pages.count) pages")
    restoreButton.target = self
    restoreButton.action = #selector(restorePressed)
    restoreButton.keyEquivalent = "\r"
    restoreButton.keyEquivalentModifierMask = []
    restoreButton.frame = NSRect(x: 225, y: height - 42, width: 97, height: 26)
    addSubview(restoreButton)
    applyAppearance()
    list.layer?.backgroundColor = ArchiveTokens.listField.resolve(flavor).cgColor
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
  override var isFlipped: Bool { true }
  private var flavor: ThemeFlavor { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light }
  override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); applyAppearance() }
  private func applyAppearance() { layer?.backgroundColor = BrandTokens.surfaceBrand.resolve(flavor).cgColor }
  private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    return field
  }
  func appear() {
    alphaValue = 0
    let motion = !reduceMotion()
    if motion {
      let slide = CASpringAnimation(keyPath: "transform.translation.y")
      let spring = SpringPreset.firm.parameters
      slide.mass = spring.mass
      slide.stiffness = spring.stiffness
      slide.damping = spring.damping
      slide.fromValue = 8
      slide.toValue = 0
      slide.duration = 0.24
      layer?.add(slide, forKey: "recovery-appear")
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = motion ? 0.24 : 0.15
      animator().alphaValue = 1
    }
  }
  @objc func dismissPressed() { answer { model.dismiss() } }
  @objc func restorePressed() { answer { model.restore() } }
  private func answer(_ action: () -> Void) {
    guard !closing else { return }
    closing = true
    action()
    guard case .none = model.presentation else { closing = false; return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      animator().alphaValue = 0
    }
    animateClose { [weak self] in self?.removeFromSuperview() }
  }
}
