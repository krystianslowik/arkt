#include "arkt/browser/arkt_extension_installs.h"

#include <map>
#include <memory>
#include <optional>
#include <set>
#include <utility>

#include "base/logging.h"
#include "base/memory/scoped_refptr.h"
#include "base/no_destructor.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/browser/extensions/extension_install_prompt.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/browser_thread.h"
#include "extensions/browser/crx_installer.h"
#include "extensions/browser/install/crx_install_error.h"
#include "extensions/browser/extension_dialog_auto_confirm.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/browser/ui_util.h"
#include "extensions/common/extension.h"
#include "extensions/common/mojom/manifest.mojom-shared.h"

namespace arkt {

namespace {

// Reported installs waiting for their post-install dialog, per profile. The
// profile pointer is only a key and never dereferenced; the watcher clears
// its profile's entry on the registry's shutdown and when it goes away. UI
// thread only.
std::map<uintptr_t, std::set<std::string>>& ReportedInstalls() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  static base::NoDestructor<std::map<uintptr_t, std::set<std::string>>>
      reported;
  return *reported;
}

void ForgetReportedInstall(uintptr_t profile, const std::string& id) {
  auto it = ReportedInstalls().find(profile);
  if (it == ReportedInstalls().end()) {
    return;
  }
  it->second.erase(id);
  if (it->second.empty()) {
    ReportedInstalls().erase(it);
  }
}

}  // namespace

bool TakeReportedInstall(Profile* profile, const std::string& extension_id) {
  if (!profile) {
    return false;
  }
  const uintptr_t key = reinterpret_cast<uintptr_t>(profile);
  auto it = ReportedInstalls().find(key);
  if (it == ReportedInstalls().end() || !it->second.contains(extension_id)) {
    return false;
  }
  ForgetReportedInstall(key, extension_id);
  return true;
}

bool ReportsExtensionInstall(const extensions::Extension& extension,
                             bool is_update) {
  return !is_update &&
         extension.location() ==
             extensions::mojom::ManifestLocation::kInternal &&
         !extension.is_theme() && !extension.is_app();
}

std::u16string ExtensionNameForDisplay(const extensions::Extension& extension) {
  return extensions::ui_util::GetFixupExtensionNameForUIDisplay(
      extension.name());
}

ExtensionInstallWatcher::ExtensionInstallWatcher(Profile* profile,
                                                 Callback callback)
    : profile_key_(reinterpret_cast<uintptr_t>(profile)),
      callback_(std::move(callback)) {
  if (extensions::ExtensionRegistry* registry =
          extensions::ExtensionRegistry::Get(profile)) {
    observation_.Observe(registry);
  }
}

ExtensionInstallWatcher::~ExtensionInstallWatcher() {
  // Nothing reports or takes this profile's installs once the watcher is
  // gone, so its pending ids would only wait for a profile that a later one
  // could reuse the address of.
  ReportedInstalls().erase(profile_key_);
}

void ExtensionInstallWatcher::OnExtensionInstalled(
    content::BrowserContext* browser_context,
    const extensions::Extension* extension,
    bool is_update) {
  if (!extension) {
    return;
  }
  const bool reports = ReportsExtensionInstall(*extension, is_update);
  LOG(WARNING) << "ARKT: extension installed " << extension->id()
               << " location=" << static_cast<int>(extension->location())
               << " update=" << is_update
               << (reports ? " reported" : " not reported");
  // An earlier report of this id no longer waits for a dialog: an update's
  // dialog keeps Chromium's sheet.
  ForgetReportedInstall(profile_key_, extension->id());
  if (reports) {
    ReportedInstalls()[profile_key_].insert(extension->id());
    callback_.Run(extension->id(), ExtensionNameForDisplay(*extension));
  }
}

void ExtensionInstallWatcher::OnExtensionUninstalled(
    content::BrowserContext* browser_context,
    const extensions::Extension* extension,
    extensions::UninstallReason reason) {
  if (extension) {
    ForgetReportedInstall(profile_key_, extension->id());
  }
}

void ExtensionInstallWatcher::OnShutdown(
    extensions::ExtensionRegistry* registry) {
  ReportedInstalls().erase(profile_key_);
  observation_.Reset();
}

void InstallCrxForSelfTest(
    Profile* profile,
    content::WebContents* contents,
    const base::FilePath& crx_path,
    bool prompt_updates,
    base::OnceCallback<void(const std::string& error)> done) {
  if (!profile || !contents) {
    std::move(done).Run("no profile or tab");
    return;
  }
  auto prompt = std::make_unique<ExtensionInstallPrompt>(
      contents, std::make_unique<extensions::InstallPromptData>(
                    extensions::InstallPromptData::UNSET_PROMPT_TYPE));
  scoped_refptr<extensions::CrxInstaller> installer =
      extensions::CrxInstaller::Create(profile, std::move(prompt));
  installer->set_error_on_unsupported_requirements(true);
  installer->set_off_store_install_allow_reason(
      prompt_updates
          ? extensions::CrxInstaller::OffStoreInstallAllowedInTest
          : extensions::CrxInstaller::OffStoreInstallAllowedFromSettingsPage);
  installer->set_install_immediately(true);
  auto accept = std::make_unique<extensions::ScopedTestDialogAutoConfirm>(
      extensions::ScopedTestDialogAutoConfirm::ACCEPT);
  installer->AddInstallerCallback(base::BindOnce(
      [](std::unique_ptr<extensions::ScopedTestDialogAutoConfirm> accept,
         base::OnceCallback<void(const std::string&)> done,
         const std::optional<extensions::CrxInstallError>& error) {
        accept.reset();
        std::move(done).Run(
            error ? base::UTF16ToUTF8(error->message()) : std::string());
      },
      std::move(accept), std::move(done)));
  installer->InstallCrx(crx_path);
}

}  // namespace arkt
