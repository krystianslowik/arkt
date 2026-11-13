#ifndef ARKT_BROWSER_ARKT_EXTENSION_KEYBINDING_REGISTRY_H_
#define ARKT_BROWSER_ARKT_EXTENSION_KEYBINDING_REGISTRY_H_

#include <map>
#include <set>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "chrome/browser/extensions/extension_keybinding_registry.h"
#include "extensions/common/extension_id.h"
#include "ui/base/accelerators/accelerator.h"

@class NSEvent;
class BrowserWindowInterface;
class Profile;
class ToolbarActionViewModel;

namespace arkt {

// Whether an item of the application's main menu has `accelerator` as its key
// equivalent, enabled or not (#598). A key the main menu holds is the shell's:
// an extension shortcut on it does not run, and a manifest suggestion for it
// is not assigned (ArktExtensionCommandsWatcher). Compares the item's key
// equivalent and modifiers as AppKit stores them, with an upper-case letter
// read as Shift plus the letter.
bool MainMenuHasAccelerator(const ui::Accelerator& accelerator);

// The extension keyboard shortcuts of one Arkt window (#598). Chrome keeps
// them in ExtensionKeybindingRegistryViews, which registers them with the
// window's views::FocusManager; an Arkt window has no Views and no focus
// manager (week-2 grep 8), so this registry sits on the platform-independent
// ExtensionKeybindingRegistry the way Android's does: it lists the named
// commands and the action command of every enabled extension, and the window
// asks it for each key down (ArktBrowserWindow::PreHandleKeyboardEvent with the
// page focused, the window's key monitor with anything else focused). A named
// command dispatches chrome.commands.onCommand with the window's active tab;
// the action command (_execute_action) runs the window's action as Chrome's
// toolbar does (TryHandleAcceleratorPress: the popup, or closes the open one).
// Global commands stay with the profile's ExtensionCommandsGlobalRegistry.
class ArktExtensionKeybindingRegistry
    : public extensions::ExtensionKeybindingRegistry {
 public:
  // The window's action view model of an extension, or nullptr.
  using ActionLookup = base::RepeatingCallback<ToolbarActionViewModel*(
      const extensions::ExtensionId&)>;

  ArktExtensionKeybindingRegistry(BrowserWindowInterface* browser,
                                  ActionLookup action_lookup);
  ArktExtensionKeybindingRegistry(const ArktExtensionKeybindingRegistry&) =
      delete;
  ArktExtensionKeybindingRegistry& operator=(
      const ArktExtensionKeybindingRegistry&) = delete;
  ~ArktExtensionKeybindingRegistry() override;

  // Runs the extension command for `event` (a key down of this window).
  // Returns whether one ran: never for a key the main menu holds
  // (MainMenuHasAccelerator), while shortcut handling is suspended, or for a
  // key no command of this window's profile has.
  bool HandleKeyDown(NSEvent* event);
  bool HandleAccelerator(const ui::Accelerator& accelerator);

  // The window became key (or stopped being key): it is the profile's
  // registry for the active window, as ExtensionKeybindingRegistryViews is.
  void OnWindowKeyChanged(bool key);

 private:
  // extensions::ExtensionKeybindingRegistry:
  bool PopulateCommands(const extensions::Extension* extension,
                        ui::CommandMap* commands) override;
  bool RegisterAccelerator(const ui::Accelerator& accelerator,
                           const extensions::ExtensionId& extension_id,
                           const std::string& command_name) override;
  void UnregisterAccelerator(const ui::Accelerator& accelerator) override;
  bool ShouldIgnoreCommand(const std::string& command) const override;

  const raw_ptr<Profile> profile_;
  ActionLookup action_lookup_;
  std::set<ui::Accelerator> accelerators_;
  // The accelerators of action commands, by extension.
  std::map<ui::Accelerator, extensions::ExtensionId> action_accelerators_;
};

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSION_KEYBINDING_REGISTRY_H_
