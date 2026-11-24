#include "arkt/browser/arkt_extension_management.h"

#include <algorithm>
#include <tuple>
#include <utility>

#include "arkt/browser/arkt_extension_uninstall.h"
#include "base/logging.h"
#include "base/memory/ref_counted_memory.h"
#include "base/memory/scoped_refptr.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/extensions/extension_management.h"
#include "chrome/browser/extensions/extension_tab_util.h"
#include "chrome/browser/extensions/extension_util.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/common/pref_names.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/browser_thread.h"
#include "extensions/browser/disable_reason.h"
#include "extensions/browser/extension_prefs.h"
#include "extensions/browser/extension_registrar.h"
#include "extensions/browser/extension_system.h"
#include "extensions/browser/image_loader.h"
#include "extensions/browser/management_policy.h"
#include "extensions/browser/pref_names.h"
#include "extensions/browser/ui_util.h"
#include "extensions/browser/unpacked_installer.h"
#include "extensions/common/extension.h"
#include "extensions/common/extension_set.h"
#include "extensions/common/manifest.h"
#include "extensions/common/manifest_handlers/description_info.h"
#include "extensions/common/manifest_handlers/options_page_info.h"
#include "extensions/common/manifest_handlers/shared_module_info.h"
#include "ui/gfx/codec/png_codec.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_rep.h"

