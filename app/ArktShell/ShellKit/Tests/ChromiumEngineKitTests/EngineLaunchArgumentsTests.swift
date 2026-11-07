import ChromiumEngineKit
import Testing

/// The switches the shell adds to every engine launch (#469). Chromium unloads a profile when its last browser
/// window closes (`DestroyProfileOnBrowserClose`, on by default on macOS); the shell keeps running with no window
/// (#241) and opens its first window later, which a dead profile turns into an abort in `CreateBrowserWindow`.
struct EngineLaunchArgumentsTests {
  private let disable = "--disable-features=DestroyProfileOnBrowserClose"

  @Test func addsTheStartupAndProfileSwitchesToABareLaunch() {
    let result = EngineLaunchArguments.applying(to: ["/App/ArktShell"])
    #expect(result == ["/App/ArktShell", "--no-startup-window", disable])
  }

  @Test func keepsProfileUnloadingOffForTheLifeOfTheProcess() {
    let result = EngineLaunchArguments.applying(to: ["/App/ArktShell", "--user-data-dir=/tmp/p"])
    #expect(result.contains(disable))
  }

  @Test func doesNotRepeatSwitchesThatAreAlreadyThere() {
    let once = EngineLaunchArguments.applying(to: ["/App/ArktShell"])
    #expect(EngineLaunchArguments.applying(to: once) == once)
  }

  /// Chromium reads one `--disable-features` value (the last), so the callers' own list is extended, not duplicated.
  @Test func extendsACallersDisableFeaturesList() {
    let result = EngineLaunchArguments.applying(to: ["/App/ArktShell", "--disable-features=A,B"])
    #expect(result.filter { $0.hasPrefix("--disable-features=") } == ["--disable-features=A,B,DestroyProfileOnBrowserClose"])
  }

  @Test func leavesACallersListThatAlreadyNamesTheFeature() {
    let given = ["/App/ArktShell", "--disable-features=DestroyProfileOnBrowserClose,A", "--no-startup-window"]
    #expect(EngineLaunchArguments.applying(to: given) == given)
  }

  @Test func neverChangesTheExecutableOrOtherArguments() {
    let given = ["/App/ArktShell", "--use-mock-keychain", "http://127.0.0.1:9/"]
    let result = EngineLaunchArguments.applying(to: given)
    #expect(Array(result.prefix(3)) == given)
  }

  @Test func testSwitchesAreStrippedAndOtherArgumentsKept() {
    let arguments = ["/App/Arkt", "--arkt-engine-test-api", "--arkt-engine-contract=a,b", "--arkt-reentrancy-probe",
                     "--arkt-embedder-fail", "--user-data-dir=/tmp/p", "https://example.com"]
    #expect(EngineLaunchArguments.strippingTestSwitches(arguments)
      == ["/App/Arkt", "--user-data-dir=/tmp/p", "https://example.com"])
    #expect(EngineLaunchArguments.strippingTestSwitches(["/App/Arkt"]) == ["/App/Arkt"])
  }
}
