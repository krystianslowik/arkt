#include "arkt/browser/arkt_permission_prompt.h"

#import <AppKit/AppKit.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "arkt/browser/arkt_browser_window.h"
#import "arkt/browser/arkt_dialog_sheet.h"
#include "base/functional/bind.h"
#include "base/i18n/rtl.h"
#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/url_identity.h"
#include "chrome/grit/generated_resources.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "components/permissions/features.h"
#include "components/permissions/permission_prompt.h"
#include "components/permissions/permission_request.h"
#include "components/permissions/permission_request_manager.h"
#include "components/permissions/permission_uma_constants.h"
#include "components/permissions/permission_util.h"
#include "components/permissions/request_type.h"
#include "components/strings/grit/components_strings.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/mac/coordinate_conversion.h"

namespace arkt {
namespace {

using permissions::PermissionPrompt;
using permissions::PermissionRequest;
using permissions::RequestType;

// Chrome's bubble ignores clicks for a moment after it appears
// (PermissionPromptBaseView input protection); the panel keeps the allow
// buttons disabled for as long.
constexpr NSTimeInterval kInputProtection = 0.5;
// Chrome's bubble width (DISTANCE_BUBBLE_PREFERRED_WIDTH).
constexpr CGFloat kPanelWidth = 320;

ArktBrowserWindow* ArktWindowOf(content::WebContents* contents) {
  tabs::TabInterface* tab =
      contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  return tab ? ArktBrowserWindow::FromBrowser(tab->GetBrowserWindowInterface())
             : nullptr;
}

// What the panel covers: the ask prompt, loud or quiet. Quiet requests
// (notifications or location asked for without a gesture, abusive sites) get
// the panel too, as Chrome shows its loud bubble for them when there is no
// location bar for the quiet chip (CreateQuietPrompt, fullscreen). The
// permission element's secondary UI and pointer/keyboard lock keep Chrome's
// prompt (recorded in the week-2 results, "#260").
bool PanelCovers(content::WebContents* contents,
                 PermissionPrompt::Delegate* delegate) {
  if (delegate->Requests().empty() ||
      permissions::PermissionUtil::
          ShouldCurrentRequestUsePermissionElementSecondaryUI(delegate,
                                                              contents)) {
    return false;
  }
  for (const auto& request : delegate->Requests()) {
    RequestType type = request->request_type();
    if (type == RequestType::kPointerLock ||
        type == RequestType::kKeyboardLock ||
        // Chrome's bubble CHECKs this one out too (approximate location is
        // not on desktop yet).
        request->GetContentSettingsType() ==
            ContentSettingsType::GEOLOCATION_WITH_OPTIONS) {
      return false;
    }
  }
  return true;
}

// As PermissionPromptBubbleBaseView::IsOneTimePermission: every request can
// be granted for this visit only (location, camera, microphone).
bool IsOneTime(PermissionPrompt::Delegate* delegate) {
  for (const auto& request : delegate->Requests()) {
    std::optional<ContentSettingsType> type =
        permissions::RequestTypeToContentSettingsType(request->request_type());
    if (!type ||
        !permissions::PermissionUtil::DoesSupportTemporaryGrants(*type)) {
      return false;
    }
  }
  return true;
}

// As the one-origin bubble: a camera request is hidden when pan-tilt-zoom is
// asked for too.
std::vector<PermissionRequest*> VisibleRequests(
    PermissionPrompt::Delegate* delegate) {
  bool has_ptz = false;
  for (const auto& request : delegate->Requests()) {
    has_ptz |= request->request_type() == RequestType::kCameraPanTiltZoom;
  }
  std::vector<PermissionRequest*> visible;
  for (const auto& request : delegate->Requests()) {
    if (has_ptz && request->request_type() == RequestType::kCameraStream) {
      continue;
    }
    visible.push_back(request.get());
  }
  return visible;
}

// The origin as the bubble names it (PermissionPromptBaseView::GetUrlIdentity).
std::u16string OriginName(content::WebContents* contents,
                          PermissionPrompt::Delegate* delegate) {
  constexpr UrlIdentity::TypeSet kAllowedTypes = {
      UrlIdentity::Type::kDefault, UrlIdentity::Type::kChromeExtension,
      UrlIdentity::Type::kIsolatedWebApp, UrlIdentity::Type::kFile};
  constexpr UrlIdentity::FormatOptions kOptions = {
      .default_options = {
          UrlIdentity::DefaultFormatOptions::kOmitCryptographicScheme}};
  UrlIdentity identity = UrlIdentity::CreateFromUrl(
      Profile::FromBrowserContext(contents->GetBrowserContext()),
      delegate->GetRequestingOrigin(), kAllowedTypes, kOptions);
  if (identity.type == UrlIdentity::Type::kFile) {
    return l10n_util::GetStringUTF16(IDS_PERMISSIONS_BUBBLE_PROMPT_THIS_FILE);
  }
  return identity.name;
}

PermissionPresenter& Presenter() {
  static base::NoDestructor<PermissionPresenter> presenter;
  return *presenter;
}

PermissionKind KindOf(RequestType type) {
  switch (type) {
    case RequestType::kGeolocation:
      return PermissionKind::kGeolocation;
    case RequestType::kNotifications:
      return PermissionKind::kNotifications;
    case RequestType::kCameraStream:
    case RequestType::kCameraPanTiltZoom:
      return PermissionKind::kCamera;
    case RequestType::kMicStream:
      return PermissionKind::kMicrophone;
    default:
      return PermissionKind::kOther;
  }
}

class ArktPermissionPrompt : public PermissionPrompt {
 public:
  enum class Choice { kAllow, kAllowThisTime, kBlock, kDismiss };