namespace arkt {

namespace {

// The icon size the pane is given, in points; ImageLoader rasterizes it at
// every scale factor, so the facade can hand out the 2x one.
constexpr int kIconDip = 32;

// The listed extensions: enabled, disabled and terminated. Blocklisted and
// blocked ones are left out, as the gate cannot change them.
constexpr int kListedSets = extensions::ExtensionRegistry::ENABLED |
                            extensions::ExtensionRegistry::DISABLED |
                            extensions::ExtensionRegistry::TERMINATED;

// The listed extension `id` of `profile`, or null.
const extensions::Extension* ListedExtension(Profile* profile,
                                             const std::string& id) {
  extensions::ExtensionRegistry* registry =
      profile ? extensions::ExtensionRegistry::Get(profile) : nullptr;
  const extensions::Extension* extension =
      registry ? registry->GetExtensionById(id, kListedSets) : nullptr;
  return extension && extensions::ui_util::ShouldDisplayInExtensionSettings(
                          *extension)
             ? extension
             : nullptr;
}

// Enabled or terminated, as management.setEnabled reads it.
bool IsOn(Profile* profile, const std::string& id) {
  extensions::ExtensionRegistry* registry =
      extensions::ExtensionRegistry::Get(profile);
  return registry->enabled_extensions().Contains(id) ||
         registry->terminated_extensions().Contains(id);
}

InstalledExtensionSource SourceOf(Profile* profile,
                                  const extensions::Extension& extension) {
  const extensions::mojom::ManifestLocation location = extension.location();
  if (extensions::Manifest::IsPolicyLocation(location)) {
    return InstalledExtensionSource::kPolicy;
  }
  if (extensions::Manifest::IsUnpackedLocation(location)) {
    return InstalledExtensionSource::kUnpacked;
  }
  if (extensions::ExtensionManagementFactory::GetForBrowserContext(profile)
          ->UpdatesFromWebstore(extension)) {
    return InstalledExtensionSource::kWebStore;
  }
  return InstalledExtensionSource::kOther;
}

}  // namespace

InstalledExtensionInfo::InstalledExtensionInfo() = default;
InstalledExtensionInfo::InstalledExtensionInfo(const InstalledExtensionInfo&) =
    default;
InstalledExtensionInfo& InstalledExtensionInfo::operator=(
    const InstalledExtensionInfo&) = default;
InstalledExtensionInfo::~InstalledExtensionInfo() = default;

std::vector<InstalledExtensionInfo> ListInstalledExtensions(Profile* profile) {
  std::vector<InstalledExtensionInfo> list;
  extensions::ExtensionRegistry* registry =
      profile ? extensions::ExtensionRegistry::Get(profile) : nullptr;
  if (!registry) {
    return list;
  }
  for (const scoped_refptr<const extensions::Extension>& extension :
       registry->GenerateInstalledExtensionsSet(kListedSets)) {
    if (!extensions::ui_util::ShouldDisplayInExtensionSettings(*extension)) {
      continue;
    }
    InstalledExtensionInfo info;
    info.id = extension->id();
    info.name = extensions::ui_util::GetFixupExtensionNameForUIDisplay(
        extension->name());
    info.version = extension->GetVersionForDisplay();
    info.description = extensions::DescriptionInfo::GetDescription(*extension);
    info.enabled = IsOn(profile, extension->id());
    info.may_change_enabled =
        CanChangeExtensionEnabled(profile, *extension, !info.enabled) ==
        ExtensionEnableResult::kApplied;
    info.source = SourceOf(profile, *extension);
    info.has_options_page =
        extensions::OptionsPageInfo::HasOptionsPage(extension.get());
    list.push_back(std::move(info));
  }
  std::sort(
      list.begin(), list.end(),
      [](const InstalledExtensionInfo& a, const InstalledExtensionInfo& b) {
        return std::tie(a.name, a.id) < std::tie(b.name, b.id);
      });
  return list;
}

ExtensionEnableResult CanChangeExtensionEnabled(
    Profile* profile,
    const extensions::Extension& extension,
    bool enabled) {
  extensions::ManagementPolicy* policy =
      extensions::ExtensionSystem::Get(profile)->management_policy();
  // The providers' refusals name the extension; they are read, never kept.
  // Not every provider checks for a null error, so each call gets one.
  std::u16string modify_error;
  if (!policy || !policy->UserMayModifySettings(&extension, &modify_error)) {
    return ExtensionEnableResult::kNotAllowed;
  }
  if (!enabled) {
    std::u16string remain_error;
    // ExtensionRegistrar refuses a user's disable of a shared module.
    return policy->MustRemainEnabled(&extension, &remain_error) ||
                   extensions::SharedModuleInfo::IsSharedModule(&extension)
               ? ExtensionEnableResult::kNotAllowed
               : ExtensionEnableResult::kApplied;
  }
  if (policy->MustRemainDisabled(&extension, nullptr)) {
    return ExtensionEnableResult::kNotAllowed;
  }
  // EnableExtension clears every disable reason, so the user's toggle may
  // enable only an extension whose every reason is one the user may lift, as
  // chrome://extensions does through management.setEnabled. A corrupted or
  // unverified one, one with unsupported requirements, one waiting for a
  // custodian or a remote-install approval, and any reason this list does
  // not know stay disabled.
  bool permissions_increase = false;
  for (const extensions::disable_reason::DisableReason reason :
       extensions::ExtensionPrefs::Get(profile)->GetDisableReasons(
           extension.id())) {
    switch (reason) {
      case extensions::disable_reason::DISABLE_USER_ACTION:
      case extensions::disable_reason::DISABLE_RELOAD:
      case extensions::disable_reason::DISABLE_GREYLIST:
      case extensions::disable_reason::DISABLE_EXTERNAL_EXTENSION:
      // management.setEnabled from another extension: Chrome leaves it to
      // the user to enable again.
      case extensions::disable_reason::DISABLE_BY_ANOTHER_EXTENSION:
      // Only while developer mode is on: MustRemainDisabled refused it above
      // otherwise.
      case extensions::disable_reason::DISABLE_UNSUPPORTED_DEVELOPER_EXTENSION:
        break;
      case extensions::disable_reason::DISABLE_PERMISSIONS_INCREASE:
        permissions_increase = true;
        break;
      default:
        return ExtensionEnableResult::kNotAllowed;
    }
  }
  return permissions_increase ? ExtensionEnableResult::kNeedsPermissionApproval
                              : ExtensionEnableResult::kApplied;
}

ExtensionEnableResult CheckSetExtensionEnabled(Profile* profile,
                                               const std::string& id,
                                               bool enabled) {
  const extensions::Extension* extension = ListedExtension(profile, id);
  if (!extension) {
    return ExtensionEnableResult::kUnknownExtension;
  }
  if (IsOn(profile, id) == enabled) {
    return ExtensionEnableResult::kApplied;
  }
  return CanChangeExtensionEnabled(profile, *extension, enabled);
}

ExtensionEnableResult SetExtensionEnabledForUser(Profile* profile,
                                                 const std::string& id,
                                                 bool enabled) {
  const ExtensionEnableResult gate =
      CheckSetExtensionEnabled(profile, id, enabled);
  if (gate != ExtensionEnableResult::kApplied) {
    LOG(WARNING) << "ARKT: extension " << (enabled ? "enable" : "disable")
                 << " refused result=" << static_cast<int>(gate);
    return gate;
  }
  if (IsOn(profile, id) == enabled) {
    return ExtensionEnableResult::kApplied;
  }
  extensions::ExtensionRegistrar* registrar =
      extensions::ExtensionRegistrar::Get(profile);
  if (enabled) {
    registrar->EnableExtension(id);
  } else {
    registrar->DisableExtension(
        id, {extensions::disable_reason::DISABLE_USER_ACTION});
  }
  // The registrar returns nothing; a refusal the gate did not foresee shows
  // as an unchanged state.
  if (IsOn(profile, id) != enabled) {
    LOG(WARNING) << "ARKT: extension " << (enabled ? "enable" : "disable")
                 << " refused by the registrar";
    return ExtensionEnableResult::kNotAllowed;
  }
  return ExtensionEnableResult::kApplied;
}

bool ExtensionDeveloperMode(Profile* profile) {
  return profile &&
         profile->GetPrefs()->GetBoolean(prefs::kExtensionsUIDeveloperMode);
}

bool SetExtensionDeveloperMode(Profile* profile, bool on) {
  if (!profile || ExtensionDeveloperMode(profile) == on) {
    return false;
  }
  if (!profile->GetPrefs()->IsUserModifiablePreference(
          prefs::kExtensionsUIDeveloperMode)) {
    LOG(WARNING) << "ARKT: developer mode is not the user's to change";
    return false;
  }
  extensions::util::SetDeveloperModeForProfile(profile, on);
  return true;
}

void LoadUnpackedExtension(
    Profile* profile,
    const base::FilePath& path,
    base::OnceCallback<void(const std::string& id, const std::string& error)>
        done) {
  // Every answer arrives on a later task: UnpackedInstaller reports some
  // errors from inside Load().
  auto answer = base::BindOnce(
      [](base::OnceCallback<void(const std::string&, const std::string&)> done,
         const std::string& id, const std::string& error) {
        base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
            FROM_HERE, base::BindOnce(std::move(done), id, error));
      },
      std::move(done));
  if (!profile) {
    std::move(answer).Run(std::string(), "No profile.");
    return;
  }
  if (!ExtensionDeveloperMode(profile)) {
    std::move(answer).Run(std::string(), kDeveloperModeOffReason);
    return;
  }
  if (extensions::ExtensionManagementFactory::GetForBrowserContext(profile)
          ->BlocklistedByDefault()) {
    std::move(answer).Run(std::string(), "Blocked by policy.");
    return;
  }
  // A folder is named by an absolute path; nothing is read here (the UI
  // thread does no disk work), the installer reports a missing manifest.
  if (path.empty() || !path.IsAbsolute()) {
    std::move(answer).Run(std::string(), "Not a folder.");
    return;
  }
  scoped_refptr<extensions::UnpackedInstaller> installer =
      extensions::UnpackedInstaller::Create(profile);
  // No Chromium error UI: the shell shows the answer.
  installer->set_be_noisy_on_failure(false);
  installer->set_completion_callback(base::BindOnce(
      [](base::OnceCallback<void(const std::string&, const std::string&)>
             answer,
         const extensions::Extension* extension, const base::FilePath&,
         const std::u16string& error) {
        // The path and Chromium's error stay out of the log.
        LOG(WARNING) << "ARKT: load unpacked "
                     << (extension ? "loaded " + extension->id()
                                   : std::string("failed"));
        std::move(answer).Run(
            extension ? extension->id() : std::string(),
            extension ? std::string() : base::UTF16ToUTF8(error));
      },
      std::move(answer)));
  installer->Load(path);
}

