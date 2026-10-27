#import "arkt/api/arkt_engine_facade.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "arkt/api/arkt_embedder.h"
#include "arkt/browser/arkt_browser_window.h"
#include "arkt/browser/arkt_extension_calls.h"
#include "arkt/browser/arkt_extensions_container.h"
#include "arkt/browser/arkt_extensions_menu.h"
#include "arkt/browser/arkt_javascript_dialog.h"
#import "arkt/browser/arkt_infobar_view.h"
#include "arkt/browser/arkt_infobars.h"
#include "arkt/browser/arkt_link_activation.h"
#include "arkt/browser/arkt_permission_prompt.h"
#import "arkt/browser/arkt_tab_container_view.h"
#include "base/check.h"
#include "base/command_line.h"
#include "base/check_op.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/ref_counted_memory.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/bind_post_task.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/thread_pool.h"
#include "base/time/time.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/tab_list/tab_removed_reason.h"
// //chrome/browser/ui reaches //arkt through //chrome/browser, so this
// target cannot depend on it; the symbol is in the same framework.
#include "chrome/browser/ui/browser_tabstrip.h"  // nogncheck
#include "chrome/browser/ui/browser_window/public/browser_collection_observer.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/tabs/tab_close_types_data.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "chrome/browser/ui/unload_controller.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/javascript_dialogs/tab_modal_dialog_manager.h"
#include "components/favicon/core/favicon_driver.h"
#include "components/favicon/core/favicon_driver_observer.h"
#include "components/sessions/content/session_tab_helper.h"
#include "components/tabs/public/tab_interface.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/reload_type.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/common/isolated_world_ids.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/strings/grit/ui_strings.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "ui/gfx/codec/png_codec.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_rep.h"
#include "ui/gfx/native_ui_types.h"
#include "url/gurl.h"

@class ArktFacadeBrowser;
@class ArktFacadeTab;

namespace arkt {
namespace {

class Facade;
Facade* g_facade = nullptr;

NSURL* ToNSURL(const GURL& url) {
  if (!url.is_valid()) {
    return nil;
  }
  return [NSURL URLWithString:base::SysUTF8ToNSString(url.spec())];
}

GURL ToGURL(NSURL* url) {
  return url ? GURL(base::SysNSStringToUTF8(url.absoluteString))
             : GURL("about:blank");
}

// Every facade entry point runs on the browser UI thread, which on macOS is
// the main thread (Decision 3).
void CheckFacadeEntry() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
}

// --arkt-engine-test-api enables the facade's test API (Task W3-5 step 5).
constexpr char kTestAPISwitch[] = "arkt-engine-test-api";

// A 16 pt icon as PNG at 2x (the size a Retina sidebar draws); nil when the
// image has no representation.
NSData* ImageSkiaPNG(const gfx::ImageSkia& image) {
  if (image.isNull()) {
    return nil;
  }
  const gfx::ImageSkiaRep& rep = image.GetRepresentation(2.0f);
  if (rep.is_null()) {
    return nil;
  }
  std::optional<std::vector<uint8_t>> png = gfx::PNGCodec::EncodeBGRASkBitmap(
      rep.GetBitmap(), /*discard_transparency=*/false);
  return png ? [NSData dataWithBytes:png->data() length:png->size()] : nil;
}

// An action icon encoded once: an icon backed by the same image as last time
// (the menu caches its rasterized icons, #258) reuses the encoding.
struct EncodedActionIcon {
  gfx::ImageSkia icon;
  NSData* __strong png = nil;
};
using ActionIconCache = std::map<std::string, EncodedActionIcon>;

NSData* ActionIconPNG(ActionIconCache& cache,
                      const std::string& action_id,
                      const gfx::ImageSkia& icon) {
  if (icon.isNull()) {
    cache.erase(action_id);
    return nil;
  }
  auto it = cache.find(action_id);
  if (it != cache.end() && it->second.icon.BackedBySameObjectAs(icon)) {
    return it->second.png;
  }
  NSData* png = ImageSkiaPNG(icon);
  cache[action_id] = EncodedActionIcon{icon, png};
  return png;
}

// The favicon as PNG, at 2x when the image has that representation, else at
// 1x; nil for an empty image.
NSData* FaviconPNG(const gfx::Image& image) {
  if (image.IsEmpty()) {
    return nil;
  }
  const gfx::ImageSkia* skia = image.ToImageSkia();
  if (skia) {
    if (NSData* png = ImageSkiaPNG(*skia)) {
      return png;
    }
  }
  scoped_refptr<base::RefCountedMemory> bytes = image.As1xPNGBytes();
  if (!bytes || bytes->size() == 0) {
    return nil;
  }
  return [NSData dataWithBytes:bytes->data() length:bytes->size()];
}

// A script result as Foundation values (the JSON-compatible subset); nil for
// none and null.
id ToFoundation(const base::Value& value) {
  switch (value.type()) {
    case base::Value::Type::NONE:
      return nil;
    case base::Value::Type::BOOLEAN:
      return @(value.GetBool());
    case base::Value::Type::INTEGER:
      return @(value.GetInt());
    case base::Value::Type::DOUBLE:
      return @(value.GetDouble());
    case base::Value::Type::STRING:
      return base::SysUTF8ToNSString(value.GetString());
    case base::Value::Type::BINARY:
      return [NSData dataWithBytes:value.GetBlob().data()
                            length:value.GetBlob().size()];
    case base::Value::Type::DICT: {
      NSMutableDictionary* dict = [NSMutableDictionary dictionary];
      for (const auto [key, item] : value.GetDict()) {
        id converted = ToFoundation(item);
        dict[base::SysUTF8ToNSString(key)] = converted ?: [NSNull null];
      }
      return dict;
    }
    case base::Value::Type::LIST: {
      NSMutableArray* list = [NSMutableArray array];
      for (const base::Value& item : value.GetList()) {
        id converted = ToFoundation(item);
        [list addObject:converted ?: [NSNull null]];
      }
      return list;
    }
  }
  return nil;
}

NSError* TestAPIError(NSString* message) {
  return [NSError errorWithDomain:@"ArktEngine"
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}

bool TestAPIEnabled() {
  return base::CommandLine::ForCurrentProcess()->HasSwitch(kTestAPISwitch);
}

const char* ReasonName(ArktCloseReason reason) {
  switch (reason) {
    case ArktCloseReasonNone:
      return "none";
    case ArktCloseReasonClient:
      return "client";
    case ArktCloseReasonPage:
      return "page";
    case ArktCloseReasonExtension:
      return "extension";
    case ArktCloseReasonWindowClosing:
      return "windowClosing";
    case ArktCloseReasonAppTerminating:
      return "appTerminating";
  }
  return "unknown";
}

const char* WindowReasonName(ArktWindowCloseReason reason) {
  switch (reason) {
    case ArktWindowCloseReasonNone:
      return "none";
    case ArktWindowCloseReasonUser:
      return "user";
    case ArktWindowCloseReasonExtension:
      return "extension";
    case ArktWindowCloseReasonLastTabClosed:
      return "lastTabClosed";
    case ArktWindowCloseReasonAppTerminating:
      return "appTerminating";
  }
  return "unknown";
}

// .skipUnloadHandlers (Decision 11): while set, UnloadController answers
// that no unload listener needs to run before closing, so TabStripModel
// detaches and deletes the tab at once without dispatching beforeunload. The
// flag is browser-wide, so it is set only around the one close.
class ScopedSkipUnloadHandlers {
 public:
  explicit ScopedSkipUnloadHandlers(UnloadController* controller)
      : controller_(controller),
        previous_(controller->force_skip_warning_user_on_close()) {
    controller_->set_force_skip_warning_user_on_close(true);
  }
  ScopedSkipUnloadHandlers(const ScopedSkipUnloadHandlers&) = delete;
  ScopedSkipUnloadHandlers& operator=(const ScopedSkipUnloadHandlers&) =
      delete;
  ~ScopedSkipUnloadHandlers() {
    controller_->set_force_skip_warning_user_on_close(previous_);
  }

 private:
  const raw_ptr<UnloadController> controller_;
  const bool previous_;
};

const char* KindName(ArktEngineEventKind kind) {
  switch (kind) {
    case ArktEngineEventKindTabCreated:
      return "TabCreated";
    case ArktEngineEventKindTabClosed:
      return "TabClosed";
    case ArktEngineEventKindActiveTabChanged:
      return "ActiveTabChanged";
    case ArktEngineEventKindCloseCancelled:
      return "CloseCancelled";
    case ArktEngineEventKindURLChanged:
      return "URLChanged";
    case ArktEngineEventKindTitleChanged:
      return "TitleChanged";
    case ArktEngineEventKindFaviconChanged:
      return "FaviconChanged";
    case ArktEngineEventKindLoadingChanged:
      return "LoadingChanged";
    case ArktEngineEventKindHistoryChanged:
      return "HistoryChanged";
    case ArktEngineEventKindTabReplaced:
      return "TabReplaced";
    case ArktEngineEventKindTabMoved:
      return "TabMoved";
    case ArktEngineEventKindWindowOpened:
      return "WindowOpened";
    case ArktEngineEventKindWindowClosed:
      return "WindowClosed";
    case ArktEngineEventKindExtensionActionsChanged:
      return "ExtensionActionsChanged";
    case ArktEngineEventKindAudibleChanged:
      return "AudibleChanged";
    case ArktEngineEventKindMutedChanged:
      return "MutedChanged";
    case ArktEngineEventKindDialogRequested:
      return "DialogRequested";
    case ArktEngineEventKindDialogEnded:
      return "DialogEnded";
    case ArktEngineEventKindPermissionRequested:
      return "PermissionRequested";
    case ArktEngineEventKindPermissionEnded:
      return "PermissionEnded";
    case ArktEngineEventKindInfobarsChanged:
      return "InfobarsChanged";
  }
  return "unknown";
}

}  // namespace
}  // namespace arkt

// -----------------------------------------------------------------------------
// Event

@interface ArktFacadeEvent : NSObject <ArktEngineEvent>
@property(nonatomic) ArktEngineEventKind kind;
@property(nonatomic, nullable) id<ArktTabHandle> tab;
@property(nonatomic, nullable) id<ArktBrowserHandle> browser;
@property(nonatomic) ArktCloseReason closeReason;
@property(nonatomic, nullable, copy) NSURL* url;
@property(nonatomic, nullable, copy) NSString* title;
@property(nonatomic, nullable, copy) NSData* faviconPNG;
@property(nonatomic) BOOL isLoading;
@property(nonatomic) BOOL canGoBack;
@property(nonatomic) BOOL canGoForward;
@property(nonatomic, nullable) id<ArktTabHandle> opener;
@property(nonatomic) ArktTabOrigin origin;
@property(nonatomic) BOOL isActive;
@property(nonatomic) BOOL isAudible;
@property(nonatomic) BOOL isMuted;
@property(nonatomic) ArktWindowCloseReason windowCloseReason;
@property(nonatomic, nullable) id<ArktJavaScriptDialog> dialog;
@property(nonatomic, nullable) id<ArktPermissionRequest> permission;
@property(nonatomic, nullable, copy) NSArray<id<ArktInfobar>>* infobars;
@end

@implementation ArktFacadeEvent
@synthesize kind = _kind;
@synthesize tab = _tab;
@synthesize browser = _browser;
@synthesize closeReason = _closeReason;
@synthesize url = _url;
@synthesize title = _title;
@synthesize faviconPNG = _faviconPNG;
@synthesize isLoading = _isLoading;
@synthesize canGoBack = _canGoBack;
@synthesize canGoForward = _canGoForward;
@synthesize opener = _opener;
@synthesize origin = _origin;
@synthesize isActive = _isActive;
@synthesize isAudible = _isAudible;
@synthesize isMuted = _isMuted;
@synthesize windowCloseReason = _windowCloseReason;
@synthesize dialog = _dialog;
@synthesize permission = _permission;
@synthesize infobars = _infobars;
@end

// A page's alert, confirm or prompt (#400): plain values read once when the
// request arrives, and the shell's one answer. The request is the overlay's
// self-owned ArktJavaScriptDialog, reached through a weak pointer that
// Chromium's manager invalidates when it ends the dialog.
@interface ArktFacadeJavaScriptDialog : NSObject <ArktJavaScriptDialog>
- (instancetype)initWithRequest:(base::WeakPtr<arkt::ArktJavaScriptDialog>)request
                            tab:(id<ArktTabHandle>)tab;
// The request is over (answered or ended by the engine).
- (void)markEnded;
@end

@implementation ArktFacadeJavaScriptDialog {
  base::WeakPtr<arkt::ArktJavaScriptDialog> _request;
  BOOL _ended;
}

@synthesize kind = _kind;
@synthesize tab = _tab;
@synthesize title = _title;
@synthesize message = _message;
@synthesize defaultPromptText = _defaultPromptText;
@synthesize acceptTitle = _acceptTitle;
@synthesize cancelTitle = _cancelTitle;

