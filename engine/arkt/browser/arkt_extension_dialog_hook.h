#ifndef ARKT_BROWSER_ARKT_EXTENSION_DIALOG_HOOK_H_
#define ARKT_BROWSER_ARKT_EXTENSION_DIALOG_HOOK_H_

#include <memory>

#include "extensions/browser/extension_install_prompt_client.h"
#include "ui/gfx/native_ui_types.h"

class ExtensionInstallPromptShowParams;

namespace extensions {
class InstallPromptData;
}  // namespace extensions

namespace ui {
class DialogModel;
}  // namespace ui

namespace arkt {

// Lets //arkt/browser show extension dialogs on Arkt windows as native sheets
// without the Views targets depending on it (that would be a GN cycle, as for
// the window factory hook). Called from patch 0007:
// - ShowExtensionInstallDialogImpl (extension_install_dialog_view.cc): the
//   install, re-enable and permission-increase prompts;
// - ShowDialog(gfx::NativeWindow, ...) (extension_dialog_utils_views.cc), when
//   there is no Views extensions container: the post-install and uninstall
//   dialogs and the other ui::DialogModel extension dialogs.
// Each function returns false and leaves its arguments untouched for a dialog
// it does not take (a window that is not an Arkt window, or a prompt variant
// the sheet does not render); Chromium then shows its Views dialog.
struct ExtensionDialogHooks {
  bool (*show_install_dialog)(
      std::unique_ptr<ExtensionInstallPromptShowParams>& show_params,
      extensions::ExtensionInstallPromptClient::DoneCallback& done_callback,
      std::unique_ptr<extensions::InstallPromptData>& prompt) = nullptr;
  bool (*show_modal_dialog)(gfx::NativeWindow parent,
                            std::unique_ptr<ui::DialogModel>& dialog_model) =
      nullptr;
};

// Set once at startup. Unset hooks mean "always use Chromium's dialogs".
void SetExtensionDialogHooks(const ExtensionDialogHooks& hooks);
const ExtensionDialogHooks& GetExtensionDialogHooks();

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSION_DIALOG_HOOK_H_