void DisableExtensionForSelfTest(Profile* profile,
                                 const std::string& id,
                                 int reason) {
  if (!profile || !ListedExtension(profile, id) ||
      reason <= extensions::disable_reason::DISABLE_NONE ||
      reason >= extensions::disable_reason::DISABLE_REASON_LAST) {
    LOG(WARNING) << "ARKT: self-test disable reason refused";
    return;
  }
  extensions::ExtensionRegistrar::Get(profile)->DisableExtension(
      id, {static_cast<extensions::disable_reason::DisableReason>(reason)});
}

bool OpenExtensionOptionsPage(Profile* profile,
                              const std::string& id,
                              BrowserWindowInterface* browser) {
  extensions::ExtensionRegistry* registry =
      profile ? extensions::ExtensionRegistry::Get(profile) : nullptr;
  const extensions::Extension* extension =
      registry ? registry->enabled_extensions().GetByID(id) : nullptr;
  if (!extension ||
      !extensions::ui_util::ShouldDisplayInExtensionSettings(*extension) ||
      !extensions::OptionsPageInfo::HasOptionsPage(extension)) {
    return false;
  }
  if (!browser || browser->GetProfile() != profile ||
      browser->GetType() != BrowserWindowInterface::TYPE_NORMAL) {
    browser = nullptr;
    GlobalBrowserCollection::GetInstance()->ForEach(
        [profile, &browser](BrowserWindowInterface* candidate) {
          if (candidate->GetProfile() == profile &&
              candidate->GetType() == BrowserWindowInterface::TYPE_NORMAL) {
            browser = candidate;
            return false;
          }
          return true;
        },
        BrowserCollection::Order::kActivation);
  }
  return browser &&
         extensions::ExtensionTabUtil::OpenOptionsPage(extension, browser);
}

