#ifndef ARKT_BROWSER_ARKT_EXTENSION_MANAGEMENT_H_
#define ARKT_BROWSER_ARKT_EXTENSION_MANAGEMENT_H_

#include <stdint.h>

#include <map>
#include <string>
#include <vector>

#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/ref_counted_memory.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "components/prefs/pref_change_registrar.h"
#include "extensions/browser/disable_reason.h"
#include "extensions/browser/extension_prefs.h"
#include "extensions/browser/extension_prefs_observer.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "ui/gfx/image/image.h"

class BrowserWindowInterface;
class Profile;

namespace extensions {
class Extension;
}

namespace arkt {

// Where an installed extension came from (#964). The values are the facade's
// ArktExtensionSource.
enum class InstalledExtensionSource {
  // Updates from the Chrome Web Store (ExtensionManagement::
  // UpdatesFromWebstore).
  kWebStore = 0,
  // Loaded from a folder: Load unpacked or --load-extension
  // (Manifest::IsUnpackedLocation).
  kUnpacked = 1,
  // Installed by policy (Manifest::IsPolicyLocation).
  kPolicy = 2,
  // Anything else: a .crx from elsewhere, an external (preferences) install.
  kOther = 3,
};

// One installed extension as the Settings pane lists it (#964).
struct InstalledExtensionInfo {
  InstalledExtensionInfo();
  InstalledExtensionInfo(const InstalledExtensionInfo&);
  InstalledExtensionInfo& operator=(const InstalledExtensionInfo&);
  ~InstalledExtensionInfo();