- (instancetype)initWithRequest:(base::WeakPtr<arkt::ArktJavaScriptDialog>)request
                            tab:(id<ArktTabHandle>)tab {
  if ((self = [super init])) {
    _request = request;
    _tab = tab;
    switch (request->type()) {
      case content::JAVASCRIPT_DIALOG_TYPE_ALERT:
        _kind = ArktDialogKindAlert;
        break;
      case content::JAVASCRIPT_DIALOG_TYPE_CONFIRM:
        _kind = ArktDialogKindConfirm;
        break;
      case content::JAVASCRIPT_DIALOG_TYPE_PROMPT:
        _kind = ArktDialogKindPrompt;
        break;
    }
    _title = base::SysUTF16ToNSString(request->title());
    _message = base::SysUTF16ToNSString(request->message());
    if (_kind == ArktDialogKindPrompt) {
      _defaultPromptText =
          base::SysUTF16ToNSString(request->default_prompt_text());
    }
    // The strings the Views dialog's buttons use (DialogDelegate): an alert
    // only has OK.
    _acceptTitle = base::SysUTF16ToNSString(l10n_util::GetStringUTF16(IDS_APP_OK));
    if (_kind != ArktDialogKindAlert) {
      _cancelTitle =
          base::SysUTF16ToNSString(l10n_util::GetStringUTF16(IDS_APP_CANCEL));
    }
  }
  return self;
}

- (BOOL)isEnded {
  return _ended || !_request;
}

- (void)markEnded {
  _ended = YES;
}

- (BOOL)respondAccepted:(BOOL)accepted userInput:(NSString*)userInput {
  arkt::CheckFacadeEntry();
  if (self.isEnded) {
    return NO;
  }
  const std::u16string input =
      userInput ? base::SysNSStringToUTF16(userInput) : std::u16string();
  // The manager runs the page's callback; the ended callback then reports
  // DialogEnded.
  return _request->Respond(accepted, input);
}

@end

// A site's permission request (#400): plain values read once when the prompt
// is created, and the shell's one answer. The request is the prompt's own
// ArktPermissionAsk, reached through a weak pointer that dies with the prompt
// (Chromium's manager deletes it on a tab switch, a navigation, a withdrawn
// request, an answer or the tab closing).
@interface ArktFacadePermissionRequest : NSObject <ArktPermissionRequest>
- (instancetype)initWithAsk:(base::WeakPtr<arkt::ArktPermissionAsk>)ask
                        tab:(id<ArktTabHandle>)tab;
// The request is over (answered or ended by the engine).
- (void)markEnded;
@end

@implementation ArktFacadePermissionRequest {
  base::WeakPtr<arkt::ArktPermissionAsk> _ask;
  BOOL _ended;
}

@synthesize tab = _tab;
@synthesize origin = _origin;
@synthesize kinds = _kinds;
@synthesize title = _title;
@synthesize items = _items;
@synthesize allowTitle = _allowTitle;
@synthesize allowThisTimeTitle = _allowThisTimeTitle;
@synthesize blockTitle = _blockTitle;

- (instancetype)initWithAsk:(base::WeakPtr<arkt::ArktPermissionAsk>)ask
                        tab:(id<ArktTabHandle>)tab {
  if ((self = [super init])) {
    _ask = ask;
    _tab = tab;
    const arkt::ArktPermissionAsk::Values& values = ask->values();
    _origin = base::SysUTF16ToNSString(values.origin);
    _title = base::SysUTF16ToNSString(values.title);
    NSMutableArray<NSString*>* items = [NSMutableArray array];
    for (const std::u16string& item : values.items) {
      [items addObject:base::SysUTF16ToNSString(item)];
    }
    _items = items;
    NSMutableArray<NSNumber*>* kinds = [NSMutableArray array];
    for (arkt::PermissionKind kind : values.kinds) {
      ArktPermissionKind mapped = ArktPermissionKindOther;
      switch (kind) {
        case arkt::PermissionKind::kGeolocation:
          mapped = ArktPermissionKindGeolocation;
          break;
        case arkt::PermissionKind::kNotifications:
          mapped = ArktPermissionKindNotifications;
          break;
        case arkt::PermissionKind::kCamera:
          mapped = ArktPermissionKindCamera;
          break;
        case arkt::PermissionKind::kMicrophone:
          mapped = ArktPermissionKindMicrophone;
          break;
        case arkt::PermissionKind::kOther:
          break;
      }
      [kinds addObject:@(mapped)];
    }
    _kinds = kinds;
    _allowTitle = base::SysUTF16ToNSString(values.allow_title);
    if (values.allow_this_time_title) {
      _allowThisTimeTitle =
          base::SysUTF16ToNSString(*values.allow_this_time_title);
    }
    _blockTitle = base::SysUTF16ToNSString(values.block_title);
  }
  return self;
}

- (BOOL)isEnded {
  return _ended || !_ask;
}

- (void)markEnded {
  _ended = YES;
}

- (BOOL)respondWithChoice:(ArktPermissionChoice)choice {
  arkt::CheckFacadeEntry();
  if (self.isEnded) {
    return NO;
  }
  arkt::PermissionChoice mapped = arkt::PermissionChoice::kDismiss;
  switch (choice) {
    case ArktPermissionChoiceAllow:
      mapped = arkt::PermissionChoice::kAllow;
      break;
    case ArktPermissionChoiceAllowThisTime:
      mapped = arkt::PermissionChoice::kAllowThisTime;
      break;
    case ArktPermissionChoiceBlock:
      mapped = arkt::PermissionChoice::kBlock;
      break;
    case ArktPermissionChoiceDismiss:
      mapped = arkt::PermissionChoice::kDismiss;
      break;
  }
  // The permission delegate resolves the request and the manager deletes the
  // prompt; its ended callback then reports PermissionEnded.
  return _ask->Respond(mapped);
}

@end

// An infobar of a tab (#400): plain values read when it joined the list, and
// the shell's actions on it. It reaches the infobar through the tab's presenter
// by id and a weak pointer, so an infobar that is gone (the delegate removed
// it, the tab closed, the presenter went with a move to another window)
// refuses every action.
@interface ArktFacadeInfobar : NSObject <ArktInfobar>
- (instancetype)initWithValues:(const arkt::PresentedInfobar&)values
                     presenter:
                         (base::WeakPtr<arkt::ArktInfobarPresenter>)presenter
                           tab:(id<ArktTabHandle>)tab;
// The infobar left the tab's list.
- (void)markEnded;
@end

namespace {

// The icon as a PNG at 2x of 20 points (the engine rasterized it in the
// window's colors); nil when the infobar has none.
NSData* PNGForInfobarIcon(NSImage* image) {
  if (!image) {
    return nil;
  }
  NSBitmapImageRep* rep = [[NSBitmapImageRep alloc]
      initWithBitmapDataPlanes:NULL
                    pixelsWide:40
                    pixelsHigh:40
                 bitsPerSample:8
               samplesPerPixel:4
                      hasAlpha:YES
                      isPlanar:NO
                colorSpaceName:NSCalibratedRGBColorSpace
                   bytesPerRow:0
                  bitsPerPixel:0];
  [NSGraphicsContext saveGraphicsState];
  NSGraphicsContext.currentContext =
      [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
  [image drawInRect:NSMakeRect(0, 0, 40, 40)
           fromRect:NSZeroRect
          operation:NSCompositingOperationSourceOver
           fraction:1.0];
  [NSGraphicsContext restoreGraphicsState];
  return [rep representationUsingType:NSBitmapImageFileTypePNG
                           properties:@{}];
}

}  // namespace

@implementation ArktFacadeInfobar {
  base::WeakPtr<arkt::ArktInfobarPresenter> _presenter;
  uint64_t _id;
  BOOL _ended;
}

@synthesize tab = _tab;
@synthesize kind = _kind;
@synthesize message = _message;
@synthesize messageLinkRanges = _messageLinkRanges;
@synthesize linkTitle = _linkTitle;
@synthesize linkAccessibilityLabel = _linkAccessibilityLabel;
@synthesize linkBeforeButtons = _linkBeforeButtons;
@synthesize okTitle = _okTitle;
@synthesize okTooltip = _okTooltip;
@synthesize okEnabled = _okEnabled;
@synthesize cancelTitle = _cancelTitle;
@synthesize cancelTooltip = _cancelTooltip;
@synthesize cancelEnabled = _cancelEnabled;
@synthesize closeAccessibilityLabel = _closeAccessibilityLabel;
@synthesize iconPNG = _iconPNG;

- (instancetype)initWithValues:(const arkt::PresentedInfobar&)values
                     presenter:
                         (base::WeakPtr<arkt::ArktInfobarPresenter>)presenter
                           tab:(id<ArktTabHandle>)tab {
  if ((self = [super init])) {
    _presenter = presenter;
    _id = values.id;
    _tab = tab;
    switch (values.kind) {
      case arkt::InfobarKind::kOther:
        _kind = ArktInfobarKindOther;
        break;
      case arkt::InfobarKind::kDebugger:
        _kind = ArktInfobarKindDebugger;
        break;
      case arkt::InfobarKind::kAutomation:
        _kind = ArktInfobarKindAutomation;
        break;
      case arkt::InfobarKind::kReload:
        _kind = ArktInfobarKindReload;
        break;
    }
    ArktInfobarContent* content = values.content;
    _message = [content.message copy] ?: @"";
    _messageLinkRanges = [content.messageLinkRanges copy] ?: @[];
    _linkTitle = [content.linkTitle copy];
    _linkAccessibilityLabel = [content.linkAccessibilityLabel copy];
    _linkBeforeButtons = content.linkBeforeButtons;
    _okTitle = [content.okButton.title copy];
    _okTooltip = [content.okButton.tooltip copy];
    _okEnabled = content.okButton.enabled;
    _cancelTitle = [content.cancelButton.title copy];
    _cancelTooltip = [content.cancelButton.tooltip copy];
    _cancelEnabled = content.cancelButton.enabled;
    _closeAccessibilityLabel = [content.closeAccessibilityLabel copy];
    _iconPNG = PNGForInfobarIcon(content.icon);
  }
  return self;
}

- (NSUInteger)infobarId {
  return static_cast<NSUInteger>(_id);
}

- (BOOL)isEnded {
  return _ended || !_presenter;
}

- (void)markEnded {
  _ended = YES;
}

- (BOOL)actWithAction:(ArktInfobarAction)action linkIndex:(NSUInteger)linkIndex {
  arkt::CheckFacadeEntry();
  if (self.isEnded) {
    return NO;
  }
  arkt::InfobarAction mapped = arkt::InfobarAction::kOk;
  switch (action) {
    case ArktInfobarActionOk:
      mapped = arkt::InfobarAction::kOk;
      break;
    case ArktInfobarActionCancel:
      mapped = arkt::InfobarAction::kCancel;
      break;
    case ArktInfobarActionLink:
      mapped = arkt::InfobarAction::kLink;
      break;
    case ArktInfobarActionMessageLink:
      mapped = arkt::InfobarAction::kMessageLink;
      break;
    case ArktInfobarActionClose:
      mapped = arkt::InfobarAction::kClose;
      break;
  }
  // The delegate runs, and decides whether the infobar goes; the presenter
  // then reports the tab's new list.
  return _presenter->Perform(_id, mapped, linkIndex);
}

@end

// A link activation as plain values (#313).
@interface ArktFacadeLinkActivation : NSObject <ArktLinkActivation>
@property(nonatomic, copy) NSURL* url;
@property(nonatomic) id<ArktTabHandle> tab;
@property(nonatomic, nullable, copy) NSURL* sourceURL;
@property(nonatomic) NSEventModifierFlags modifierFlags;
@property(nonatomic) NSInteger disposition;
@end

@implementation ArktFacadeLinkActivation
@synthesize url = _url;
@synthesize tab = _tab;
@synthesize sourceURL = _sourceURL;
@synthesize modifierFlags = _modifierFlags;
@synthesize disposition = _disposition;
@end

// One registered event sink.
@interface ArktFacadeSink : NSObject
@property(nonatomic, copy) void (^block)(NSArray<id<ArktEngineEvent>>*);
@end

@implementation ArktFacadeSink
@synthesize block = _block;
@end


// One back or forward entry.
@interface ArktFacadeHistoryEntry : NSObject <ArktHistoryEntry>
@property(nonatomic, copy) NSURL* url;
@property(nonatomic, copy) NSString* title;
@end

@implementation ArktFacadeHistoryEntry
@synthesize url = _url;
@synthesize title = _title;
@end

// One extension toolbar action of a window.
@interface ArktFacadeExtensionAction : NSObject <ArktExtensionAction>
@property(nonatomic, copy) NSString* actionId;
@property(nonatomic, copy) NSString* name;
@property(nonatomic, nullable, copy) NSData* iconPNG;
@property(nonatomic) BOOL isEnabled;
@end

@implementation ArktFacadeExtensionAction
@synthesize actionId = _actionId;
@synthesize name = _name;
@synthesize iconPNG = _iconPNG;
@synthesize isEnabled = _isEnabled;
@end

// -----------------------------------------------------------------------------
// Tab handle

@interface ArktFacadeTab : NSObject <ArktTabHandle>
- (instancetype)initWithOrigin:(ArktTabOrigin)origin;
// Binds the handle to `tab` in `browser` (insertion, a move between windows,
// a contents replacement). The handle observes the tab's current contents.
- (void)bindTab:(tabs::TabInterface*)tab browser:(ArktFacadeBrowser*)browser;
- (void)unbind;
- (tabs::TabInterface*)tabInterface;
- (content::WebContents*)contents;
// The per-tab state as last reported: seeded without events when the tab is
// announced, then every change is recorded (Task W3-5 step 2).
- (void)seedState;
- (void)reportState;
- (void)setOpenerHandle:(ArktFacadeTab*)opener;
// A client createTab whose insert was deferred (Decision 3): calls that
// change the tab queue behind the insert until -insertFinished: runs them.
// `browser` is the window the tab is to be inserted in.
- (void)markPendingIn:(ArktFacadeBrowser*)browser;
// The deferred insert ran (`inserted`) or was dropped (its window is gone).
- (void)insertFinished:(BOOL)inserted;
// The contents' beforeunload outcome (WebContentsObserver::BeforeUnloadFired).
- (void)beforeUnloadFired:(BOOL)proceed;
@property(nonatomic) BOOL closingByClient;
@property(nonatomic) BOOL closing;
@end

// -----------------------------------------------------------------------------
// Browser handle

@interface ArktFacadeBrowser : NSObject <ArktBrowserHandle>
- (instancetype)initWithBrowser:(BrowserWindowInterface*)browser;
- (BrowserWindowInterface*)browserInterface;
- (void)unbind;
// The window's encoded action icons, keyed by action id (one cache per
// window: windows with different active tabs have different icons).
- (arkt::ActionIconCache&)actionIconCache;
@end

namespace arkt {
namespace {

// The facade's model: handles, the pending event batch and the sinks.
class Facade : public BrowserCollectionObserver, public TabStripModelObserver {
 public:
  explicit Facade(FacadeDelegate* delegate) : delegate_(delegate) {
    pending_ = [[NSMutableArray alloc] init];
    sinks_ = [[NSMutableArray alloc] init];
    browsers_ = [[NSMutableArray alloc] init];
    infobar_objects_ = [[NSMutableDictionary alloc] init];
  }

