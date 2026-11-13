#ifndef ARKT_API_ARKT_ENGINE_H_
#define ARKT_API_ARKT_ENGINE_H_

// The engine facade: the only interface between the Swift shell and the
// engine inside the Chromium framework (week-3 plan, Decision 1).
//
// Rules for this file:
// - Objective-C only: Foundation and AppKit, no C++, no Chromium includes.
// - Protocols and enums only, no classes. The framework hides every symbol
//   except ChromeMain and the app never links it, so nothing in Swift may
//   reference an engine class. Both sides meet through the Objective-C
//   runtime: the hook finds the Swift embedder with
//   NSClassFromString(@"ArktShellEmbedder"), and the facade hands Swift
//   objects of private classes typed as these protocols.
// - Every protocol is main-thread only (NS_SWIFT_UI_ACTOR). On macOS
//   Chromium's browser UI thread is the main thread.
// - Two byte-identical copies: engine/arkt/api/arkt_engine.h and
//   app/ArktShell/ShellKit/Sources/ArktEngineABI/include/arkt_engine.h. A
//   change is one pull request that both lanes approve and that edits both.
//
// Events are delivered in batches from a posted task, never from inside a
// Chromium notification, in Chromium's order (Decision 3).

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ArktBrowserHandle;
@protocol ArktEngine;
@protocol ArktDownloadItem;
@protocol ArktEngineEvent;
@protocol ArktExtensionAction;
@protocol ArktExtensionCommand;
@protocol ArktExtensionShortcutChange;
@protocol ArktExtensionInstallResult;
@protocol ArktHistoryEntry;
@protocol ArktImportBookmark;
@protocol ArktImportCookie;
@protocol ArktImportHistoryEntry;
@protocol ArktImportLogin;
@protocol ArktImportResult;
@protocol ArktInfobar;
@protocol ArktJavaScriptDialog;
@protocol ArktLinkActivation;
@protocol ArktPageInfo;
@protocol ArktPermissionRequest;
@protocol ArktSitePermission;
@protocol ArktSitePermissions;
@protocol ArktTabHandle;
@protocol ArktWindowHost;
@protocol ArktWindowRequest;

// How a tab close treats the page's unload handlers (Decision 11).
typedef NS_ENUM(NSInteger, ArktCloseMode) {
  // Chrome's behaviour: beforeunload may hold the close behind a dialog.
  ArktCloseModeHonourUnloadHandlers = 0,
  // Closes without firing beforeunload; unload handlers still run without
  // blocking.
  ArktCloseModeSkipUnloadHandlers = 1,
};

// The answer of -[ArktTabHandle closeWithMode:].
typedef NS_ENUM(NSInteger, ArktCloseResult) {
  // The tab is gone when the call returns.
  ArktCloseResultClosed = 0,
  // Unload processing holds the close (a dialog, an unload handler, attached
  // DevTools, or a call made inside a nested run loop). The tab stays listed
  // with isClosing until a TabClosed or a CloseCancelled event.
  ArktCloseResultHeld = 1,
};

// Why a tab closed (Decision 12). None on every event other than TabClosed.
typedef NS_ENUM(NSInteger, ArktCloseReason) {
  ArktCloseReasonNone = 0,
  // This client asked (closeWithMode:).
  ArktCloseReasonClient = 1,
  // The page closed itself (window.close()).
  ArktCloseReasonPage = 2,
  // An extension closed it (chrome.tabs.remove, chrome.windows.remove).
  ArktCloseReasonExtension = 3,
  // Its window is being closed.
  ArktCloseReasonWindowClosing = 4,
  // The application is quitting.
  ArktCloseReasonAppTerminating = 5,
};

// Why a window closed (#401). None on every event other than WindowClosed.
typedef NS_ENUM(NSInteger, ArktWindowCloseReason) {
  ArktWindowCloseReasonNone = 0,
  // The user or this client closed it: the host's closeRequested, -close on
  // the handle, Chromium's own Close Window command.
  ArktWindowCloseReasonUser = 1,
  // An extension closed it (chrome.windows.remove).
  ArktWindowCloseReasonExtension = 2,
  // Its last tab closed or moved to another window, and Chromium closed the
  // emptied window.
  ArktWindowCloseReasonLastTabClosed = 3,
  // The application is quitting.
  ArktWindowCloseReasonAppTerminating = 4,
};

// Who created a tab.
typedef NS_ENUM(NSInteger, ArktTabOrigin) {
  // createTabWithURL:active: or duplicate on a handle.
  ArktTabOriginClient = 0,
  // The engine on its own: a link with target=_blank, window.open,
  // chrome.tabs.create, a startup URL.
  ArktTabOriginEngine = 1,
};

// What an ArktEngineEvent reports. Tab events carry `tab` and `browser`;
// window events carry `browser` only.
typedef NS_ENUM(NSInteger, ArktEngineEventKind) {
  // A tab was inserted. Values: url, title, opener, origin, isActive.
  ArktEngineEventKindTabCreated = 0,
  // A tab is gone. Values: closeReason. Nothing follows for this tab.
  ArktEngineEventKindTabClosed = 1,
  // The tab became its window's active tab.
  ArktEngineEventKindActiveTabChanged = 2,
  // A held close was cancelled; the tab stays open. When the engine ends a
  // leave-site dialog itself (a cancel that runs the page's callback before
  // the dialog closes), this can come before that dialog's DialogEnded; a
  // shell answer always reports DialogEnded first.
  ArktEngineEventKindCloseCancelled = 3,
  // Values: url (the visible URL, pending while a navigation starts).
  ArktEngineEventKindURLChanged = 4,
  // Values: title.
  ArktEngineEventKindTitleChanged = 5,
  // Values: faviconPNG (nil clears it).
  ArktEngineEventKindFaviconChanged = 6,
  // Values: isLoading.
  ArktEngineEventKindLoadingChanged = 7,
  // Values: canGoBack, canGoForward.
  ArktEngineEventKindHistoryChanged = 8,
  // The tab's contents were replaced (crash recovery, prerender). The
  // handle and its containerView stay the same; sessionId may change.
  ArktEngineEventKindTabReplaced = 9,
  // The tab moved to another window (`browser` is the new one) or index.
  ArktEngineEventKindTabMoved = 10,
  // A window was created and is listed in -[ArktEngine browsers].
  ArktEngineEventKindWindowOpened = 11,
  // A window is gone, after the TabClosed events of its tabs. Values:
  // windowCloseReason.
  ArktEngineEventKindWindowClosed = 12,
  // The extension action list of `browser` changed.
  ArktEngineEventKindExtensionActionsChanged = 13,
  // The page started or stopped playing sound (#364). Values: isAudible.
  ArktEngineEventKindAudibleChanged = 14,
  // The tab was muted or unmuted (#364). Values: isMuted.
  ArktEngineEventKindMutedChanged = 15,
  // The page raised an alert, confirm or prompt, or its beforeunload handler
  // a leave-site dialog (#585), in a window whose host presents it (#400).
  // Values: dialog. At most one is pending per tab; a later one ends the
  // earlier first.
  ArktEngineEventKindDialogRequested = 16,
  // The dialog is over: the shell answered it, or the engine ended it (a
  // navigation, a later dialog, the tab closing, a confirm or prompt in a
  // tab that was hidden). Values: dialog. Exactly one per request.
  ArktEngineEventKindDialogEnded = 17,
  // A site asks for a permission (camera, microphone, location, notifications
  // and the like) in a window whose host presents it (#400). Values:
  // permission. At most one is pending per tab. A tab that stops being shown
  // ends its request without an answer and gets a new request when it is shown
  // again (Chromium keeps the ask pending).
  ArktEngineEventKindPermissionRequested = 18,
  // The permission request is over: the shell answered it, or the engine ended
  // it (a navigation, the tab hidden or closing, the site withdrawing it).
  // Values: permission. Exactly one per request.
  ArktEngineEventKindPermissionEnded = 19,
  // The infobars of a tab changed (#400): one is added, removed or replaced.
  // Values: tab, infobars (the tab's whole list, in Chromium's order, empty
  // when the last one went). Sent only for a tab in a window whose host
  // presents them; the engine then draws no row itself and only reserves the
  // rows' height at the top of the tab's container. A tab keeps its infobars
  // while it is hidden or moved to another window (the new list follows the
  // move). The list is empty before the tab's TabClosed.
  ArktEngineEventKindInfobarsChanged = 20,
  // A find-in-page reply (#134). Values: findRequestId, findOrdinal,
  // findCount, findIsFinal. One per reply of WebContents::Find that
  // FindTabHelper accepts (replies for a replaced or stopped search are
  // dropped), and one 0-of-0 final reply, request id 0, for empty text.
  // Nothing is reported for -stopFindingWithAction:.
  ArktEngineEventKindFindResult = 21,
  // The link under the pointer changed (#114), from
  // WebContentsDelegate::UpdateTargetURL. Values: url (nil when the pointer
  // left the link). Only changes are reported; nothing is delayed or merged.
  ArktEngineEventKindTargetURLChanged = 22,
  // A download exists (#132): started, or found in the profile's list at
  // launch. Values: download. Downloads belong to no tab and no window, so
  // `tab` and `browser` are nil on the three download kinds. Sent for every
  // download of the profile, in Chromium's order.
  ArktEngineEventKindDownloadCreated = 23,
  // Any change to a download's values (#132): bytes, speed, state, target,
  // danger. Values: download, a snapshot read when the change happened. The
  // engine merges the updates of one download in a batch into the last one,
  // so received bytes never go backwards across events.
  ArktEngineEventKindDownloadUpdated = 24,
  // The download left the list (#132); its file stays unless it was deleted.
  // Values: download, as it was last. Nothing follows for that guid.
  ArktEngineEventKindDownloadRemoved = 25,
  // The page's process went away (#577), from
  // WebContentsObserver::PrimaryMainFrameRenderProcessGone. Values:
  // terminationStatus. The tab stays listed with its URL and history. A load
  // in progress is reported ended (LoadingChanged NO) and HTML fullscreen left
  // (TabFullscreenChanged NO) before it. Reported once until TabRecovered.
  ArktEngineEventKindTabCrashed = 26,
  // A crashed tab has a live page process again (#577): its primary main
  // frame was created or swapped in, at the latest when the reload or the new
  // navigation commits. Reported once per TabCrashed.
  ArktEngineEventKindTabRecovered = 27,
  // The tab's page zoom changed (#577), from the tab's zoom::ZoomController.
  // Values: zoomPercent, zoomIsDefault and zoomIsUserInitiated, as recorded;
  // the handle has the live zoom. User initiated means the change was made
  // through this tab's zoom controller (zoomIn, zoomOut and resetZoom here,
  // Chromium's zoom commands, an extension's chrome.tabs.setZoom). A site's
  // saved zoom applied on navigation, another tab of the same host zoomed, or
  // a new default zoom are not. Exception: in an isolated or manual zoom mode
  // (an extension's chrome.tabs.setZoomSettings) the controller sets the
  // tab's own level on navigation, so that change can report user initiated.
  // Only changes of percent or default are reported.
  ArktEngineEventKindZoomChanged = 28,
  // An element of the page entered or left HTML fullscreen (#577), from
  // WebContentsObserver::DidToggleFullscreenModeForTab. Values:
  // isTabFullscreen. Not sent for the window's own full screen. The engine
  // reserves no infobar height while the tab is fullscreen.
  ArktEngineEventKindTabFullscreenChanged = 29,
  // The tab's page info changed (#583): a content setting of its site
  // changed in its profile (from this facade, Chromium's settings pages or an
  // extension), its connection's security state changed, or, while its page
  // info panel is open (-pageInfoDidOpen), the site data count it waits for
  // arrived. No values: the handle's pageInfo has the new
  // state. Sent only for tabs whose last committed origin the change matches;
  // one call of this facade that changes settings reports once per tab.
  ArktEngineEventKindPageInfoChanged = 30,
  // An extension was installed in the embedder profile for the first time
  // (#592), from ExtensionRegistryObserver::OnExtensionInstalled. Values:
  // extensionID, extensionName. Profile-wide: `tab` and `browser` are nil.
  // Sent when the install is not an update (an extension the profile already
  // has), its location is ManifestLocation::kInternal (the Chrome Web Store, a
  // user's .crx, a batch of -installExtensions:completion:) and it is neither
  // a theme nor an app. Unpacked, command-line, external, policy and
  // component extensions send nothing. Its order against the
  // ExtensionActionsChanged that lists its action is not guaranteed. On an
  // Arkt window the engine drops Chromium's post-install dialog only for an
  // install this event reported, so a dropped dialog always has its event;
  // other post-install dialogs (an update's) keep Chromium's sheet, and an
  // install that skips its post-install UI (a batch) sends the event with no
  // dialog to drop.
  ArktEngineEventKindExtensionInstalled = 31,
  // extensionCommands changed (#598): a shortcut or scope was set or cleared
  // (through this facade, an extension update, or the engine clearing a
  // suggestion a main-menu item holds), or an extension with commands was
  // loaded or unloaded (installed, enabled, disabled, updated, removed). No
  // values; profile-wide, `tab` and `browser` are nil. The changes of one task
  // are merged into one event, sent on a later task.
  ArktEngineEventKindExtensionCommandsChanged = 32,
};

