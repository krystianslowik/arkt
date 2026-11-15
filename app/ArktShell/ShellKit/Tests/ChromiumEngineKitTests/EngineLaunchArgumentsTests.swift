import ChromiumEngineKit
import Testing

/// The switches the shell adds to every engine launch (#469). Chromium unloads a profile when its last browser
/// window closes (`DestroyProfileOnBrowserClose`, on by default on macOS); the shell keeps running with no window
/// (#241) and opens its first window later, which a dead profile turns into an abort in `CreateBrowserWindow`.
/// Three Chromium features stay off until Arkt draws their UI natively (engine connector design, E1), and the
/// HTTPS-First dialog stays off so HTTPS-First shows its interstitial instead (#846).
struct EngineLaunchArgumentsTests {
  private let features =
    "DestroyProfileOnBrowserClose,WebAuthenticationAmbientSignin,MediaRouter,Glic,HttpsFirstDialogUi"
  private var disable: String { "--disable-features=" + features }

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
    #expect(result.filter { $0.hasPrefix("--disable-features=") } == ["--disable-features=A,B," + features])
  }

  @Test func leavesACallersListThatAlreadyNamesTheFeatures() {
    let given = ["/App/ArktShell", "--disable-features=" + features + ",A", "--no-startup-window"]
    #expect(EngineLaunchArguments.applying(to: given) == given)
  }

  /// WebAuthn ambient sign-in, Cast (and its remoting dialog) and glic show Views UI that looks for a BrowserView,
  /// which an Arkt window does not have: they stay off until the shell draws them.
  @Test func keepsFeaturesWithoutNativeUIOff() {
    let result = EngineLaunchArguments.applying(to: ["/App/ArktShell"])
    let list = result.first { $0.hasPrefix("--disable-features=") }?.split(separator: "=").last?.split(separator: ",")
    for feature in ["WebAuthenticationAmbientSignin", "MediaRouter", "Glic"] {
      #expect(list?.contains(Substring(feature)) == true, "\(feature) is not disabled")
    }
  }

  /// The HTTPS-First fallback dialog is a tab-modal Views dialog: on an Arkt window its `TabDialogManager` has no host
  /// widget and stops the browser process at `CHECK(host)` (#846). With it off, HTTPS-First shows its interstitial.
  @Test func keepsTheHttpsFirstDialogOff() {
    let result = EngineLaunchArguments.applying(to: ["/App/ArktShell"])
    let list = result.first { $0.hasPrefix("--disable-features=") }?.split(separator: "=").last?.split(separator: ",")
    #expect(list?.contains("HttpsFirstDialogUi") == true)
  }

  @Test func addsOnlyTheFeaturesACallerDidNotName() {
    let result = EngineLaunchArguments.applying(to: ["/App/ArktShell", "--disable-features=MediaRouter,A"])
    #expect(result.filter { $0.hasPrefix("--disable-features=") }
      == ["--disable-features=MediaRouter,A,DestroyProfileOnBrowserClose,WebAuthenticationAmbientSignin,Glic,"
        + "HttpsFirstDialogUi"])
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
