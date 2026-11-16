#ifndef ARKT_BROWSER_ARKT_EXTENSION_INSTALLS_H_
#define ARKT_BROWSER_ARKT_EXTENSION_INSTALLS_H_

#include <stdint.h>

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
// OnExtensionInstalled. Each reported id is also kept as pending until its
// post-install dialog takes it (TakeReportedInstall); an update or an
// uninstall of that extension, the registry's shutdown or the watcher's
// destruction drops it first. UI thread only.
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
  void OnExtensionUninstalled(content::BrowserContext* browser_context,
                              const extensions::Extension* extension,
                              extensions::UninstallReason reason) override;
  void OnShutdown(extensions::ExtensionRegistry* registry) override;

 private:
  // A key into the pending ids only, never dereferenced (the watcher may
  // outlive the profile at shutdown).
  const uintptr_t profile_key_;
  Callback callback_;
  base::ScopedObservation<extensions::ExtensionRegistry,
                          extensions::ExtensionRegistryObserver>
      observation_{this};
};

// Whether `extension_id` of `profile` is a reported install still waiting
// for its post-install dialog; true uses it up. The 0007 hook drops a
// post-install dialog only then, so a dropped dialog always has its event.
bool TakeReportedInstall(Profile* profile, const std::string& extension_id);

// Self-test only (--arkt-facade-selftest, #592): installs the packed
// extension at `crx_path` into `profile` the way chrome://extensions installs
// a .crx dropped on it (developerPrivate.installDroppedFile): CrxInstaller
// with an install prompt for `contents`, off-store allowed from the settings
// page. The prompt is accepted at once (ScopedTestDialogAutoConfirm, held
// until the installer finishes), so Chromium continues as after the user's
// Add: ExtensionInstallUI::OnInstallSuccess and its post-install dialog, the
// path a Web Store install takes. An update of an installed extension takes
// chrome://extensions' own path there (CheckUpdateFromSettingsPage): no
// prompt and no post-install UI. With `prompt_updates`, off-store is allowed
// as for a test instead, so an update also goes through the prompt and
// OnInstallSuccess, as a Web Store update does. The auto-confirm is
// process-wide while it is held: any other install prompt in that time is
// accepted too. `done` receives the error, empty on success.
void InstallCrxForSelfTest(
    Profile* profile,
    content::WebContents* contents,
    const base::FilePath& crx_path,
    bool prompt_updates,
    base::OnceCallback<void(const std::string& error)> done);

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSION_INSTALLS_H_
