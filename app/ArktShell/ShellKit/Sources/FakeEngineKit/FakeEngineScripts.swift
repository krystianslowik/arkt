import EngineAPI
import Foundation

/// The page scripts of `FakeEngine`'s find in page and link hover (#134, #114). WKWebView's own find API answers only
/// whether a match exists, with no count or position, so the stand-in searches with `window.find` and counts the matches
/// itself.
enum FakeEngineScripts {
  /// The message handler the hover script posts to.
  static let targetURLHandler = "arktTargetURL"

  /// Posts the URL of the link under the pointer, or null when the pointer leaves it. Runs in every frame.
  static let hover = """
    (function () {
      if (window.__arktHover) { return; }
      window.__arktHover = true;
      var current = null;
      function linkOf(node) {
        while (node && node.nodeType === 1) {
          if (node.tagName === 'A' && node.href) { return node; }
          node = node.parentElement;
        }
        return null;
      }
      function post(url) {
        if (url === current) { return; }
        current = url;
        window.webkit.messageHandlers.\(targetURLHandler).postMessage(url);
      }
      document.addEventListener('mouseover', function (event) {
        var link = linkOf(event.target);
        post(link ? link.href : null);
      }, true);
      document.addEventListener('mouseout', function (event) {
        if (!linkOf(event.relatedTarget)) { post(null); }
      }, true);
      window.addEventListener('pagehide', function () { post(null); });
    })();
    """

  private static func json(_ value: some Encodable) -> String {
    (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "null"
  }

  /// Selects the next or previous match (or the first, for a new search) and answers `[count, ordinal]`: the number of
  /// matches in the page text and the 1-based position of the selected one, 0 without a match.
  static func find(text: String, forward: Bool, matchCase: Bool, isNew: Bool) -> String {
    """
    (function (text, caseSensitive, backwards, isNew) {
      var selection = window.getSelection();
      if (isNew) { selection.removeAllRanges(); }
      var found = window.find(text, caseSensitive, backwards, true, false, false, false);
      var anchor = found && selection.rangeCount ? selection.getRangeAt(0) : null;
      var needle = caseSensitive ? text : text.toLowerCase();
      var count = 0, ordinal = 0;
      var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      for (var node = walker.nextNode(); node; node = walker.nextNode()) {
        var hay = caseSensitive ? node.nodeValue : node.nodeValue.toLowerCase();
        for (var at = hay.indexOf(needle); at !== -1; at = hay.indexOf(needle, at + needle.length)) {
          count += 1;
          if (anchor && anchor.startContainer === node && anchor.startOffset === at) { ordinal = count; }
        }
      }
      return [count, ordinal];
    })(\(json(text)), \(matchCase), \(!forward), \(isNew))
    """
  }

  /// Ends a find: removes the selection, keeps it, or keeps it and clicks a link that contains it.
  static func stopFind(_ action: FindStopAction) -> String {
    switch action {
    case .clear:
      return "window.getSelection().removeAllRanges(); true"
    case .keep:
      return "true"
    case .activate:
      return """
        (function () {
          var node = window.getSelection().anchorNode;
          while (node && !(node.nodeType === 1 && node.tagName === 'A')) { node = node.parentNode; }
          if (node) { node.click(); }
          return true;
        })()
        """
    }
  }
}