// Why a tab's page process went away (#577), folded from
// base::TerminationStatus: PROCESS_CRASHED and ABNORMAL_TERMINATION are
// Crashed, PROCESS_WAS_KILLED is Killed, OOM and EVICTED_FOR_MEMORY are
// OutOfMemory, LAUNCH_FAILED is LaunchFailed. None while the page is alive,
// and on every event other than TabCrashed.
typedef NS_ENUM(NSInteger, ArktTerminationStatus) {
  ArktTerminationStatusNone = 0,
  ArktTerminationStatusCrashed = 1,
  ArktTerminationStatusKilled = 2,
  ArktTerminationStatusOutOfMemory = 3,
  ArktTerminationStatusLaunchFailed = 4,
};

// A page zoom step (#577), as content::PageZoom through zoom::PageZoom::Zoom:
// ZoomIn and ZoomOut walk Chromium's preset zoom levels (with the default
// level among them), Reset returns to the default zoom.
typedef NS_ENUM(NSInteger, ArktZoomCommand) {
  ArktZoomCommandZoomIn = 0,
  ArktZoomCommandZoomOut = 1,
  ArktZoomCommandReset = 2,
};

// How a page reached the browser (#583), from the tab's security level and
// visible security state (chrome_security_state) and the URL's scheme:
// SECURE is Secure; DANGEROUS with a Safe Browsing verdict
// (malicious_content_status set) is Flagged, else with a certificate error
// (cert_status) CertificateError, else NotSecure; any other level on https
// with mixed content (displayed_mixed_content, contained_mixed_form,
// ran_mixed_content) is NotFullySecure, else NotSecure. file is LocalFile;
// every scheme other than http, https and file (chrome, chrome-extension,
// devtools, view-source, about, data) is InternalPage.
typedef NS_ENUM(NSInteger, ArktPageConnection) {
  ArktPageConnectionSecure = 0,
  ArktPageConnectionNotSecure = 1,
  ArktPageConnectionNotFullySecure = 2,
  ArktPageConnectionCertificateError = 3,
  ArktPageConnectionFlagged = 4,
  ArktPageConnectionLocalFile = 5,
  ArktPageConnectionInternalPage = 6,
};

// A content setting as page info offers it (#583): CONTENT_SETTING_ALLOW,
// _ASK and _BLOCK.
typedef NS_ENUM(NSInteger, ArktPermissionSetting) {
  ArktPermissionSettingAllow = 0,
  ArktPermissionSettingAsk = 1,
  ArktPermissionSettingBlock = 2,
};

// The permissions page info lists (#583), each one ContentSettingsType.
typedef NS_ENUM(NSInteger, ArktSitePermissionKind) {
  ArktSitePermissionKindLocation = 0,            // GEOLOCATION
  ArktSitePermissionKindCamera = 1,              // MEDIASTREAM_CAMERA
  ArktSitePermissionKindMicrophone = 2,          // MEDIASTREAM_MIC
  ArktSitePermissionKindNotifications = 3,       // NOTIFICATIONS
  ArktSitePermissionKindPopups = 4,              // POPUPS
  ArktSitePermissionKindSound = 5,               // SOUND
  ArktSitePermissionKindJavaScript = 6,          // JAVASCRIPT
  ArktSitePermissionKindImages = 7,              // IMAGES
  ArktSitePermissionKindAutomaticDownloads = 8,  // AUTOMATIC_DOWNLOADS
  ArktSitePermissionKindClipboard = 9,           // CLIPBOARD_READ_WRITE
  ArktSitePermissionKindMidiDevices = 10,        // MIDI_SYSEX
  ArktSitePermissionKindMotionSensors = 11,      // SENSORS
  ArktSitePermissionKindUsbDevices = 12,         // USB_GUARD
  ArktSitePermissionKindSerialPorts = 13,        // SERIAL_GUARD
  ArktSitePermissionKindHidDevices = 14,         // HID_GUARD
  ArktSitePermissionKindBluetoothDevices = 15,   // BLUETOOTH_GUARD
  ArktSitePermissionKindFileEditing = 16,        // FILE_SYSTEM_WRITE_GUARD
  ArktSitePermissionKindWindowManagement = 17,   // WINDOW_MANAGEMENT
  ArktSitePermissionKindLocalFonts = 18,         // LOCAL_FONTS
  ArktSitePermissionKindIdleDetection = 19,      // IDLE_DETECTION
  ArktSitePermissionKindBackgroundSync = 20,     // BACKGROUND_SYNC
  ArktSitePermissionKindInsecureContent = 21,    // MIXEDSCRIPT
};

// Why the engine asks the embedder for a window host.
typedef NS_ENUM(NSInteger, ArktWindowRequestKind) {
  // chrome.windows.create, or a tab an extension moves to a new window.
  ArktWindowRequestKindExtension = 0,
  // A page asked (window.open with window features: a popup Browser).
  ArktWindowRequestKindPage = 1,
  // Dock reopen, or a new window from a Chromium menu command.
  ArktWindowRequestKindReopen = 2,
  // A URL passed at startup or opened by another application.
  ArktWindowRequestKindStartupURL = 3,
};

// A host's answer to a link activation (#313).
typedef NS_ENUM(NSInteger, ArktLinkDecision) {
  // The navigation goes on as Chromium would run it.
  ArktLinkDecisionNavigate = 0,
  // The navigation is dropped; the host opens the link itself (a Peek, a new
  // tab) after the call returns.
  ArktLinkDecisionCancel = 1,
};

// What a page's JavaScript dialog is (#400).
typedef NS_ENUM(NSInteger, ArktDialogKind) {
  ArktDialogKindAlert = 0,
  ArktDialogKindConfirm = 1,
  ArktDialogKindPrompt = 2,
  // The page's beforeunload handler holds a close or a navigation (#585):
  // Chromium's Leave site (or Reload site) dialog. Accepting leaves: the
  // close or navigation goes on. Declining stays: a held close reports
  // CloseCancelled, and a held window close or quit stops. Chromium raises
  // one at a time, across all windows, and activates the tab first.
  ArktDialogKindBeforeUnload = 3,
};

// What a permission request asks for (#400). Other covers the rest; its words
// are in the request's items.
typedef NS_ENUM(NSInteger, ArktPermissionKind) {
  ArktPermissionKindOther = 0,
  ArktPermissionKindGeolocation = 1,
  ArktPermissionKindNotifications = 2,
  ArktPermissionKindCamera = 3,
  ArktPermissionKindMicrophone = 4,
};

// How the shell answers a permission request (#400). Dismiss is closing the
// prompt without choosing (Escape): Chromium counts it as ignored.
typedef NS_ENUM(NSInteger, ArktPermissionChoice) {
  ArktPermissionChoiceAllow = 0,
  ArktPermissionChoiceAllowThisTime = 1,
  ArktPermissionChoiceBlock = 2,
  ArktPermissionChoiceDismiss = 3,
};

// What an infobar is about, for the few the shell tells apart (#400). Other
// covers the rest; its words are in the infobar's message.
typedef NS_ENUM(NSInteger, ArktInfobarKind) {
  ArktInfobarKindOther = 0,
  // An extension or DevTools session started debugging the browser.
  ArktInfobarKindDebugger = 1,
  // The browser is controlled by automated test software.
  ArktInfobarKindAutomation = 2,
  // Settings changed in Page Info and the page needs a reload to apply them.
  ArktInfobarKindReload = 3,
};