  std::string id;
  // As Chromium's UI shows it (ui_util::GetFixupExtensionNameForUIDisplay).
  std::u16string name;
  // Extension::GetVersionForDisplay (the manifest's version_name when set).
  std::string version;
  // The manifest's description, localized; may be empty.
  std::string description;
  // Enabled or terminated (a crashed extension is still on).
  bool enabled = false;
  // CanChangeExtensionEnabled's answer for the opposite of `enabled`.
  bool may_change_enabled = false;
  InstalledExtensionSource source = InstalledExtensionSource::kOther;
  bool has_options_page = false;
};

// The extensions of `profile` the pane lists, sorted by name then id:
// enabled, disabled and terminated, as chrome://extensions lists them
// (ui_util::ShouldDisplayInExtensionSettings: no component, hidden or
// theme-less internal items). Blocklisted and policy-blocked extensions are
// not in the registry sets read, so they are not listed.
std::vector<InstalledExtensionInfo> ListInstalledExtensions(Profile* profile);

// LoadUnpackedExtension's sentence while developer mode is off; the shell
// matches it.
inline constexpr char kDeveloperModeOffReason[] = "Developer mode is off.";

// The answer to SetExtensionEnabledForUser. The values are the facade's
// ArktExtensionEnableResult.
enum class ExtensionEnableResult {
  // The extension has that state now (or had it already).
  kApplied = 0,
  // The profile has no listed extension with that id.
  kUnknownExtension = 1,
  // The management policy keeps it in its current state (installed or
  // blocked by policy, a component, a shared module, or an unpacked one
  // while developer mode is off), or, enabling, it has a disable reason the
  // user may not lift (corrupted, not verified, unsupported requirements,
  // waiting for a custodian or a remote-install approval, ...).
  kNotAllowed = 2,
  // Enabling only: it was disabled because an update asks for more
  // permissions. Chrome enables it only after its re-enable prompt, which
  // grants them; the engine does not grant them silently.
  kNeedsPermissionApproval = 3,
};

// Whether the user may move `extension` to `enabled` (#964): the checks
// management.setEnabled and ExtensionRegistrar make. Disabling: the policy
// lets the user modify it, it need not remain enabled, and it is not a
// shared module. Enabling: the policy lets the user modify it, it need not
// remain disabled, and every disable reason is one the user may lift (user
// action, reload, greylist, external install, another extension, an
// unpacked one while developer mode is on); a permissions increase among
// them answers kNeedsPermissionApproval, any other reason kNotAllowed. The
// listing's may_change_enabled is this answer, so the list and the setter
// cannot disagree.
ExtensionEnableResult CanChangeExtensionEnabled(
    Profile* profile,
    const extensions::Extension& extension,
    bool enabled);

// What SetExtensionEnabledForUser would answer without changing anything:
// kUnknownExtension for an id that is not listed, kApplied when it has that
// state already, else CanChangeExtensionEnabled.
ExtensionEnableResult CheckSetExtensionEnabled(Profile* profile,
                                               const std::string& id,
                                               bool enabled);

// Enables or disables a listed extension as the user's choice:
// ExtensionRegistrar::EnableExtension, or DisableExtension with
// DISABLE_USER_ACTION, after CheckSetExtensionEnabled. Synchronous; the
// registry's observers see the change before this returns.
ExtensionEnableResult SetExtensionEnabledForUser(Profile* profile,
                                                 const std::string& id,
                                                 bool enabled);

// The extensions.ui.developer_mode pref of `profile`.
bool ExtensionDeveloperMode(Profile* profile);

// Sets it as chrome://extensions does (util::SetDeveloperModeForProfile).
// Nothing when the pref is not the user's to change (a policy or a
// supervised profile) or already has that value. Returns whether it changed.
// At the pin, turning it off disables the extensions loaded with Load
// unpacked (DISABLE_UNSUPPORTED_DEVELOPER_EXTENSION) and turning it on
// enables them again.
bool SetExtensionDeveloperMode(Profile* profile, bool on);

// Loads the unpacked extension in the folder `path` into `profile` as
// chrome://extensions' Load unpacked does (developerPrivate.loadUnpacked,
// UnpackedInstaller), without Chromium's error UI. Refused while developer
// mode is off, when policy blocks installs by default, and for a path that
// is not absolute. `done` runs on a later task, never inside the call: with
// the loaded id and an empty error, or an empty id and a short sentence
// (kDeveloperModeOffReason, "Blocked by policy.", "Not a folder.", or
// Chromium's load error, as chrome://extensions shows it).
void LoadUnpackedExtension(
    Profile* profile,
    const base::FilePath& path,
    base::OnceCallback<void(const std::string& id, const std::string& error)>
        done);

// Self-test only (--arkt-facade-selftest, #964): disables the listed
// extension `id` with the single disable reason `reason` (a
// disable_reason::DisableReason value), as Chromium does for a corrupted
// extension or a permissions increase, so the enable gate can be checked.
void DisableExtensionForSelfTest(Profile* profile,
                                 const std::string& id,
                                 int reason);

// Opens the options page of the enabled, listed extension `id` as Chrome does
// (ExtensionTabUtil::OpenOptionsPage), in `browser` when it is a window of
// `profile`, else in the profile's last active normal window. Returns whether
// a page opened; false for an unknown or disabled extension, one without an
// options page, or no window.
bool OpenExtensionOptionsPage(Profile* profile,
                              const std::string& id,
                              BrowserWindowInterface* browser);

// Reports changes to ListInstalledExtensions and ExtensionDeveloperMode,
// merged into one callback per task: an extension installed, updated,
// uninstalled, enabled, disabled, terminated or loaded unpacked, the
// developer mode pref changed, or a listed icon finished loading, always; a
// disable reason, an extension's prefs (a blocklisting) or the management
// policy prefs changed, only when the listed ids, versions, names, enabled,
// may-change or may-uninstall states differ from the last report. Also keeps
// the listed extensions' icons (32 pt, encoded once as PNG at 2x), loaded off
// the UI thread on first request. UI thread only.
class InstalledExtensionsWatcher : public extensions::ExtensionRegistryObserver,
                                   public extensions::ExtensionPrefsObserver {
 public:
  InstalledExtensionsWatcher(Profile* profile, base::RepeatingClosure changed);
  InstalledExtensionsWatcher(const InstalledExtensionsWatcher&) = delete;
  InstalledExtensionsWatcher& operator=(const InstalledExtensionsWatcher&) =
      delete;
  ~InstalledExtensionsWatcher() override;

  // The icon of the installed extension `id` as PNG at 2x when loaded; null
  // until then (the load starts here, and the changed callback follows it),
  // and null for an extension without an icon.
  scoped_refptr<base::RefCountedMemory> IconPNG(const std::string& id);

  // extensions::ExtensionRegistryObserver:
  void OnExtensionLoaded(content::BrowserContext* browser_context,
                         const extensions::Extension* extension) override;
  void OnExtensionUnloaded(content::BrowserContext* browser_context,
                           const extensions::Extension* extension,
                           extensions::UnloadedExtensionReason reason) override;
  void OnExtensionInstalled(content::BrowserContext* browser_context,
                            const extensions::Extension* extension,
                            bool is_update) override;
  void OnExtensionUninstalled(content::BrowserContext* browser_context,
                              const extensions::Extension* extension,
                              extensions::UninstallReason reason) override;
  void OnShutdown(extensions::ExtensionRegistry* registry) override;

  // extensions::ExtensionPrefsObserver:
  void OnExtensionDisableReasonsChanged(
      const extensions::ExtensionId& extension_id,
      extensions::DisableReasonSet disabled_reasons) override;
  void OnExtensionPrefsUpdated(
      const extensions::ExtensionId& extension_id) override;
  void OnExtensionPrefsWillBeDestroyed(
      extensions::ExtensionPrefs* prefs) override;

 private:
  struct CachedIcon {
    // The request that owns the entry: every install, update or reload drops
    // the entry, so a load that finishes after it is ignored.
    uint64_t generation = 0;
    bool loaded = false;
    scoped_refptr<base::RefCountedMemory> png;
  };

  // `force`: report even when the listed state looks the same.
  void NotifyChanged(const char* why, bool force);
  void IconLoaded(const std::string& id,
                  uint64_t generation,
                  const gfx::Image& image);
  // What the pane shows of each listed extension, apart from icons.
  std::string Fingerprint() const;

  raw_ptr<Profile> profile_;
  base::RepeatingClosure changed_;
  bool notify_posted_ = false;
  bool force_pending_ = false;
  std::string last_fingerprint_;
  uint64_t last_generation_ = 0;
  std::map<std::string, CachedIcon> icons_;
  PrefChangeRegistrar prefs_;
  base::ScopedObservation<extensions::ExtensionRegistry,
                          extensions::ExtensionRegistryObserver>
      observation_{this};
  base::ScopedObservation<extensions::ExtensionPrefs,
                          extensions::ExtensionPrefsObserver>
      prefs_observation_{this};
  base::WeakPtrFactory<InstalledExtensionsWatcher> weak_factory_{this};
};

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSION_MANAGEMENT_H_