  static Choice ToChoice(PermissionChoice choice) {
    switch (choice) {
      case PermissionChoice::kAllow:
        return Choice::kAllow;
      case PermissionChoice::kAllowThisTime:
        return Choice::kAllowThisTime;
      case PermissionChoice::kBlock:
        return Choice::kBlock;
      case PermissionChoice::kDismiss:
        return Choice::kDismiss;
    }
  }

  ArktPermissionPrompt(content::WebContents* contents,
                       Delegate* delegate,
                       ArktBrowserWindow* window)
      : contents_(contents),
        delegate_(delegate->GetWeakPtr()),
        window_(window->GetWeakPtr()) {
    std::vector<PermissionRequest*> visible = VisibleRequests(delegate);
    const bool one_time = IsOneTime(delegate);

    ArktPermissionAsk::Values values;
    values.origin = OriginName(contents, delegate);
    values.title = l10n_util::GetStringFUTF16(IDS_PERMISSIONS_BUBBLE_PROMPT,
                                               values.origin);
    for (PermissionRequest* request : visible) {
      values.items.push_back(request->GetMessageTextFragment());
      values.kinds.push_back(KindOf(request->request_type()));
    }
    if (one_time) {
      // Chrome's three answers, in its order and with its labels.
      std::optional<std::u16string> allow =
          visible.size() == 1 ? visible[0]->GetAllowAlwaysText()
                              : std::nullopt;
      std::optional<std::u16string> block =
          visible.size() == 1 ? visible[0]->GetBlockText() : std::nullopt;
      values.allow_title = allow.value_or(
          l10n_util::GetStringUTF16(IDS_PERMISSION_ALLOW_WHILE_VISITING));
      values.allow_this_time_title =
          l10n_util::GetStringUTF16(IDS_PERMISSION_ALLOW_THIS_TIME);
      values.block_title = block.value_or(
          l10n_util::GetStringUTF16(IDS_PERMISSION_NEVER_ALLOW));
    } else {
      values.allow_title = l10n_util::GetStringUTF16(IDS_PERMISSION_ALLOW);
      values.block_title = l10n_util::GetStringUTF16(IDS_PERMISSION_DENY);
    }

    base::WeakPtr<ArktPermissionPrompt> weak = weak_factory_.GetWeakPtr();
    // The shell draws the request when the window's host presents it (issue
    // #400); the panel below is the fallback.
    if (window->host_mode() && Presenter()) {
      ask_ = std::make_unique<ArktPermissionAsk>(
          values, base::BindRepeating(
                      [](base::WeakPtr<ArktPermissionPrompt> prompt,
                         PermissionChoice choice) {
                        if (prompt) {
                          prompt->Answer(ToChoice(choice));
                        }
                      },
                      weak));
      if (Presenter().Run(contents, ask_->GetWeakPtr())) {
        LOG(WARNING) << "ARKT: permission prompt presented to the shell "
                     << "requests=" << visible.size()
                     << " one_time=" << one_time
                     << " quiet=" << delegate->ShouldCurrentRequestUseQuietUI();
        return;
      }
      ask_.reset();
    }

    ArktDialogSheetContent* content = [[ArktDialogSheetContent alloc] init];
    content.width = kPanelWidth;
    content.title = base::SysUTF16ToNSString(values.title);
    NSMutableArray<ArktDialogSheetItem*>* items = [NSMutableArray array];
    for (const std::u16string& text : values.items) {
      ArktDialogSheetItem* item = [[ArktDialogSheetItem alloc] init];
      item.text = base::SysUTF16ToNSString(text);
      [items addObject:item];
    }
    content.listItems = items;
    content.primaryTitle = base::SysUTF16ToNSString(values.allow_title);
    content.cancelTitle = base::SysUTF16ToNSString(values.block_title);
    if (one_time) {
      content.secondaryTitle =
          base::SysUTF16ToNSString(*values.allow_this_time_title);
      content.stackedButtons = YES;
    }
    // Equal weight for every answer and no Return default, as Chrome's tonal
    // buttons: the prompt does not steer toward Allow.
    content.neutralPrimary = YES;
    content.defaultButton = ArktDialogSheetDefaultNone;
    content.escapeDismisses = YES;
    content.primaryEnableDelay = kInputProtection;

    sheet_ = [[ArktDialogSheet alloc] initWithContent:content];
    // Each answer may destroy this prompt (the manager finalizes the request
    // and deletes its view), so nothing is touched after the delegate call.
    sheet_.onPrimary = ^{
      if (weak) {
        weak->Answer(Choice::kAllow);
      }
    };
    sheet_.onSecondary = ^{
      if (weak) {
        weak->Answer(Choice::kAllowThisTime);
      }
    };
    sheet_.onCancel = ^{
      if (weak) {
        weak->Answer(Choice::kBlock);
      }
    };
    // Escape, or the window closing: dismissed, as closing Chrome's bubble.
    sheet_.onDismiss = ^{
      if (weak) {
        weak->Answer(Choice::kDismiss);
      }
    };

    NSView* anchor = window->PromptAnchorViewFor(contents);
    [sheet_ beginPanelOnView:anchor rightToLeft:base::i18n::IsRTL()];
    NSRect frame = sheet_.window.frame;
    NSRect host = [anchor.window frame];
    LOG(WARNING) << "ARKT: permission prompt shown requests="
                 << visible.size() << " one_time=" << one_time
                 << " quiet=" << delegate->ShouldCurrentRequestUseQuietUI()
                 << " parent=" << anchor.window.windowNumber
                 << " child=" << (sheet_.window.parentWindow == anchor.window)
                 << " frame " << NSMinX(frame) << "," << NSMinY(frame) << " "
                 << NSWidth(frame) << "x" << NSHeight(frame) << " window "
                 << NSMinX(host) << "," << NSMinY(host) << " "
                 << NSWidth(host) << "x" << NSHeight(host)
                 << " rtl=" << base::i18n::IsRTL();
  }

