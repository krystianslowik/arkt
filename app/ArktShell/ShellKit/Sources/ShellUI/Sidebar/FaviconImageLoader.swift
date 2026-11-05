import AppKit

/// Decodes favicons of keyed rows (sidebar nodes, Archive items) off the main actor and hands the images back on it
/// (#605). Only the newest bytes per key count: bytes set again for a key, or a key cancelled, drop the older request,
/// and a job whose keys are all dropped is cancelled. Images are cached by their bytes, so tabs of one site and an
/// icon reported again are decoded once and shown at once.
@MainActor
final class FaviconImageLoader<Key: Hashable & Sendable> {
  var decoder: FaviconDecoder
  /// The newest request per key: its bytes and the job decoding them.
  private var wanted: [Key: (data: Data, job: Int)] = [:]
  /// The keys each job still decodes for; a cancelled job is gone from here.
  private var jobs: [Int: Set<Key>] = [:]
  /// Every job's task until it ends, cancelled or not.
  private var tasks: [Int: Task<Void, Never>] = [:]
  private var nextJob = 0
  private let decoded = NSCache<NSData, NSImage>()

  init(decoder: FaviconDecoder = .offMain, cacheLimit: Int = 256) {
    self.decoder = decoder
    decoded.countLimit = cacheLimit
  }

  isolated deinit { cancelAll() }

  /// Number of keys waiting for a decode.
  var pendingCount: Int { wanted.count }

  /// Requests images for `batch`. Bytes already decoded are handed to `apply` before this returns; the rest are
  /// decoded in one job, and `apply` gets the images of the keys still wanted for those bytes when it ends, in one
  /// call. A nil image means the bytes are not an image. Keys whose same bytes are already being decoded are skipped.
  func load(_ batch: [Key: Data], apply: @escaping @MainActor ([Key: NSImage?]) -> Void) {
    var ready: [Key: NSImage?] = [:]
    var pending: [Key: Data] = [:]
    for (key, data) in batch {
      if let request = wanted[key], request.data == data { continue }
      cancel(key)
      if let image = decoded.object(forKey: data as NSData) { ready[key] = image } else { pending[key] = data }
    }
    if !ready.isEmpty { apply(ready) }
    guard !pending.isEmpty else { return }
    // One decode per distinct bytes in the job.
    var order: [Data] = []
    var index: [Data: Int] = [:]
    for data in pending.values where index[data] == nil {
      index[data] = order.count
      order.append(data)
    }
    let job = nextJob
    nextJob += 1
    let decoder = decoder
    let task = Task { [weak self] in
      let bitmaps = await decoder.decode(order)
      self?.finish(job: job, order: order, bitmaps: bitmaps, apply: apply)
    }
    for (key, data) in pending { wanted[key] = (data, job) }
    jobs[job] = Set(pending.keys)
    tasks[job] = task
  }

  private func finish(job: Int, order: [Data], bitmaps: [CGImage?], apply: @MainActor ([Key: NSImage?]) -> Void) {
    tasks[job] = nil
    guard let keys = jobs.removeValue(forKey: job) else { return }            // cancelled
    var images: [Data: NSImage] = [:]
    for (data, bitmap) in zip(order, bitmaps) {
      guard let bitmap else { continue }
      let image = FaviconDecoder.image(bitmap)
      images[data] = image
      decoded.setObject(image, forKey: data as NSData)
    }
    var result: [Key: NSImage?] = [:]
    for key in keys {
      guard let request = wanted[key], request.job == job else { continue }
      wanted[key] = nil
      result[key] = .some(images[request.data])
    }
    if !result.isEmpty { apply(result) }
  }

  /// Drops the pending request of `key`, if any; cancels its job when no other key waits for it.
  func cancel(_ key: Key) {
    guard let request = wanted.removeValue(forKey: key) else { return }
    jobs[request.job]?.remove(key)
    if jobs[request.job]?.isEmpty == true {
      jobs[request.job] = nil
      tasks[request.job]?.cancel()
    }
  }

  /// Drops the pending requests of the keys matching `predicate`.
  func cancel(where predicate: (Key) -> Bool) {
    for key in wanted.keys where predicate(key) { cancel(key) }
  }

  func cancelAll() {
    for task in tasks.values { task.cancel() }
    jobs = [:]
    wanted = [:]
  }

  /// Tests: returns once every job has ended, cancelled ones and ones started meanwhile included. No clock: each job's
  /// task is awaited.
  func settle() async {
    while let task = tasks.values.first { await task.value }
  }
}
