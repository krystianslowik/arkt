#include "arkt/browser/arkt_extension_dialog_hook.h"

namespace arkt {

namespace {
ExtensionDialogHooks& Hooks() {
  static ExtensionDialogHooks hooks;
  return hooks;
}
}  // namespace

void SetExtensionDialogHooks(const ExtensionDialogHooks& hooks) {
  Hooks() = hooks;
}

const ExtensionDialogHooks& GetExtensionDialogHooks() {
  return Hooks();
}

}  // namespace arkt
