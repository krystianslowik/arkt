import Foundation

/// The clean-URL rules behind Copy URL (BH-191, KB-013): the known tracker parameters are dropped from the copy;
/// every other query parameter, the path and the fragment stay exactly as the page had them. Arc's own rule list is
/// unpublished ([S] gives the toast strings only), so this list is ours, documented here and pinned by
/// `TrackerStrippingTests`.
public enum TrackerStripping {
  /// Parameter names dropped whatever their case or value. Campaign trackers (`utm_*`, see `trackerPrefixes`), the
  /// click ids the ad networks append (`fbclid`, `gclid`, `dclid`, `gbraid`, `wbraid`, `msclkid`, `ttclid`,
  /// `twclid`, `yclid`), the mailing-list tags (`mc_cid`, `mc_eid`, `mkt_tok`, `ml_subscriber`, `_hsenc`, `_hsmi`,
  /// `vero_id`), the social and referral tags (`igshid`, `spm`, `ref_src`, `ref_url`, `s_cid`, `oly_anon_id`,
  /// `oly_enc_id`, `rb_clickid`, `wickedid`) and the analytics ids (`_ga`, `_gl`, `__s`).
  public static let trackerNames: Set<String> = [
    "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "mc_cid", "mc_eid", "igshid", "ttclid", "twclid",
    "yclid", "_hsenc", "_hsmi", "vero_id", "s_cid", "spm", "ref_src", "ref_url", "__s", "_ga", "_gl", "oly_anon_id",
    "oly_enc_id", "ml_subscriber", "ml_subscriber_hash", "wickedid", "rb_clickid", "mkt_tok",
  ]

  /// Parameter-name prefixes dropped whatever their suffix: the whole `utm_*` campaign family.
  public static let trackerPrefixes = ["utm_"]

  /// Whether `name` is a tracker parameter (case-insensitive; exact name or a listed prefix).
  public static func isTracker(_ name: String) -> Bool {
    let lowercased = name.lowercased()
    return trackerNames.contains(lowercased) || trackerPrefixes.contains { lowercased.hasPrefix($0) }
  }

  /// The URL without its tracker parameters, and whether anything was dropped (`false`: the URL is unchanged, and
  /// the copy says "Current URL").
  public static func clean(_ url: URL) -> (url: URL, stripped: Bool) {
    // The percent-encoded items keep every kept parameter byte for byte: the decoded `queryItems` would write
    // `%2B` back as `+` (a space to the server) and `%2F` as `/`.
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let items = components.percentEncodedQueryItems, !items.isEmpty else { return (url, false) }
    let kept = items.filter { !isTracker($0.name.removingPercentEncoding ?? $0.name) }
    guard kept.count != items.count else { return (url, false) }
    components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
    guard let cleaned = components.url else { return (url, false) }
    return (cleaned, true)
  }
}
