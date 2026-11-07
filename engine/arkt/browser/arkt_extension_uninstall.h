#ifndef ARKT_BROWSER_ARKT_EXTENSION_UNINSTALL_H_
#define ARKT_BROWSER_ARKT_EXTENSION_UNINSTALL_H_

#include <string>

class Profile;

namespace arkt {

// Uninstalls `extension_id` from `profile` as the user's own choice, with no
// prompt (#721): ExtensionRegistrar::UninstallExtension with
// UNINSTALL_REASON_USER_INITIATED, the call ExtensionUninstallDialog makes
// once its dialog is accepted; the dialog itself is never created. Returns
// true once the extension is gone. On false `failure` holds a short sentence
// with no id or name and nothing changed: "unknown extension" (the profile
// has no such extension, enabled or not), "not removable" (policy, a
// component extension, or anything else the management policy keeps).
//
// With `report_abuse`, after a successful uninstall and only for an extension
// that updated from the Web Store (ExtensionManagement::UpdatesFromWebstore,
// the condition for Chrome's checkbox), the Web Store's report page opens in
// a new foreground tab, after the uninstall so it is the active tab even when
// the extension set an uninstall URL; as
// ExtensionUninstallDialog::HandleReportAbuse, the navigation names only the
// profile, so the tab lands in its last active window.
bool UninstallExtensionForUser(Profile* profile,
                               const std::string& extension_id,
                               bool report_abuse,
                               std::string* failure);

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSION_UNINSTALL_H_
