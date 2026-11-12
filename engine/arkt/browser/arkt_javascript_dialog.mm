#include "arkt/browser/arkt_javascript_dialog.h"

#include <utility>

#include "arkt/browser/arkt_browser_window.h"
#include "base/check.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/supports_user_data.h"
#include "chrome/browser/chrome_browser_application_mac.h"
#include "chrome/browser/ui/javascript_dialogs/javascript_tab_modal_dialog_manager_delegate_desktop.h"
#include "components/javascript_dialogs/app_modal_dialog_controller.h"
#include "components/javascript_dialogs/app_modal_dialog_manager.h"
#include "components/javascript_dialogs/tab_modal_dialog_manager.h"
#include "components/strings/grit/components_strings.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_delegate.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/strings/grit/ui_strings.h"

namespace arkt {
namespace {

JavaScriptDialogPresenter& Presenter() {
  static base::NoDestructor<JavaScriptDialogPresenter> presenter;
  return *presenter;
}

// True when a dialog of `contents` would go to the shell: the tab is in an
// Arkt window whose host presents dialogs, and the facade set a presenter.
// The presenter can still decline (no tab handle, nobody listening).
bool InArktHostWindow(content::WebContents* contents) {
  tabs::TabInterface* tab =
      contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  ArktBrowserWindow* window =
      tab ? ArktBrowserWindow::FromBrowser(tab->GetBrowserWindowInterface())
          : nullptr;
  return window && window->host_mode() && Presenter();
}

// Chromium's app-modal factory (Cocoa, or Views behind its feature), saved
// when the overlay wraps it.
javascript_dialogs::AppModalDialogManager::AppModalViewFactory&
ChromiumAppModalFactory() {
  static base::NoDestructor<
      javascript_dialogs::AppModalDialogManager::AppModalViewFactory>
      factory;
  return *factory;
}

// Marks contents that already have Arkt's delegate (the manager's delegate is
// private, so this is the only way to tell), so a tab that binds again, after
// a move or a replacement, keeps its manager and any dialog it holds.
class InstalledMarker : public base::SupportsUserData::Data {
 public:
  static const void* Key() { return &kKey; }

