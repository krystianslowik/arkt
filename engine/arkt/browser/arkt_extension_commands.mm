#include "arkt/browser/arkt_extension_commands.h"

#include <algorithm>
#include <utility>

#include "arkt/browser/arkt_extension_installs.h"
#include "arkt/browser/arkt_extension_keybinding_registry.h"
#include "base/auto_reset.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/extensions/extension_commands_global_registry.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/grit/generated_resources.h"
#include "extensions/common/api/commands/commands_handler.h"
#include "extensions/common/api/extension_action/action_info.h"
#include "extensions/common/command.h"
#include "extensions/common/extension.h"
#include "ui/base/accelerators/command.h"
#include "ui/base/l10n/l10n_util.h"

namespace arkt {

namespace {

using extensions::CommandService;

// True while SetExtensionCommandShortcut writes: its shortcuts are the
// user's, after the shell's conflict flow, so the watcher keeps them.
bool g_setting_from_facade = false;

bool HasCommands(const extensions::Extension& extension) {
  const ui::CommandMap* named =
      extensions::CommandsInfo::GetNamedCommands(&extension);
  return (named && !named->empty()) ||
         extensions::CommandsInfo::GetActionCommand(&extension) ||
         extensions::CommandsInfo::GetBrowserActionCommand(&extension) ||
         extensions::CommandsInfo::GetPageActionCommand(&extension);
}

// The extension's commands as ConstructCommands lists them: the action
// command (with no shortcut unless active), then the named commands with the
// shortcut and scope the profile has for them.
void AppendCommands(CommandService* service,
                    const extensions::Extension& extension,
                    std::vector<ExtensionCommandInfo>* out) {
  const std::u16string extension_name = ExtensionNameForDisplay(extension);
  for (auto type : {extensions::ActionInfo::Type::kBrowser,
                    extensions::ActionInfo::Type::kPage,
                    extensions::ActionInfo::Type::kAction}) {
    bool active = false;
    extensions::Command command;
    if (service->GetExtensionActionCommand(
            extension.id(), type, CommandService::ALL, &command, &active)) {
      ExtensionCommandInfo info;
      info.extension_id = extension.id();
      info.name = command.command_name();
      info.extension_name = extension_name;
      info.description =
          l10n_util::GetStringUTF16(IDS_EXTENSION_COMMANDS_GENERIC_ACTIVATE);
      if (active) {
        info.shortcut = ui::Command::AcceleratorToString(command.accelerator());
      }
      out->push_back(std::move(info));
    }
  }
  ui::CommandMap named;
  if (service->GetNamedCommands(extension.id(), CommandService::ALL,
                                CommandService::ANY_SCOPE, &named)) {
    for (const auto& [name, command] : named) {
      // As ConstructCommands: the saved command has the live shortcut and
      // scope, the manifest's the description.
      extensions::Command saved =
          service->FindCommandByName(extension.id(), name);
      ExtensionCommandInfo info;
      info.extension_id = extension.id();
      info.name = name;
      info.extension_name = extension_name;
      info.description = command.description();
      if (saved.accelerator().key_code() != ui::VKEY_UNKNOWN) {
        info.shortcut = ui::Command::AcceleratorToString(saved.accelerator());
      }
      info.global = saved.global();
      out->push_back(std::move(info));
    }
  }
}

// The command of an enabled extension other than (`extension_id`,
// `command_name`) that has `accelerator`, if any.
bool FindHolder(Profile* profile,
                const ui::Accelerator& accelerator,
                const extensions::ExtensionId& extension_id,
                const std::string& command_name,
                extensions::ExtensionId* holder_id,
                std::string* holder_name) {
  CommandService* service = CommandService::Get(profile);
  std::vector<ExtensionCommandInfo> all;
  for (const auto& extension :
       extensions::ExtensionRegistry::Get(profile)->enabled_extensions()) {
    AppendCommands(service, *extension, &all);
  }
  const std::string wanted = ui::Command::AcceleratorToString(accelerator);
  for (const ExtensionCommandInfo& info : all) {
    if (info.shortcut == wanted &&
        !(info.extension_id == extension_id && info.name == command_name)) {
      *holder_id = info.extension_id;
      *holder_name = info.name;
      return true;
    }
  }
  return false;
}

// The user cleared the command's shortcut (Chrome's shortcuts page, or the
// facade's clear): no key, but the cleared state is kept so an update of the
// extension does not assign its suggestion again.
bool ClearedByUser(CommandService* service,
                   const extensions::ExtensionId& extension_id,
                   const std::string& command_name) {
  for (auto type : {extensions::ActionInfo::Type::kBrowser,
                    extensions::ActionInfo::Type::kPage,
                    extensions::ActionInfo::Type::kAction}) {
    bool active = false;
    extensions::Command command;
    if (service->GetExtensionActionCommand(
            extension_id, type, CommandService::ACTIVE_OR_USER_MODIFIED,
            &command, &active) &&
        command.command_name() == command_name) {
      return !active;
    }
  }
  ui::CommandMap named;
  return service->GetNamedCommands(extension_id,
                                   CommandService::ACTIVE_OR_USER_MODIFIED,
                                   CommandService::ANY_SCOPE, &named) &&
         named.contains(command_name) &&
         service->FindCommandByName(extension_id, command_name)
                 .accelerator()
                 .key_code() == ui::VKEY_UNKNOWN;
}

}  // namespace

ExtensionCommandInfo::ExtensionCommandInfo() = default;
ExtensionCommandInfo::ExtensionCommandInfo(const ExtensionCommandInfo&) =
    default;
ExtensionCommandInfo::~ExtensionCommandInfo() = default;

std::vector<ExtensionCommandInfo> ListExtensionCommands(Profile* profile) {
  std::vector<ExtensionCommandInfo> result;
  if (!profile) {
    return result;
  }
  CommandService* service = CommandService::Get(profile);
  std::vector<scoped_refptr<const extensions::Extension>> extensions;
  for (const auto& extension :
       extensions::ExtensionRegistry::Get(profile)->enabled_extensions()) {
    extensions.push_back(extension);
  }
  std::stable_sort(
      extensions.begin(), extensions.end(), [](const auto& a, const auto& b) {
        return ExtensionNameForDisplay(*a) < ExtensionNameForDisplay(*b);
      });
  for (const auto& extension : extensions) {
    AppendCommands(service, *extension, &result);
  }
  return result;
}

ExtensionShortcutResult SetExtensionCommandShortcut(
    Profile* profile,
    const extensions::ExtensionId& extension_id,
    const std::string& command_name,
    const std::string& shortcut,
    bool global,
    bool replacing_conflict,
    extensions::ExtensionId* conflict_extension_id,
    std::string* conflict_command_name) {
  const extensions::Extension* extension =
      profile ? extensions::ExtensionRegistry::Get(profile)
                    ->enabled_extensions()
                    .GetByID(extension_id)
              : nullptr;
  if (!extension) {
    return ExtensionShortcutResult::kUnknownCommand;
  }
  CommandService* service = CommandService::Get(profile);
  std::vector<ExtensionCommandInfo> own;
  AppendCommands(service, *extension, &own);
  if (std::ranges::none_of(own, [&](const ExtensionCommandInfo& info) {
        return info.name == command_name;
      })) {
    return ExtensionShortcutResult::kUnknownCommand;
  }

  base::AutoReset<bool> setting(&g_setting_from_facade, true);
  const extensions::Command current =
      service->FindCommandByName(extension_id, command_name);
  const bool action = extensions::Command::IsActionRelatedCommand(command_name);
  const bool cleared = current.accelerator().key_code() == ui::VKEY_UNKNOWN &&
                       ClearedByUser(service, extension_id, command_name);
  if (shortcut.empty()) {
    // As Chrome's shortcuts page clears one (UpdateKeybindingPrefs with no
    // keystroke): the cleared state counts as the user's, so an update of
    // the extension does not bring its suggestion back.
    if (current.accelerator().key_code() != ui::VKEY_UNKNOWN) {
      service->UpdateKeybindingPrefs(extension_id, command_name, std::string());
    }
    return ExtensionShortcutResult::kApplied;
  }
  const ui::Accelerator accelerator =
      extensions::Command::StringToAccelerator(shortcut, command_name);
  // Global scope on a key the main menu holds would take the key from the
  // menu (a system hot key comes before Arkt's menu and windows), so it is
  // refused like Chrome refuses global scope on an action command.
  if (accelerator.key_code() == ui::VKEY_UNKNOWN || (global && action) ||
      (global && MainMenuHasAccelerator(accelerator))) {
    return ExtensionShortcutResult::kNotAllowed;
  }
  if (current.accelerator() == accelerator && current.global() == global) {
    return ExtensionShortcutResult::kApplied;
  }
  extensions::ExtensionId holder_id;
  std::string holder_name;
  bool holder_global = false;
  if (!accelerator.IsMediaKey() &&
      FindHolder(profile, accelerator, extension_id, command_name, &holder_id,
                 &holder_name)) {
    if (!replacing_conflict) {
      *conflict_extension_id = holder_id;
      *conflict_command_name = holder_name;
      return ExtensionShortcutResult::kConflict;
    }
    holder_global = service->FindCommandByName(holder_id, holder_name).global();
    service->RemoveKeybindingPrefs(holder_id, holder_name);
  }
  // As updateExtensionCommand: the old shortcut goes, the new one is the
  // user's (so an update of the extension keeps it,
  // IsCommandShortcutUserModified).
  service->RemoveKeybindingPrefs(extension_id, command_name);
  service->AddKeybindingPref(accelerator, extension_id, command_name,
                             /*allow_overrides=*/true, global);
  if (global) {
    extensions::ExtensionCommandsGlobalRegistry* registry =
        extensions::ExtensionCommandsGlobalRegistry::Get(profile);
    if (!registry || !registry->IsAcceleratorRegistered(accelerator)) {
      service->RemoveKeybindingPrefs(extension_id, command_name);
      if (current.accelerator().key_code() != ui::VKEY_UNKNOWN) {
        service->AddKeybindingPref(current.accelerator(), extension_id,
                                   command_name, /*allow_overrides=*/true,
                                   current.global());
      } else if (cleared) {
        // Removal also dropped the user's cleared state; without it an
        // update of the extension would assign its suggestion again.
        service->UpdateKeybindingPrefs(extension_id, command_name,
                                       std::string());
      }
      // Nothing changed for the command the conflict would have replaced
      // either.
      if (!holder_id.empty()) {
        service->AddKeybindingPref(accelerator, holder_id, holder_name,
                                   /*allow_overrides=*/true, holder_global);
        if (holder_global && registry &&
            !registry->IsAcceleratorRegistered(accelerator)) {
          LOG(WARNING) << "ARKT: extension shortcut "
                       << ui::Command::AcceleratorToString(accelerator)
                       << " of " << holder_id << " " << holder_name
                       << " restored, but its global hot key did not "
                          "register again";
        }
      }
      return ExtensionShortcutResult::kGlobalShortcutTaken;
    }
  }
  return ExtensionShortcutResult::kApplied;
}

ExtensionCommandsWatcher::ExtensionCommandsWatcher(
    Profile* profile,
    base::RepeatingClosure changed)
    : profile_(profile), changed_(std::move(changed)) {
  command_observation_.Observe(CommandService::Get(profile));
  registry_observation_.Observe(extensions::ExtensionRegistry::Get(profile));
}

ExtensionCommandsWatcher::~ExtensionCommandsWatcher() = default;

void ExtensionCommandsWatcher::OnExtensionCommandAdded(
    const extensions::ExtensionId& extension_id,
    const std::string& command_name) {
  if (!g_setting_from_facade) {
    // Not inside CommandService's own pref update: on a later task. This also
    // sees CommandService moving a user-set action shortcut to the new action
    // command on an MV2 to MV3 upgrade (RemoveRelinquishedKeybindings); a
    // main-menu key the user set through the facade is cleared then, though
    // the menu kept that key anyway.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(&ExtensionCommandsWatcher::ClearIfMainMenuHolds,
                       weak_factory_.GetWeakPtr(), extension_id, command_name));
  }
  NotifyChanged();
}