// What the shell does on an infobar (#400).
typedef NS_ENUM(NSInteger, ArktInfobarAction) {
  // The OK (or only) button.
  ArktInfobarActionOk = 0,
  ArktInfobarActionCancel = 1,
  // The link after the message.
  ArktInfobarActionLink = 2,
  // An inline link inside the message; linkIndex says which.
  ArktInfobarActionMessageLink = 3,
  // The close button.
  ArktInfobarActionClose = 4,
};

// What stopping a find leaves behind (#134), as FindTabHelper's
// SelectionAction.
typedef NS_ENUM(NSInteger, ArktFindAction) {
  // Removes the highlight and the selection of the active match.
  ArktFindActionClear = 0,
  // The active match becomes the page's selection.
  ArktFindActionKeep = 1,
  // As Keep, and a matched link is clicked.
  ArktFindActionActivate = 2,
};

// A download's state (#132), as download::DownloadItem: Paused is IN_PROGRESS
// with IsPaused().
typedef NS_ENUM(NSInteger, ArktDownloadState) {
  ArktDownloadStateInProgress = 0,
  ArktDownloadStatePaused = 1,
  ArktDownloadStateComplete = 2,
  ArktDownloadStateCancelled = 3,
  ArktDownloadStateInterrupted = 4,
};

// What the shell asks of a download (#132), by guid. Each is a no-op for an
// unknown guid or a state it does not apply to.
typedef NS_ENUM(NSInteger, ArktDownloadCommand) {
  // DownloadItem::Cancel(true): an active download becomes Cancelled and its
  // partial file is deleted.
  ArktDownloadCommandCancel = 0,
  // DownloadItem::Pause().
  ArktDownloadCommandPause = 1,
  // DownloadItem::Resume(true): a paused download continues, an interrupted
  // one that can resume continues where it stopped.
  ArktDownloadCommandResume = 2,
  // DownloadItem::OpenDownload(), only for a complete download whose danger
  // type is not dangerous (not dangerous, user validated, allowlisted by
  // policy, deep scanned safe). Anything else does nothing.
  ArktDownloadCommandOpen = 3,
  // DownloadItem::ShowDownloadInShell().
  ArktDownloadCommandShowInFinder = 4,
  // A cancelled or interrupted download starts again: in place
  // (Resume(true)) when it can resume, else as a new download of the same
  // URL (DownloadManager::DownloadUrl) and the old item is removed in the
  // same call: DownloadRemoved at once, DownloadCreated when the new download
  // has started.
  ArktDownloadCommandRetry = 5,
  // DownloadItem::ValidateDangerousDownload(), only while the item
  // IsDangerous(); a blocked download is not kept.
  ArktDownloadCommandKeepDangerous = 6,
  // The held file is deleted and the item removed.
  ArktDownloadCommandDiscardDangerous = 7,
  // DownloadItem::Remove(): the item leaves the list and keeps its file; an
  // active download is cancelled first.
  ArktDownloadCommandRemove = 8,
};

// One recorded engine change, as plain values. Fields that do not apply to
// the kind are nil, NO, ArktCloseReasonNone or ArktWindowCloseReasonNone.
NS_SWIFT_UI_ACTOR
@protocol ArktEngineEvent <NSObject>
@property(nonatomic, readonly) ArktEngineEventKind kind;
@property(nonatomic, readonly, nullable) id<ArktTabHandle> tab;
@property(nonatomic, readonly, nullable) id<ArktBrowserHandle> browser;
@property(nonatomic, readonly) ArktCloseReason closeReason;
@property(nonatomic, readonly, nullable, copy) NSURL* url;
@property(nonatomic, readonly, nullable, copy) NSString* title;
@property(nonatomic, readonly, nullable, copy) NSData* faviconPNG;
@property(nonatomic, readonly) BOOL isLoading;
@property(nonatomic, readonly) BOOL canGoBack;
@property(nonatomic, readonly) BOOL canGoForward;
@property(nonatomic, readonly, nullable) id<ArktTabHandle> opener;
@property(nonatomic, readonly) ArktTabOrigin origin;
@property(nonatomic, readonly) BOOL isActive;
@property(nonatomic, readonly) BOOL isAudible;
@property(nonatomic, readonly) BOOL isMuted;
@property(nonatomic, readonly) ArktWindowCloseReason windowCloseReason;
// DialogRequested and DialogEnded; nil on every other kind.
@property(nonatomic, readonly, nullable) id<ArktJavaScriptDialog> dialog;
// PermissionRequested and PermissionEnded; nil on every other kind.
@property(nonatomic, readonly, nullable) id<ArktPermissionRequest> permission;
// InfobarsChanged; nil on every other kind.
@property(nonatomic, readonly, nullable, copy) NSArray<id<ArktInfobar>>* infobars;
// FindResult; 0 on every other kind. The ordinal is 1-based, 0 without a
// match; the count is the matches found so far.
@property(nonatomic, readonly) NSInteger findRequestId;
@property(nonatomic, readonly) NSInteger findOrdinal;
@property(nonatomic, readonly) NSInteger findCount;
@property(nonatomic, readonly) BOOL findIsFinal;
// DownloadCreated, DownloadUpdated and DownloadRemoved; nil on every other
// kind.
@property(nonatomic, readonly, nullable) id<ArktDownloadItem> download;
// TabCrashed; None on every other kind (#577).
@property(nonatomic, readonly) ArktTerminationStatus terminationStatus;
// ZoomChanged; 0, NO and NO on every other kind (#577). The percent is
// zoom::ZoomController::GetZoomPercent(), rounded.
@property(nonatomic, readonly) NSInteger zoomPercent;
@property(nonatomic, readonly) BOOL zoomIsDefault;
@property(nonatomic, readonly) BOOL zoomIsUserInitiated;
// TabFullscreenChanged; NO on every other kind (#577).
@property(nonatomic, readonly) BOOL isTabFullscreen;
// ExtensionInstalled; nil on every other kind (#592). The id, and the
// extension's name as Chromium shows it in its UI.
@property(nonatomic, readonly, nullable, copy) NSString* extensionID;
@property(nonatomic, readonly, nullable, copy) NSString* extensionName;
@end

// One download as plain values, read when the event was recorded (#132).
NS_SWIFT_UI_ACTOR
@protocol ArktDownloadItem <NSObject>
// download::DownloadItem::GetGuid(), stable across restarts.
@property(nonatomic, readonly, copy) NSString* guid;
// GetURL(): the final URL of the request.
@property(nonatomic, readonly, copy) NSURL* url;
// GetFileNameToReportUser(), or the suggested name while the target is not
// chosen yet; never empty.
@property(nonatomic, readonly, copy) NSString* filename;
// GetTargetFilePath(); nil until the target is chosen.
@property(nonatomic, readonly, nullable, copy) NSURL* targetPath;
// GetTotalBytes(); 0 when the server did not say.
@property(nonatomic, readonly) int64_t totalBytes;
// GetReceivedBytes().
@property(nonatomic, readonly) int64_t receivedBytes;
@property(nonatomic, readonly) ArktDownloadState state;
// GetLastReason() as download::DownloadInterruptReason when the state is
// Interrupted; 0 otherwise.
@property(nonatomic, readonly) NSInteger interruptReason;
// GetDangerType() as download::DownloadDangerType; 0 is not dangerous.
@property(nonatomic, readonly) NSInteger dangerType;
@property(nonatomic, readonly, copy) NSString* mimeType;
@property(nonatomic, readonly, copy) NSDate* startTime;
// GetEndTime(); nil while the download is active.
@property(nonatomic, readonly, nullable, copy) NSDate* endTime;
// CurrentSpeed(), bytes per second; 0 when not moving.
@property(nonatomic, readonly) int64_t bytesPerSecond;
// CanResume().
@property(nonatomic, readonly) BOOL canResume;
@end

// A page's alert, confirm or prompt, or its leave-site dialog (#585), held
// until the shell answers it or the engine ends it (#400). Every string is
// Chromium's.
NS_SWIFT_UI_ACTOR
@protocol ArktJavaScriptDialog <NSObject>
@property(nonatomic, readonly) ArktDialogKind kind;
// The tab whose page raised it; stays valid after the tab has closed.
@property(nonatomic, readonly) id<ArktTabHandle> tab;
// "example.com says"; "Leave site?" or "Reload site?" for a leave-site
// dialog.
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy) NSString* message;
// A prompt's initial text; nil for an alert or a confirm.
@property(nonatomic, readonly, nullable, copy) NSString* defaultPromptText;
// OK; Leave or Reload for a leave-site dialog.
@property(nonatomic, readonly, copy) NSString* acceptTitle;
// Cancel; nil for an alert, which only has OK, and for a leave-site dialog:
// Chromium's own decline button there is a plain Cancel, and the shell draws
// its Stay (#584).
@property(nonatomic, readonly, nullable, copy) NSString* cancelTitle;
// The dialog is over, however it ended.
@property(nonatomic, readonly) BOOL isEnded;
// Answers the page's call: `accepted` is OK (Leave for a leave-site
// dialog), `userInput` a prompt's text.
// Returns NO, and does nothing, when the dialog is already over (the engine
// ended it first), so an answer that races the end is harmless. Reported with
// one DialogEnded.
- (BOOL)respondAccepted:(BOOL)accepted
              userInput:(nullable NSString*)userInput
    NS_SWIFT_NAME(respond(accepted:userInput:));
@end

