import AppKit
import EngineAPI

/// The surface the rows sit on: one view for the whole list, so two stacked infobars read as one strip with no hairline
/// between them (the surface against the page is the edge). Rows are laid out with frames, top to bottom.
@MainActor
final class InfobarStackView: NSView {
  override var isFlipped: Bool { true }
  override var wantsUpdateLayer: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func updateLayer() {
    layer?.backgroundColor = AlertTokens.dialogSurface.resolve(archiveFlavor).cgColor
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  override func layout() {
    super.layout()
    var y: CGFloat = 0
    for case let row as InfobarRowView in subviews {
      row.frame = NSRect(x: 0, y: y, width: bounds.width, height: InfobarMetrics.rowHeight)
      y += InfobarMetrics.rowHeight
    }
  }
}

private final class InfobarWindow: NSPanel {
  override var canBecomeKey: Bool { true }
}

/// The infobars of one tab as a strip flush with the top of the tab's page view (#400): a non-activating child panel,
/// full width, 40 pt per infobar, with the page card's top corners. The engine reserves the same height at the top of
/// the tab's container, so the page sits below the strip and moves down once when a row arrives; nothing animates
/// the height. A row that arrives fades in over 0.14 s, none fades out, and Reduce Motion shows both at once. The panel
/// never takes key focus from the page.
@MainActor
final class InfobarPanel: AnchoredPanel {
  let panel: NSPanel
  let stack = InfobarStackView()
  private(set) var infobars: [Infobar]
  private(set) var rows: [InfobarRowView] = []
  /// A click on a row: the infobar and what was clicked. The owner sends it to the engine; the row stays until the
  /// engine's next list drops it.
  var onAction: (@MainActor (Infobar, InfobarAction) -> Void)?
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  private var isShown = false

  init(infobars: [Infobar], width: CGFloat) {
    self.infobars = []
    let window = InfobarWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: InfobarMetrics.rowHeight),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.becomesKeyOnlyIfNeeded = true
    panel = window
    stack.wantsLayer = true
    stack.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]        // the top corners, unflipped
    stack.layer?.cornerCurve = .continuous
    stack.layer?.masksToBounds = true
    window.contentView = stack
    apply(infobars, animated: false)
    resizeToContent(width: width)
  }

  /// The strip's height: 40 pt per infobar.
  var height: CGFloat { CGFloat(rows.count) * InfobarMetrics.rowHeight }

  /// Shows `list`: a row whose infobar is still there keeps its place (its values refresh), a new infobar gets a new row
  /// (faded in once the strip is up), a missing one goes at once. The panel keeps its top edge.
  func update(_ list: [Infobar]) {
    guard list != infobars else { return }
    apply(list, animated: isShown)
    let top = panel.frame.maxY
    let size = NSSize(width: panel.frame.width, height: height)
    panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height),
                   display: true)
  }

  private func apply(_ list: [Infobar], animated: Bool) {
    var existing = Dictionary(uniqueKeysWithValues: rows.map { ($0.infobar.id, $0) })
    var next: [InfobarRowView] = []
    var added: [Infobar] = []
    for infobar in list {
      if let row = existing.removeValue(forKey: infobar.id) {
        row.update(infobar)
        next.append(row)
      } else {
        let row = InfobarRowView(infobar: infobar)
        // The row reports the infobar as it is now, not as it was when the row was made.
        row.onAction = { [weak self, weak row] action in
          guard let self, let row else { return }
          onAction?(row.infobar, action)
        }
        stack.addSubview(row)
        next.append(row)
        added.append(infobar)
      }
    }
    for gone in existing.values { gone.removeFromSuperview() }
    rows = next
    infobars = list
    stack.needsLayout = true
    stack.layoutSubtreeIfNeeded()
    if animated {
      let reduced = reduceMotion()
      for infobar in added { rows.first { $0.infobar.id == infobar.id }?.fadeIn(reduceMotion: reduced) }
    }
    for infobar in added {
      NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
        .announcement: infobar.message, .priority: NSAccessibilityPriorityLevel.medium.rawValue,
      ])
    }
  }

  private func resizeToContent(width: CGFloat) {
    panel.setContentSize(NSSize(width: width, height: height))
    stack.frame = NSRect(x: 0, y: 0, width: width, height: height)
    stack.layoutSubtreeIfNeeded()
  }

  // MARK: AnchoredPanel

  /// The strip's frame for `anchor` (screen coordinates): flush with its top-leading corner, as wide as the page.
  func frame(anchoredTo anchor: NSRect) -> NSRect {
    NSRect(x: anchor.minX, y: anchor.maxY - height, width: anchor.width, height: height)
  }

  func resize(width: CGFloat) {
    guard width != panel.frame.width else { return }
    resizeToContent(width: width)
  }

  func reposition(anchoredTo anchor: NSRect) {
    guard !anchor.isEmpty else { return }
    panel.setFrame(frame(anchoredTo: anchor), display: true)
  }

  func detach() {
    onAction = nil
  }

  /// Takes the strip down at once: no exit animation (design section 5).
  func close(keyboard: Bool) {
    panel.parent?.removeChildWindow(panel)
    panel.orderOut(nil)
    isShown = false
  }

  /// Shows the strip over `parent`, flush with the top of `anchor` (screen coordinates), with the card's corner radius
  /// on its top corners. It fades in over 0.14 s (Reduce Motion: at once).
  func show(over parent: NSWindow, anchoredTo anchor: NSRect, topCornerRadius: CGFloat) {
    stack.layer?.cornerRadius = topCornerRadius
    panel.setFrame(frame(anchoredTo: anchor), display: false)
    parent.addChildWindow(panel, ordered: .above)
    panel.orderFront(nil)
    isShown = true
    if !reduceMotion(), let layer = stack.layer {
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 0
      fade.toValue = 1
      fade.duration = InfobarMetrics.fadeDuration
      fade.timingFunction = ArchiveMotion.easeOut
      layer.add(fade, forKey: "infobarFade")
    }
  }
}