  void Start() {
    SetLinkActivationDecider(base::BindRepeating(
        &Facade::DecideLinkActivation, base::Unretained(this)));
    SetJavaScriptDialogPresenter(base::BindRepeating(
        &Facade::PresentJavaScriptDialog, base::Unretained(this)));
    SetPermissionPresenter(base::BindRepeating(
        &Facade::PresentPermission, base::Unretained(this)));
    SetInfobarSink(base::BindRepeating(&Facade::PresentInfobars,
                                       base::Unretained(this)));
    observation_.Observe(GlobalBrowserCollection::GetInstance());
    GlobalBrowserCollection::GetInstance()->ForEach(
        [this](BrowserWindowInterface* browser) {
          Adopt(browser);
          return true;
        });
  }

  FacadeDelegate* delegate() { return delegate_; }

  // The link activation throttle asks (#313), from inside the navigation
  // start, and OpenURLFromTab for a modified click (#345), before it opens a
  // tab or a window: the host answers as a Chromium notification would, so a
  // facade call it makes CHECKs. A tab without a handle, or a host without the
  // optional member, navigates. True drops the link.
  bool DecideLinkActivation(const LinkActivation& link) {
    content::WebContents* contents = link.source.get();
    tabs::TabInterface* tab =
        contents ? tabs::TabInterface::MaybeGetFromContents(contents)
                 : nullptr;
    ArktFacadeTab* handle = tab ? HandleForTab(tab) : nil;
    id<ArktWindowHost> host = handle.browser.host;
    if (!host ||
        ![host respondsToSelector:@selector(decideLinkActivation:)]) {
      return false;
    }
    ArktFacadeLinkActivation* activation =
        [[ArktFacadeLinkActivation alloc] init];
    activation.url = ToNSURL(link.url);
    activation.tab = handle;
    activation.sourceURL = ToNSURL(contents->GetLastCommittedURL());
    activation.modifierFlags = ModifierFlagsForDisposition(link.disposition);
    activation.disposition = static_cast<NSInteger>(link.disposition);
    ++in_notification_;
    const ArktLinkDecision decision = [host decideLinkActivation:activation];
    --in_notification_;
    LOG(INFO) << "ARKT: link activation (disposition "
              << static_cast<int>(link.disposition) << ") answered "
              << (decision == ArktLinkDecisionCancel ? "cancel" : "navigate");
    return decision == ArktLinkDecisionCancel;
  }

  // A page's alert, confirm or prompt in an Arkt window with an embedder host
  // (#400), called by Chromium's TabModalDialogManager from inside
  // RunJavaScriptDialog (or when a pending alert's tab comes forward). True
  // takes the dialog: DialogRequested goes to the shell, which answers with
  // -respondAccepted:userInput: or lets the engine end it. False leaves it to
  // Chromium's Views dialog: the tab has no handle, or its window's host is
  // the placeholder (nobody would show the dialog).
  bool PresentJavaScriptDialog(content::WebContents* contents,
                               base::WeakPtr<ArktJavaScriptDialog> request) {
    tabs::TabInterface* tab =
        contents ? tabs::TabInterface::MaybeGetFromContents(contents)
                 : nullptr;
    ArktFacadeTab* handle = tab ? HandleForTab(tab) : nil;
    ArktFacadeBrowser* browser = handle.browser;
    if (!request || !handle || !browser || sinks_.count == 0) {
      return false;
    }
    ArktFacadeJavaScriptDialog* dialog =
        [[ArktFacadeJavaScriptDialog alloc] initWithRequest:request
                                                        tab:handle];
    request->SetEndedCallback(base::BindOnce(
        &Facade::DialogEnded, base::Unretained(this),
        base::Owned(new DialogReference(dialog))));
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = ArktEngineEventKindDialogRequested;
    event.tab = handle;
    event.browser = browser;
    event.dialog = dialog;
    LOG(WARNING) << "ARKT: facade dialog requested kind="
                 << static_cast<int>(dialog.kind);
    RecordFromNotification(event);
    return true;
  }

  // A site's permission request in an Arkt window with an embedder host
  // (#400), called by the permission prompt factory when Chromium creates the
  // prompt (a new request, or a tab that comes forward again). True takes the
  // request: PermissionRequested goes to the shell, which answers with
  // -respondWithChoice: or lets the engine end it. False leaves it to the
  // engine-drawn panel: the tab has no handle, or nobody listens.
  bool PresentPermission(content::WebContents* contents,
                         base::WeakPtr<ArktPermissionAsk> ask) {
    tabs::TabInterface* tab =
        contents ? tabs::TabInterface::MaybeGetFromContents(contents)
                 : nullptr;
    ArktFacadeTab* handle = tab ? HandleForTab(tab) : nil;
    ArktFacadeBrowser* browser = handle.browser;
    if (!ask || !handle || !browser || sinks_.count == 0) {
      return false;
    }
    ArktFacadePermissionRequest* request =
        [[ArktFacadePermissionRequest alloc] initWithAsk:ask tab:handle];
    ask->SetEndedCallback(base::BindOnce(
        &Facade::PermissionEnded, base::Unretained(this),
        base::Owned(new PermissionReference(request))));
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = ArktEngineEventKindPermissionRequested;
    event.tab = handle;
    event.browser = browser;
    event.permission = request;
    LOG(WARNING) << "ARKT: facade permission requested items="
                 << request.items.count;
    RecordFromNotification(event);
    return true;
  }

  // A tab's infobars in an Arkt window with an embedder host (#400), called by
  // the tab's infobar presenter after every change of its list. True takes the
  // list: InfobarsChanged goes to the shell with the tab's whole list, and the
  // presenter keeps its rows hidden (only their height stays, so the page sits
  // below the strip the shell draws). False leaves the rows engine-drawn: the
  // tab has no handle, or nobody listens. One event per tab per batch: a later
  // change replaces the list of the pending one.
  bool PresentInfobars(content::WebContents* contents,
                       base::WeakPtr<ArktInfobarPresenter> presenter) {
    tabs::TabInterface* tab =
        contents ? tabs::TabInterface::MaybeGetFromContents(contents)
                 : nullptr;
    ArktFacadeTab* handle = tab ? HandleForTab(tab) : nil;
    ArktFacadeBrowser* browser = handle.browser;
    if (!presenter || !handle || !browser || sinks_.count == 0) {
      return false;
    }
    NSMutableArray<id<ArktInfobar>>* list = [NSMutableArray array];
    NSMutableSet<NSNumber*>* keep = [NSMutableSet set];
    for (const PresentedInfobar& presented : presenter->Presented()) {
      NSNumber* key = @(presented.id);
      ArktFacadeInfobar* object = infobar_objects_[key];
      if (!object) {
        object = [[ArktFacadeInfobar alloc] initWithValues:presented
                                                 presenter:presenter
                                                       tab:handle];
        infobar_objects_[key] = object;
      }
      [list addObject:object];
      [keep addObject:key];
    }
    // Infobars of this tab that are not in the list any more are gone (acted
    // on, removed by the page, or left behind by a move to another window).
    for (NSNumber* key in [infobar_objects_ allKeys]) {
      ArktFacadeInfobar* object = infobar_objects_[key];
      if (object.tab == handle && ![keep containsObject:key]) {
        [object markEnded];
        [infobar_objects_ removeObjectForKey:key];
      }
    }
    LOG(WARNING) << "ARKT: facade infobars changed count=" << list.count;
    for (ArktFacadeEvent* pending in pending_) {
      if (pending.kind == ArktEngineEventKindInfobarsChanged &&
          pending.tab == handle) {
        pending.infobars = list;
        return true;
      }
    }
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = ArktEngineEventKindInfobarsChanged;
    event.tab = handle;
    event.browser = browser;
    event.infobars = list;
    RecordFromNotification(event);
    return true;
  }

  // The tab is gone: its infobar objects refuse actions and are let go.
  void DropInfobars(ArktFacadeTab* handle) {
    for (NSNumber* key in [infobar_objects_ allKeys]) {
      ArktFacadeInfobar* object = infobar_objects_[key];
      if (object.tab == handle) {
        [object markEnded];
        [infobar_objects_ removeObjectForKey:key];
      }
    }
  }

  // The modifiers Blink derived a link's disposition from
  // (NavigationPolicyFromEventModifiers, Mac): the browser gets the
  // disposition only. NEEDS-RUNTIME-CHECK: a middle click reads as Command,
  // and Shift-Option reads as Shift (Blink ignores Option with Shift).
  static NSEventModifierFlags ModifierFlagsForDisposition(
      WindowOpenDisposition disposition) {
    switch (disposition) {
      case WindowOpenDisposition::NEW_WINDOW:
        return NSEventModifierFlagShift;
      case WindowOpenDisposition::NEW_BACKGROUND_TAB:
        return NSEventModifierFlagCommand;
      case WindowOpenDisposition::NEW_FOREGROUND_TAB:
        return NSEventModifierFlagCommand | NSEventModifierFlagShift;
      default:
        return 0;
    }
  }
  NSArray<ArktFacadeBrowser*>* browsers() { return [browsers_ copy]; }

  // Facade calls from the embedder must never arrive while the facade is
  // inside a Chromium notification (Decision 3).
  void CheckNotInNotification(const char* call) {
    CHECK_EQ(in_notification_, 0)
        << "ARKT: facade " << call << " called inside a Chromium notification";
  }

  ArktFacadeBrowser* HandleForBrowser(BrowserWindowInterface* browser) {
    auto it = browser_handles_.find(browser);
    return it == browser_handles_.end() ? nil : it->second;
  }

  ArktFacadeBrowser* HandleForModel(TabStripModel* model) {
    for (auto& [browser, handle] : browser_handles_) {
      if (browser->GetTabStripModel() == model) {
        return handle;
      }
    }
    return nil;
  }

  ArktFacadeTab* HandleForTab(tabs::TabInterface* tab) {
    auto it = tab_handles_.find(tab);
    return it == tab_handles_.end() ? nil : it->second;
  }

  // The next inserted tab is bound to `handle` (a client createTab).
  void SetBinding(ArktFacadeTab* handle) { binding_ = handle; }
  // Ends a binding. True when a tab was inserted for it (Inserted took it),
  // even if that tab has closed again since.
  bool EndBinding() {
    const bool inserted = binding_ == nil;
    binding_ = nil;
    return inserted;
  }

  void SetTerminating(bool terminating) { terminating_ = terminating; }