InstalledExtensionsWatcher::InstalledExtensionsWatcher(
    Profile* profile,
    base::RepeatingClosure changed)
    : profile_(profile), changed_(std::move(changed)) {
  if (extensions::ExtensionRegistry* registry =
          extensions::ExtensionRegistry::Get(profile)) {
    observation_.Observe(registry);
  }
  if (extensions::ExtensionPrefs* extension_prefs =
          extensions::ExtensionPrefs::Get(profile)) {
    prefs_observation_.Observe(extension_prefs);
  }
  // Developer mode changes even when no extension does (and a change by
  // policy reaches the pane the same way).
  prefs_.Init(profile->GetPrefs());
  prefs_.Add(prefs::kExtensionsUIDeveloperMode,
             base::BindRepeating(&InstalledExtensionsWatcher::NotifyChanged,
                                 base::Unretained(this), "developer mode",
                                 /*force=*/true));
  // The extension management policy (the prefs ExtensionManagement reads):
  // a change can flip mayChangeEnabled or canUninstall with no registry
  // event. Checked on a later task, after ExtensionManagement has refreshed.
  for (const char* pref :
       {extensions::pref_names::kInstallAllowList,
        extensions::pref_names::kInstallDenyList,
        extensions::pref_names::kInstallForceList,
        extensions::pref_names::kAllowedInstallSites,
        extensions::pref_names::kAllowedTypes,
        extensions::pref_names::kExtensionManagement,
        extensions::pref_names::kExtensionUnpublishedAvailability}) {
    prefs_.Add(pref,
               base::BindRepeating(&InstalledExtensionsWatcher::NotifyChanged,
                                   base::Unretained(this), "policy",
                                   /*force=*/false));
  }
  last_fingerprint_ = Fingerprint();
}

InstalledExtensionsWatcher::~InstalledExtensionsWatcher() = default;

scoped_refptr<base::RefCountedMemory> InstalledExtensionsWatcher::IconPNG(
    const std::string& id) {
  if (!profile_) {
    return nullptr;
  }
  const extensions::Extension* extension =
      extensions::ExtensionRegistry::Get(profile_)->GetExtensionById(
          id, kListedSets);
  if (!extension) {
    icons_.erase(id);
    return nullptr;
  }
  auto it = icons_.find(id);
  if (it != icons_.end()) {
    return it->second.png;
  }
  // Every install, update or reload drops the entry, so a new request (with
  // its own generation) loads the icon the extension has now.
  const uint64_t generation = ++last_generation_;
  icons_[id] = CachedIcon{generation, false, nullptr};
  extensions::ImageLoader::Get(profile_)->LoadImageAtEveryScaleFactorAsync(
      extension, gfx::Size(kIconDip, kIconDip),
      base::BindOnce(&InstalledExtensionsWatcher::IconLoaded,
                     weak_factory_.GetWeakPtr(), id, generation));
  return nullptr;
}

void InstalledExtensionsWatcher::IconLoaded(const std::string& id,
                                            uint64_t generation,
                                            const gfx::Image& image) {
  auto it = icons_.find(id);
  // An install, reload or uninstall since the load started: a newer request
  // owns the entry, or none does.
  if (it == icons_.end() || it->second.generation != generation ||
      it->second.loaded) {
    return;
  }
  it->second.loaded = true;
  // Encoded once here (the 2x representation), not on every listing.
  const gfx::ImageSkia* skia = image.IsEmpty() ? nullptr : image.ToImageSkia();
  const gfx::ImageSkiaRep rep =
      skia ? skia->GetRepresentation(2.0f) : gfx::ImageSkiaRep();
  std::optional<std::vector<uint8_t>> png =
      rep.is_null() ? std::nullopt
                    : gfx::PNGCodec::EncodeBGRASkBitmap(
                          rep.GetBitmap(), /*discard_transparency=*/false);
  // An extension without an icon has nothing new to show.
  if (png && !png->empty()) {
    it->second.png =
        base::MakeRefCounted<base::RefCountedBytes>(std::move(*png));
    NotifyChanged("icon", /*force=*/true);
  }
}

