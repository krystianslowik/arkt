#ifndef ARKT_BROWSER_ARKT_EXTENSION_INSTALLS_H_
#define ARKT_BROWSER_ARKT_EXTENSION_INSTALLS_H_

#include <string>

#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "base/scoped_observation.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"

class Profile;

namespace content {
class WebContents;
}

namespace extensions {
class Extension;
}

namespace arkt {

// Whether an install reaches the shell as an install event (#592): a first
// install (not `is_update`) at ManifestLocation::kInternal (the Chrome Web
// Store, a user's .crx, the import's batch) that is neither a theme nor an
// app. Those are the installs Chromium follows with its post-install dialog;
// unpacked, command-line, external, policy and component extensions report
// nothing.
bool ReportsExtensionInstall(const extensions::Extension& extension,
                             bool is_update);

// The name Chromium's own install UI shows for `extension`
// (ui_util::GetFixupExtensionNameForUIDisplay).
std::u16string ExtensionNameForDisplay(const extensions::Extension& extension);

// Watches one profile's ExtensionRegistry and runs `callback` with the id and
// display name of each install ReportsExtensionInstall accepts, from inside
// OnExtensionInstalled.
class ExtensionInstallWatcher : public extensions::ExtensionRegistryObserver {
 public:
  using Callback = base::RepeatingCallback<void(const std::string& id,
                                                const std::u16string& name)>;

  ExtensionInstallWatcher(Profile* profile, Callback callback);
  ExtensionInstallWatcher(const ExtensionInstallWatcher&) = delete;
  ExtensionInstallWatcher& operator=(const ExtensionInstallWatcher&) = delete;
  ~ExtensionInstallWatcher() override;

  // extensions::ExtensionRegistryObserver:
  void OnExtensionInstalled(content::BrowserContext* browser_context,
                            const extensions::Extension* extension,
                            bool is_update) override;
  void OnShutdown(extensions::ExtensionRegistry* registry) override;

 private:
  Callback callback_;
  base::ScopedObservation<extensions::ExtensionRegistry,
                          extensions::ExtensionRegistryObserver>
      observation_{this};
};

// Self-test only (--arkt-facade-selftest, #592): installs the packed
// extension at `crx_path` into `profile` the way chrome://extensions installs
// a .crx dropped on it (developerPrivate.installDroppedFile): CrxInstaller
// with an install prompt for `contents`, off-store allowed from the settings
// page. The prompt is accepted at once (ScopedTestDialogAutoConfirm, held
// until the installer finishes), so Chromium continues as after the user's
// Add: ExtensionInstallUI::OnInstallSuccess and its post-install dialog, the
// path a Web Store install takes. `done` receives the error, empty on
// success.
void InstallCrxForSelfTest(
    Profile* profile,
    content::WebContents* contents,
    const base::FilePath& crx_path,
    base::OnceCallback<void(const std::string& error)> done);

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSION_INSTALLS_H_
