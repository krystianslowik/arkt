import AppKit

/// The copy-link actions of the Edit menu (#118): Copy URL (KB-013, BH-191), Copy URL as Markdown (KB-014), Copy URL
/// as Quote (KB-015) and Paste URL as New Tab (KB-016). The URLs copied are tracker-stripped by `TrackerStripping`;
/// the toasts use BH-191's strings.
extension ShellWindowController {
  // MARK: Copy URL (KB-013, BH-191)

  /// Cmd-Shift-C: the current tab's clean URL, or every selected tab's (one per line, BH-191) with a multi-selection.
  @objc public func copyCurrentURL(_ sender: Any?) {
    let targets = copyTargets()
    guard !targets.isEmpty else { return }
    let cleaned = targets.map { TrackerStripping.clean($0.url) }
    write(cleaned.map(\.url.absoluteString).joined(separator: "\n"))
    let stripped = cleaned.contains { $0.stripped }
    toasts.show(Toast(text: Self.copyToastText(stripped: stripped, count: targets.count)))
  }

  /// BH-191's strings: the clean-link toast for a copy that dropped a tracker, the [S] "Copied Current URL" for one
  /// that did not. BH-192 leaves Arc's exact wording and duration unknown (RT-28); the duration is the notice's.
  nonisolated static func copyToastText(stripped: Bool, count: Int) -> String {
    if stripped {
      return count == 1 ? "Copied a clean link without trackers" : "Copied clean links without trackers"
    }
    return count == 1 ? "Copied Current URL" : "Copied Current URLs"    // [I]: no plural string is documented
  }

  // MARK: Copy URL as Markdown / Quote (KB-014, KB-015)

  /// Cmd-Shift-Opt-C: `[title](url)`; a multi-selection copies one line per tab. The toast wording is [I] (no [S]
  /// string is documented; BH-192's gap covers it).
  @objc public func copyCurrentURLAsMarkdown(_ sender: Any?) {
    let targets = copyTargets()
    guard !targets.isEmpty else { return }
    write(targets.map { target in
      let url = TrackerStripping.clean(target.url).url.absoluteString
      return "[\(target.title)](\(url))"
    }.joined(separator: "\n"))
    toasts.show(Toast(text: targets.count == 1 ? "Copied as Markdown" : "Copied as Markdown links"))
  }

  /// Ctrl-Shift-Cmd-C: the same link as a Markdown quote (`> [title](url)`). The format is [I]: Arc's quote layout
  /// is not documented beyond the menu row (KB-015).
  @objc public func copyCurrentURLAsQuote(_ sender: Any?) {
    let targets = copyTargets()
    guard !targets.isEmpty else { return }
    write(targets.map { target in
      let url = TrackerStripping.clean(target.url).url.absoluteString
      return "> [\(target.title)](\(url))"
    }.joined(separator: "\n"))
    toasts.show(Toast(text: targets.count == 1 ? "Copied as Quote" : "Copied as Quote links"))
  }

  // MARK: Paste URL as New Tab (KB-016)

  /// Cmd-Opt-V: the clipboard's http(s) URL opens as a new tab. Anything else (text, another scheme, an empty
  /// clipboard) does nothing, so Cmd-Opt-V never opens a page the user did not copy.
  @objc public func pasteURLAsNewTab(_ sender: Any?) {
    guard let text = pasteboard.string(forType: .string) else { return }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme) else { return }
    open(url, inNewTab: true)
  }

  // MARK: Shared

  /// The Edit menu validation: the copy actions need something to copy, Paste URL as New Tab always works.
  func validateCopyLinkMenuItem(_ item: NSMenuItem) -> Bool? {
    switch item.action {
    case #selector(copyCurrentURL(_:)), #selector(copyCurrentURLAsMarkdown(_:)), #selector(copyCurrentURLAsQuote(_:)):
      return currentNode != nil
    case #selector(pasteURLAsNewTab(_:)):
      return true
    default:
      return nil
    }
  }

  /// What the copy actions take: an open Peek's page first (KB-013 works "in Peek"), else the selected tab rows
  /// (BH-191's multi-selection), else the current tab. Folder and split rows are skipped: their panes are not rows of
  /// their own in the selection.
  private func copyTargets() -> [(url: URL, title: String)] {
    if peek.isOpen, let session = peek.session {
      let snapshot = engine.snapshot(of: session.tab)
      let title = (snapshot?.title).flatMap { $0.isEmpty ? nil : $0 } ?? (session.url.host() ?? "")
      return [(snapshot?.url ?? session.url, title)]
    }
    let selected = sidebarController.selectedNodes
    let nodes = selected.isEmpty ? (currentNode.map { [$0] } ?? []) : selected
    return nodes.compactMap { node in
      guard case .tab(_, let nodeURL, let nodeTitle)? = sidebar.node(node) else { return nil }
      let snapshot = tabsByNode[node].flatMap { engine.snapshot(of: $0) }
      let url = snapshot?.url ?? nodeURL
      let title = (snapshot?.title).flatMap { $0.isEmpty ? nil : $0 } ?? nodeTitle
      return (url, title)
    }
  }

  private func write(_ text: String) {
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }
}