  void AdoptHeld(BrowserWindowInterface* browser) {
    ++in_notification_;
    Adopt(browser);
    --in_notification_;
  }

  id<NSObject> AddSink(void (^block)(NSArray<id<ArktEngineEvent>>*)) {
    ArktFacadeSink* sink = [[ArktFacadeSink alloc] init];
    sink.block = block;
    [sinks_ addObject:sink];
    return sink;
  }

  void RemoveSink(id<NSObject> token) { [sinks_ removeObject:token]; }

  void Record(ArktFacadeEvent* event) {
    [pending_ addObject:event];
    if (posted_) {
      return;
    }
    posted_ = true;
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&Facade::Deliver, base::Unretained(this)));
  }

  // Keeps the Objective-C dialog alive until its request ends.
  struct DialogReference {
    explicit DialogReference(ArktFacadeJavaScriptDialog* dialog)
        : dialog(dialog) {}
    ArktFacadeJavaScriptDialog* __strong dialog;
  };

  // Keeps the Objective-C permission request alive until its prompt ends.
  struct PermissionReference {
    explicit PermissionReference(ArktFacadePermissionRequest* request)
        : request(request) {}
    ArktFacadePermissionRequest* __strong request;
  };

  // The prompt is over, answered or ended by the engine: one PermissionEnded.
  void PermissionEnded(PermissionReference* reference) {
    ArktFacadePermissionRequest* request = reference->request;
    [request markEnded];
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = ArktEngineEventKindPermissionEnded;
    event.tab = request.tab;
    event.browser = request.tab.browser;
    event.permission = request;
    RecordFromNotification(event);
  }

  // The request is over, answered or ended by the engine: one DialogEnded.
  void DialogEnded(DialogReference* reference) {
    ArktFacadeJavaScriptDialog* dialog = reference->dialog;
    [dialog markEnded];
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = ArktEngineEventKindDialogEnded;
    event.tab = dialog.tab;
    event.browser = dialog.tab.browser;
    event.dialog = dialog;
    RecordFromNotification(event);
  }

  // Records an event from inside a Chromium notification (a WebContents or
  // favicon observer): a facade call made from there CHECKs.
  void RecordFromNotification(ArktFacadeEvent* event) {
    ++in_notification_;
    Record(event);
    --in_notification_;
  }

  // A held close (of the tab, or of its window or the application) was
  // cancelled: the tab stays (Decision 11). Called from a WebContents
  // notification.
  void RecordCloseCancelled(ArktFacadeTab* tab) {
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = ArktEngineEventKindCloseCancelled;
    event.tab = tab;
    event.browser = tab.browser;
    RecordFromNotification(event);
  }

  // A client createTab or duplicate whose insert did not happen: its window
  // closed first, or the insert added nothing to a live window. ChromiumEngine
  // announced the tab when the call returned (Decision 4), so it gets its
  // terminal TabClosed: client when the client had asked to close it
  // meanwhile, else windowClosing (window gone) or page (nothing inserted).
  void RecordDroppedInsert(ArktFacadeTab* tab,
                           ArktFacadeBrowser* browser,
                           bool window_gone) {
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = ArktEngineEventKindTabClosed;
    event.tab = tab;
    event.browser = browser;
    event.closeReason = tab.closingByClient ? ArktCloseReasonClient
                        : window_gone       ? ArktCloseReasonWindowClosing
                                            : ArktCloseReasonPage;
    LOG(WARNING) << "ARKT: facade insert dropped ("
                 << (window_gone ? "window gone" : "nothing inserted")
                 << "), TabClosed reason " << ReasonName(event.closeReason);
    Record(event);
  }

  // The window's extension action list changed (ToolbarActionsModel, a
  // Chromium notification). One event per window per batch.
  void RecordActionsChanged(ArktFacadeBrowser* browser) {
    for (ArktFacadeEvent* pending in pending_) {
      if (pending.kind == ArktEngineEventKindExtensionActionsChanged &&
          pending.browser == browser) {
        return;
      }
    }
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = ArktEngineEventKindExtensionActionsChanged;
    event.browser = browser;
    RecordFromNotification(event);
  }

  // BrowserCollectionObserver:
  void OnBrowserCreated(BrowserWindowInterface* browser) override {
    ++in_notification_;
    Adopt(browser);
    --in_notification_;
  }

  void OnBrowserClosed(BrowserWindowInterface* browser) override {
    ++in_notification_;
    ArktFacadeBrowser* handle = HandleForBrowser(browser);
    if (handle) {
      TabStripModel* model = browser->GetTabStripModel();
      if (model) {
        model->RemoveObserver(this);
      }
      ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
      event.kind = ArktEngineEventKindWindowClosed;
      event.browser = handle;
      event.windowCloseReason = WindowCloseReasonFor(browser, model);
      LOG(WARNING) << "ARKT: facade window closed, reason "
                   << WindowReasonName(event.windowCloseReason);
      Record(event);
      [handle unbind];
      [browsers_ removeObject:handle];
      browser_handles_.erase(browser);
    }
    --in_notification_;
  }

  // TabStripModelObserver:
  void OnTabStripModelChanged(
      TabStripModel* model,
      const TabStripModelChange& change,
      const TabStripSelectionChange& selection) override {
    ++in_notification_;
    ArktFacadeBrowser* browser = HandleForModel(model);
    if (browser) {
      switch (change.type()) {
        case TabStripModelChange::kInserted:
          for (const auto& inserted : change.GetInsert()->contents) {
            Inserted(inserted.tab, browser, model);
          }
          break;
        case TabStripModelChange::kRemoved:
          for (const auto& removed : change.GetRemove()->contents) {
            Removed(removed.tab, removed.remove_reason, browser, model);
          }
          break;
        case TabStripModelChange::kMoved:
          // An index move inside the window.
          if (ArktFacadeTab* tab = HandleForTab(change.GetMove()->tab)) {
            RecordTabMoved(tab, browser);
          }
          break;
        case TabStripModelChange::kReplaced:
          Replaced(change.GetReplace(), browser);
          break;
        case TabStripModelChange::kSelectionOnly:
          break;
      }
      if (selection.active_tab_changed() && selection.new_tab) {
        ArktFacadeTab* tab = HandleForTab(selection.new_tab);
        if (tab) {
          ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
          event.kind = ArktEngineEventKindActiveTabChanged;
          event.tab = tab;
          event.browser = browser;
          event.isActive = YES;
          Record(event);
        }
        // Action icons and enabled states are for the active tab, so the
        // list changes with it (#258 decision).
        ArktBrowserWindow* window =
            ArktBrowserWindow::FromBrowser(browser.browserInterface);
        if (window && window->host_mode() &&
            window->extensions_container()->menu()) {
          RecordActionsChanged(browser);
        }
      }
    }
    --in_notification_;
  }

 private:
  void Adopt(BrowserWindowInterface* browser) {
    ArktBrowserWindow* window = ArktBrowserWindow::FromBrowser(browser);
    if (HandleForBrowser(browser) || !window) {
      return;
    }
    // A window held before the embedder was ready is announced at replay,
    // once it has the embedder's host (AdoptHeldBrowser).
    if (window->IsShowHeld()) {
      return;
    }
    ArktFacadeBrowser* handle =
        [[ArktFacadeBrowser alloc] initWithBrowser:browser];
    browser_handles_[browser] = handle;
    [browsers_ addObject:handle];
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = ArktEngineEventKindWindowOpened;
    event.browser = handle;
    Record(event);
    TabStripModel* model = browser->GetTabStripModel();
    model->AddObserver(this);
    for (int i = 0; i < model->count(); ++i) {
      Inserted(model->GetTabAtIndex(i), handle, model);
    }
    // A window held before the embedder was ready already has its tabs and
    // its active tab when it is adopted at replay; no selection change will
    // announce that tab (W3-9: a URL opened by another app at a cold launch
    // got a Today row the shell never showed).
    if (ArktFacadeTab* active = HandleForTab(model->GetActiveTab())) {
      ArktFacadeEvent* activated = [[ArktFacadeEvent alloc] init];
      activated.kind = ArktEngineEventKindActiveTabChanged;
      activated.tab = active;
      activated.browser = handle;
      activated.isActive = YES;
      Record(activated);
    }
    // The action list needs a fully constructed Browser (we may be inside
    // its construction), so the window's actions menu is attached from a
    // posted task.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&AttachActionsAfterAdopt, window->GetWeakPtr()));
  }

  static void AttachActionsAfterAdopt(base::WeakPtr<ArktBrowserWindow> window);

  void Inserted(tabs::TabInterface* tab,
                ArktFacadeBrowser* browser,
                TabStripModel* model) {
    ArktFacadeTab* handle = HandleForTab(tab);
    if (handle) {
      // Moved here from another window (DetachTabAtForInsertion): same
      // handle, same container (Decision 5).
      [handle bindTab:tab browser:browser];
      RecordTabMoved(handle, browser);
      return;
    }
    if (binding_) {
      handle = binding_;
      binding_ = nil;
    } else {
      handle = [[ArktFacadeTab alloc] initWithOrigin:ArktTabOriginEngine];
    }
    tab_handles_[tab] = handle;
    [handle bindTab:tab browser:browser];
    int index = model->GetIndexOfTab(tab);
    if (index != TabStripModel::kNoTab) {
      [handle setOpenerHandle:HandleForTab(model->GetOpenerOfTabAt(index))];
    }
    [handle seedState];
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = ArktEngineEventKindTabCreated;
    event.tab = handle;
    event.browser = browser;
    event.url = handle.url;
    event.title = handle.title;
    event.opener = handle.opener;
    event.origin = handle.origin;
    event.isActive = model->GetActiveTab() == tab;
    Record(event);
    // Loading and history the tab already had when it was inserted (a tab
    // that started its navigation before insertion), right after TabCreated.
    [handle reportState];
  }

  void Replaced(const TabStripModelChange::Replace* replace,
                ArktFacadeBrowser* browser) {
    ArktFacadeTab* tab = HandleForTab(replace->tab);
    if (!tab) {
      return;
    }
    // Same tab, new contents (a discard, a prerender activation): the handle
    // and its container stay, the new contents view fills the container.
    [tab bindTab:replace->tab browser:browser];
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = ArktEngineEventKindTabReplaced;
    event.tab = tab;
    event.browser = browser;
    event.url = tab.url;
    event.title = tab.title;
    Record(event);
    [tab reportState];
  }

  void RecordTabMoved(ArktFacadeTab* tab, ArktFacadeBrowser* browser) {
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = ArktEngineEventKindTabMoved;
    event.tab = tab;
    event.browser = browser;
    event.isActive = tab.isActive;
    Record(event);
  }

  void Removed(tabs::TabInterface* tab,
               TabRemovedReason reason,
               ArktFacadeBrowser* browser,
               TabStripModel* model) {
    if (!TabRemoveReasonUtils::WillDeleteTab(reason)) {
      // Moving to another window: the handle stays and TabMoved follows.
      return;
    }
    ArktFacadeTab* handle = HandleForTab(tab);
    if (!handle) {
      return;
    }
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = ArktEngineEventKindTabClosed;
    event.tab = handle;
    event.browser = handle.browser;
    event.closeReason = CloseReasonFor(handle, browser, model);
    LOG(WARNING) << "ARKT: facade tab closed session id " << handle.sessionId
                 << " reason " << ReasonName(event.closeReason);
    Record(event);
    DropInfobars(handle);
    [handle unbind];
    tab_handles_.erase(tab);
  }

  // Decision 12. The facade marks the tabs it closes (client) and every tab
  // once quitting starts (appTerminating). A window close closes every tab
  // at once (TabStripModel::CloseAllTabs): windowClosing, or extension when
  // chrome.windows.remove asked for it. A single tab the facade did not
  // close: extension while an extension's chrome.tabs.remove call is in
  // flight, else page. In 156 chrome.tabs.remove and window.close() both end
  // in WebContentsDelegate::CloseContents, so that call alone does not tell
  // them apart (arkt_extension_calls.h). Other engine-side closes of a
  // single tab (Chromium's own Close Tab command) also report page.
  ArktCloseReason CloseReasonFor(ArktFacadeTab* handle,
                                 ArktFacadeBrowser* browser,
                                 TabStripModel* model) {
    if (handle.closingByClient) {
      return ArktCloseReasonClient;
    }
    if (terminating_) {
      return ArktCloseReasonAppTerminating;
    }
    BrowserWindowInterface* interface = browser.browserInterface;
    if (model->closing_all()) {
      ArktBrowserWindow* window =
          interface ? ArktBrowserWindow::FromBrowser(interface) : nullptr;
      return window && window->IsClosedByExtension()
                 ? ArktCloseReasonExtension
                 : ArktCloseReasonWindowClosing;
    }
    return IsExtensionApiCallInFlight(model->profile(), "tabs.remove")
               ? ArktCloseReasonExtension
               : ArktCloseReasonPage;
  }

