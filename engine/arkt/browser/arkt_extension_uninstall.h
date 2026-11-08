#ifndef ARKT_BROWSER_ARKT_EXTENSION_UNINSTALL_H_
#define ARKT_BROWSER_ARKT_EXTENSION_UNINSTALL_H_

#include <string>

class BrowserWindowInterface;
class Profile;

namespace extensions {
class Extension;
}

namespace arkt {

// What the user may do with an installed extension when removing it (#721).
struct UninstallAbility {
  // ManagementPolicy::UserMayModifySettings and not MustRemainInstalled: the
  // checks ExtensionRegistrar::UninstallExtension makes for a user-initiated
  // uninstall (policy-installed and component extensions fail them).
  bool can_uninstall = false;
  // ExtensionManagement::UpdatesFromWebstore: the condition for the Report
  // abuse checkbox of Chrome's own uninstall dialog.
  bool can_report_abuse = false;
};

// The ability for `extension` of `profile`. The shell reads it with each
// action listing; UninstallExtensionForUser applies the same answer as its
// gate, so the listed flags and the gate cannot disagree.
UninstallAbility GetUninstallAbility(Profile* profile,
                                     const extensions::Extension& extension);

// The ability for the installed extension `extension_id` (enabled or not);
// both false for an id the profile does not have.
UninstallAbility GetUninstallAbility(Profile* profile,
                                     const std::string& extension_id);

// Uninstalls `extension_id` from `profile` as the user's own choice, with no
// prompt (#721): ExtensionRegistrar::UninstallExtension with
// UNINSTALL_REASON_USER_INITIATED, the call ExtensionUninstallDialog makes
// once its dialog is accepted; the dialog itself is never created. Returns
// true once the extension is gone. On false `failure` holds a short sentence
// with no id or name and nothing changed: "unknown extension" (the profile
// has no such extension, enabled or not), "not removable" (can_uninstall is
// false, or the registrar refused).
//
// With `report_abuse`, after a successful uninstall and only when
// can_report_abuse was true, the Web Store's report page opens in a new
// foreground tab, after the uninstall so it is the active tab even when the
// extension set an uninstall URL: in `browser` when given (a window of
// `profile`), else, as ExtensionUninstallDialog::HandleReportAbuse, in the
// profile's last active window.
bool UninstallExtensionForUser(Profile* profile,
                               const std::string& extension_id,
                               bool report_abuse,
                               BrowserWindowInterface* browser,
                               std::string* failure);

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSION_UNINSTALL_H_
