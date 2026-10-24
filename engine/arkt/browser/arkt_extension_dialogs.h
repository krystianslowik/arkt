#ifndef ARKT_BROWSER_ARKT_EXTENSION_DIALOGS_H_
#define ARKT_BROWSER_ARKT_EXTENSION_DIALOGS_H_

namespace arkt {

// Registers the extension dialog hooks (patch 0007): on Arkt windows the
// extension install prompt and the ui::DialogModel extension dialogs
// (post-install, uninstall) become native sheets (ArktDialogSheet). Call once
// at startup, only when Arkt windows are on.
void RegisterExtensionDialogSheets();

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSION_DIALOGS_H_