  // #401. Called from BrowserDidClose (UnloadController::OnWindowCloseComplete):
  // the Browser and its ArktBrowserWindow are still alive, deletion is only
  // scheduled. Quitting wins; then chrome.windows.remove (the window recorded
  // it when Close() started); then a close that closed every tab at once
  // (UnloadController::OnWindowClosing -> CloseAllTabs: the host's
  // closeRequested, -close, Chromium's Close Window). Otherwise the strip
  // emptied by a tab close or move and TabStripEmpty() closed the window. A
  // window closed with no tabs at all also reads as lastTabClosed; the shell
  // tells that case apart by its own close request.
  ArktWindowCloseReason WindowCloseReasonFor(BrowserWindowInterface* browser,
                                             TabStripModel* model) {
    if (terminating_) {
      return ArktWindowCloseReasonAppTerminating;
    }
    ArktBrowserWindow* window = ArktBrowserWindow::FromBrowser(browser);
    if (window && window->IsClosedByExtension()) {
      return ArktWindowCloseReasonExtension;
    }
    if (model && model->closing_all()) {
      return ArktWindowCloseReasonUser;
    }
    return ArktWindowCloseReasonLastTabClosed;
  }

  void Deliver() {
    posted_ = false;
    NSArray<id<ArktEngineEvent>>* batch = [pending_ copy];
    [pending_ removeAllObjects];
    if (batch.count == 0) {
      return;
    }
    std::string kinds;
    for (id<ArktEngineEvent> event in batch) {
      kinds += kinds.empty() ? "" : ",";
      kinds += KindName(event.kind);
    }
    LOG(WARNING) << "ARKT: facade batch " << batch.count << " event(s) "
                 << kinds << " to " << sinks_.count << " sink(s)";
    for (ArktFacadeSink* sink in [sinks_ copy]) {
      sink.block(batch);
    }
  }

  const raw_ptr<FacadeDelegate> delegate_;
  int in_notification_ = 0;
  bool posted_ = false;
  bool terminating_ = false;
  NSMutableArray<ArktFacadeEvent*>* __strong pending_;
  NSMutableArray<ArktFacadeSink*>* __strong sinks_;
  NSMutableArray<ArktFacadeBrowser*>* __strong browsers_;
  // The infobar objects the shell holds, by infobar id (unique per run).
  NSMutableDictionary<NSNumber*, ArktFacadeInfobar*>* __strong
      infobar_objects_;
  std::map<BrowserWindowInterface*, ArktFacadeBrowser* __strong>
      browser_handles_;
  std::map<tabs::TabInterface*, ArktFacadeTab* __strong> tab_handles_;
  ArktFacadeTab* __strong binding_ = nil;
  base::ScopedObservation<GlobalBrowserCollection, BrowserCollectionObserver>
      observation_{this};
};

// Runs `work` now, or, inside a nested run loop, from a posted task (Decision
// 3). Returns true when the work was deferred.
bool RunOrDefer(const char* call, base::OnceClosure work) {
  CheckFacadeEntry();
  g_facade->CheckNotInNotification(call);
  if (!IsInNestedLoop()) {
    std::move(work).Run();
    return false;
  }
  LOG(WARNING) << "ARKT: facade " << call << " deferred ("
               << DescribeRunLoopNesting() << ")";
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
                                                           std::move(work));
  return true;
}

// Records a tab's state changes as facade events, in Chromium's order
// (Task W3-5 step 2). Each kind is recorded only when its value changed
// since the last report. Every callback is a Chromium notification.
class TabObserver : public content::WebContentsObserver,
                    public favicon::FaviconDriverObserver {
 public:
  explicit TabObserver(ArktFacadeTab* handle) : handle_(handle) {}
  TabObserver(const TabObserver&) = delete;
  TabObserver& operator=(const TabObserver&) = delete;
  ~TabObserver() override = default;

  // Observes `contents` (a new tab, or the new contents after a
  // replacement). The reported values stay, so the next report records what
  // differs on the new contents.
  void SetContents(content::WebContents* contents) {
    if (web_contents() == contents) {
      return;
    }
    Observe(contents);
    favicon_observation_.Reset();
    if (auto* driver =
            favicon::ContentFaviconDriver::FromWebContents(contents)) {
      favicon_observation_.Observe(driver);
    }
  }

  // The values TabCreated carries, taken without recording events. Loading,
  // history, sound and mute start from false, so a tab inserted while
  // loading, with history, playing or muted reports it right after
  // TabCreated.
  void Seed() {
    content::WebContents* contents = web_contents();
    if (!contents) {
      return;
    }
    url_ = contents->GetVisibleURL();
    title_ = contents->GetTitle();
    loading_ = false;
    can_go_back_ = false;
    can_go_forward_ = false;
    audible_ = false;
    muted_ = false;
    host_ = std::string(contents->GetLastCommittedURL().host());
    favicon_ = nil;
  }

  void ReportAll() {
    content::WebContents* contents = web_contents();
    if (!contents) {
      return;
    }
    ReportURL();
    ReportTitle();
    ReportLoading(contents->IsLoading());
    ReportHistory();
    ReportAudible(contents->IsCurrentlyAudible());
    ReportMuted(contents->IsAudioMuted());
    // New contents without a favicon (yet) clear the old one (#256
    // review); a later OnFaviconUpdated sets it.
    favicon::FaviconDriver* driver = favicon_observation_.GetSource();
    ReportFavicon(driver && driver->FaviconIsValid()
                      ? FaviconPNG(driver->GetFavicon())
                      : nil);
  }

  NSData* favicon() const { return favicon_; }

  // content::WebContentsObserver:
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame()) {
      // The pending URL (rule 2: URL before loading starts).
      ReportURL();
    }
  }

  void DidFinishNavigation(content::NavigationHandle* navigation) override {
    if (!navigation->IsInPrimaryMainFrame()) {
      return;
    }
    if (navigation->HasCommitted() && !navigation->IsSameDocument()) {
      std::string host(navigation->GetURL().host());
      if (host != host_) {
        // Committed to another host: the old favicon no longer applies
        // (contract rule 6, cleared before the load ends).
        host_ = host;
        ReportFavicon(nil);
      }
    }
    // A failed or redirected navigation can leave another visible URL.
    ReportURL();
  }

  void DidStartLoading() override {
    // A browser-initiated navigation starts loading before
    // DidStartNavigation; its pending URL is already the visible URL, so it
    // is reported first (contract rule 2: URL, then loading).
    ReportURL();
    ReportLoading(true);
  }

  void DidStopLoading() override {
    ReportURL();
    ReportTitle();
    ReportLoading(false);
  }

  void TitleWasSet(content::NavigationEntry* entry) override { ReportTitle(); }

  void NavigationEntryCommitted(
      const content::LoadCommittedDetails& details) override {
    ReportHistory();
  }

  void NavigationListPruned(const content::PrunedDetails& details) override {
    ReportHistory();
  }

  void NavigationEntriesDeleted() override { ReportHistory(); }

  void BeforeUnloadFired(bool proceed) override {
    [handle_ beforeUnloadFired:proceed];
  }

  // Sound (#364). The audio stream monitor reports a muted page that plays
  // as audible; the shell shows the muted state first.
  void OnAudioStateChanged(bool audible) override { ReportAudible(audible); }

  void DidUpdateAudioMutingState(bool muted) override { ReportMuted(muted); }

  // favicon::FaviconDriverObserver:
  void OnFaviconUpdated(favicon::FaviconDriver* driver,
                        NotificationIconType type,
                        const GURL& icon_url,
                        bool icon_url_changed,
                        const gfx::Image& image) override {
    if (type != NON_TOUCH_16_DIP) {
      return;
    }
    // An empty icon URL means the page removed its favicon.
    ReportFavicon(icon_url.is_empty() ? nil : FaviconPNG(image));
  }

 private:
  ArktFacadeEvent* NewEvent(ArktEngineEventKind kind) {
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = kind;
    return event;
  }

  void Emit(ArktFacadeEvent* event) {
    ArktFacadeTab* handle = handle_;
    if (!handle || !g_facade) {
      return;
    }
    event.tab = handle;
    event.browser = handle.browser;
    g_facade->RecordFromNotification(event);
  }

  void ReportURL() {
    GURL url = web_contents()->GetVisibleURL();
    if (url == url_) {
      return;
    }
    url_ = url;
    ArktFacadeEvent* event = NewEvent(ArktEngineEventKindURLChanged);
    event.url = ToNSURL(url);
    Emit(event);
  }

  void ReportTitle() {
    std::u16string title = web_contents()->GetTitle();
    if (title == title_) {
      return;
    }
    title_ = title;
    ArktFacadeEvent* event = NewEvent(ArktEngineEventKindTitleChanged);
    event.title = base::SysUTF16ToNSString(title);
    Emit(event);
  }

  void ReportLoading(bool loading) {
    if (loading == loading_) {
      return;
    }
    loading_ = loading;
    ArktFacadeEvent* event = NewEvent(ArktEngineEventKindLoadingChanged);
    event.isLoading = loading;
    Emit(event);
  }

  void ReportHistory() {
    content::NavigationController& controller = web_contents()->GetController();
    bool back = controller.CanGoBack();
    bool forward = controller.CanGoForward();
    if (back == can_go_back_ && forward == can_go_forward_) {
      return;
    }
    can_go_back_ = back;
    can_go_forward_ = forward;
    ArktFacadeEvent* event = NewEvent(ArktEngineEventKindHistoryChanged);
    event.canGoBack = back;
    event.canGoForward = forward;
    Emit(event);
  }

  void ReportAudible(bool audible) {
    if (audible == audible_) {
      return;
    }
    audible_ = audible;
    ArktFacadeEvent* event = NewEvent(ArktEngineEventKindAudibleChanged);
    event.isAudible = audible;
    Emit(event);
  }

  void ReportMuted(bool muted) {
    if (muted == muted_) {
      return;
    }
    muted_ = muted;
    ArktFacadeEvent* event = NewEvent(ArktEngineEventKindMutedChanged);
    event.isMuted = muted;
    Emit(event);
  }

  void ReportFavicon(NSData* png) {
    if (png == favicon_ || [png isEqualToData:favicon_]) {
      return;
    }
    favicon_ = png;
    ArktFacadeEvent* event = NewEvent(ArktEngineEventKindFaviconChanged);
    event.faviconPNG = png;
    Emit(event);
  }

  ArktFacadeTab* __weak handle_;
  GURL url_;
  std::u16string title_;
  bool loading_ = false;
  bool can_go_back_ = false;
  bool can_go_forward_ = false;
  bool audible_ = false;
  bool muted_ = false;
  std::string host_;
  NSData* __strong favicon_ = nil;
  base::ScopedObservation<favicon::FaviconDriver,
                          favicon::FaviconDriverObserver>
      favicon_observation_{this};
};

}  // namespace
}  // namespace arkt

namespace arkt {
namespace {

// -----------------------------------------------------------------------------
// Frame copy (#370 thumbnails, #352 Little Arkt's flight).

using FrameCompletion = void (^)(NSData* png, NSSize pixelSize, CGFloat scale);

// The copy may give up after this long in viz (a frame that never comes).
constexpr base::TimeDelta kFrameCopyTimeout = base::Seconds(2);

void AnswerNoFrame(FrameCompletion completion) {
  completion(nil, NSZeroSize, 0);
}

// Posts the empty answer, so the completion never runs inside the call.
void PostNoFrame(FrameCompletion completion) {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&AnswerNoFrame, completion));
}

// On the UI thread: hands the bitmap to the thread pool for the PNG encode and
// answers on the UI thread with the PNG, its size and its pixels per point.
void OnFrameCopied(FrameCompletion completion,
                   int point_width,
                   const content::CopyFromSurfaceResult& result) {
  if (!result.has_value() || result->bitmap.drawsNothing() ||
      result->bitmap.colorType() != kN32_SkColorType || point_width <= 0) {
    VLOG(1) << "ARKT: facade copyFrame: no frame ("
            << (result.has_value() ? "empty or unsupported bitmap"
                                   : "copy failed")
            << ")";
    AnswerNoFrame(completion);
    return;
  }
  SkBitmap bitmap = result->bitmap;
  bitmap.setImmutable();
  const NSSize size = NSMakeSize(bitmap.width(), bitmap.height());
  const CGFloat scale = static_cast<CGFloat>(bitmap.width()) / point_width;
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE,
      {base::TaskPriority::USER_VISIBLE,
       base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN},
      base::BindOnce(
          [](SkBitmap bitmap) {
            return gfx::PNGCodec::FastEncodeBGRASkBitmap(
                bitmap, /*discard_transparency=*/true);
          },
          std::move(bitmap)),
      base::BindOnce(
          [](FrameCompletion completion, NSSize size, CGFloat scale,
             std::optional<std::vector<uint8_t>> png) {
            if (!png || png->empty()) {
              AnswerNoFrame(completion);
              return;
            }
            completion([NSData dataWithBytes:png->data() length:png->size()],
                       size, scale);
          },
          completion, size, scale));
}

