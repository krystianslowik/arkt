/// The name of a Space made by New Space (decision on #106): "Space N", N the smallest number from 1 that no Space in
/// `taken` already has as exactly "Space N".
enum SpaceNaming {
  static func nextTitle(base: String, taken: some Sequence<String>) -> String {
    let prefix = base + " "
    var used = Set<Int>()
    for title in taken where title.hasPrefix(prefix) {
      let digits = title.dropFirst(prefix.count)
      // Only the canonical spelling counts: "Space 01" or "Space +1" do not hold number 1.
      guard let n = Int(digits), n > 0, String(n) == digits else { continue }
      used.insert(n)
    }
    let n = (1...).first { !used.contains($0) } ?? 1
    return prefix + String(n)
  }
}
