import AppKit
internal import ArktEngineABI
import EngineAPI
import os

// MARK: - Page images (#370, #352, contract rule 18)

extension ChromiumEngine {
  private static let pageImageLog = Logger(subsystem: "dev.arkt.shell", category: "ChromiumPageImage")

  /// The facade copies the tab's compositor surface (`RenderWidgetHostView::CopyFromSurface`), scaled on the GPU to
  /// fit the pixel cap, and encodes it as PNG on Chromium's thread pool; the byte cap is applied here, on the
  /// concurrent pool. The main thread only starts the copy and awaits.
  public func pageImage(of id: TabID, _ request: PageImageRequest) async -> PageImage? {
    guard let handle = tabs[id]?.handle else { return nil }
    let started = ContinuousClock.now
    let cap = request.maxPixelSize.map { NSSize(width: $0.width, height: $0.height) } ?? .zero
    let frame: (png: Data?, size: NSSize, scale: CGFloat) = await withCheckedContinuation { continuation in
      handle.copyFrame(maxPixelSize: cap) { png, size, scale in
        continuation.resume(returning: (png, size, scale))
      }
    }
    // A tab that closed while its frame was copied gives nil, as a closed tab does.
    guard let png = frame.png, frame.scale > 0, tabs[id] != nil else {
      Self.pageImageLog.debug("no frame to copy")
      return nil
    }
    let image = await PageImageEncoder.fit(png, scale: Double(frame.scale), request)
    let elapsed = started.duration(to: .now)
    if let image {
      Self.pageImageLog.notice("""
        page image \(image.pixelWidth)x\(image.pixelHeight) px, \(image.data.count) bytes, \
        \(Int(frame.size.width))x\(Int(frame.size.height)) px copied, \(elapsed.milliseconds) ms
        """)
    }
    return image
  }
}

private extension Duration {
  var milliseconds: Int64 {
    let parts = components
    return parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000
  }
}
