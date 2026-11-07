#ifndef ARKT_BROWSER_ARKT_JAVASCRIPT_DIALOG_H_
#define ARKT_BROWSER_ARKT_JAVASCRIPT_DIALOG_H_

#include <memory>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "components/javascript_dialogs/tab_modal_dialog_view.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/javascript_dialog_manager.h"

namespace content {
class WebContents;
}

namespace arkt {

// A page's alert, confirm or prompt in a tab of an Arkt window, held for the
// shell to present (issue #400). Chromium's TabModalDialogManager decides
// everything about when a dialog shows and ends (foremost tab, a background
// alert staying pending, auto-dismissal of a confirm or prompt when the tab is
// hidden, a navigation, a later dialog, the tab closing) and holds this object
// as its TabModalDialogView; the shell only draws it and answers.
//
// Owns itself: it lives until the shell answers it or the manager ends it.
class ArktJavaScriptDialog : public javascript_dialogs::TabModalDialogView {
 public:
  ArktJavaScriptDialog(const ArktJavaScriptDialog&) = delete;
  ArktJavaScriptDialog& operator=(const ArktJavaScriptDialog&) = delete;

  content::JavaScriptDialogType type() const { return type_; }
  const std::u16string& title() const { return title_; }
  const std::u16string& message() const { return message_; }
  const std::u16string& default_prompt_text() const {
    return default_prompt_text_;
  }
  content::WebContents* contents() const { return contents_; }

  // Runs once when the dialog is over, however it ended, before the object is
  // deleted.
  void SetEndedCallback(base::OnceClosure ended) {
    ended_ = std::move(ended);
  }

  // The shell's answer: hands it to the manager, which runs the page's
  // callback and closes its side. False, and nothing happens, when the dialog
  // is already over.
  bool Respond(bool accepted, const std::u16string& user_input);

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
  base::OnceClosure ended_;
  bool over_ = false;
  base::WeakPtrFactory<ArktJavaScriptDialog> weak_factory_{this};
};

// Presents `dialog` to the shell and returns true, or returns false to leave
// it to Chromium's Views dialog (no facade yet, or the tab is not in a
// window whose host presents it). Set by the facade.
using JavaScriptDialogPresenter = base::RepeatingCallback<bool(
    content::WebContents*,
    base::WeakPtr<ArktJavaScriptDialog>)>;
void SetJavaScriptDialogPresenter(JavaScriptDialogPresenter presenter);

// Gives `contents` a TabModalDialogManager whose dialogs go to the presenter
// while the tab is in an Arkt window. Chromium's own delegate stays the
// fallback for every other case, so a tab that moves to a Views window gets
// Chrome's dialog there. Safe to call more than once; a no-op for contents
// that already have Arkt's delegate.
void UseArktJavaScriptDialogs(content::WebContents* contents);

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_JAVASCRIPT_DIALOG_H_
