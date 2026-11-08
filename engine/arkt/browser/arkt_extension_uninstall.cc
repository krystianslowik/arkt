#include "arkt/browser/arkt_extension_uninstall.h"

#include "base/logging.h"
#include "base/memory/scoped_refptr.h"
#include "chrome/browser/extensions/extension_management.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/navigator/browser_navigator.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "extensions/browser/extension_registrar.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_system.h"
#include "extensions/browser/management_policy.h"
#include "extensions/browser/uninstall_reason.h"
#include "extensions/common/extension.h"
#include "extensions/common/extension_urls.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"

namespace arkt {

namespace {

// Chrome's referrer for the report page opened after its uninstall dialog
// (kReferrerId in extension_uninstall_dialog.cc): the Web Store counts these
// reports as coming from the browser's remove flow.
constexpr char kReportAbuseReferrer[] = "chrome-remove-extension-dialog";

}  // namespace

UninstallAbility GetUninstallAbility(Profile* profile,
                                     const extensions::Extension& extension) {
  UninstallAbility ability;
  if (!profile) {
    return ability;
  }
  extensions::ManagementPolicy* policy =
      extensions::ExtensionSystem::Get(profile)->management_policy();
  // The providers' refusals name the extension; they are read, never kept.
  // Not every provider checks for a null error, so each call gets one.
  std::u16string modify_error;
  std::u16string remain_error;
  ability.can_uninstall =
      policy && policy->UserMayModifySettings(&extension, &modify_error) &&
      !policy->MustRemainInstalled(&extension, &remain_error);
  ability.can_report_abuse =
      extensions::ExtensionManagementFactory::GetForBrowserContext(profile)
          ->UpdatesFromWebstore(extension);
  return ability;
}

UninstallAbility GetUninstallAbility(Profile* profile,
                                     const std::string& extension_id) {
  extensions::ExtensionRegistry* registry =
      profile ? extensions::ExtensionRegistry::Get(profile) : nullptr;
  const extensions::Extension* extension =
      registry ? registry->GetInstalledExtension(extension_id) : nullptr;
  return extension ? GetUninstallAbility(profile, *extension)
                   : UninstallAbility();
}

bool UninstallExtensionForUser(Profile* profile,
                               const std::string& extension_id,
                               bool report_abuse,
                               BrowserWindowInterface* browser,
                               std::string* failure) {
  CHECK(failure);
  extensions::ExtensionRegistry* registry =
      profile ? extensions::ExtensionRegistry::Get(profile) : nullptr;
  // UninstallExtension CHECKs that the extension exists; an unknown id is a
  // failure here, not a crash.
  scoped_refptr<const extensions::Extension> extension =
      registry ? registry->GetInstalledExtension(extension_id) : nullptr;
  if (!extension) {
    *failure = "unknown extension";
    return false;
  }
  // Read before the uninstall: the management settings no longer know the
  // extension afterwards. The same answer the action listing gave the shell.
  const UninstallAbility ability = GetUninstallAbility(profile, *extension);
  if (!ability.can_uninstall) {
    LOG(WARNING) << "ARKT: uninstall refused: the user may not remove it";
    *failure = "not removable";
    return false;
  }
  // The registrar checks the policy again; its refusal names the extension,
  // so it is neither returned nor logged.
  std::u16string error;
  if (!extensions::ExtensionRegistrar::Get(profile)->UninstallExtension(
          extension->id(), extensions::UNINSTALL_REASON_USER_INITIATED,
          &error)) {
    LOG(WARNING) << "ARKT: uninstall refused by the management policy";
    *failure = "not removable";
    return false;
  }
  if (report_abuse && ability.can_report_abuse) {
    const GURL url = extension_urls::GetWebstoreReportAbuseUrl(
        extension->id(), kReportAbuseReferrer);
    // A window of another profile cannot take the tab; the profile's last
    // active window does then. Like Chrome's dialog, the window is not
    // brought forward: the sheet's window is in front already.
    const bool in_browser = browser && browser->GetProfile() == profile;
    NavigateParams params =
        in_browser ? NavigateParams(browser, url, ui::PAGE_TRANSITION_LINK)
                   : NavigateParams(profile, url, ui::PAGE_TRANSITION_LINK);
    params.disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB;
    LOG(WARNING) << "ARKT: uninstall report page in "
                 << (in_browser ? "the given window"
                                : "the last active window");
    Navigate(&params);
  } else if (report_abuse) {
    LOG(WARNING) << "ARKT: uninstall report page skipped: the extension does "
                    "not update from the Web Store";
  }
  return true;
}

}  // namespace arkt
