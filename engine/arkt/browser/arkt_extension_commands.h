#ifndef ARKT_BROWSER_ARKT_EXTENSION_COMMANDS_H_
#define ARKT_BROWSER_ARKT_EXTENSION_COMMANDS_H_

#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "chrome/browser/extensions/commands/command_service.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/common/extension_id.h"

class Profile;

namespace arkt {

// One chrome.commands command of an enabled extension (#598), as Chrome's
// keyboard shortcuts page lists it (developerPrivate's ConstructCommands):
// the action command first, then the named commands.
struct ExtensionCommandInfo {
  ExtensionCommandInfo();
  ExtensionCommandInfo(const ExtensionCommandInfo&);
  ~ExtensionCommandInfo();
  extensions::ExtensionId extension_id;
  // The manifest name (_execute_action for the action).
  std::string name;
  std::u16string extension_name;
  // The manifest's description, or "Activate the extension" for the action.
  std::u16string description;
  // Chromium's form ("Command+Shift+Y", ui::Command::AcceleratorToString);
  // empty when the command has no shortcut.
  std::string shortcut;
  bool global = false;
};

// Every command of the profile's enabled extensions, by extension name.
std::vector<ExtensionCommandInfo> ListExtensionCommands(Profile* profile);

enum class ExtensionShortcutResult {
  kApplied,
  kConflict,
  kNotAllowed,
  kUnknownCommand,
  kGlobalShortcutTaken,
};

// Sets (an empty `shortcut` clears) a command's shortcut and scope through
// CommandService, as Chrome's shortcuts page does (developerPrivate's
// updateExtensionCommand). `shortcut` is in Chromium's form and must pass
// extensions::Command::StringToAccelerator (ui::Command::ParseImpl), else
// kNotAllowed; so is global scope for an action command (Chrome's page
// disables the scope there). Another command holding the shortcut is
// kConflict with its ids in `conflict_*` unless `replacing_conflict`, which
// clears it first (media keys are shared, as in Chrome). A global shortcut the
// profile's global registry could not register (another profile of the
// process, or the system refused the hot key) is undone and reported as
// kGlobalShortcutTaken.
ExtensionShortcutResult SetExtensionCommandShortcut(
    Profile* profile,
    const extensions::ExtensionId& extension_id,
    const std::string& command_name,
    const std::string& shortcut,
    bool global,
    bool replacing_conflict,
    extensions::ExtensionId* conflict_extension_id,
    std::string* conflict_command_name);

// Reports changes to ListExtensionCommands (a shortcut or scope set or
// cleared, an extension with commands loaded or unloaded), merged into one
// callback per task. Also keeps the main menu's keys the shell's (#598): a
// shortcut CommandService assigns on its own (a manifest suggestion at install
// or update, Chrome's shortcuts page) that a main-menu item holds is cleared,
// so the command is unassigned until the user sets it, as #590 decided for a
// taken shortcut. Shortcuts set through SetExtensionCommandShortcut are kept.
class ExtensionCommandsWatcher : public extensions::CommandService::Observer,
                                 public extensions::ExtensionRegistryObserver {
 public:
  ExtensionCommandsWatcher(Profile* profile, base::RepeatingClosure changed);
  ExtensionCommandsWatcher(const ExtensionCommandsWatcher&) = delete;
  ExtensionCommandsWatcher& operator=(const ExtensionCommandsWatcher&) = delete;
  ~ExtensionCommandsWatcher() override;

  // extensions::CommandService::Observer:
  void OnExtensionCommandAdded(const extensions::ExtensionId& extension_id,
                               const std::string& command_name) override;
  void OnExtensionCommandRemoved(const extensions::ExtensionId& extension_id,
                                 const std::string& command_name) override;
  void OnCommandServiceDestroying() override;

  // extensions::ExtensionRegistryObserver:
  void OnExtensionLoaded(content::BrowserContext* browser_context,
                         const extensions::Extension* extension) override;
  void OnExtensionUnloaded(content::BrowserContext* browser_context,
                           const extensions::Extension* extension,
                           extensions::UnloadedExtensionReason reason) override;
  void OnShutdown(extensions::ExtensionRegistry* registry) override;

 private:
  void NotifyChanged();
  void ClearIfMainMenuHolds(const extensions::ExtensionId& extension_id,
                            const std::string& command_name);

  raw_ptr<Profile> profile_;
  base::RepeatingClosure changed_;
  bool notify_posted_ = false;
  base::ScopedObservation<extensions::CommandService,
                          extensions::CommandService::Observer>
      command_observation_{this};
  base::ScopedObservation<extensions::ExtensionRegistry,
                          extensions::ExtensionRegistryObserver>
      registry_observation_{this};
  base::WeakPtrFactory<ExtensionCommandsWatcher> weak_factory_{this};
};

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSION_COMMANDS_H_