// A site's permission request, held until the shell answers it or the engine
// ends it (#400). Every string is Chromium's.
NS_SWIFT_UI_ACTOR
@protocol ArktPermissionRequest <NSObject>
// The tab whose page asked; stays valid after the tab has closed.
@property(nonatomic, readonly) id<ArktTabHandle> tab;
// The asking origin as the permission bubble names it ("example.com").
@property(nonatomic, readonly, copy) NSString* origin;
// What is asked for, one ArktPermissionKind (boxed) per item, in order.
@property(nonatomic, readonly, copy) NSArray<NSNumber*>* kinds;
// "example.com wants to".
@property(nonatomic, readonly, copy) NSString* title;
// What it wants to do, one phrase per kind ("Know your location").
@property(nonatomic, readonly, copy) NSArray<NSString*>* items;
// Allow (for a request that can be granted for one visit: Allow while visiting
// the site).
@property(nonatomic, readonly, copy) NSString* allowTitle;
// Allow this time; nil when the request has no one-visit grant.
@property(nonatomic, readonly, nullable, copy) NSString* allowThisTimeTitle;
// Block (Never allow when the request has a one-visit grant).
@property(nonatomic, readonly, copy) NSString* blockTitle;
// The request is over, however it ended.
@property(nonatomic, readonly) BOOL isEnded;
// Answers the site's ask. Returns NO, and does nothing, when the request is
// already over or already answered, so an answer that races the end is
// harmless. Reported with one PermissionEnded. AllowThisTime on a request
// without that answer counts as Allow.
- (BOOL)respondWithChoice:(ArktPermissionChoice)choice
    NS_SWIFT_NAME(respond(choice:));
@end

// One infobar of a tab (#400): plain values read when it is added, and the
// shell's actions on it. Every string is Chromium's. The object is the handle:
// the same infobar keeps its object across the lists the engine sends, and
// after it is gone (acted on, removed by the page, the tab closing) an action
// returns NO and does nothing.
NS_SWIFT_UI_ACTOR
@protocol ArktInfobar <NSObject>
// Unique among the infobars of the run; a replaced infobar is a new one.
@property(nonatomic, readonly) NSUInteger infobarId;
// The tab the infobar belongs to; stays valid after the tab has closed.
@property(nonatomic, readonly) id<ArktTabHandle> tab;
@property(nonatomic, readonly) ArktInfobarKind kind;
@property(nonatomic, readonly, copy) NSString* message;
// One entry per substitution of the message's format string, in order: an
// NSValue holding an NSRange (UTF-16, into message) for a link, an NSRange with
// location NSNotFound for plain text. Empty when the message is plain.
@property(nonatomic, readonly, copy) NSArray<NSValue*>* messageLinkRanges;
// The link after the message (or before the buttons); nil: none.
@property(nonatomic, readonly, nullable, copy) NSString* linkTitle;
@property(nonatomic, readonly, nullable, copy) NSString* linkAccessibilityLabel;
@property(nonatomic, readonly) BOOL linkBeforeButtons;
// nil: no such button.
@property(nonatomic, readonly, nullable, copy) NSString* okTitle;
@property(nonatomic, readonly, nullable, copy) NSString* okTooltip;
@property(nonatomic, readonly) BOOL okEnabled;
@property(nonatomic, readonly, nullable, copy) NSString* cancelTitle;
@property(nonatomic, readonly, nullable, copy) NSString* cancelTooltip;
@property(nonatomic, readonly) BOOL cancelEnabled;
// The close button's accessibility label; nil: the infobar cannot be closed.
@property(nonatomic, readonly, nullable, copy) NSString* closeAccessibilityLabel;
// The infobar's icon as a PNG at 2x of 20 points, in the window's colors; nil:
// none.
@property(nonatomic, readonly, nullable, copy) NSData* iconPNG;
// The infobar is gone, however it went.
@property(nonatomic, readonly) BOOL isEnded;
// Runs the delegate as the click would. Returns NO, and does nothing, when
// the infobar is already gone. The delegate decides whether the infobar goes
// (Accept returning false keeps it); the shell sees the next list. linkIndex
// is the substitution index for MessageLink and ignored otherwise.
- (BOOL)actWithAction:(ArktInfobarAction)action
            linkIndex:(NSUInteger)linkIndex
    NS_SWIFT_NAME(act(_:linkIndex:));
@end

// A request for a window the engine creates on its own, after
// -[ArktEngine embedderReady] (Decision 2).
NS_SWIFT_UI_ACTOR
@protocol ArktWindowRequest <NSObject>
@property(nonatomic, readonly) ArktWindowRequestKind kind;
// The window the request came from, when there is one.
@property(nonatomic, readonly, nullable) id<ArktBrowserHandle> opener;
// The requested frame in screen coordinates; meaningful only when hasBounds.
@property(nonatomic, readonly) NSRect bounds;
@property(nonatomic, readonly) BOOL hasBounds;
// A popup window: always for a page's request, and for an extension's
// chrome.windows.create({type: "popup"}). NO for a normal window.
@property(nonatomic, readonly) BOOL isPopup;
// Opaque profile identifier (one profile in week 3).
@property(nonatomic, readonly, copy) NSString* profileId;
@property(nonatomic, readonly, nullable, copy) NSURL* initialURL;
@end

// What an extension may read and change on sites (#593): Chromium's user site
// access for the window's active tab, as its toolbar context menu shows it.
typedef NS_ENUM(NSInteger, ArktExtensionSiteAccess) {
  // It asks for no site access the user can change on this tab (no host
  // permissions, or a page it may not run on): no site access submenu.
  ArktExtensionSiteAccessNone = 0,
  // Only when the user clicks its action.
  ArktExtensionSiteAccessOnClick = 1,
  // On the active tab's site.
  ArktExtensionSiteAccessOnThisSite = 2,
  // On all sites.
  ArktExtensionSiteAccessOnAllSites = 3,
};

// The commands of an extension action's context menu (#593), the menu
// design/extensions fixes. The values are the shell's ExtensionContextCommand
// raw values.
typedef NS_ENUM(NSInteger, ArktExtensionContextCommand) {
  // The extension's name, a disabled header.
  ArktExtensionContextCommandHeader = 0,
  // Opens the extension's options page in a tab.
  ArktExtensionContextCommandOptions = 1,
  // Pin or Unpin, by the current state.
  ArktExtensionContextCommandTogglePin = 2,
  // One place earlier or later in the pinned order.
  ArktExtensionContextCommandMoveUp = 3,
  ArktExtensionContextCommandMoveDown = 4,
  // The site access submenu's three choices.
  ArktExtensionContextCommandSiteAccessOnClick = 5,
  ArktExtensionContextCommandSiteAccessOnThisSite = 6,
  ArktExtensionContextCommandSiteAccessOnAllSites = 7,
  // Manage Extension... and Remove from Arkt...: the shell runs these itself;
  // performExtensionContextCommand ignores them.
  ArktExtensionContextCommandManage = 8,
  ArktExtensionContextCommandRemove = 9,
  // The extension's own chrome.contextMenus items for its action (#915) use
  // the commands from CustomFirst to CustomLast: its item n (Chromium's
  // IDC_EXTENSIONS_CONTEXT_CUSTOM_FIRST + n) is CustomFirst + n. They come
  // right after the header and run through performExtensionContextCommand,
  // which fires chrome.contextMenus.onClicked for the tab that was active
  // when the menu was built.
  ArktExtensionContextCommandCustomFirst = 1000,
  ArktExtensionContextCommandCustomLast = 2000,
};

typedef NS_ENUM(NSInteger, ArktMenuItemKind) {
  ArktMenuItemKindCommand = 0,
  ArktMenuItemKindSeparator = 1,
  ArktMenuItemKindSubmenu = 2,
};

// One item of a menu the engine gives the shell to draw (#593), as plain
// values. Titles are the engine's.
NS_SWIFT_UI_ACTOR
@protocol ArktMenuItem <NSObject>
@property(nonatomic, readonly) ArktMenuItemKind kind;
// "" for a separator.
@property(nonatomic, readonly, copy) NSString* title;
// The command passed back when the user chooses the item; meaningful only for
// ArktMenuItemKindCommand, and only to the menu's source.
@property(nonatomic, readonly) NSInteger command;
// NO for a separator.
@property(nonatomic, readonly) BOOL isEnabled;
// Shown with a check mark; NO for a separator or a submenu holder.
@property(nonatomic, readonly) BOOL isChecked;
// The submenu's items; empty for any other kind.
@property(nonatomic, readonly, copy) NSArray<id<ArktMenuItem>>* children;
@end

// One extension toolbar action of a window, as plain values (Decision 10).
NS_SWIFT_UI_ACTOR
@protocol ArktExtensionAction <NSObject>
@property(nonatomic, readonly, copy) NSString* actionId;
@property(nonatomic, readonly, copy) NSString* name;
// The 16 pt icon at 2x, PNG.
@property(nonatomic, readonly, nullable, copy) NSData* iconPNG;
@property(nonatomic, readonly) BOOL isEnabled;
// The user may uninstall the extension (#721): the management policy lets
// the user change it and does not keep it installed (not policy-installed,
// not a component). The shell offers Remove only then; uninstallExtension
// refuses the others anyway.
@property(nonatomic, readonly) BOOL canUninstall;
// The extension updates from the Chrome Web Store, so it has a report page
// there (#721). The shell offers Report abuse only then; uninstallExtension
// opens no report page for the others anyway.
@property(nonatomic, readonly) BOOL canReportAbuse;
// Pinned in the profile (#593, pinnedExtensionIDs).
@property(nonatomic, readonly) BOOL isPinned;
// The extension has an options page (the context menu's Options...).
@property(nonatomic, readonly) BOOL hasOptionsPage;
// Its site access on the window's active tab.
@property(nonatomic, readonly) ArktExtensionSiteAccess siteAccess;
@end

// One chrome.commands command of an enabled extension (#598), as Chrome's
// keyboard shortcuts page lists it: an extension's action command first, then
// its named commands.
NS_SWIFT_UI_ACTOR
@protocol ArktExtensionCommand <NSObject>
@property(nonatomic, readonly, copy) NSString* extensionID;
// The manifest's command name: _execute_action for the action (or
// _execute_browser_action, _execute_page_action), else the extension's own.
@property(nonatomic, readonly, copy) NSString* commandName;
// The extension's name as Chromium shows it.
@property(nonatomic, readonly, copy) NSString* extensionName;
// The manifest's description, or Chromium's "Activate the extension" for the
// action.
@property(nonatomic, readonly, copy) NSString* commandDescription;
// The shortcut in Chromium's form, Ctrl, Alt, Command and Shift in that
// order, then the key, joined by "+" (ui::Command::AcceleratorToString), for
// example "Command+Shift+Y" or "Ctrl+Alt+Comma" (Ctrl is the Control key,
// Alt the Option key). Keys: A to Z, 0 to 9, Comma, Period, Up, Down, Left,
// Right, Insert, Delete, Home, End, PageUp, PageDown, Space, Tab,
// MediaNextTrack, MediaPrevTrack, MediaPlayPause, MediaStop. Nil when the
// command has no shortcut.
@property(nonatomic, readonly, nullable, copy) NSString* shortcut;
// Works while other applications are active (Chromium's global scope).
@property(nonatomic, readonly) BOOL isGlobal;
@end

