#include "arkt/browser/arkt_extension_uninstall.h"

#include "base/logging.h"
#include "base/memory/scoped_refptr.h"
#include "chrome/browser/extensions/extension_management.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/navigator/browser_navigator.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "extensions/browser/extension_registrar.h"
#include "extensions/browser/extension_registry.h"
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

bool UninstallExtensionForUser(Profile* profile,
                               const std::string& extension_id,
                               bool report_abuse,
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
  // extension afterwards.
  const bool from_webstore =
      extensions::ExtensionManagementFactory::GetForBrowserContext(profile)
          ->UpdatesFromWebstore(*extension);
  // The policy's refusal names the extension; it is neither returned nor
  // logged.
  std::u16string error;
  if (!extensions::ExtensionRegistrar::Get(profile)->UninstallExtension(
          extension->id(), extensions::UNINSTALL_REASON_USER_INITIATED,
          &error)) {
    LOG(WARNING) << "ARKT: uninstall refused by the management policy";
    *failure = "not removable";
    return false;
  }
  if (report_abuse && from_webstore) {
    NavigateParams params(profile,
                          extension_urls::GetWebstoreReportAbuseUrl(
                              extension->id(), kReportAbuseReferrer),
                          ui::PAGE_TRANSITION_LINK);
    params.disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB;
    Navigate(&params);
  } else if (report_abuse) {
    LOG(WARNING) << "ARKT: uninstall report page skipped: the extension does "
                    "not update from the Web Store";
  }
  return true;
}

}  // namespace arkt