 private:
  static constexpr int kKey = 0;
};

}  // namespace

// Chromium's desktop delegate with its dialog factory replaced: a dialog the
// presenter takes is an ArktJavaScriptDialog, any other is Chromium's own
// Views dialog. Foremost, attention, activation and tab strip handling stay
// the base class's.
class ArktJavaScriptDialogDelegate
    : public JavaScriptTabModalDialogManagerDelegateDesktop {
 public:
  explicit ArktJavaScriptDialogDelegate(content::WebContents* contents)
      : JavaScriptTabModalDialogManagerDelegateDesktop(contents),
        contents_(contents) {}

  base::WeakPtr<javascript_dialogs::TabModalDialogView> CreateNewDialog(
      content::WebContents* alerting_web_contents,
      const std::u16string& title,
      content::JavaScriptDialogType dialog_type,
      const std::u16string& message_text,
      const std::u16string& default_prompt_text,
      content::JavaScriptDialogManager::DialogClosedCallback dialog_callback,
      base::OnceClosure dialog_closed_callback) override {
    tabs::TabInterface* tab = tabs::TabInterface::MaybeGetFromContents(
        contents_);
    if (InArktHostWindow(contents_) && tab->CanShowModalUI()) {
      auto* dialog = new ArktJavaScriptDialog(
          contents_, dialog_type, title, message_text, default_prompt_text,
          std::move(dialog_callback), tab->ShowModalUI());
      if (Presenter().Run(contents_, dialog->GetWeakPtr())) {
        return dialog->view_weak_factory_.GetWeakPtr();
      }
      // Nobody took it: the page would wait on a dialog no one shows. Take it
      // back (the page's callback goes with it, so use Chromium's dialog
      // below with a fresh one); the dialog was not handed out yet.
      dialog_callback = std::move(dialog->dialog_callback_);
      delete dialog;
    }
    return JavaScriptTabModalDialogManagerDelegateDesktop::CreateNewDialog(
        alerting_web_contents, title, dialog_type, message_text,
        default_prompt_text, std::move(dialog_callback),
        std::move(dialog_closed_callback));
  }

 private:
  raw_ptr<content::WebContents> contents_;
};

// Chromium's app-modal factory with a leave-site dialog of a tab in an Arkt
// window taken out: it becomes an ArktBeforeUnloadDialog that the presenter
// hands to the shell. Every other dialog, and one the presenter declines,
// goes to Chromium's factory.
class ArktBeforeUnloadDialogFactory {
 public:
  static javascript_dialogs::AppModalDialogView* Create(
      std::unique_ptr<javascript_dialogs::AppModalDialogController>
          controller) {
    content::WebContents* contents = controller->web_contents();
    if (controller->is_before_unload_dialog() && contents &&
        InArktHostWindow(contents)) {
      // As Chromium's Cocoa dialog: the tab comes forward when the dialog is
      // created, so it is the shown tab (ActiveTabChanged before
      // DialogRequested).
      if (content::WebContentsDelegate* delegate = contents->GetDelegate()) {
        delegate->ActivateContents(contents);
      }
      auto* dialog = new ArktBeforeUnloadDialog(std::move(controller));
      if (Presenter().Run(contents, dialog->GetWeakPtr())) {
        LOG(WARNING) << "ARKT: leave-site dialog to the shell";
        return dialog;
      }
      // Nobody took it: Chromium's dialog shows it (the controller goes back
      // with it; the dialog was not handed out).
      controller = std::move(dialog->controller_);
      dialog->over_ = true;
      delete dialog;
    }
    return ChromiumAppModalFactory().Run(std::move(controller));
  }
};

ArktPageDialog::ArktPageDialog() = default;
ArktPageDialog::~ArktPageDialog() = default;

ArktJavaScriptDialog::ArktJavaScriptDialog(
    content::WebContents* contents,
    content::JavaScriptDialogType type,
    const std::u16string& title,
    const std::u16string& message,
    const std::u16string& default_prompt_text,
    content::JavaScriptDialogManager::DialogClosedCallback dialog_callback,
    std::unique_ptr<tabs::ScopedTabModalUI> modal_ui)
    : contents_(contents),
      type_(type),
      title_(title),
      message_(message),
      default_prompt_text_(default_prompt_text),
      dialog_callback_(std::move(dialog_callback)),
      modal_ui_(std::move(modal_ui)) {}

ArktJavaScriptDialog::~ArktJavaScriptDialog() = default;

ArktPageDialog::Kind ArktJavaScriptDialog::kind() const {
  switch (type_) {
    case content::JAVASCRIPT_DIALOG_TYPE_ALERT:
      return Kind::kAlert;
    case content::JAVASCRIPT_DIALOG_TYPE_CONFIRM:
      return Kind::kConfirm;
    case content::JAVASCRIPT_DIALOG_TYPE_PROMPT:
      return Kind::kPrompt;
  }
  return Kind::kAlert;
}

std::u16string ArktJavaScriptDialog::title() const {
  return title_;
}

std::u16string ArktJavaScriptDialog::message() const {
  return message_;
}

std::u16string ArktJavaScriptDialog::default_prompt_text() const {
  return default_prompt_text_;
}

content::WebContents* ArktJavaScriptDialog::contents() const {
  return contents_;
}

// The strings the Views dialog's buttons use (DialogDelegate): an alert only
// has OK.
std::u16string ArktJavaScriptDialog::accept_title() const {
  return l10n_util::GetStringUTF16(IDS_APP_OK);
}

std::optional<std::u16string> ArktJavaScriptDialog::cancel_title() const {
  if (type_ == content::JAVASCRIPT_DIALOG_TYPE_ALERT) {
    return std::nullopt;
  }
  return l10n_util::GetStringUTF16(IDS_APP_CANCEL);
}

bool ArktJavaScriptDialog::Respond(bool accepted,
                                   const std::u16string& user_input) {
  if (over_) {
    return false;
  }
  over_ = true;
  // The manager closes its side from this callback (kDialogButtonClicked),
  // runs the page's callback and drops its weak pointer.
  if (dialog_callback_) {
    std::move(dialog_callback_)
        .Run(accepted,
             accepted && type_ == content::JAVASCRIPT_DIALOG_TYPE_PROMPT
                 ? user_input
                 : std::u16string());
  }
  Finish();
  return true;
}

void ArktJavaScriptDialog::CloseDialogWithoutCallback() {
  if (over_) {
    return;
  }
  over_ = true;
  Finish();
}

std::u16string ArktJavaScriptDialog::GetUserInput() {
  // The shell passes a prompt's text with its answer; this is read only when
  // the engine itself accepts the dialog (the test API).
  return default_prompt_text_;
}

void ArktJavaScriptDialog::Finish() {
  // Before the tab's model goes, as the Views dialog does on window close.
  modal_ui_.reset();
  RunEndedCallback();
  delete this;
}

ArktBeforeUnloadDialog::ArktBeforeUnloadDialog(
    std::unique_ptr<javascript_dialogs::AppModalDialogController> controller)
    : controller_(std::move(controller)) {
  DCHECK(controller_->is_before_unload_dialog());
}

ArktBeforeUnloadDialog::~ArktBeforeUnloadDialog() = default;

ArktPageDialog::Kind ArktBeforeUnloadDialog::kind() const {
  return Kind::kBeforeUnload;
}

std::u16string ArktBeforeUnloadDialog::title() const {
  return controller_->title();
}

std::u16string ArktBeforeUnloadDialog::message() const {
  return controller_->message_text();
}

std::u16string ArktBeforeUnloadDialog::default_prompt_text() const {
  return controller_->default_prompt_text();
}

// Chromium's leave-site buttons (Cocoa and Views): Leave or Reload, and
// Cancel.
std::u16string ArktBeforeUnloadDialog::accept_title() const {
  return l10n_util::GetStringUTF16(
      controller_->is_reload() ? IDS_BEFORERELOAD_MESSAGEBOX_OK_BUTTON_LABEL
                               : IDS_BEFOREUNLOAD_MESSAGEBOX_OK_BUTTON_LABEL);
}

std::optional<std::u16string> ArktBeforeUnloadDialog::cancel_title() const {
  return l10n_util::GetStringUTF16(IDS_APP_CANCEL);
}

content::WebContents* ArktBeforeUnloadDialog::contents() const {
  return controller_->web_contents();
}

bool ArktBeforeUnloadDialog::Respond(bool accepted,
                                     const std::u16string& user_input) {
  if (over_) {
    return false;
  }
  over_ = true;
  // The end is reported first: the answer can close the tab or cancel the
  // close synchronously (BeforeUnloadFired), and the shell sees DialogEnded
  // before either.
  RunEndedCallback();
  LOG(WARNING) << "ARKT: leave-site dialog answered "
               << (accepted ? "leave" : "stay");
  if (accepted) {
    controller_->OnAccept(std::u16string(), /*suppress_js_messages=*/false);
  } else {
    // As Chromium's Cocoa dialog: staying stops a quit in progress.
    chrome_browser_application_mac::CancelTerminate();
    controller_->OnCancel(/*suppress_js_messages=*/false);
  }
  delete this;
  return true;
}

void ArktBeforeUnloadDialog::ShowAppModalDialog() {
  showing_ = true;
}

void ArktBeforeUnloadDialog::ActivateAppModalDialog() {}

void ArktBeforeUnloadDialog::CloseAppModalDialog() {
  // The queue ends the dialog (a navigation, the tab closing, a shutdown);
  // the page's callback has run or runs as cancelled. The controller expects
  // OnClose before this returns.
  if (!over_) {
    over_ = true;
    RunEndedCallback();
  }
  controller_->OnClose();
  delete this;
}

void ArktBeforeUnloadDialog::AcceptAppModalDialog() {
  Respond(true, std::u16string());
}

void ArktBeforeUnloadDialog::CancelAppModalDialog() {
  Respond(false, std::u16string());
}

bool ArktBeforeUnloadDialog::IsShowing() const {
  return showing_;
}

void SetJavaScriptDialogPresenter(JavaScriptDialogPresenter presenter) {
  Presenter() = std::move(presenter);
}

void UseArktBeforeUnloadDialogs() {
  javascript_dialogs::AppModalDialogManager* manager =
      javascript_dialogs::AppModalDialogManager::GetInstance();
  if (ChromiumAppModalFactory()) {
    return;
  }
  CHECK(!manager->view_factory()->is_null());
  ChromiumAppModalFactory() = *manager->view_factory();
  manager->SetNativeDialogFactory(
      base::BindRepeating(&ArktBeforeUnloadDialogFactory::Create));
  LOG(WARNING) << "ARKT: leave-site dialog factory installed";
}

void UseArktJavaScriptDialogs(content::WebContents* contents) {
  if (!contents ||
      !javascript_dialogs::TabModalDialogManager::FromWebContents(contents) ||
      contents->GetUserData(InstalledMarker::Key())) {
    return;
  }
  // Replace the manager TabHelpers attached, which holds Chromium's delegate
  // (both calls are public). No dialog can be up yet: the tab was just
  // inserted.
  contents->RemoveUserData(
      javascript_dialogs::TabModalDialogManager::UserDataKey());
  javascript_dialogs::TabModalDialogManager::CreateForWebContents(
      contents, std::make_unique<ArktJavaScriptDialogDelegate>(contents));
  contents->SetUserData(InstalledMarker::Key(),
                        std::make_unique<InstalledMarker>());
}

}  // namespace arkt