// Starts the copy of `contents`' current frame, scaled by viz to fit
// `max_pixel_size` (empty: the full frame). Never shows or wakes the tab: a
// discarded tab, or one without a surface to copy, answers nil.
void CopyFrame(content::WebContents* contents,
               NSSize max_pixel_size,
               FrameCompletion completion) {
  content::RenderWidgetHostView* view =
      contents && !contents->WasDiscarded()
          ? contents->GetRenderWidgetHostView()
          : nullptr;
  if (!view || !view->IsSurfaceAvailableForCopy()) {
    PostNoFrame(completion);
    return;
  }
  const gfx::Size points = view->GetViewBounds().size();
  const double device_scale = view->GetDeviceScaleFactor();
  if (points.IsEmpty() || device_scale <= 0) {
    PostNoFrame(completion);
    return;
  }
  // An empty output size copies at the surface's own (device pixel) size.
  gfx::Size output;
  if (max_pixel_size.width > 0 && max_pixel_size.height > 0) {
    const double width = points.width() * device_scale;
    const double height = points.height() * device_scale;
    const double factor = std::min({1.0, max_pixel_size.width / width,
                                    max_pixel_size.height / height});
    if (factor < 1.0) {
      output = gfx::Size(std::max(1, static_cast<int>(width * factor)),
                         std::max(1, static_cast<int>(height * factor)));
    }
  }
  // CopyFromSurface may answer on another sequence; the answer is posted
  // back to this one (the UI thread).
  view->CopyFromSurface(
      gfx::Rect(), output, kFrameCopyTimeout,
      base::BindPostTask(
          base::SequencedTaskRunner::GetCurrentDefault(),
          base::BindOnce(&OnFrameCopied, completion, points.width())));
}

// Runs `insert` with `handle` bound to the next inserted tab (createTab,
// duplicate). A handle whose insert did not happen gets its terminal
// TabClosed (#256 review); one that was inserted runs the calls queued
// behind it.
void InsertClientTab(
    ArktFacadeBrowser* browser_handle,
    ArktFacadeTab* handle,
    base::OnceCallback<void(BrowserWindowInterface*)> insert) {
  BrowserWindowInterface* browser = browser_handle.browserInterface;
  if (!browser) {
    g_facade->RecordDroppedInsert(handle, browser_handle,
                                  /*window_gone=*/true);
    [handle insertFinished:NO];
    return;
  }
  g_facade->SetBinding(handle);
  std::move(insert).Run(browser);
  if (!g_facade->EndBinding()) {
    g_facade->RecordDroppedInsert(handle, browser_handle,
                                  /*window_gone=*/false);
    [handle insertFinished:NO];
    return;
  }
  // Inserted. A tab closed again within the same call already got its
  // TabClosed from the removal (#258); it is not a dropped insert.
  LOG(WARNING) << "ARKT: facade client tab inserted session id "
               << handle.sessionId
               << (handle.tabInterface ? "" : " (closed again at once)");
  [handle insertFinished:YES];
}

// The actions menu of an embedder host's window (Decision 10): it holds the
// view models of the profile's toolbar actions, runs them and anchors their
// popups, and is the window's ExtensionsContainer menu, so
// chrome.action.openPopup works there too. The placeholder host gets its
// sidebar menu from the hook; the facade lists and runs that one.
ArktExtensionsMenu* EnsureActionsMenu(ArktBrowserWindow* window) {
  if (!window) {
    return nullptr;
  }
  ArktExtensionsContainer* container = window->extensions_container();
  ArktExtensionsMenu* menu = container->menu();
  if (!menu) {
    if (!window->host_mode()) {
      return nullptr;
    }
    container->SetMenu(std::make_unique<ArktExtensionsMenu>(
        window->browser(), nullptr, window->host().cardView));
    menu = container->menu();
    menu->SetDump(base::CommandLine::ForCurrentProcess()->HasSwitch(
        "arkt-extensions-menu-dump"));
    LOG(WARNING) << "ARKT: facade actions menu attached, window session id "
                 << window->browser()->GetSessionID().id();
  }
  menu->SetOnChanged(base::BindRepeating(
      [](base::WeakPtr<ArktBrowserWindow> window) {
        if (!window || !g_facade) {
          return;
        }
        if (ArktFacadeBrowser* handle =
                g_facade->HandleForBrowser(window->browser())) {
          g_facade->RecordActionsChanged(handle);
        }
      },
      window->GetWeakPtr()));
  return menu;
}

// static
void Facade::AttachActionsAfterAdopt(base::WeakPtr<ArktBrowserWindow> window) {
  if (!window || !g_facade || !window->host_mode()) {
    return;
  }
  ArktFacadeBrowser* handle = g_facade->HandleForBrowser(window->browser());
  if (handle && EnsureActionsMenu(window.get())) {
    // The list can be read now.
    g_facade->RecordActionsChanged(handle);
  }
}

}  // namespace
}  // namespace arkt

// -----------------------------------------------------------------------------

@implementation ArktFacadeTab {
  raw_ptr<tabs::TabInterface> _tab;
  std::unique_ptr<arkt::TabObserver> _observer;
  ArktFacadeBrowser* __weak _browser;
  ArktFacadeTab* __weak _opener;
  // The stable container (Decision 6), for the handle's whole life.
  ArktTabContainerView* _container;
  // The last session id the tab had; kept after the tab has closed.
  int32_t _sessionId;
  ArktTabOrigin _origin;
  BOOL _pending;
  // The window a pending insert is for (a pending handle has no _browser).
  ArktFacadeBrowser* __weak _pendingBrowser;
  // Calls made while the insert is pending, run in order after it.
  std::vector<base::OnceClosure> _queued;
}

@synthesize closingByClient = _closingByClient;
@synthesize closing = _closing;

- (instancetype)initWithOrigin:(ArktTabOrigin)origin {
  if ((self = [super init])) {
    _origin = origin;
    _sessionId = -1;
    _container = [[ArktTabContainerView alloc] initWithFrame:NSZeroRect];
  }
  return self;
}

- (void)bindTab:(tabs::TabInterface*)tab browser:(ArktFacadeBrowser*)browser {
  _tab = tab;
  _browser = browser;
  if (!_observer) {
    _observer = std::make_unique<arkt::TabObserver>(self);
  }
  content::WebContents* contents = tab->GetContents();
  _sessionId = sessions::SessionTabHelper::IdForTab(contents).id();
  _observer->SetContents(contents);
  [self adoptContentsView];
}

- (void)unbind {
  _tab = nullptr;
  _browser = nil;
  _closing = NO;
  _observer.reset();
  [_container showContentsView:nil];
}

// In an embedder host's window the container holds the current contents
// view. The placeholder host mounts contents views in its card itself
// (week 2), so there the container stays empty; a window that moves from the
// placeholder to the embedder's host at replay rebinds its tabs
// (AdoptHeldBrowser), which fills the containers.
- (void)adoptContentsView {
  content::WebContents* contents = self.contents;
  ArktFacadeBrowser* browser = _browser;
  arkt::ArktBrowserWindow* window =
      contents && browser
          ? arkt::ArktBrowserWindow::FromBrowser(browser.browserInterface)
          : nullptr;
  if (!window || !window->host_mode()) {
    return;
  }
  NSView* view = contents->GetNativeView().GetNativeNSView();
  if (view && view.superview != _container) {
    [_container showContentsView:view];
  }
  // The tab's infobars sit at the top of the container (Task W3-10).
  window->OnTabContentsViewAdopted(contents);
}

- (void)seedState {
  if (_observer) {
    _observer->Seed();
  }
}

- (void)reportState {
  if (_observer) {
    _observer->ReportAll();
  }
}

- (void)setOpenerHandle:(ArktFacadeTab*)opener {
  _opener = opener;
}

- (void)markPendingIn:(ArktFacadeBrowser*)browser {
  _pending = YES;
  _pendingBrowser = browser;
}

- (void)insertFinished:(BOOL)inserted {
  _pending = NO;
  std::vector<base::OnceClosure> queued;
  queued.swap(_queued);
  if (!inserted || !_tab) {
    LOG(WARNING) << "ARKT: facade "
                 << (inserted ? "tab closed at its insert"
                              : "deferred insert dropped")
                 << ", " << queued.size() << " queued call(s) dropped";
    _closing = NO;
    return;
  }
  if (!queued.empty()) {
    LOG(WARNING) << "ARKT: facade running " << queued.size()
                 << " call(s) queued behind the insert of session id "
                 << _sessionId;
  }
  for (base::OnceClosure& work : queued) {
    std::move(work).Run();
  }
}

// Runs a call that changes the tab: queued behind a pending insert, else now
// or deferred (Decision 3). Returns YES when it did not run now.
- (BOOL)runOrQueue:(const char*)call work:(base::OnceClosure)work {
  arkt::CheckFacadeEntry();
  arkt::g_facade->CheckNotInNotification(call);
  if (_pending) {
    LOG(WARNING) << "ARKT: facade " << call << " queued behind the insert";
    _queued.push_back(std::move(work));
    return YES;
  }
  return arkt::RunOrDefer(call, std::move(work));
}

- (void)beforeUnloadFired:(BOOL)proceed {
  content::WebContents* contents = self.contents;
  if (proceed || !contents) {
    return;
  }
  // A navigation's beforeunload can be cancelled too; only a close counts:
  // this client's close, its window's close, or a close the engine started
  // (chrome.tabs.remove, window.close()) that unload processing held, which
  // TabStripModel marks with TabCloseTypesData (CloseWebContentses).
  arkt::ArktBrowserWindow* window =
      _browser ? arkt::ArktBrowserWindow::FromBrowser(_browser.browserInterface)
               : nullptr;
  const bool engine_close_held =
      TabCloseTypesData::FromWebContents(contents) != nullptr;
  if (!_closing && !(window && window->IsAttemptingToClose()) &&
      !engine_close_held) {
    return;
  }
  if (engine_close_held) {
    // Chromium leaves the marker after a cancel; a later close would read
    // its stale close types, and isClosing would stay true.
    contents->RemoveUserData(TabCloseTypesData::UserDataKey());
  }
  _closing = NO;
  _closingByClient = NO;
  LOG(WARNING) << "ARKT: facade close cancelled session id " << _sessionId;
  arkt::g_facade->RecordCloseCancelled(self);
}

- (tabs::TabInterface*)tabInterface {
  return _tab;
}

- (content::WebContents*)contents {
  return _tab ? _tab->GetContents() : nullptr;
}

- (NSView*)containerView {
  arkt::CheckFacadeEntry();
  [self adoptContentsView];
  return _container;
}

- (int32_t)sessionId {
  arkt::CheckFacadeEntry();
  if (content::WebContents* contents = self.contents) {
    _sessionId = sessions::SessionTabHelper::IdForTab(contents).id();
  }
  return _sessionId;
}

- (id<ArktBrowserHandle>)browser {
  arkt::CheckFacadeEntry();
  return _browser;
}

- (NSURL*)url {
  arkt::CheckFacadeEntry();
  content::WebContents* contents = self.contents;
  return contents ? arkt::ToNSURL(contents->GetVisibleURL()) : nil;
}

- (NSString*)title {
  arkt::CheckFacadeEntry();
  content::WebContents* contents = self.contents;
  return contents ? base::SysUTF16ToNSString(contents->GetTitle()) : @"";
}

- (NSData*)faviconPNG {
  arkt::CheckFacadeEntry();
  return _observer ? _observer->favicon() : nil;
}

- (BOOL)isLoading {
  arkt::CheckFacadeEntry();
  content::WebContents* contents = self.contents;
  return contents && contents->IsLoading();
}

- (BOOL)canGoBack {
  arkt::CheckFacadeEntry();
  content::WebContents* contents = self.contents;
  return contents && contents->GetController().CanGoBack();
}

- (BOOL)canGoForward {
  arkt::CheckFacadeEntry();
  content::WebContents* contents = self.contents;
  return contents && contents->GetController().CanGoForward();
}

// Entries from the current one outwards, `step` -1 (back) or +1 (forward),
// nearest first (contract rule 9). Entry i is goToHistory(offset: step * (i +
// 1)): counted from the pending entry when a history navigation is pending,
// as GoToOffset does (GetIndexForOffset), and an entry without a valid URL
// keeps its place (as about:blank) instead of shifting the later ones (#258).
- (NSArray<id<ArktHistoryEntry>>*)historyEntriesInDirection:(int)step {
  content::WebContents* contents = self.contents;
  NSMutableArray<id<ArktHistoryEntry>>* entries = [NSMutableArray array];
  if (!contents) {
    return entries;
  }
  content::NavigationController& controller = contents->GetController();
  int current = controller.GetCurrentEntryIndex();
  if (current < 0) {
    return entries;
  }
  for (int i = current + step; i >= 0 && i < controller.GetEntryCount();
       i += step) {
    content::NavigationEntry* entry = controller.GetEntryAtIndex(i);
    NSURL* url = entry ? arkt::ToNSURL(entry->GetURL()) : nil;
    ArktFacadeHistoryEntry* item = [[ArktFacadeHistoryEntry alloc] init];
    item.url = url ?: [NSURL URLWithString:@"about:blank"];
    item.title =
        entry ? base::SysUTF16ToNSString(entry->GetTitleForDisplay()) : @"";
    [entries addObject:item];
  }
  return entries;
}