void ExtensionCommandsWatcher::OnExtensionCommandRemoved(
    const extensions::ExtensionId& extension_id,
    const std::string& command_name) {
  NotifyChanged();
}

void ExtensionCommandsWatcher::OnCommandServiceDestroying() {
  command_observation_.Reset();
}

void ExtensionCommandsWatcher::OnExtensionLoaded(
    content::BrowserContext* browser_context,
    const extensions::Extension* extension) {
  if (HasCommands(*extension)) {
    NotifyChanged();
  }
}

void ExtensionCommandsWatcher::OnExtensionUnloaded(
    content::BrowserContext* browser_context,
    const extensions::Extension* extension,
    extensions::UnloadedExtensionReason reason) {
  if (HasCommands(*extension)) {
    NotifyChanged();
  }
}

void ExtensionCommandsWatcher::OnShutdown(
    extensions::ExtensionRegistry* registry) {
  registry_observation_.Reset();
  command_observation_.Reset();
  profile_ = nullptr;
}

void ExtensionCommandsWatcher::NotifyChanged() {
  if (notify_posted_) {
    return;
  }
  notify_posted_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<ExtensionCommandsWatcher> watcher) {
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

void ExtensionCommandsWatcher::ClearIfMainMenuHolds(
    const extensions::ExtensionId& extension_id,
    const std::string& command_name) {
  if (!profile_ || !command_observation_.IsObserving()) {
    return;
  }
  CommandService* service = CommandService::Get(profile_);
  const extensions::Command command =
      service->FindCommandByName(extension_id, command_name);
  if (command.accelerator().key_code() == ui::VKEY_UNKNOWN ||
      !MainMenuHasAccelerator(command.accelerator())) {
    return;
  }
  LOG(WARNING) << "ARKT: extension shortcut "
               << ui::Command::AcceleratorToString(command.accelerator())
               << " of " << extension_id << " " << command_name
               << " is a main-menu key; left unassigned";
  // Cleared as the user would clear it, so an update does not assign the
  // suggestion again.
  service->UpdateKeybindingPrefs(extension_id, command_name, std::string());
}

}  // namespace arkt
