#include "arkt/browser/arkt_javascript_dialog.h"

#include <utility>

#include "arkt/browser/arkt_browser_window.h"
#include "base/no_destructor.h"
#include "base/supports_user_data.h"
#include "chrome/browser/ui/javascript_dialogs/javascript_tab_modal_dialog_manager_delegate_desktop.h"
#include "components/javascript_dialogs/tab_modal_dialog_manager.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"

namespace arkt {
namespace {

JavaScriptDialogPresenter& Presenter() {
  static base::NoDestructor<JavaScriptDialogPresenter> presenter;
  return *presenter;
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
    ArktBrowserWindow* window =
        tab ? ArktBrowserWindow::FromBrowser(tab->GetBrowserWindowInterface())
            : nullptr;
    if (window && window->host_mode() && Presenter() && tab->CanShowModalUI()) {
      auto* dialog = new ArktJavaScriptDialog(
          contents_, dialog_type, title, message_text, default_prompt_text,
          std::move(dialog_callback), tab->ShowModalUI());
      base::WeakPtr<ArktJavaScriptDialog> weak =
          dialog->weak_factory_.GetWeakPtr();
      if (Presenter().Run(contents_, weak)) {
        return weak;
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
  if (ended_) {
    std::move(ended_).Run();
  }
  delete this;
}

void SetJavaScriptDialogPresenter(JavaScriptDialogPresenter presenter) {
  Presenter() = std::move(presenter);
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