- (NSArray<id<ArktHistoryEntry>>*)backEntries {
  arkt::CheckFacadeEntry();
  return [self historyEntriesInDirection:-1];
}

- (NSArray<id<ArktHistoryEntry>>*)forwardEntries {
  arkt::CheckFacadeEntry();
  return [self historyEntriesInDirection:1];
}

- (id<ArktTabHandle>)opener {
  arkt::CheckFacadeEntry();
  return _opener;
}

- (ArktTabOrigin)origin {
  arkt::CheckFacadeEntry();
  return _origin;
}

- (BOOL)isActive {
  arkt::CheckFacadeEntry();
  return _tab && _browser &&
         _browser.browserInterface->GetTabStripModel()->GetActiveTab() == _tab;
}

- (BOOL)isClosing {
  arkt::CheckFacadeEntry();
  content::WebContents* contents = self.contents;
  if (_closing ||
      (contents && TabCloseTypesData::FromWebContents(contents) != nullptr)) {
    return YES;
  }
  // A window close runs every tab's beforeunload through UnloadController
  // without marking the tabs (contract rule 16: a held window close shows its
  // tabs closing until the dialog is answered; W3-9 contract runner).
  arkt::ArktBrowserWindow* window =
      _tab && _browser
          ? arkt::ArktBrowserWindow::FromBrowser(_browser.browserInterface)
          : nullptr;
  return window && window->IsAttemptingToClose();
}

- (BOOL)wouldHoldClose {
  arkt::CheckFacadeEntry();
  content::WebContents* contents = self.contents;
  if (!contents) {
    return NO;
  }
  // TabStripModel::ShouldRunUnloadListenerBeforeClosing: unload-time
  // handlers in any frame, or the browser's own reasons (attached DevTools,
  // a custom confirmation; UnloadController::ShouldRunUnloadEventsHelper).
  if (contents->NeedToFireBeforeUnloadOrUnloadEvents()) {
    return YES;
  }
  BrowserWindowInterface* browser =
      _browser ? _browser.browserInterface : nullptr;
  UnloadController* unload =
      browser ? UnloadController::From(browser) : nullptr;
  return unload && unload->ShouldRunUnloadListenerBeforeClosing(contents);
}

- (BOOL)isAudible {
  arkt::CheckFacadeEntry();
  content::WebContents* contents = self.contents;
  return contents && contents->IsCurrentlyAudible();
}

- (BOOL)isMuted {
  arkt::CheckFacadeEntry();
  content::WebContents* contents = self.contents;
  return contents && contents->IsAudioMuted();
}

- (void)setMuted:(BOOL)muted {
  // WebContents::SetAudioMuted notifies DidUpdateAudioMutingState only when
  // the state changes; the observer records MutedChanged from there.
  [self runOrQueue:"setMuted"
              work:base::BindOnce(
                       [](ArktFacadeTab* that, bool muted) {
                         if (content::WebContents* contents = that.contents) {
                           contents->SetAudioMuted(muted);
                         }
                       },
                       self, static_cast<bool>(muted))];
}

- (void)copyFrameWithMaxPixelSize:(NSSize)maxPixelSize
                       completion:(void (^)(NSData* _Nullable png,
                                            NSSize pixelSize,
                                            CGFloat scale))completion {
  // A read: nothing about the tab changes, so it is not queued or deferred
  // like the mutators; a pending or closed tab has no contents and answers
  // nil.
  arkt::CheckFacadeEntry();
  arkt::CopyFrame(_pending ? nullptr : self.contents, maxPixelSize,
                  completion);
}

- (void)navigateToURL:(NSURL*)url {
  GURL target = arkt::ToGURL(url);
  [self runOrQueue:"navigate"
              work:base::BindOnce(
                       [](ArktFacadeTab* that, GURL target) {
                         content::WebContents* contents = that.contents;
                         if (!contents) {
                           return;
                         }
                         content::NavigationController::LoadURLParams params(
                             target);
                         params.transition_type = ui::PAGE_TRANSITION_TYPED;
                         contents->GetController().LoadURLWithParams(params);
                       },
                       self, target)];
}

- (void)reload {
  [self runOrQueue:"reload"
              work:base::BindOnce(
                       [](ArktFacadeTab* that) {
                         if (content::WebContents* contents = that.contents) {
                           contents->GetController().Reload(
                               content::ReloadType::NORMAL, true);
                         }
                       },
                       self)];
}

- (void)goBack {
  [self runOrQueue:"goBack"
              work:base::BindOnce(
                       [](ArktFacadeTab* that) {
                         content::WebContents* contents = that.contents;
                         if (contents &&
                             contents->GetController().CanGoBack()) {
                           contents->GetController().GoBack();
                         }
                       },
                       self)];
}

- (void)goForward {
  [self runOrQueue:"goForward"
              work:base::BindOnce(
                       [](ArktFacadeTab* that) {
                         content::WebContents* contents = that.contents;
                         if (contents &&
                             contents->GetController().CanGoForward()) {
                           contents->GetController().GoForward();
                         }
                       },
                       self)];
}

- (void)goToHistoryOffset:(NSInteger)offset {
  [self runOrQueue:"goToHistoryOffset"
              work:base::BindOnce(
                       [](ArktFacadeTab* that, int offset) {
                         content::WebContents* contents = that.contents;
                         if (offset != 0 && contents &&
                             contents->GetController().CanGoToOffset(offset)) {
                           contents->GetController().GoToOffset(offset);
                         }
                       },
                       self, static_cast<int>(offset))];
}

- (void)activate {
  [self runOrQueue:"activate"
              work:base::BindOnce(
                       [](ArktFacadeTab* that) {
                         ArktFacadeTab* tab = that;
                         if (!tab.tabInterface || !tab.browser) {
                           return;
                         }
                         TabStripModel* model =
                             static_cast<ArktFacadeBrowser*>(tab.browser)
                                 .browserInterface->GetTabStripModel();
                         int index = model->GetIndexOfTab(tab.tabInterface);
                         if (index != TabStripModel::kNoTab) {
                           model->ActivateTabAt(index);
                         }
                       },
                       self)];
}

- (ArktCloseResult)closeWithMode:(ArktCloseMode)mode {
  self.closingByClient = YES;
  BOOL not_now = [self
      runOrQueue:"close"
            work:base::BindOnce(
                     [](ArktFacadeTab* that, ArktCloseMode mode) {
                       ArktFacadeTab* tab = that;
                       if (!tab.tabInterface || !tab.browser) {
                         return;
                       }
                       BrowserWindowInterface* browser =
                           static_cast<ArktFacadeBrowser*>(tab.browser)
                               .browserInterface;
                       TabStripModel* model = browser->GetTabStripModel();
                       int index = model->GetIndexOfTab(tab.tabInterface);
                       if (index == TabStripModel::kNoTab) {
                         return;
                       }
                       if (mode == ArktCloseModeSkipUnloadHandlers) {
                         arkt::ScopedSkipUnloadHandlers skip(
                             UnloadController::From(browser));
                         model->CloseWebContentsAt(
                             index, TabCloseTypes::CLOSE_USER_GESTURE);
                       } else {
                         model->CloseWebContentsAt(
                             index, TabCloseTypes::CLOSE_USER_GESTURE);
                       }
                     },
                     self, mode)];
  // Still bound after the close ran: unload processing holds it. Queued or
  // deferred: the tab closes, or holds, when the call runs.
  if (not_now || _tab) {
    _closing = YES;
    return ArktCloseResultHeld;
  }
  return ArktCloseResultClosed;
}

- (void)focus {
  arkt::CheckFacadeEntry();
  if (content::WebContents* contents = self.contents) {
    contents->Focus();
  }
}

- (void)moveToBrowser:(id<ArktBrowserHandle>)target {
  ArktFacadeBrowser* destination =
      [(NSObject*)target isKindOfClass:[ArktFacadeBrowser class]]
          ? static_cast<ArktFacadeBrowser*>(target)
          : nil;
  // The TabModel leaves its strip and joins the other one: the contents,
  // their history and this handle's container stay (Decision 5), and the
  // facade reports TabMoved from the insert. Chromium closes a Browser whose
  // last tab left (Little Arkt's Open in, #314).
  [self runOrQueue:"moveToBrowser"
              work:base::BindOnce(
                       [](ArktFacadeTab* that,
                          ArktFacadeBrowser* destination) {
                         ArktFacadeTab* tab = that;
                         ArktFacadeBrowser* source =
                             static_cast<ArktFacadeBrowser*>(tab.browser);
                         if (!tab.tabInterface || !source || !destination ||
                             source == destination ||
                             !source.browserInterface ||
                             !destination.browserInterface) {
                           return;
                         }
                         TabStripModel* from =
                             source.browserInterface->GetTabStripModel();
                         TabStripModel* to =
                             destination.browserInterface->GetTabStripModel();
                         int index = from->GetIndexOfTab(tab.tabInterface);
                         if (index == TabStripModel::kNoTab) {
                           return;
                         }
                         LOG(WARNING) << "ARKT: facade moving session id "
                                      << tab.sessionId << " to window "
                                      << destination.windowId;
                         std::unique_ptr<tabs::TabModel> detached =
                             from->DetachTabAtForInsertion(index);
                         to->InsertDetachedTabAt(to->count(),
                                                 std::move(detached),
                                                 AddTabTypes::ADD_ACTIVE);
                       },
                       self, destination)];
}

- (id<ArktTabHandle>)duplicate {
  arkt::CheckFacadeEntry();
  arkt::g_facade->CheckNotInNotification("duplicate");
  ArktFacadeBrowser* browser = _pending ? _pendingBrowser : _browser;
  if (!_pending) {
    BrowserWindowInterface* interface =
        browser ? browser.browserInterface : nullptr;
    if (!_tab || !interface) {
      return nil;
    }
    int index = interface->GetTabStripModel()->GetIndexOfTab(_tab);
    if (index == TabStripModel::kNoTab ||
        !chrome::CanDuplicateTabAt(interface, index)) {
      return nil;
    }
  }
  // The copy (navigation entries, the current one loading) is inserted next
  // to this tab and reported with TabCreated, origin client, like createTab:
  // now, from a posted task inside a nested run loop, or right after this
  // tab's own pending insert.
  ArktFacadeTab* handle =
      [[ArktFacadeTab alloc] initWithOrigin:ArktTabOriginClient];
  base::OnceClosure work = base::BindOnce(
      [](ArktFacadeBrowser* original, ArktFacadeTab* source,
         ArktFacadeTab* handle) {
        // The window the source is in when the insert runs: it may have
        // moved since the call (#258).
        ArktFacadeBrowser* target =
            static_cast<ArktFacadeBrowser*>(source.browser) ?: original;
        arkt::InsertClientTab(
            target, handle,
            base::BindOnce(
                [](ArktFacadeTab* source, BrowserWindowInterface* browser) {
                  int index = source.tabInterface
                                  ? browser->GetTabStripModel()->GetIndexOfTab(
                                        source.tabInterface)
                                  : TabStripModel::kNoTab;
                  if (index != TabStripModel::kNoTab &&
                      chrome::CanDuplicateTabAt(browser, index)) {
                    chrome::DuplicateTabAt(browser, index);
                  }
                },
                source));
      },
      browser, self, handle);
  if (_pending) {
    // The source is not inserted yet: the duplicate queues behind it like
    // every other call (#258). If the source's insert is dropped, so is the
    // copy's, with its own terminal TabClosed.
    [handle markPendingIn:browser];
    LOG(WARNING) << "ARKT: facade duplicate queued behind the insert";
    _queued.push_back(mojo::WrapCallbackWithDropHandler(
        std::move(work), base::BindOnce(
                             [](ArktFacadeBrowser* original,
                                ArktFacadeTab* handle) {
                               arkt::g_facade->RecordDroppedInsert(
                                   handle, original,
                                   /*window_gone=*/!original.browserInterface);
                               [handle insertFinished:NO];
                             },
                             browser, handle)));
    return handle;
  }
  if (arkt::RunOrDefer("duplicate", std::move(work))) {
    [handle markPendingIn:browser];
  }
  return handle;
}

@end


// -----------------------------------------------------------------------------

@implementation ArktFacadeBrowser {
  raw_ptr<BrowserWindowInterface> _browser;
  // The last host the window had: a held window moves to the embedder's host
  // at replay, and the handle keeps answering after the window is gone.
  id<ArktWindowHost> __weak _host;
  int32_t _windowId;
  arkt::ActionIconCache _actionIcons;
}

