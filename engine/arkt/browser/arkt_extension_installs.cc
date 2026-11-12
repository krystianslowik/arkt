#include "arkt/browser/arkt_extension_installs.h"

#include <memory>
#include <optional>
#include <utility>

#include "base/logging.h"
#include "base/memory/scoped_refptr.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/browser/extensions/extension_install_prompt.h"
#include "chrome/browser/profiles/profile.h"
#include "extensions/browser/crx_installer.h"
#include "extensions/browser/install/crx_install_error.h"
#include "extensions/browser/extension_dialog_auto_confirm.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/browser/ui_util.h"
#include "extensions/common/extension.h"
#include "extensions/common/mojom/manifest.mojom-shared.h"

namespace arkt {

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
    : callback_(std::move(callback)) {
  if (extensions::ExtensionRegistry* registry =
          extensions::ExtensionRegistry::Get(profile)) {
    observation_.Observe(registry);
  }
}

ExtensionInstallWatcher::~ExtensionInstallWatcher() = default;

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
  if (reports) {
    callback_.Run(extension->id(), ExtensionNameForDisplay(*extension));
  }
}

void ExtensionInstallWatcher::OnShutdown(
    extensions::ExtensionRegistry* registry) {
  observation_.Reset();
}

void InstallCrxForSelfTest(
    Profile* profile,
    content::WebContents* contents,
    const base::FilePath& crx_path,
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
      extensions::CrxInstaller::OffStoreInstallAllowedFromSettingsPage);
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
