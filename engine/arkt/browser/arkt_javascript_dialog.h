#ifndef ARKT_BROWSER_ARKT_JAVASCRIPT_DIALOG_H_
#define ARKT_BROWSER_ARKT_JAVASCRIPT_DIALOG_H_

#include <memory>
#include <optional>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "components/javascript_dialogs/app_modal_dialog_view.h"
#include "components/javascript_dialogs/tab_modal_dialog_view.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/javascript_dialog_manager.h"

namespace content {
class WebContents;
}

namespace javascript_dialogs {
class AppModalDialogController;
}

namespace arkt {

// A page dialog held for the shell to present (#400, #585): a page's alert,
// confirm or prompt (ArktJavaScriptDialog) or its leave-site dialog
// (ArktBeforeUnloadDialog). The facade reads its values once and answers it
// through a weak pointer that dies with the dialog.
class ArktPageDialog {
 public:
  enum class Kind { kAlert, kConfirm, kPrompt, kBeforeUnload };

  ArktPageDialog(const ArktPageDialog&) = delete;
  ArktPageDialog& operator=(const ArktPageDialog&) = delete;

  virtual Kind kind() const = 0;
  virtual std::u16string title() const = 0;
  virtual std::u16string message() const = 0;
  // A prompt's initial text; empty for the other kinds.
  virtual std::u16string default_prompt_text() const = 0;
  // Chromium's button titles: OK (Leave or Reload for a leave-site dialog),
  // and Cancel, which an alert has not.
  virtual std::u16string accept_title() const = 0;
  virtual std::optional<std::u16string> cancel_title() const = 0;
  virtual content::WebContents* contents() const = 0;

  // The shell's answer. False, and nothing happens, when the dialog is
  // already over.
  virtual bool Respond(bool accepted, const std::u16string& user_input) = 0;

  // Runs once when the dialog is over, however it ended, before the object is
  // deleted. For an answer it runs before the answer reaches Chromium, so the
  // end is reported before whatever the answer brings (a closed tab, a
  // cancelled close; contract rules 16 and 19).
  void SetEndedCallback(base::OnceClosure ended) {
    ended_ = std::move(ended);
  }

  base::WeakPtr<ArktPageDialog> GetWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }

 protected:
  ArktPageDialog();
  virtual ~ArktPageDialog();

  void RunEndedCallback() {
    if (ended_) {
      std::move(ended_).Run();
    }
  }

 private:
  base::OnceClosure ended_;
  base::WeakPtrFactory<ArktPageDialog> weak_factory_{this};
};

// A page's alert, confirm or prompt in a tab of an Arkt window, held for the
// shell to present (issue #400). Chromium's TabModalDialogManager decides
// everything about when a dialog shows and ends (foremost tab, a background
// alert staying pending, auto-dismissal of a confirm or prompt when the tab is
// hidden, a navigation, a later dialog, the tab closing) and holds this object
// as its TabModalDialogView; the shell only draws it and answers.
//
// Owns itself: it lives until the shell answers it or the manager ends it.
class ArktJavaScriptDialog : public ArktPageDialog,
                             public javascript_dialogs::TabModalDialogView {
 public:
  // ArktPageDialog:
  Kind kind() const override;
  std::u16string title() const override;
  std::u16string message() const override;
  std::u16string default_prompt_text() const override;
  std::u16string accept_title() const override;
  std::optional<std::u16string> cancel_title() const override;
  content::WebContents* contents() const override;
  // Hands the answer to the manager, which runs the page's callback and
  // closes its side.
  bool Respond(bool accepted, const std::u16string& user_input) override;

  // javascript_dialogs::TabModalDialogView: the manager ends the dialog
  // without an answer.
  void CloseDialogWithoutCallback() override;
  std::u16string GetUserInput() override;

 private:
  friend class ArktJavaScriptDialogDelegate;

  ArktJavaScriptDialog(
      content::WebContents* contents,
      content::JavaScriptDialogType type,
      const std::u16string& title,
      const std::u16string& message,
      const std::u16string& default_prompt_text,
      content::JavaScriptDialogManager::DialogClosedCallback dialog_callback,
      std::unique_ptr<tabs::ScopedTabModalUI> modal_ui);
  ~ArktJavaScriptDialog() override;

  // Runs the ended callback and deletes the dialog.
  void Finish();

  raw_ptr<content::WebContents> contents_;
  const content::JavaScriptDialogType type_;
  const std::u16string title_;
  const std::u16string message_;
  const std::u16string default_prompt_text_;
  content::JavaScriptDialogManager::DialogClosedCallback dialog_callback_;
  // Keeps the tab's modal UI slot while the dialog is up, as the Views
  // dialog does.
  std::unique_ptr<tabs::ScopedTabModalUI> modal_ui_;
  bool over_ = false;
  // The manager's pointer to this as its TabModalDialogView.
  base::WeakPtrFactory<ArktJavaScriptDialog> view_weak_factory_{this};
};