// The answer to setExtensionCommandShortcut (#598).
typedef NS_ENUM(NSInteger, ArktExtensionShortcutResult) {
  // The command has the shortcut and scope now (or already had them).
  ArktExtensionShortcutResultApplied = 0,
  // Another command has the shortcut; nothing changed. See conflict*.
  ArktExtensionShortcutResultConflict = 1,
  // Chromium does not accept the shortcut for this command
  // (extensions::Command::StringToAccelerator: an unknown key or form, no
  // Command, Control or Option on a non-media key, Option with Command or
  // Control, a media key with modifiers or on an action command), or global
  // scope for an action command; nothing changed.
  ArktExtensionShortcutResultNotAllowed = 2,
  // No enabled extension with that id has that command.
  ArktExtensionShortcutResultUnknownCommand = 3,
  // A global shortcut the engine's global listener could not register;
  // the command keeps what it had.
  ArktExtensionShortcutResultGlobalShortcutTaken = 4,
};

NS_SWIFT_UI_ACTOR
@protocol ArktExtensionShortcutChange <NSObject>
@property(nonatomic, readonly) ArktExtensionShortcutResult result;
// The command that has the shortcut, on Conflict only.
@property(nonatomic, readonly, nullable, copy) NSString* conflictExtensionID;
@property(nonatomic, readonly, nullable, copy) NSString* conflictCommandName;
@end

// One back or forward history entry of a tab.
NS_SWIFT_UI_ACTOR
@protocol ArktHistoryEntry <NSObject>
@property(nonatomic, readonly, copy) NSURL* url;
@property(nonatomic, readonly, copy) NSString* title;
@end

// One cookie to write into the profile (#512). Implemented by the shell; the
// engine reads it during the call and never keeps it. The value is lent, not
// copied: the shell zeroes its buffer after the completion runs.
NS_SWIFT_UI_ACTOR
@protocol ArktImportCookie <NSObject>
// Chromium's host_key: a leading dot makes a domain cookie, none a host
// cookie.
@property(nonatomic, readonly, copy) NSString* hostKey;
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy) NSString* path;
// Lends the value's UTF-8 bytes to `body` for the duration of the call.
- (void)withValueBytes:(void(NS_NOESCAPE ^)(const void* bytes, NSUInteger length))body
    NS_SWIFT_NAME(withValueBytes(_:));
@property(nonatomic, readonly, copy) NSDate* expires;
@property(nonatomic, readonly, nullable, copy) NSDate* creation;
@property(nonatomic, readonly, nullable, copy) NSDate* lastAccess;
@property(nonatomic, readonly) BOOL isSecure;
@property(nonatomic, readonly) BOOL isHTTPOnly;
// Chromium's samesite values: -1 unspecified, 0 none, 1 lax, 2 strict.
@property(nonatomic, readonly) NSInteger sameSite;
// 0 low, 1 medium, 2 high.
@property(nonatomic, readonly) NSInteger priority;
// 0 unset, 1 non-secure, 2 secure.
@property(nonatomic, readonly) NSInteger sourceScheme;
// -1 when unspecified.
@property(nonatomic, readonly) NSInteger sourcePort;
// Chromium's top_frame_site_key: empty for an ordinary cookie. The engine
// skips a partitioned cookie (non-empty): written without its partition key it
// would be readable in every top-level context.
@property(nonatomic, readonly, copy) NSString* partitionKey;
@end

// One saved login to write into the profile's password store (#512). Same
// lending rules as ArktImportCookie.
NS_SWIFT_UI_ACTOR
@protocol ArktImportLogin <NSObject>
@property(nonatomic, readonly, copy) NSString* originURL;
@property(nonatomic, readonly, nullable, copy) NSString* actionURL;
@property(nonatomic, readonly, copy) NSString* signonRealm;
@property(nonatomic, readonly, copy) NSString* username;
- (void)withPasswordBytes:(void(NS_NOESCAPE ^)(const void* bytes, NSUInteger length))body
    NS_SWIFT_NAME(withPasswordBytes(_:));
@property(nonatomic, readonly, nullable, copy) NSDate* dateCreated;
@property(nonatomic, readonly, nullable, copy) NSDate* dateLastUsed;
@end

// One imported history entry (#511): a URL with its title and every visit,
// as two parallel arrays of equal length. Implemented by the shell; the engine
// reads it during the call and never keeps it.
NS_SWIFT_UI_ACTOR
@protocol ArktImportHistoryEntry <NSObject>
@property(nonatomic, readonly, copy) NSString* url;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy) NSArray<NSDate*>* visitTimes;
// Chromium's core page transition per visit (the low 8 bits of
// ui::PageTransition): 0 link, 1 typed, 2 auto bookmark, ... 10 keyword
// generated. Anything else is written as a link.
@property(nonatomic, readonly, copy) NSArray<NSNumber*>* visitTransitions;
@end

// One imported bookmark (#511).
NS_SWIFT_UI_ACTOR
@protocol ArktImportBookmark <NSObject>
@property(nonatomic, readonly, copy) NSString* url;
@property(nonatomic, readonly, copy) NSString* title;
// The source's guid; nil when it had none.
@property(nonatomic, readonly, nullable, copy) NSString* guid;
@property(nonatomic, readonly, nullable, copy) NSDate* dateAdded;
// Folder titles below the Imported folder, outermost first.
@property(nonatomic, readonly, copy) NSArray<NSString*>* folderPath;
@end

// The counts of one import call. written + skipped + failed equals the
// batch size. Never carries a host, a name or a value.
NS_SWIFT_UI_ACTOR
@protocol ArktImportResult <NSObject>
// Stored.
@property(nonatomic, readonly) NSInteger written;
// Not stored on purpose: a duplicate in the batch, an expired or partitioned
// cookie, or a cookie the profile already holds that is as new or newer.
@property(nonatomic, readonly) NSInteger skipped;
// Refused by the cookie store or the password store.
@property(nonatomic, readonly) NSInteger failed;
// Failure reasons with their counts, as "reason: count" lines; nil when
// nothing failed.
@property(nonatomic, readonly, nullable, copy) NSString* failureReason;
// History only (#511): the newest visit time that was written; nil when none
// was, and for every other kind of batch.
@property(nonatomic, readonly, nullable, copy) NSDate* lastVisitTime;
@end

// How one extension of an install batch ended (#513).
typedef NS_ENUM(NSInteger, ArktExtensionInstallStatus) {
  // Downloaded from the Chrome Web Store and installed.
  ArktExtensionInstallStatusInstalled = 0,
  // The profile already has it (enabled or not); nothing was changed.
  ArktExtensionInstallStatusAlreadyInstalled = 1,
  // Not installed; see failureReason.
  ArktExtensionInstallStatusFailed = 2,
};

// The result for one id of installExtensions.
NS_SWIFT_UI_ACTOR
@protocol ArktExtensionInstallResult <NSObject>
@property(nonatomic, readonly, copy) NSString* extensionID;
@property(nonatomic, readonly) ArktExtensionInstallStatus status;
// Failed only: a short sentence that holds no id or name ("not a Web Store
// id", "not available from the Web Store" (a missing item and an unreachable
// store look the same to the fetch), "not confirmed", ...); nil otherwise.
@property(nonatomic, readonly, nullable, copy) NSString* failureReason;
@end

// A user link activation in a tab's main frame (a click or key press on a
// link, with a user gesture), before Chromium starts the navigation (#313).
// Script navigations, forms, reloads and history moves are never reported.
NS_SWIFT_UI_ACTOR
@protocol ArktLinkActivation <NSObject>
@property(nonatomic, readonly, copy) NSURL* url;
// The tab the link is in.
@property(nonatomic, readonly) id<ArktTabHandle> tab;
// The tab's committed URL, so the host can decide without calling the
// engine.
@property(nonatomic, readonly, nullable, copy) NSURL* sourceURL;
// Shift, Command, Option and Control as held for the activation.
@property(nonatomic, readonly) NSEventModifierFlags modifierFlags;
// A WindowOpenDisposition value (CURRENT_TAB for a plain click).
@property(nonatomic, readonly) NSInteger disposition;
@end

// One permission of a site as page info shows it (#583), read from the
// profile's HostContentSettingsMap as chrome://settings/content/siteDetails
// reads it.
NS_SWIFT_UI_ACTOR
@protocol ArktSitePermission <NSObject>
@property(nonatomic, readonly) ArktSitePermissionKind kind;
// Chromium's name for it (PageInfoUI::PermissionTypeToUIString).
@property(nonatomic, readonly, copy) NSString* title;
// The effective setting: the site's exception, else the default; an
// embargoed permission reads Block.
@property(nonatomic, readonly) ArktPermissionSetting setting;
// No exception for the site: the setting is the default.
@property(nonatomic, readonly) BOOL isDefault;
// ArktPermissionSetting values the permission takes, in Allow, Ask, Block
// order (the content settings registry's valid settings). Contains setting.
@property(nonatomic, readonly, copy) NSArray<NSNumber*>* options;
@end

// A tab's page info as plain values (#583), read when the property is read.
NS_SWIFT_UI_ACTOR
@protocol ArktPageInfo <NSObject>
// The site's origin, url::Origin::Serialize() ("https://example.com",
// "http://127.0.0.1:8080"); "file://" for a local file; the URL for an
// internal page.
@property(nonatomic, readonly, copy) NSString* origin;
// The host as Chromium shows it (url_formatter::IDNToUnicode, which keeps
// punycode when its spoof checks decline), the file name for a local file,
// the URL for an internal page.
@property(nonatomic, readonly, copy) NSString* host;
@property(nonatomic, readonly) ArktPageConnection connection;
// The certificate of a Secure connection: the subject's common name, the
// issuer's organization (else common name) and the expiry; nil otherwise.
@property(nonatomic, readonly, nullable, copy) NSString* certificateIssuedTo;
@property(nonatomic, readonly, nullable, copy) NSString* certificateIssuedBy;
@property(nonatomic, readonly, nullable, copy) NSDate* certificateValidUntil;
// Site data as chrome://settings/content/siteDetails counts it
// (BrowsingDataModel entries matching the origin: their storage bytes and
// first-party cookies). Counted only for a tab whose page info panel is open
// (-pageInfoDidOpen until -pageInfoDidClose): NO before the profile's first
// count has arrived, and PageInfoChanged follows when it does. While the panel
// is open, a count older than 10 s is recounted when read: the old count is
// reported meanwhile, and PageInfoChanged follows when the new one differs
// from what the tab read. With no panel open, a read reports the profile's
// last count, however old, or NO without one, and never starts a count. NO
// for a page without site settings.
@property(nonatomic, readonly) BOOL hasSiteData;
@property(nonatomic, readonly) NSInteger siteDataCookies;
@property(nonatomic, readonly) int64_t siteDataBytes;
// Location, camera, microphone and notifications first, then every other
// kind that has an exception for the site, is embargoed or in use, in
// ArktSitePermissionKind order. Empty for a local file or an internal page.
@property(nonatomic, readonly, copy)
    NSArray<id<ArktSitePermission>>* permissions;
