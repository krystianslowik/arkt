import CoreFoundation
import Testing
@testable import ShellUI

@MainActor
struct MainThreadBusyProbeTests {
  /// A probe freed while it is still running must take its run loop observer with it; otherwise the observer stays
  /// installed on the main run loop after the probe is gone.
  @Test func freeingARunningProbeRemovesItsObserver() {
    var probe: MainThreadBusyProbe? = MainThreadBusyProbe()
    probe?.start()
    #expect(probe?.isRunning == true)
    let observer = probe?.observerForTesting
    probe = nil
    #expect(observer != nil)
    if let observer {
      #expect(!CFRunLoopContainsObserver(CFRunLoopGetMain(), observer, .commonModes))
    }
  }
}