  ArktPermissionPrompt(const ArktPermissionPrompt&) = delete;
  ArktPermissionPrompt& operator=(const ArktPermissionPrompt&) = delete;

  ~ArktPermissionPrompt() override {
    // The manager deletes its view on a tab switch (the request stays
    // pending), when the request is answered or dropped, and when the tab
    // goes. None of that is an answer: close without a callback. The sheet
    // may be running the callback that led here, so it lives to the next
    // turn of the run loop.
    if (ask_) {
      ask_->End();
    }
    ArktDialogSheet* sheet = sheet_;
    [sheet close];
    dispatch_async(dispatch_get_main_queue(), ^{
      (void)sheet;
    });
    LOG(WARNING) << "ARKT: permission prompt closed";
  }

  // PermissionPrompt:
  bool UpdateAnchor() override {
    // A tab moved to another window gets a new prompt there.
    if (ArktWindowOf(contents_) != window_.get()) {
      return false;
    }
    return true;
  }
  TabSwitchingBehavior GetTabSwitchingBehavior() override {
    return TabSwitchingBehavior::kDestroyPromptButKeepRequestPending;
  }
  permissions::PermissionPromptDisposition GetPromptDisposition()
      const override {
    return permissions::PermissionPromptDisposition::ANCHORED_BUBBLE;
  }
  bool IsAskPrompt() const override { return true; }
  std::optional<gfx::Rect> GetViewBoundsInScreen() const override {
    NSWindow* window = sheet_.window;
    if (!window.visible) {
      return std::nullopt;
    }
    return gfx::ScreenRectFromNSRect(window.frame);
  }
  std::vector<permissions::ElementAnchoredBubbleVariant> GetPromptVariants()
      const override {
    return {};
  }
  std::optional<permissions::feature_params::PermissionElementPromptPosition>
  GetPromptPosition() const override {
    return std::nullopt;
  }

