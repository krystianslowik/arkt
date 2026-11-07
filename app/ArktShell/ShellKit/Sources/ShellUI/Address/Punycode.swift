/// Punycode (RFC 3492), the encoding behind a host's `xn--` labels. Only the codec: the `xn--` prefix, case folding
/// and what is safe to show belong to `HostDisplay`. Both directions fail (nil) instead of trapping on hostile input:
/// a bad digit, a value past U+10FFFF or a delta that would overflow.
enum Punycode {
  private static let base = 36
  private static let tMin = 1
  private static let tMax = 26
  private static let skew = 38
  private static let damp = 700
  private static let initialBias = 72
  private static let initialN = 0x80
  private static let delimiter: Unicode.Scalar = "-"
  /// Every intermediate value stays below this, so the arithmetic below can never overflow `Int`.
  private static let limit = Int(Int32.max)

  /// The code points `encoded` stands for; nil for malformed input or an empty result. Digits are read
  /// case-insensitively; basic code points keep their case.
  static func decode(_ encoded: String) -> [Unicode.Scalar]? {
    let input = Array(encoded.unicodeScalars)
    guard input.allSatisfy(\.isASCII) else { return nil }
    var output: [Unicode.Scalar] = []
    var position = 0
    if let lastDelimiter = input.lastIndex(of: delimiter) {
      output = Array(input[..<lastDelimiter])
      position = lastDelimiter + 1
    }
    var n = initialN
    var i = 0
    var bias = initialBias
    while position < input.count {
      let oldI = i
      var weight = 1
      var k = base
      while true {
        guard position < input.count, let digit = digitValue(input[position]) else { return nil }
        position += 1
        guard digit <= (limit - i) / weight else { return nil }
        i += digit * weight
        let t = threshold(k, bias: bias)
        if digit < t { break }
        guard weight <= limit / (base - t) else { return nil }
        weight *= base - t
        k += base
      }
      let count = output.count + 1
      bias = adapt(delta: i - oldI, count: count, first: oldI == 0)
      guard i / count <= limit - n else { return nil }
      n += i / count
      i %= count
      guard n >= initialN, let scalar = Unicode.Scalar(UInt32(clamping: n)) else { return nil }
      output.insert(scalar, at: i)
      i += 1
    }
    // An empty result ("-", or nothing at all) is not the encoding of any label.
    return output.isEmpty ? nil : output
  }

  /// The encoded form of `scalars`, lowercase digits, without the `xn--` prefix.
  static func encode(_ scalars: [Unicode.Scalar]) -> String? {
    let values = scalars.map { Int($0.value) }
    var output = String.UnicodeScalarView()
    for scalar in scalars where scalar.isASCII { output.append(scalar) }
    let basicCount = output.count
    var handled = basicCount
    if basicCount > 0 { output.append(delimiter) }
    var n = initialN
    var delta = 0
    var bias = initialBias
    while handled < values.count {
      guard let m = values.filter({ $0 >= n }).min() else { return nil }
      guard m - n <= (limit - delta) / (handled + 1) else { return nil }
      delta += (m - n) * (handled + 1)
      n = m
      for value in values {
        if value < n {
          guard delta < limit else { return nil }
          delta += 1
        }
        guard value == n else { continue }
        var q = delta
        var k = base
        while true {
          let t = threshold(k, bias: bias)
          if q < t { break }
          output.append(digit(t + (q - t) % (base - t)))
          q = (q - t) / (base - t)
          k += base
        }
        output.append(digit(q))
        bias = adapt(delta: delta, count: handled + 1, first: handled == basicCount)
        delta = 0
        handled += 1
      }
      delta += 1
      n += 1
    }
    return String(output)
  }

  private static func threshold(_ k: Int, bias: Int) -> Int {
    k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
  }

  private static func adapt(delta: Int, count: Int, first: Bool) -> Int {
    var delta = first ? delta / damp : delta / 2
    delta += delta / count
    var k = 0
    while delta > ((base - tMin) * tMax) / 2 {
      delta /= base - tMin
      k += base
    }
    return k + (base - tMin + 1) * delta / (delta + skew)
  }

  private static func digitValue(_ scalar: Unicode.Scalar) -> Int? {
    switch scalar.value {
    case 0x30...0x39: Int(scalar.value) - 0x30 + 26
    case 0x41...0x5A: Int(scalar.value) - 0x41
    case 0x61...0x7A: Int(scalar.value) - 0x61
    default: nil
    }
  }

  private static func digit(_ value: Int) -> Unicode.Scalar {
    Unicode.Scalar(UInt8(value < 26 ? 0x61 + value : 0x30 + value - 26))
  }
}
