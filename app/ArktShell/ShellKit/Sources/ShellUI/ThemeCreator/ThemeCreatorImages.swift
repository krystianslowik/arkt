import AppKit

/// The theme creator's images: the pad's colour field and the texture previews (#410). They take hundreds of
/// milliseconds to synthesize in a Debug build, so they are built off the main thread, once per backing scale. The
/// window starts them when it opens (`prepare(scale:)`), well before the popover can be opened; a popover opened
/// earlier shows its pad and swatches without them and fills them in on `didLoad`.
@MainActor
enum ThemeCreatorImages {
  /// Posted on the main thread when a scale's images are ready.
  static let didLoad = Notification.Name("ThemeCreatorImages.didLoad")

  private static var tasks: [Int: Task<Void, Never>] = [:]

  private struct Built: Sendable {
    var field: CGImage?
    var fieldKey: String
    var inks: [String: CGImage]
  }

  /// Starts building `scale`'s images unless they are built or being built. Await the task to wait for them.
  @discardableResult
  static func prepare(scale: CGFloat) -> Task<Void, Never> {
    let key = key(scale)
    if let task = tasks[key] { return task }
    let task = Task { @MainActor in
      let built = await build(scale: scale)
      if let field = built.field { ThemePadField.store(field, key: built.fieldKey) }
      ThemeTextureInk.store(built.inks)
      NotificationCenter.default.post(name: didLoad, object: nil)
    }
    tasks[key] = task
    return task
  }

  private static func key(_ scale: CGFloat) -> Int { Int((scale * 100).rounded()) }

  @concurrent
  private static func build(scale: CGFloat) async -> Built {
    var inks: [String: CGImage] = [:]
    for texture in ThemeTexture.allCases {
      for dark in [false, true] {
        if let image = ThemeTextureInk.makeImage(texture, dark: dark) {
          inks[ThemeTextureInk.key(texture, dark: dark)] = image
        }
      }
    }
    return Built(field: ThemePadField.makeImage(size: ThemePad.size, scale: scale),
                 fieldKey: ThemePadField.key(size: ThemePad.size, scale: scale), inks: inks)
  }
}