- (arkt::ActionIconCache&)actionIconCache {
  return _actionIcons;
}

- (instancetype)initWithBrowser:(BrowserWindowInterface*)browser {
  if ((self = [super init])) {
    _browser = browser;
    _windowId = browser->GetSessionID().id();
  }
  return self;
}

- (BrowserWindowInterface*)browserInterface {
  return _browser;
}

- (void)unbind {
  _browser = nullptr;
  _actionIcons.clear();
}

- (int32_t)windowId {
  arkt::CheckFacadeEntry();
  return _windowId;
}

- (id<ArktWindowHost>)host {
  arkt::CheckFacadeEntry();
  if (arkt::ArktBrowserWindow* window =
          _browser ? arkt::ArktBrowserWindow::FromBrowser(_browser) : nullptr) {
    _host = window->host();
  }
  return _host;
}

- (NSArray<id<ArktTabHandle>>*)tabs {
  arkt::CheckFacadeEntry();
  NSMutableArray<id<ArktTabHandle>>* tabs = [NSMutableArray array];
  if (!_browser) {
    return tabs;
  }
  TabStripModel* model = _browser->GetTabStripModel();
  for (int i = 0; i < model->count(); ++i) {
    if (ArktFacadeTab* tab =
            arkt::g_facade->HandleForTab(model->GetTabAtIndex(i))) {
      [tabs addObject:tab];
    }
  }
  return tabs;
}

- (id<ArktTabHandle>)activeTab {
  arkt::CheckFacadeEntry();
  return _browser ? arkt::g_facade->HandleForTab(
                        _browser->GetTabStripModel()->GetActiveTab())
                  : nil;
}

- (id<ArktTabHandle>)createTabWithURL:(NSURL*)url active:(BOOL)active {
  // The handle exists at once; the tab is inserted now or, inside a nested
  // run loop, when the posted task runs (Decision 3). Calls on a handle whose
  // insert is pending queue behind it (W3-3 review).
  ArktFacadeTab* handle =
      [[ArktFacadeTab alloc] initWithOrigin:ArktTabOriginClient];
  bool deferred = arkt::RunOrDefer(
      "createTab",
      base::BindOnce(
          [](ArktFacadeBrowser* that, ArktFacadeTab* handle, GURL url,
             bool active) {
            arkt::InsertClientTab(
                that, handle,
                base::BindOnce(
                    [](GURL url, bool active, BrowserWindowInterface* browser) {
                      chrome::AddTabAt(browser, url, -1, active);
                    },
                    url, active));
          },
          self, handle, arkt::ToGURL(url), static_cast<bool>(active)));
  if (deferred) {
    [handle markPendingIn:self];
  }
  return handle;
}

- (void)close {
  arkt::RunOrDefer("closeBrowser",
                   base::BindOnce(
                       [](ArktFacadeBrowser* that) {
                         BrowserWindowInterface* browser =
                             that.browserInterface;
                         if (arkt::ArktBrowserWindow* window =
                                 browser ? arkt::ArktBrowserWindow::FromBrowser(
                                               browser)
                                         : nullptr) {
                           window->Close();
                         }
                       },
                       self));
}

@end

// -----------------------------------------------------------------------------

@interface ArktFacadeEngine : NSObject <ArktEngine>
@end

@implementation ArktFacadeEngine

- (void)embedderReady {
  arkt::CheckFacadeEntry();
  arkt::g_facade->CheckNotInNotification("embedderReady");
  arkt::g_facade->delegate()->OnEmbedderReady();
}

- (void)embedderFailed {
  arkt::CheckFacadeEntry();
  arkt::g_facade->CheckNotInNotification("embedderFailed");
  arkt::g_facade->delegate()->OnEmbedderFailed();
}

- (NSArray<id<ArktBrowserHandle>>*)browsers {
  arkt::CheckFacadeEntry();
  return arkt::g_facade->browsers();
}

- (id<ArktBrowserHandle>)createBrowserWithHost:(id<ArktWindowHost>)host {
  arkt::CheckFacadeEntry();
  arkt::g_facade->CheckNotInNotification("createBrowser");
  // Created at once even inside a nested run loop: a deferred creation could
  // not return the handle (W3-4 deviation, kept in W3-5).
  BrowserWindowInterface* browser =
      arkt::g_facade->delegate()->CreateBrowserForHost(host);
  // Adopted from OnBrowserCreated, inside Browser construction.
  ArktFacadeBrowser* handle = arkt::g_facade->HandleForBrowser(browser);
  CHECK(handle);
  LOG(WARNING) << "ARKT: facade createBrowser(host:) window id "
               << handle.windowId;
  return handle;
}

- (NSArray<id<ArktExtensionAction>>*)extensionActionsForBrowser:
    (id<ArktBrowserHandle>)browser {
  arkt::CheckFacadeEntry();
  NSMutableArray<id<ArktExtensionAction>>* actions = [NSMutableArray array];
  if (![browser isKindOfClass:[ArktFacadeBrowser class]]) {
    return actions;
  }
  BrowserWindowInterface* interface =
      static_cast<ArktFacadeBrowser*>(browser).browserInterface;
  arkt::ArktExtensionsMenu* menu = arkt::EnsureActionsMenu(
      interface ? arkt::ArktBrowserWindow::FromBrowser(interface) : nullptr);
  if (!menu) {
    return actions;
  }
  arkt::ActionIconCache& icons =
      static_cast<ArktFacadeBrowser*>(browser).actionIconCache;
  const std::vector<arkt::ArktExtensionsMenu::ActionInfo> infos =
      menu->GetActions();
  // Actions no longer listed (uninstalled, removed) drop their encodings.
  std::erase_if(icons, [&infos](const auto& entry) {
    return std::none_of(infos.begin(), infos.end(), [&entry](const auto& info) {
      return info.id == entry.first;
    });
  });
  for (const auto& info : infos) {
    ArktFacadeExtensionAction* action =
        [[ArktFacadeExtensionAction alloc] init];
    action.actionId = base::SysUTF8ToNSString(info.id);
    action.name = base::SysUTF16ToNSString(info.name);
    action.iconPNG = arkt::ActionIconPNG(icons, info.id, info.icon);
    action.isEnabled = info.enabled;
    [actions addObject:action];
  }
  return actions;
}

- (void)runExtensionAction:(NSString*)actionId
                 inBrowser:(id<ArktBrowserHandle>)browser
                    anchor:(NSView*)anchor {
  arkt::CheckFacadeEntry();
  if (![browser isKindOfClass:[ArktFacadeBrowser class]]) {
    return;
  }
  arkt::RunOrDefer(
      "runExtensionAction",
      base::BindOnce(
          [](ArktFacadeBrowser* browser, std::string action_id, NSView* anchor) {
            BrowserWindowInterface* interface = browser.browserInterface;
            arkt::ArktExtensionsMenu* menu = arkt::EnsureActionsMenu(
                interface ? arkt::ArktBrowserWindow::FromBrowser(interface)
                          : nullptr);
            if (!menu) {
              LOG(WARNING) << "ARKT: facade runExtensionAction: no window";
              return;
            }
            // The popup anchors to the shell's view (Decision 10). The
            // popover takes the anchor while the action runs, so the
            // window's own anchor is restored after it: a later popup the
            // engine opens (chrome.action.openPopup) does not land on a view
            // the shell passed for one call (#258).
            NSView* previous = menu->anchor();
            menu->SetAnchor(anchor);
            LOG(WARNING) << "ARKT: facade runExtensionAction " << action_id;
            menu->RunAction(action_id);
            menu->SetAnchor(previous);
            LOG(WARNING) << "ARKT: facade runExtensionAction anchor restored "
                         << (__bridge void*)previous << " (call anchor "
                         << (__bridge void*)anchor << ")";
          },
          static_cast<ArktFacadeBrowser*>(browser),
          base::SysNSStringToUTF8(actionId), anchor));
}

- (id<NSObject>)addEventSink:
    (void (^)(NSArray<id<ArktEngineEvent>>* events))sink {
  arkt::CheckFacadeEntry();
  return arkt::g_facade->AddSink(sink);
}

- (void)removeEventSink:(id<NSObject>)token {
  arkt::CheckFacadeEntry();
  arkt::g_facade->RemoveSink(token);
}

- (BOOL)testAPIEnabled {
  arkt::CheckFacadeEntry();
  return arkt::TestAPIEnabled();
}

// Runs `script` in the tab's main frame (the page's world) through
// RenderFrameHost::ExecuteJavaScriptForTests or its user-gesture variant.
// Unlike CDP Runtime.evaluate, a returned promise is not awaited (the public
// API passes resolve_promises=false) and a thrown exception gives a nil
// result, not an error.
- (void)evaluateScript:(NSString*)script
                 inTab:(id<ArktTabHandle>)tab
           userGesture:(BOOL)userGesture
            completion:(void (^)(id _Nullable result,
                                 NSError* _Nullable error))completion {
  arkt::CheckFacadeEntry();
  if (!arkt::TestAPIEnabled()) {
    LOG(WARNING) << "ARKT: facade evaluateScript ignored (no --"
                 << arkt::kTestAPISwitch << ")";
    completion(nil, arkt::TestAPIError(@"The test API is not enabled"));
    return;
  }
  content::WebContents* contents =
      [tab isKindOfClass:[ArktFacadeTab class]]
          ? static_cast<ArktFacadeTab*>(tab).contents
          : nullptr;
  content::RenderFrameHost* frame =
      contents ? contents->GetPrimaryMainFrame() : nullptr;
  if (!frame || !frame->IsRenderFrameLive()) {
    completion(nil, arkt::TestAPIError(@"The tab has no live page"));
    return;
  }
  // The reply comes over the frame's mojo connection; if the renderer goes
  // away first the callback is dropped unrun (#258). The drop runs while
  // the frame is being torn down, so the error completion is posted.
  auto done = mojo::WrapCallbackWithDropHandler(
      base::BindOnce(
          [](void (^completion)(id, NSError*), base::Value result) {
            completion(arkt::ToFoundation(result), nil);
          },
          completion),
      base::BindOnce(
          [](void (^completion)(id, NSError*)) {
            LOG(WARNING) << "ARKT: facade evaluateScript: the page went away "
                            "before it answered";
            NSError* error = arkt::TestAPIError(
                @"The page went away before the script answered");
            base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
                FROM_HERE, base::BindOnce(
                               [](void (^completion)(id, NSError*),
                                  NSError* error) { completion(nil, error); },
                               completion, error));
          },
          completion));
  std::u16string source = base::SysNSStringToUTF16(script);
  if (userGesture) {
    frame->ExecuteJavaScriptWithUserGestureForTests(
        source, std::move(done), content::ISOLATED_WORLD_ID_GLOBAL);
  } else {
    frame->ExecuteJavaScriptForTests(source, std::move(done),
                                     content::ISOLATED_WORLD_ID_GLOBAL);
  }
}

// Closes the tab's pending JavaScript dialog (alert, confirm, prompt,
// beforeunload) through its TabModalDialogManager. A prompt is answered with
// an empty string.
- (BOOL)answerDialogInTab:(id<ArktTabHandle>)tab accept:(BOOL)accept {
  arkt::CheckFacadeEntry();
  if (!arkt::TestAPIEnabled()) {
    LOG(WARNING) << "ARKT: facade answerDialog ignored (no --"
                 << arkt::kTestAPISwitch << ")";
    return NO;
  }
  content::WebContents* contents =
      [tab isKindOfClass:[ArktFacadeTab class]]
          ? static_cast<ArktFacadeTab*>(tab).contents
          : nullptr;
  auto* manager =
      contents
          ? javascript_dialogs::TabModalDialogManager::FromWebContents(contents)
          : nullptr;
  if (!manager) {
    return NO;
  }
  // HandleJavaScriptDialog reads the dialog's input unless an override is
  // given, and a dialog still pending has no view to read it from.
  std::u16string prompt;
  bool answered = manager->HandleJavaScriptDialog(contents, accept, &prompt);
  LOG(WARNING) << "ARKT: facade answerDialog accept=" << (accept ? "yes" : "no")
               << " answered=" << (answered ? "yes" : "no");
  return answered;
}

@end

namespace arkt {

id<ArktEngine> CreateEngineFacade(FacadeDelegate* delegate) {
  CHECK(!g_facade);
  static base::NoDestructor<Facade> facade(delegate);
  g_facade = facade.get();
  g_facade->Start();
  return [[ArktFacadeEngine alloc] init];
}

id<ArktBrowserHandle> BrowserHandleFor(BrowserWindowInterface* browser) {
  return g_facade ? g_facade->HandleForBrowser(browser) : nil;
}

void AdoptHeldBrowser(BrowserWindowInterface* browser) {
  if (g_facade) {
    g_facade->AdoptHeld(browser);
  }
}

void SetFacadeTerminating(bool terminating) {
  if (g_facade) {
    g_facade->SetTerminating(terminating);
  }
}

}  // namespace arkt
