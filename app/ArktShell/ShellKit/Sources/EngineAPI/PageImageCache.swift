import CryptoKit
import Foundation
import os

/// The last thumbnail of each page, on disk, for history items in the command bar preview (#370). Bounded by count
/// and bytes, the oldest stored evicted first; keyed by a SHA-256 of the URL, so no part of a URL reaches a file
/// name. Kept in the app's cache folder, never the browsing profile; `removeAll()` empties it (Clear Archive,
/// history clearing). An actor: every file operation runs off the main thread.
public actor PageImageCache {
  public static let defaultMaxEntries = 200
  public static let defaultMaxBytes = 20 * 1024 * 1024

  private struct Entry {
    var bytes: Int
    var stored: Date
  }

  private let directory: URL
  private let maxEntries: Int
  private let maxBytes: Int
  private let now: @Sendable () -> Date
  private let log = Logger(subsystem: "dev.arkt.shell", category: "PageImageCache")
  /// Loaded from the folder on first use.
  private var entries: [String: Entry]?

  /// `now` dates each store; tests pass a clock whose order does not depend on the file system's time resolution.
  public init(directory: URL, maxEntries: Int = defaultMaxEntries, maxBytes: Int = defaultMaxBytes,
              now: @escaping @Sendable () -> Date = Date.init) {
    self.directory = directory
    self.maxEntries = maxEntries
    self.maxBytes = maxBytes
    self.now = now
  }

  /// The cache folder for an app: `<Caches>/<bundle id>/PageImages`.
  public static func defaultDirectory(bundleIdentifier: String) -> URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appending(path: bundleIdentifier, directoryHint: .isDirectory)
      .appending(path: "PageImages", directoryHint: .isDirectory)
  }

  public var count: Int { loaded().count }
  public var totalBytes: Int { loaded().values.reduce(0) { $0 + $1.bytes } }

  /// The image last stored for `url`; nil when none is cached.
  public func image(for url: URL) -> PageImage? {
    let key = Self.key(for: url)
    guard loaded()[key] != nil else { return nil }
    guard let file = try? Data(contentsOf: fileURL(key)), let image = PageImageFile.decode(file) else {
      forget(key)
      return nil
    }
    return image
  }

  /// Stores `image` as `url`'s, the newest entry, then evicts the oldest until both caps hold. An image larger than
  /// the byte cap is not kept.
  public func store(_ image: PageImage, for url: URL) {
    let key = Self.key(for: url)
    let file = PageImageFile.encode(image)
    guard file.count <= maxBytes else {
      forget(key)
      return
    }
    var entries = loaded()
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try file.write(to: fileURL(key), options: .atomic)
    } catch {
      log.error("store failed: \(file.count) bytes, \(String(describing: type(of: error)), privacy: .public)")
      return
    }
    let stored = now()
    try? FileManager.default.setAttributes([.modificationDate: stored], ofItemAtPath: fileURL(key).path)
    entries[key] = Entry(bytes: file.count, stored: stored)
    self.entries = entries
    evict()
  }

  /// Empties the cache and its folder.
  public func removeAll() {
    let removed = loaded().count
    try? FileManager.default.removeItem(at: directory)
    entries = [:]
    log.notice("cleared \(removed) page image(s)")
  }

  // MARK: - Storage

  static func key(for url: URL) -> String {
    SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func fileURL(_ key: String) -> URL { directory.appending(path: key + ".pageimage") }

  private func loaded() -> [String: Entry] {
    if let entries { return entries }
    var found: [String: Entry] = [:]
    let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
    for file in files where file.pathExtension == "pageimage" {
      guard let values = try? file.resourceValues(forKeys: Set(keys)) else { continue }
      found[file.deletingPathExtension().lastPathComponent] =
        Entry(bytes: values.fileSize ?? 0, stored: values.contentModificationDate ?? .distantPast)
    }
    entries = found
    return found
  }

  private func forget(_ key: String) {
    guard loaded()[key] != nil else { return }
    try? FileManager.default.removeItem(at: fileURL(key))
    entries?[key] = nil
  }

  private func evict() {
    var entries = loaded()
    var bytes = entries.values.reduce(0) { $0 + $1.bytes }
    let oldestFirst = entries.sorted { $0.value.stored < $1.value.stored }.map(\.key)
    var evicted = 0
    for key in oldestFirst where entries.count > maxEntries || bytes > maxBytes {
      bytes -= entries[key]?.bytes ?? 0
      entries[key] = nil
      try? FileManager.default.removeItem(at: fileURL(key))
      evicted += 1
    }
    self.entries = entries
    if evicted > 0 { log.debug("evicted \(evicted), kept \(entries.count) page image(s), \(bytes) bytes") }
  }
}

/// A cached image file: a fixed header with the pixel size, scale and format, then the encoded image.
enum PageImageFile {
  private static let magic = Array("APIM".utf8)
  static let headerSize = 16

  static func encode(_ image: PageImage) -> Data {
    var header = Data(magic)
    header.append(image.format == .png ? 1 : 2)
    header.append(contentsOf: [0, 0, 0])
    for value in [UInt16(clamping: image.pixelWidth), UInt16(clamping: image.pixelHeight)] {
      withUnsafeBytes(of: value.bigEndian) { header.append(contentsOf: $0) }
    }
    withUnsafeBytes(of: UInt32(clamping: Int((image.scale * 10_000).rounded())).bigEndian) {
      header.append(contentsOf: $0)
    }
    return header + image.data
  }

  static func decode(_ file: Data) -> PageImage? {
    let bytes = [UInt8](file.prefix(headerSize))
    guard bytes.count == headerSize, Array(bytes[0..<4]) == magic, file.count > headerSize else { return nil }
    let format: PageImage.Format
    switch bytes[4] {
    case 1: format = .png
    case 2: format = .jpeg
    default: return nil
    }
    let width = Int(bytes[8]) << 8 | Int(bytes[9])
    let height = Int(bytes[10]) << 8 | Int(bytes[11])
    let scale = Int(bytes[12]) << 24 | Int(bytes[13]) << 16 | Int(bytes[14]) << 8 | Int(bytes[15])
    return PageImage(data: Data(file.dropFirst(headerSize)), pixelWidth: width, pixelHeight: height,
                     scale: Double(scale) / 10_000, format: format)
  }
}