@end

// A site with at least one exception in the profile (#583).
NS_SWIFT_UI_ACTOR
@protocol ArktSitePermissions <NSObject>
@property(nonatomic, readonly, copy) NSString* origin;
@property(nonatomic, readonly, copy) NSString* host;
// Only the kinds with an exception, in ArktSitePermissionKind order.
@property(nonatomic, readonly, copy)
    NSArray<id<ArktSitePermission>>* permissions;
@end

// The embedder seam of an engine window (week 2's protocol, moved here).
// The engine never creates or lays out the window: it asks its host for the
// NSWindow and for the fallback view, and sets the blocks below.
NS_SWIFT_UI_ACTOR
@protocol ArktWindowHost <NSObject>
@property(nonatomic, readonly) NSWindow* window;
// Fallback for the tab-modal dialog host and for the contents size when no
// tab container is mounted. Never a mount point the engine fills: embedder
// hosts mount tab containers themselves (Decision 6).
@property(nonatomic, readonly) NSView* cardView;
// Set by the engine. The host calls it when the user asks to close the
// window (close button, Close Window menu item) and never closes the window
// itself: the engine closes the Browser and then releases the host.
@property(nonatomic, nullable, copy) void (^closeRequested)(void);
// Set by the engine. Chrome's main menu sends browser commands
// (commandDispatch:, tag = command id) down the key window's responder
// chain; the host answers the commands it does not implement itself through
// these blocks. `disposition` is a WindowOpenDisposition value.
@property(nonatomic, nullable, copy) BOOL (^validateCommand)(NSInteger command);
@property(nonatomic, nullable, copy) void (^executeCommand)
    (NSInteger command, NSInteger disposition);

@optional
// A link activation in one of the window's tabs (#313), asked from inside
// the navigation start: the host must not call the engine before it
// returns. Not implemented: every link navigates.
- (ArktLinkDecision)decideLinkActivation:(id<ArktLinkActivation>)activation
    NS_SWIFT_NAME(decideLinkActivation(_:));
// A key down that the page of `tab` did not handle (an Esc the page did not
// use), from a task posted after the engine finished with the event.
- (void)unhandledKeyDown:(NSEvent*)event
                   inTab:(nullable id<ArktTabHandle>)tab
    NS_SWIFT_NAME(unhandledKeyDown(_:in:));
// Placeholder host only. Set by the engine; the host calls it when the user
// picks a tab in its own tab list.
@property(nonatomic, nullable, copy) void (^activateTab)(int32_t tabId);
// Placeholder host only: tab list changes, in order. The elements are
// ArktTabEvent objects (arkt/browser/arkt_window_host.h), a class this header
// cannot name.
- (void)tabListChanged:(NSArray*)events;
@end

// A tab. The handle is the tab's identity for its whole life, across contents
// replacement and moves between windows (Decision 5).
NS_SWIFT_UI_ACTOR
@protocol ArktTabHandle <NSObject>
// The tab's stable container. The current contents view fills it; the
// embedder mounts and removes it (Decision 6).
@property(nonatomic, readonly) NSView* containerView;
// The Chromium session id (what chrome.tabs reports). Can change when the
// contents are replaced; never the Swift identity.
@property(nonatomic, readonly) int32_t sessionId;
// The window the tab is in; nil once it has closed.
@property(nonatomic, readonly, nullable) id<ArktBrowserHandle> browser;
@property(nonatomic, readonly, nullable, copy) NSURL* url;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, nullable, copy) NSData* faviconPNG;
@property(nonatomic, readonly) BOOL isLoading;
@property(nonatomic, readonly) BOOL canGoBack;
@property(nonatomic, readonly) BOOL canGoForward;
// Back and forward history, nearest first: backEntries[0] is one step back,
// forwardEntries[0] one step forward (EngineClient.history(of:), contract
// rule 9).
@property(nonatomic, readonly, copy) NSArray<id<ArktHistoryEntry>>* backEntries;
@property(nonatomic, readonly, copy)
    NSArray<id<ArktHistoryEntry>>* forwardEntries;
@property(nonatomic, readonly, nullable) id<ArktTabHandle> opener;
@property(nonatomic, readonly) ArktTabOrigin origin;
@property(nonatomic, readonly) BOOL isActive;
// A held close is pending.
@property(nonatomic, readonly) BOOL isClosing;
// A close with ArktCloseModeHonourUnloadHandlers would be held now.
@property(nonatomic, readonly) BOOL wouldHoldClose;
// The page plays sound now (WebContents::IsCurrentlyAudible). A muted page
// that plays stays audible.
@property(nonatomic, readonly) BOOL isAudible;
// The tab's sound is muted (WebContents::IsAudioMuted).
@property(nonatomic, readonly) BOOL isMuted;
// Why the page's process went away, None while it is alive
// (WebContents::IsCrashed and GetCrashedStatus, #577).
@property(nonatomic, readonly) ArktTerminationStatus terminationStatus;
// The page zoom (#577): zoom::ZoomController::GetZoomPercent() and
// IsAtDefaultZoom(); 100 and YES for a closed tab.
@property(nonatomic, readonly) NSInteger zoomPercent;
@property(nonatomic, readonly) BOOL zoomIsDefault;
// An element of the page is in HTML fullscreen, or about to be
// (WebContents::IsFullscreen, #577).
@property(nonatomic, readonly) BOOL isTabFullscreen;

- (void)navigateToURL:(NSURL*)url;
// A navigation the user typed in the shell's address field (#784), with the
// transition Chrome's omnibox sends (PAGE_TRANSITION_TYPED |
// PAGE_TRANSITION_FROM_ADDRESS_BAR) where navigateToURL: sends TYPED alone.
// The differences: the same URL as the page on screen loads again as a new
// navigation that replaces the entry, not as a reload (the back list does not
// grow either way); the history records the visit with the FROM_ADDRESS_BAR
// qualifier (both calls count it as typed). Browser debug URLs
// (chrome://gpucrash, chrome://inducebrowsercrashforrealz, the hang and
// memory-pressure URLs, chrome://crash/browser/... and chrome://crash/gpu/...)
// only run with --arkt-engine-test-api; without it they load as
// navigateToURL: does, which does nothing.
- (void)navigateFromAddressBarToURL:(NSURL*)url
    NS_SWIFT_NAME(navigate(fromAddressBarTo:));
- (void)reload;
// No-ops when the tab cannot go back or forward.
- (void)goBack;
- (void)goForward;
// -1 is one step back, +1 one step forward; 0 or out of range is a no-op
// (EngineClient.goToHistory(_:offset:)).
- (void)goToHistoryOffset:(NSInteger)offset
    NS_SWIFT_NAME(goToHistory(offset:));
// Makes the tab its window's active tab.
- (void)activate;
- (ArktCloseResult)closeWithMode:(ArktCloseMode)mode NS_SWIFT_NAME(close(mode:));
// Makes the contents the first responder.
- (void)focus;
// A new tab next to this one with its URL, title and back and forward
// history, reported with TabCreated and origin Client
// (EngineClient.duplicateTab(_:), contract rule 10); nil when the tab cannot
// be duplicated.
- (nullable id<ArktTabHandle>)duplicate;
// Moves the tab, with its contents, history and container, to the end of
// `browser`'s tabs and makes it active there, without a reload. Reported
// with TabMoved (same handle). A window left without tabs closes. A no-op for
// a closed tab, a closed `browser` or the tab's own window.
- (void)moveToBrowser:(id<ArktBrowserHandle>)browser NS_SWIFT_NAME(move(to:));
// Mutes or unmutes the tab's sound (WebContents::SetAudioMuted), reported
// with MutedChanged when the state changes (#364).
- (void)setMuted:(BOOL)muted NS_SWIFT_NAME(setMuted(_:));
// One zoom step (#577), reported with ZoomChanged (user initiated) when the
// zoom changes; nothing at either end of the steps or when Reset finds the
// default. The handle's zoomPercent and zoomIsDefault have the new zoom when
// the call returns. A no-op for a closed or crashed tab (Chromium does not
// zoom a page without a live process).
- (void)zoomWithCommand:(ArktZoomCommand)command NS_SWIFT_NAME(zoom(_:));
// Starts or continues a find in the tab's page (#134), as
// FindTabHelper::StartFinding with find_match set: a new text or case starts
// a new search at the first match; the same text and case again moves to the
// next match (`forward`) or the previous one, wrapping. Replies are reported
// with FindResult. Empty text stops the find like ArktFindActionClear and is
// reported once as 0 of 0. A no-op for a closed tab.
- (void)findInPageWithText:(NSString*)text
                   forward:(BOOL)forward
                 matchCase:(BOOL)matchCase
    NS_SWIFT_NAME(findInPage(text:forward:matchCase:));
// Ends the tab's find (FindTabHelper::StopFinding). Reports nothing; the next
// find starts a new search. A no-op for a closed tab. -moveToBrowser: ends a
// running find the same way (Clear, no report): the shell closes its find bar
// when it moves a tab.
- (void)stopFindingWithAction:(ArktFindAction)action
    NS_SWIFT_NAME(stopFinding(action:));