void InstalledExtensionsWatcher::OnExtensionLoaded(
    content::BrowserContext* browser_context,
    const extensions::Extension* extension) {
  NotifyChanged("loaded", /*force=*/true);
}

void InstalledExtensionsWatcher::OnExtensionUnloaded(
    content::BrowserContext* browser_context,
    const extensions::Extension* extension,
    extensions::UnloadedExtensionReason reason) {
  NotifyChanged("unloaded", /*force=*/true);
}

void InstalledExtensionsWatcher::OnExtensionInstalled(
    content::BrowserContext* browser_context,
    const extensions::Extension* extension,
    bool is_update) {
  if (extension) {
    icons_.erase(extension->id());
  }
  NotifyChanged(is_update ? "updated" : "installed", /*force=*/true);
}

void InstalledExtensionsWatcher::OnExtensionUninstalled(
    content::BrowserContext* browser_context,
    const extensions::Extension* extension,
    extensions::UninstallReason reason) {
  if (extension) {
    icons_.erase(extension->id());
  }
  NotifyChanged("uninstalled", /*force=*/true);
}

void InstalledExtensionsWatcher::OnShutdown(
    extensions::ExtensionRegistry* registry) {
  observation_.Reset();
  prefs_observation_.Reset();
  prefs_.RemoveAll();
  icons_.clear();
  profile_ = nullptr;
}

void InstalledExtensionsWatcher::OnExtensionDisableReasonsChanged(
    const extensions::ExtensionId& extension_id,
    extensions::DisableReasonSet disabled_reasons) {
  // A disabled extension's reasons decide mayChangeEnabled.
  NotifyChanged("disable reasons", /*force=*/false);
}

void InstalledExtensionsWatcher::OnExtensionPrefsUpdated(
    const extensions::ExtensionId& extension_id) {
  // Blocklisting a disabled extension writes its prefs and moves it out of
  // the disabled set with no registry event.
  NotifyChanged("extension prefs", /*force=*/false);
}

void InstalledExtensionsWatcher::OnExtensionPrefsWillBeDestroyed(
    extensions::ExtensionPrefs* prefs) {
  prefs_observation_.Reset();
}

std::string InstalledExtensionsWatcher::Fingerprint() const {
  std::string fingerprint;
  if (!profile_) {
    return fingerprint;
  }
  for (const InstalledExtensionInfo& info : ListInstalledExtensions(profile_)) {
    fingerprint +=
        info.id + " " + info.version + " " + base::UTF16ToUTF8(info.name) +
        " " + (info.enabled ? "1" : "0") +
        (info.may_change_enabled ? "1" : "0") +
        (GetUninstallAbility(profile_, info.id).can_uninstall ? "1" : "0") +
        "\n";
  }
  return fingerprint;
}

void InstalledExtensionsWatcher::NotifyChanged(const char* why, bool force) {
  VLOG(1) << "ARKT: installed extensions changed: " << why
          << (force ? "" : " (check)");
  force_pending_ = force_pending_ || force;
  if (notify_posted_) {
    return;
  }
  notify_posted_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<InstalledExtensionsWatcher> watcher) {
                       if (!watcher) {
                         return;
                       }
                       watcher->notify_posted_ = false;
                       const bool force = watcher->force_pending_;
                       watcher->force_pending_ = false;
                       if (!watcher->profile_) {
                         return;
                       }
                       // A check (prefs, policy) reports only when what the
                       // pane shows changed; a registry change, developer mode
                       // or an icon always.
                       std::string fingerprint = watcher->Fingerprint();
                       const bool changed =
                           fingerprint != watcher->last_fingerprint_;
                       watcher->last_fingerprint_ = std::move(fingerprint);
                       if (force || changed) {
                         watcher->changed_.Run();
                       }
                     },
                     weak_factory_.GetWeakPtr()));
}

}  // namespace arkt
