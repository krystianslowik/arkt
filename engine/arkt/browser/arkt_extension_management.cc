#include "arkt/browser/arkt_extension_management.h"

#include <algorithm>
#include <tuple>
#include <utility>

#include "base/logging.h"
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
#include "extensions/browser/ui_util.h"
#include "extensions/browser/unpacked_installer.h"
#include "extensions/common/extension.h"
#include "extensions/common/extension_set.h"
#include "extensions/common/manifest.h"
#include "extensions/common/manifest_handlers/description_info.h"
#include "extensions/common/manifest_handlers/options_page_info.h"
#include "extensions/common/manifest_handlers/shared_module_info.h"
#include "ui/gfx/geometry/size.h"

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
  if (extensions::ExtensionPrefs::Get(profile)->HasDisableReason(
          extension.id(),
          extensions::disable_reason::DISABLE_PERMISSIONS_INCREASE)) {
    return ExtensionEnableResult::kNeedsPermissionApproval;
  }
  return ExtensionEnableResult::kApplied;
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
    std::move(answer).Run(std::string(), "no profile");
    return;
  }
  if (!ExtensionDeveloperMode(profile)) {
    std::move(answer).Run(std::string(), "developer mode is off");
    return;
  }
  if (extensions::ExtensionManagementFactory::GetForBrowserContext(profile)
          ->BlocklistedByDefault()) {
    std::move(answer).Run(std::string(), "blocked by policy");
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
  // Developer mode changes even when no extension does (and a change by
  // policy reaches the pane the same way).
  prefs_.Init(profile->GetPrefs());
  prefs_.Add(prefs::kExtensionsUIDeveloperMode,
             base::BindRepeating(&InstalledExtensionsWatcher::NotifyChanged,
                                 base::Unretained(this), "developer mode"));
}

InstalledExtensionsWatcher::~InstalledExtensionsWatcher() = default;

gfx::Image InstalledExtensionsWatcher::Icon(const std::string& id) {
  if (!profile_) {
    return gfx::Image();
  }
  extensions::ExtensionRegistry* registry =
      extensions::ExtensionRegistry::Get(profile_);
  const extensions::Extension* extension =
      registry->GetExtensionById(id, kListedSets);
  if (!extension) {
    icons_.erase(id);
    return gfx::Image();
  }
  const std::string version = extension->VersionString();
  auto it = icons_.find(id);
  if (it != icons_.end() && it->second.version == version) {
    return it->second.image;
  }
  icons_[id] = CachedIcon{version, false, gfx::Image()};
  extensions::ImageLoader::Get(profile_)->LoadImageAtEveryScaleFactorAsync(
      extension, gfx::Size(kIconDip, kIconDip),
      base::BindOnce(&InstalledExtensionsWatcher::IconLoaded,
                     weak_factory_.GetWeakPtr(), id, version));
  return gfx::Image();
}

void InstalledExtensionsWatcher::IconLoaded(const std::string& id,
                                            const std::string& version,
                                            const gfx::Image& image) {
  auto it = icons_.find(id);
  // An update or an uninstall since the load started: a newer request owns
  // the entry, or none does.
  if (it == icons_.end() || it->second.version != version ||
      it->second.loaded) {
    return;
  }
  it->second.loaded = true;
  it->second.image = image;
  // An extension without an icon has nothing new to show.
  if (!image.IsEmpty()) {
    NotifyChanged("icon");
  }
}

void InstalledExtensionsWatcher::OnExtensionLoaded(
    content::BrowserContext* browser_context,
    const extensions::Extension* extension) {
  NotifyChanged("loaded");
}

void InstalledExtensionsWatcher::OnExtensionUnloaded(
    content::BrowserContext* browser_context,
    const extensions::Extension* extension,
    extensions::UnloadedExtensionReason reason) {
  NotifyChanged("unloaded");
}

void InstalledExtensionsWatcher::OnExtensionInstalled(
    content::BrowserContext* browser_context,
    const extensions::Extension* extension,
    bool is_update) {
  NotifyChanged(is_update ? "updated" : "installed");
}

void InstalledExtensionsWatcher::OnExtensionUninstalled(
    content::BrowserContext* browser_context,
    const extensions::Extension* extension,
    extensions::UninstallReason reason) {
  if (extension) {
    icons_.erase(extension->id());
  }
  NotifyChanged("uninstalled");
}

void InstalledExtensionsWatcher::OnShutdown(
    extensions::ExtensionRegistry* registry) {
  observation_.Reset();
  prefs_.RemoveAll();
  icons_.clear();
  profile_ = nullptr;
}

void InstalledExtensionsWatcher::NotifyChanged(const char* why) {
  VLOG(1) << "ARKT: installed extensions changed: " << why;
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
                       if (watcher->profile_) {
                         watcher->changed_.Run();
                       }
                     },
                     weak_factory_.GetWeakPtr()));
}

}  // namespace arkt