// A copy of the tab's current frame as PNG (#370, #352), from the
// compositor surface (RenderWidgetHostView::CopyFromSurface), scaled down on
// the GPU to fit `maxPixelSize`; NSZeroSize copies the full frame at the
// backing scale. `pixelSize` is the PNG's size and `scale` its pixels per
// point of the page. Never shows, wakes or reloads the tab: a closed or
// discarded tab, or one without a surface to copy (not drawn yet, hidden
// long enough to be evicted), answers nil, NSZeroSize and 0. The copy and the
// encode run off the main thread; `completion` runs later on the main
// thread, never inside the call.
- (void)copyFrameWithMaxPixelSize:(NSSize)maxPixelSize
                       completion:(void (^)(NSData* _Nullable png,
                                            NSSize pixelSize,
                                            CGFloat scale))completion
    NS_SWIFT_NAME(copyFrame(maxPixelSize:completion:)) NS_SWIFT_DISABLE_ASYNC;
// Page info (#583) of the tab's last committed page, in the tab's profile;
// nil for a closed tab or one without a committed page. Reading it while the
// tab's page info panel is open starts the site data count when the
// profile's count is older than 10 s; otherwise reading it counts nothing.
@property(nonatomic, readonly, nullable) id<ArktPageInfo> pageInfo;
// Sets one permission of `origin` in the tab's profile, as Chromium's page
// info does (PageInfo::OnSitePermissionChanged: the narrowest pattern,
// embargo cleared when it is not Block). The default setting removes the
// exception. A setting the kind does not take, or the one it has, does
// nothing. When `origin` is the tab's own, the change counts for the reload
// infobar of -pageInfoDidClose. Reported with PageInfoChanged on the tabs of
// that origin.
- (void)setPermission:(ArktSitePermissionKind)kind
            toSetting:(ArktPermissionSetting)setting
            forOrigin:(NSString*)origin
    NS_SWIFT_NAME(setPermission(_:to:forOrigin:));
// Removes the origin-scoped exceptions and the embargoes of `origin`'s
// permissions in the tab's profile, as setting each to its default
// (SetNarrowestContentSetting). A broader user exception (a [*.]host pattern)
// stays, as with Chromium's page info. Cookies and site data stay.
- (void)resetPermissionsForOrigin:(NSString*)origin
    NS_SWIFT_NAME(resetPermissions(forOrigin:));
// The shell's page info panel of this tab opened (#782). Until
// -pageInfoDidClose or the tab closing, reads of pageInfo count the site
// data, on every page of the tab: the count starts now when the profile's
// count is older than 10 s or missing, and PageInfoChanged follows when it
// differs from the one the tab had. A second call while open does nothing
// more.
- (void)pageInfoDidOpen;
// The shell's page info panel of this tab closed (PageInfo::OnUIClosing).
// After a change from this tab that needs a reload (any kind but sound),
// Chromium's reload infobar (ArktInfobarKindReload) is added to this tab,
// once; otherwise nothing happens.
- (void)pageInfoDidClose;
// Opens chrome://settings/content/siteDetails for `origin` in the tab's
// window, as page info's Site settings link does.
- (void)openSiteSettingsForOrigin:(NSString*)origin
    NS_SWIFT_NAME(openSiteSettings(forOrigin:));
@end

// An engine window (one Browser).
NS_SWIFT_UI_ACTOR
@protocol ArktBrowserHandle <NSObject>
// The Browser's session id (what chrome.windows reports).
@property(nonatomic, readonly) int32_t windowId;
@property(nonatomic, readonly) id<ArktWindowHost> host;
// In tab strip order.
@property(nonatomic, readonly, copy) NSArray<id<ArktTabHandle>>* tabs;
@property(nonatomic, readonly, nullable) id<ArktTabHandle> activeTab;
// Returns the new tab at once; a nil URL opens about:blank.
- (id<ArktTabHandle>)createTabWithURL:(nullable NSURL*)url
                               active:(BOOL)active
    NS_SWIFT_NAME(createTab(url:active:));
// Closes the Browser after unload processing of its tabs. A held tab whose
// close is cancelled keeps the window open (CloseCancelled, no
// WindowClosed).
- (void)close;
@end

// The facade. Created by the hook and handed to -[ArktEngineEmbedder
// engineDidStart:].
NS_SWIFT_UI_ACTOR
@protocol ArktEngine <NSObject>
// The shell's session exists: create the queued engine-initiated windows,
// in order (Decision 2).
- (void)embedderReady;
// The shell failed to start: drop the queue. The shell then quits.
- (void)embedderFailed;
@property(nonatomic, readonly, copy) NSArray<id<ArktBrowserHandle>>* browsers;
// Creates a Browser in the host's window, synchronously.
- (id<ArktBrowserHandle>)createBrowserWithHost:(id<ArktWindowHost>)host
    NS_SWIFT_NAME(createBrowser(host:));
// The window's actions: the pinned ones first, in pinnedExtensionIDs order,
// then the rest.
- (NSArray<id<ArktExtensionAction>>*)extensionActionsForBrowser:
    (id<ArktBrowserHandle>)browser NS_SWIFT_NAME(extensionActions(in:));
// Runs the action; its popup is anchored to `anchor`.
- (void)runExtensionAction:(NSString*)actionId
                 inBrowser:(id<ArktBrowserHandle>)browser
                    anchor:(NSView*)anchor
    NS_SWIFT_NAME(runExtensionAction(_:in:anchor:));
// Every sink receives every batch, in order. Returns a token for
// removeEventSink:.
- (id<NSObject>)addEventSink:
    (void (^)(NSArray<id<ArktEngineEvent>>* events))sink;
- (void)removeEventSink:(id<NSObject>)token;

// Test API (Task W3-5 step 5). Enabled only at run time by
// --arkt-engine-test-api; without the switch every call is a logged no-op
// whose completion reports an error.
@property(nonatomic, readonly) BOOL testAPIEnabled;
// Runtime.evaluate semantics; `result` is the JSON-compatible value.
- (void)evaluateScript:(NSString*)script
                 inTab:(id<ArktTabHandle>)tab
           userGesture:(BOOL)userGesture
            completion:(void (^)(id _Nullable result,
                                 NSError* _Nullable error))completion
    NS_SWIFT_NAME(evaluateScript(_:in:userGesture:completion:))
        NS_SWIFT_DISABLE_ASYNC;
// Answers the tab's pending JavaScript dialog. Returns NO when none is
// pending.
- (BOOL)answerDialogInTab:(id<ArktTabHandle>)tab
                   accept:(BOOL)accept NS_SWIFT_NAME(answerDialog(in:accept:));

// Import writes (#512), into the profile the engine started with. Plaintext
// crosses in-process only; the engine builds its own copies inside the
// lending blocks and zeroes them once it has handed them on, and the shell
// zeroes its buffers after `completion`. Copies Chromium makes itself (the
// cookie and its mojo message, the password store's) are not zeroed.
// `completion` runs on the main thread after the writes reached the store (a
// cookie batch is flushed to disk first), never inside the call, and also for
// an empty batch.
//
// Cookies: written through the profile's CookieManager
// (SetCanonicalCookie) with HttpOnly and an inclusive SameSite context.
// Duplicates in the batch by (name, domain, path) keep the newest by last
// access, then creation, then the later entry; a cookie that already expired
// or is partitioned, and one the profile holds that was last used at or after the imported one's
// last access, are skipped. The network service caps an expiry at 400 days
// after the creation date, so a cookie created longer ago keeps its expiry by
// moving its creation date forward to expiry - 400 days (never past now).
- (void)importCookies:(NSArray<id<ArktImportCookie>>*)cookies
           completion:(void (^)(id<ArktImportResult> result))completion
    NS_SWIFT_NAME(importCookies(_:completion:)) NS_SWIFT_DISABLE_ASYNC;
// Passwords: written through the profile's password store (AddLogin).
// Duplicates in the batch by (signon_realm, username, action) keep the later
// entry. A login the store already holds under that key is skipped unless the
// imported one is newer (the later of date_last_used and date_created, against
// the stored one's). `written` counts logins after the store answered.
- (void)importPasswords:(NSArray<id<ArktImportLogin>>*)logins
             completion:(void (^)(id<ArktImportResult> result))completion
    NS_SWIFT_NAME(importPasswords(_:completion:)) NS_SWIFT_DISABLE_ASYNC;
// History (#511): every visit is written through the profile's history
// service with its time and core transition; a URL's visit count and typed
// count follow from the visits written. A visit at or before `after` (the
// watermark of the last import, nil for none), one older than the 90 days the
// history keeps, and one of a URL the history refuses (not http, https, ftp
// or file) is skipped; a URL that is not valid fails its visits. The result's
// lastVisitTime is the newest visit written. Counts are in visits.
// `completion` runs once the history thread has processed the writes.
- (void)importHistory:(NSArray<id<ArktImportHistoryEntry>>*)entries
                after:(nullable NSDate*)after
           completion:(void (^)(id<ArktImportResult> result))completion
    NS_SWIFT_NAME(importHistory(_:after:completion:)) NS_SWIFT_DISABLE_ASYNC;
// Bookmarks (#511): written under "Other bookmarks" in a folder named
// "Imported", with their folders. A bookmark whose guid the model holds, or
// whose url and title the target folder holds, is skipped; an invalid url
// fails. `completion` runs after the write (the engine waits for the bookmark
// model to load).
- (void)importBookmarks:(NSArray<id<ArktImportBookmark>>*)bookmarks
             completion:(void (^)(id<ArktImportResult> result))completion
    NS_SWIFT_NAME(importBookmarks(_:completion:)) NS_SWIFT_DISABLE_ASYNC;

// Extensions by Chrome Web Store id (#513), into the profile the engine
// started with. Each distinct id gets one result, in the order the ids first
// appear, in `completion` (main thread, never inside the call, also for an
// empty array). An id the profile already has is reported as already
// installed and left alone. The engine fetches the Web Store listing of every
// other id, then shows ONE native confirmation sheet for the whole batch
// (each extension's name with the permission warnings Chrome's own prompt shows)
// on the key shell window; on accept it installs the
// ones it found, without a per-extension prompt, on decline it fails them
// with "not confirmed". An id that is not a Web Store id, one the store does
// not have, an unreachable store and a listing that does not answer within
// 30 s fail only their own results; nothing
// else stops. Built on the Web Store install path a click on "Add to Chrome"
// uses (WebstoreStandaloneInstaller), with its install prompt replaced by the
// batch sheet.
- (void)installExtensions:(NSArray<NSString*>*)ids
               completion:(void (^)(NSArray<id<ArktExtensionInstallResult>>*
                                        results))completion
    NS_SWIFT_NAME(installExtensions(_:completion:)) NS_SWIFT_DISABLE_ASYNC;
