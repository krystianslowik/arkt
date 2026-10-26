import AppKit
import Carbon.HIToolbox

/// The system-wide Option-Command-N (BH-130, BH-131, KB-045): Carbon's `RegisterEventHotKey`, off by default (decision
/// 2026-10-25) and turned on in Settings > Links. A Carbon hotkey needs no accessibility permission and reaches the
/// app while another app, a full-screen one included, is frontmost; the menu item (KB-044) works either way.
///
/// `state` is the last registration answer, so Settings can say "⌥⌘N is used by another app." A taken or failed
/// registration leaves the setting on, as the menu item still works; turning the switch off and on tries again.
@MainActor
public final class LittleArktHotKeyMonitor {
  public enum State: Equatable, Sendable {
    case off
    case active
    /// Another app holds the combination (`eventHotKeyExistsErr`).
    case taken
    /// Any other Carbon status, kept for the log.
    case failed(OSStatus)
  }

  /// The combination the menu item and the hotkey share (KB-044, KB-045).
  public static let keyCode = UInt32(kVK_ANSI_N)
  public static let modifiers = UInt32(cmdKey | optionKey)
  /// Four-character code `ARKT`, so the handler only takes its own hotkey.
  static let signature: OSType = 0x4152_4B54

  public private(set) var isEnabled = false
  public private(set) var state: State = .off
  /// The bar to open.
  public var onPress: (@MainActor () -> Void)?
  /// Every registration answer (the Settings conflict line).
  public var onStateChange: (@MainActor (State) -> Void)?

  private let registrar: any LittleArktHotKeyRegistering

  public convenience init() {
    self.init(registrar: CarbonLittleArktHotKey())
  }

  /// Test seam: a stand-in for Carbon records the calls and presses the combination.
  init(registrar: any LittleArktHotKeyRegistering) {
    self.registrar = registrar
  }

  /// Applies the setting. A repeated call with the same value does nothing, so a Settings sync cannot register twice.
  public func setEnabled(_ enabled: Bool) {
    guard enabled != isEnabled else { return }
    isEnabled = enabled
    guard enabled else {
      registrar.unregister()
      update(.off)
      return
    }
    let status = registrar.register { [weak self] in self?.onPress?() }
    update(Self.state(for: status))
  }

  static func state(for status: OSStatus) -> State {
    if status == OSStatus(noErr) { return .active }
    if status == OSStatus(eventHotKeyExistsErr) { return .taken }
    return .failed(status)
  }

  private func update(_ new: State) {
    guard new != state else { return }
    state = new
    onStateChange?(new)
  }
}

/// What registers the combination; Carbon in the app, a fake in the tests.
@MainActor
protocol LittleArktHotKeyRegistering: AnyObject {
  func register(action: @escaping @MainActor () -> Void) -> OSStatus
  func unregister()
}

/// Carbon's registration: the app event target receives the press even while the app is in the background.
@MainActor
private final class CarbonLittleArktHotKey: LittleArktHotKeyRegistering {
  private var hotKeyRef: EventHotKeyRef?
  private var handlerRef: EventHandlerRef?

  func register(action: @escaping @MainActor () -> Void) -> OSStatus {
    guard hotKeyRef == nil, handlerRef == nil else { return noErr }
    LittleArktHotKeyRouter.action = action
    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
    var handler: EventHandlerRef?
    let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), littleArktHotKeyEventHandler, 1,
                                            &eventType, nil, &handler)
    guard handlerStatus == noErr else {
      LittleArktHotKeyRouter.action = nil
      return handlerStatus
    }
    handlerRef = handler
    let hotKeyID = EventHotKeyID(signature: LittleArktHotKeyMonitor.signature, id: 1)
    var reference: EventHotKeyRef?
    let status = RegisterEventHotKey(LittleArktHotKeyMonitor.keyCode, LittleArktHotKeyMonitor.modifiers, hotKeyID,
                                     GetApplicationEventTarget(), 0, &reference)
    guard status == noErr else {
      RemoveEventHandler(handler)
      handlerRef = nil
      LittleArktHotKeyRouter.action = nil
      return status
    }
    hotKeyRef = reference
    return noErr
  }

  func unregister() {
    if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    hotKeyRef = nil
    if let handlerRef { RemoveEventHandler(handlerRef) }
    handlerRef = nil
    LittleArktHotKeyRouter.action = nil
  }

  isolated deinit { unregister() }
}

/// The press handler: Carbon delivers on the main thread, where the app's action lives.
@MainActor
private enum LittleArktHotKeyRouter {
  static var action: (@MainActor () -> Void)?
}

private func littleArktHotKeyEventHandler(_ call: EventHandlerCallRef?, _ event: EventRef?,
                                          _ userData: UnsafeMutableRawPointer?) -> OSStatus {
  MainActor.assumeIsolated {
    LittleArktHotKeyRouter.action?()
  }
  return noErr
}