 private:
  // As PermissionPromptBubbleBaseView::RunButtonCallback and
  // ClosingPermission.
  void Answer(Choice choice) {
    LOG(WARNING) << "ARKT: permission prompt answer "
                 << static_cast<int>(choice) << " (0 allow, 1 allow this "
                 << "time, 2 block, 3 dismiss)";
    if (!delegate_) {
      return;
    }
    // `this` may be gone after any of these.
    switch (choice) {
      case Choice::kAllow:
        delegate_->Accept(std::monostate());
        return;
      case Choice::kAllowThisTime:
        delegate_->AcceptThisTime(std::monostate());
        return;
      case Choice::kBlock:
        delegate_->Deny(std::monostate());
        return;
      case Choice::kDismiss:
        delegate_->Dismiss(std::monostate());
        return;
    }
  }

  raw_ptr<content::WebContents> contents_;
  base::WeakPtr<Delegate> delegate_;
  base::WeakPtr<ArktBrowserWindow> window_;
  ArktDialogSheet* __strong sheet_ = nil;
  // Set while the shell presents the request (no panel then).
  std::unique_ptr<ArktPermissionAsk> ask_;
  base::WeakPtrFactory<ArktPermissionPrompt> weak_factory_{this};
};

std::unique_ptr<PermissionPrompt> CreatePrompt(
    content::WebContents* contents,
    PermissionPrompt::Delegate* delegate) {
  ArktBrowserWindow* window = ArktWindowOf(contents);
  if (!window || !PanelCovers(contents, delegate)) {
    if (window) {
      LOG(WARNING) << "ARKT: permission prompt left to Chrome (element or "
                      "lock request)";
    }
    return PermissionPrompt::Create(contents, delegate);
  }
  // As Chrome without a location bar: a request that may only be shown
  // quietly is not shown; the manager then resolves it as ignored, so the
  // page does not wait.
  if (delegate->ShouldCurrentRequestUseQuietUI() &&
      delegate->ShouldDropCurrentRequestIfCannotShowQuietly()) {
    LOG(WARNING) << "ARKT: permission prompt dropped (quiet only, no "
                    "location bar)";
    return nullptr;
  }
  return std::make_unique<ArktPermissionPrompt>(contents, delegate, window);
}

}  // namespace

ArktPermissionAsk::ArktPermissionAsk(Values values, AnswerCallback answer)
    : values_(std::move(values)), answer_(std::move(answer)) {}

ArktPermissionAsk::~ArktPermissionAsk() = default;

bool ArktPermissionAsk::Respond(PermissionChoice choice) {
  if (over_ || answered_) {
    return false;
  }
  answered_ = true;
  if (choice == PermissionChoice::kAllowThisTime &&
      !values_.allow_this_time_title) {
    choice = PermissionChoice::kAllow;
  }
  // The callback may delete the prompt, and this object with it: run a copy.
  AnswerCallback answer = answer_;
  answer.Run(choice);
  return true;
}

void ArktPermissionAsk::End() {
  if (over_) {
    return;
  }
  over_ = true;
  if (ended_) {
    std::move(ended_).Run();
  }
}

void SetPermissionPresenter(PermissionPresenter presenter) {
  Presenter() = std::move(presenter);
}

void UseArktPermissionPrompts(content::WebContents* contents) {
  auto* manager =
      contents ? permissions::PermissionRequestManager::FromWebContents(contents)
               : nullptr;
  if (!manager) {
    return;
  }
  // The manager's only view factory setter. The factory decides per request,
  // so a tab that later moves to a Views window gets Chrome's prompt there.
  manager->set_view_factory_for_testing(base::BindRepeating(&CreatePrompt));
}

}  // namespace arkt
