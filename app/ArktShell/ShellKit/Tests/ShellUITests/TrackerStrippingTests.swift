import Foundation
import Testing
@testable import ShellUI

/// BH-191, KB-013: the clean-URL rule list. Known tracker parameters are dropped; everything else (path, the other
/// query parameters, the fragment) is kept exactly as it was.
struct TrackerStrippingTests {
  private func clean(_ string: String) -> (url: URL, stripped: Bool) {
    let url = URL(string: string)!
    return TrackerStripping.clean(url)
  }

  @Test func aURLWithoutTrackersIsUnchanged() {
    let (url, stripped) = clean("https://example.com/read?page=2&sort=new")
    #expect(url.absoluteString == "https://example.com/read?page=2&sort=new")
    #expect(!stripped)
  }

  @Test func aURLWithoutAQueryIsUnchanged() {
    let (url, stripped) = clean("https://example.com/read#section-2")
    #expect(url.absoluteString == "https://example.com/read#section-2")
    #expect(!stripped)
  }

  @Test func everyUTMParameterIsDropped() {
    let (url, stripped) = clean(
      "https://example.com/read?utm_source=news&utm_medium=email&utm_campaign=launch&utm_term=arc&utm_content=a"
        + "&utm_id=1&utm_name=x&page=2")
    #expect(url.absoluteString == "https://example.com/read?page=2")
    #expect(stripped)
  }

  /// The single-name trackers of the documented rule list.
  @Test(arguments: [
    "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "mc_cid", "mc_eid", "igshid", "ttclid", "twclid",
    "yclid", "_hsenc", "_hsmi", "vero_id", "s_cid", "spm", "ref_src", "ref_url", "__s", "_ga", "_gl", "oly_anon_id",
    "oly_enc_id", "ml_subscriber", "ml_subscriber_hash", "wickedid", "rb_clickid", "mkt_tok",
  ])
  func aKnownTrackerIsDropped(_ name: String) {
    let (url, stripped) = clean("https://example.com/p?\(name)=abc&keep=1")
    #expect(url.absoluteString == "https://example.com/p?keep=1", "\(name) is a tracker")
    #expect(stripped)
  }

  @Test func theMatchIsCaseInsensitive() {
    let (url, stripped) = clean("https://example.com/p?UTM_Source=x&FBCLID=y&keep=1")
    #expect(url.absoluteString == "https://example.com/p?keep=1")
    #expect(stripped)
  }

  /// A parameter whose name merely looks like a tracker is kept (no substring matches); a utm_-prefixed name is a
  /// tracker whatever follows the prefix.
  @Test func similarNamesAreKept() {
    let (url, stripped) = clean("https://example.com/p?xutm_source=1&gclidish=2&page=3")
    #expect(url.absoluteString == "https://example.com/p?xutm_source=1&gclidish=2&page=3")
    #expect(!stripped)
    let (prefixed, dropped) = clean("https://example.com/p?utm_source_x=1&page=3")
    #expect(prefixed.absoluteString == "https://example.com/p?page=3")
    #expect(dropped)
  }

  @Test func whenEveryParameterIsATrackerTheQueryGoesAway() {
    let (url, stripped) = clean("https://example.com/path?utm_source=a&fbclid=b")
    #expect(url.absoluteString == "https://example.com/path")
    #expect(stripped)
  }

  @Test func thePathAndFragmentSurvive() {
    let (url, stripped) = clean("https://example.com/a/b?utm_source=x&page=2#section-2")
    #expect(url.absoluteString == "https://example.com/a/b?page=2#section-2")
    #expect(stripped)
  }

  /// A parameter without a value (`?utm_source&page=1`) is a tracker too.
  @Test func aValuedAndAValuelessTrackerBothDrop() {
    let (url, stripped) = clean("https://example.com/p?utm_source&page=1")
    #expect(url.absoluteString == "https://example.com/p?page=1")
    #expect(stripped)
  }

  /// The kept parameters are copied byte for byte: an encoded `+`, `/`, `?`, `&` or `=` stays encoded, so the server
  /// reads the same values.
  @Test func keptParametersKeepTheirPercentEncoding() {
    let (url, stripped) = clean("https://example.com/s?q=1%2B1&utm_source=x&r=%2Fx%3Fy&t=a%26b%3Dc&s=a+b")
    #expect(url.absoluteString == "https://example.com/s?q=1%2B1&r=%2Fx%3Fy&t=a%26b%3Dc&s=a+b")
    #expect(stripped)
  }

  /// A percent-encoded tracker name is still a tracker.
  @Test func anEncodedTrackerNameIsDropped() {
    let (url, stripped) = clean("https://example.com/p?utm%5Fsource=x&keep=1")
    #expect(url.absoluteString == "https://example.com/p?keep=1")
    #expect(stripped)
  }
}