// A page's leave-site dialog in a tab of an Arkt window, held for the shell to
// present (#585). Chromium's app-modal dialog queue decides everything about
// when it shows and ends: one at a time across all windows, a window close or
// a quit prompting its held tabs in turn, the tab activated first (here, at
// creation, as Chromium's Cocoa dialog does), a navigation or the tab closing
// ending it. The queue holds this object as the dialog's AppModalDialogView;
// the shell only draws it and answers. Owns itself and its controller.
class ArktBeforeUnloadDialog : public ArktPageDialog,
                               public javascript_dialogs::AppModalDialogView {
 public:
  // ArktPageDialog:
  Kind kind() const override;
  std::u16string title() const override;
  std::u16string message() const override;
  std::u16string default_prompt_text() const override;
  std::u16string accept_title() const override;
  std::optional<std::u16string> cancel_title() const override;
  content::WebContents* contents() const override;
  bool Respond(bool accepted, const std::u16string& user_input) override;

  // javascript_dialogs::AppModalDialogView. Accept and Cancel come from
  // HandleJavaScriptDialog (the engine test API, DevTools); Close is the
  // queue ending the dialog without an answer.
  void ShowAppModalDialog() override;
  void ActivateAppModalDialog() override;
  void CloseAppModalDialog() override;
  void AcceptAppModalDialog() override;
  void CancelAppModalDialog() override;
  bool IsShowing() const override;

 private:
  friend class ArktBeforeUnloadDialogFactory;

  explicit ArktBeforeUnloadDialog(
      std::unique_ptr<javascript_dialogs::AppModalDialogController>
          controller);
  ~ArktBeforeUnloadDialog() override;

  std::unique_ptr<javascript_dialogs::AppModalDialogController> controller_;
  bool showing_ = false;
  bool over_ = false;
};

// Presents `dialog` to the shell and returns true, or returns false to leave
// it to Chromium's own dialog (no facade yet, or the tab is not in a window
// whose host presents it). Set by the facade.
using JavaScriptDialogPresenter =
    base::RepeatingCallback<bool(content::WebContents*,
                                 base::WeakPtr<ArktPageDialog>)>;
void SetJavaScriptDialogPresenter(JavaScriptDialogPresenter presenter);

// Wraps the app-modal dialog factory Chromium installed (Cocoa or Views) so a
// leave-site dialog of a tab in an Arkt window goes to the presenter; every
// other app-modal dialog keeps Chromium's. Call once, after Chromium installs
// its factory (ChromeBrowserMainParts::PreProfileInit).
void UseArktBeforeUnloadDialogs();

// Gives `contents` a TabModalDialogManager whose dialogs go to the presenter
// while the tab is in an Arkt window. Chromium's own delegate stays the
// fallback for every other case, so a tab that moves to a Views window gets
// Chrome's dialog there. Safe to call more than once; a no-op for contents
// that already have Arkt's delegate.
void UseArktJavaScriptDialogs(content::WebContents* contents);

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_JAVASCRIPT_DIALOG_H_