// Ends the installs in progress early: the batch sheet closes, listing
// fetches stop and every id that is not being installed yet fails with
// "cancelled"; the batch's completion then runs as usual. An id whose install
// was already confirmed finishes with its real result. Does nothing when no
// batch is running.
- (void)cancelExtensionInstalls NS_SWIFT_NAME(cancelExtensionInstalls());
// Uninstalls an extension of the profile the engine started with (#721) as
// the user's own choice (UNINSTALL_REASON_USER_INITIATED), with no prompt of
// the engine's: the shell asked already. Built on ExtensionRegistrar's
// UninstallExtension, the call Chrome's own uninstall dialog makes; that
// dialog is not shown. Every other uninstall path (chrome.management, for
// one) keeps its dialog. `completion` runs on the main thread, never inside
// the call, and always arrives except when the engine shuts down first:
// `uninstalled` YES once the extension is gone, or NO with a short sentence
// that holds no id or name ("unknown extension" for an id the profile does
// not have, "not removable" for one the user may not uninstall, see
// canUninstall); nothing changed then. The removal reaches the sinks as
// ExtensionActionsChanged for every window that listed the action.
// `reportAbuse`: after a successful uninstall the Web Store's report page for
// the extension opens in a new foreground tab of `browser` (the window of the
// shell's sheet), as Chrome does after its dialog; when `browser` is nil or
// has closed meanwhile, of the last active window. Only for an extension
// whose canReportAbuse is YES; for any other no tab opens.
- (void)uninstallExtension:(NSString*)extensionID
               reportAbuse:(BOOL)reportAbuse
                 inBrowser:(nullable id<ArktBrowserHandle>)browser
                completion:(void (^)(BOOL uninstalled,
                                     NSString* _Nullable failureReason))
                               completion
    NS_SWIFT_NAME(uninstallExtension(_:reportAbuse:in:completion:))
        NS_SWIFT_DISABLE_ASYNC;

// Pinned extensions (#593), of the profile the engine started with: Chromium's
// toolbar pins, stored in the profile (what chrome://extensions shows as "Pin
// to toolbar"), in order. Action ids are extension ids.
@property(nonatomic, readonly, copy) NSArray<NSString*>* pinnedExtensionIDs;
// Pins (at the end of the order) or unpins an extension that has an action.
// Nothing for an unknown id, one already in that state, or one the policy
// pins. A change reaches the sinks as ExtensionActionsChanged for every window.
- (void)setExtensionPinned:(NSString*)extensionID
                    pinned:(BOOL)pinned
    NS_SWIFT_NAME(setExtensionPinned(_:pinned:));
// Moves a pinned extension to `index` in pinnedExtensionIDs, clamped to the
// ends. Nothing for one that is not pinned, already there, or policy-pinned.
- (void)movePinnedExtension:(NSString*)extensionID
                    toIndex:(NSInteger)index
    NS_SWIFT_NAME(movePinnedExtension(_:to:));
// The context menu of action `actionId` in `browser`, from Chromium's
// ExtensionContextMenuModel for the window's active tab, with
// ArktExtensionContextCommand commands; empty for an unknown action. The
// engine keeps that model until the next call for the window, so a choice made
// after the tab moved to another site changes no site access.
- (NSArray<id<ArktMenuItem>>*)extensionContextMenuForAction:(NSString*)actionId
                                                  inBrowser:
                                                      (id<ArktBrowserHandle>)
                                                          browser
    NS_SWIFT_NAME(extensionContextMenu(forAction:in:));
// Runs a command the user chose from that menu. Nothing for an unknown action
// or command, a disabled item, or Header, Manage and Remove (the shell's).
// An extension's own item (CustomFirst to CustomLast) runs only while the tab
// that was active when the menu was built is still the active one.
- (void)performExtensionContextCommand:(NSInteger)command
                             forAction:(NSString*)actionId
                             inBrowser:(id<ArktBrowserHandle>)browser
    NS_SWIFT_NAME(performExtensionContextCommand(_:forAction:in:));

// Extension keyboard commands (#598), of the profile the engine started with:
// every command of its enabled extensions, sorted by extension name, with the
// shortcut and scope the profile has for them. A command's shortcut works in
// every Arkt window of the profile, with the page or anything else of the
// window focused, before the page sees the key (as in Chrome), except a key an
// item of the main menu has as its key equivalent: the menu keeps it. A
// manifest suggestion for such a key is not assigned (the engine clears it,
// see ExtensionCommandsChanged), so the command starts without a shortcut.
@property(nonatomic, readonly, copy)
    NSArray<id<ArktExtensionCommand>>* extensionCommands;
// Sets (nil clears) a command's shortcut, in ArktExtensionCommand's form, and
// its scope, through Chromium's CommandService, as Chrome's shortcuts page
// does: the shortcut is the user's from then on, so an update of the
// extension keeps it. Synchronous; ExtensionCommandsChanged follows when
// something changed. With `replacingConflict` NO, a shortcut another command
// has answers Conflict and changes nothing; with YES that command loses it
// first. Media keys may be shared, as in Chrome. The engine checks only
// extension commands: conflicts with Arkt's own shortcuts are the shell's to
// check first. `global` is ignored when clearing.
- (id<ArktExtensionShortcutChange>)
    setExtensionCommandShortcut:(nullable NSString*)shortcut
                     forCommand:(NSString*)commandName
                    ofExtension:(NSString*)extensionID
                         global:(BOOL)global
              replacingConflict:(BOOL)replacingConflict
    NS_SWIFT_NAME(setExtensionCommandShortcut(_:forCommand:ofExtension:global:replacingConflict:));

// Downloads (#132), of the profile the engine started with. The events are
// DownloadCreated, DownloadUpdated and DownloadRemoved (no tab, no window).
// The list in creation order, newest last: a snapshot of every download the
// profile holds, including those found at launch before a sink was added.
@property(nonatomic, readonly, copy) NSArray<id<ArktDownloadItem>>* downloads;
// Runs `command` on the download with that guid.
- (void)performDownloadCommand:(ArktDownloadCommand)command
             onDownloadWithGUID:(NSString*)guid
    NS_SWIFT_NAME(perform(download:on:));
// DownloadManager::DownloadUrl for `url`, as Save Link As does (no user
// gesture, no tab).
- (void)startDownloadFromURL:(NSURL*)url NS_SWIFT_NAME(startDownload(from:));
// Where downloads go: the profile's download.prompt_for_download and
// download.default_directory prefs. The folder is used as given; the caller
// checks it exists and is writable (Chromium creates a missing one). Setting
// either applies to downloads that start afterwards.
@property(nonatomic) BOOL downloadPromptsForLocation;
@property(nonatomic, copy) NSURL* downloadDirectory;
// DownloadPrefs::GetDefaultDownloadDirectory(): the system Downloads folder.
@property(nonatomic, readonly, copy) NSURL* defaultDownloadDirectory;
// Answers a download's save panel (the prompt_for_download case) and Save As
// of other saves: while set, a SELECT_SAVEAS_FILE dialog is not shown by
// Chromium but handed to this block with the suggested file name and the
// folder to open in. `answer` takes the chosen file URL, or nil when the user
// cancels (the download is then cancelled), exactly once, on the main thread.
// Every other kind of file dialog keeps Chromium's. Nil restores Chromium's
// panels.
@property(nonatomic, copy, nullable) void (^downloadDestinationHandler)
    (NSString* suggestedFilename, NSURL* directory,
     void (^answer)(NSURL* _Nullable chosen));

// The crashed-session prompt (#577), for the profile the engine started with.
// YES when the previous run of that profile ended without a clean quit
// (ExitTypeService's last session exit type is kCrashed, read once at start)
// or an earlier run's prompt was never answered (#785), and the shell has not
// dismissed it in this run. A run that quits without dismissing asks again on
// the next run, as Chrome does until its bubble is answered. Chromium's own
// "restore pages" bubble needs a BrowserView, so it never shows on an engine
// window: the shell is the only one that asks. NO for a profile without an
// exit type service and no marker. Known limit: a run killed before the
// profile's first Preferences write (about 10 s after start; 7 s in #577's
// runs, 12 to 16 s in #785's) has no crash mark on disk, so the next run
// reports a clean exit.
@property(nonatomic, readonly) BOOL lastSessionCrashed;
// The shell answered the prompt: lastSessionCrashed is NO for the rest of the
// run and for later runs until the next crash. A second call does nothing.
- (void)dismissLastSession;

// Every site with a permission exception (a user-set pattern for one origin)
// in the profile the engine started with (#583), sorted by host.
@property(nonatomic, readonly, copy)
    NSArray<id<ArktSitePermissions>>* sitesWithPermissions;
@end

// Implemented by the Swift app: @objc(ArktShellEmbedder), in the main
// executable. The hook looks the class up by name; absent, the engine keeps
// its placeholder host.
NS_SWIFT_UI_ACTOR
@protocol ArktEngineEmbedder <NSObject>
+ (id<ArktEngineEmbedder>)sharedEmbedder NS_SWIFT_NAME(sharedEmbedder());
// Records the facade and starts the shell. The shell calls embedderReady or
// embedderFailed when its start finishes.
- (void)engineDidStart:(id<ArktEngine>)engine;
// A host for a window the engine creates on its own. Called inside Browser
// construction: build the window and return its host, never call the engine
// before the WindowOpened event.
- (id<ArktWindowHost>)hostForEngineWindowRequest:
    (id<ArktWindowRequest>)request NS_SWIFT_NAME(host(for:));
// Quit started (the first Browser closing while trying to quit); the windows
// still exist.
- (void)engineWillBeginTerminating;
// The quit was cancelled (a held beforeunload, or the user).
- (void)engineDidCancelTerminating;
// The application is terminating. Call `completion` when the shell has
// flushed; the engine waits at most 5 s.
- (void)engineWillTerminate:(void (^)(void))completion
    NS_SWIFT_DISABLE_ASYNC;
@end

NS_ASSUME_NONNULL_END

#endif  // ARKT_API_ARKT_ENGINE_H_
