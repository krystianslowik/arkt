#include "arkt/browser/arkt_extension_keybinding_registry.h"

#import <AppKit/AppKit.h>

#include "base/apple/owned_objc.h"
#include "base/logging.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/extensions/commands/command_service.h"
#include "chrome/browser/extensions/extension_commands_global_registry.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/tab_list/tab_list_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/toolbar/toolbar_action_view_model.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/sessions/core/session_id.h"
#include "extensions/common/api/extension_action/action_info.h"
#include "extensions/common/command.h"
#include "extensions/common/extension.h"
#include "ui/base/accelerators/command.h"
#import "ui/base/accelerators/platform_accelerator_cocoa.h"
#include "ui/content_accelerators/accelerator_util.h"
#include "ui/events/keycodes/keyboard_codes.h"

namespace arkt {

namespace {

constexpr NSEventModifierFlags kKeyModifiers =
    NSEventModifierFlagShift | NSEventModifierFlagControl |
    NSEventModifierFlagOption | NSEventModifierFlagCommand;

// A key equivalent and its modifiers with an upper-case letter written as
// Shift plus the lower-case letter, so "Y" with Command and "y" with Command
// and Shift compare equal.
struct KeyEquivalent {
  NSString* key;
  NSEventModifierFlags modifiers;
};

KeyEquivalent Normalized(NSString* key, NSEventModifierFlags modifiers) {
  modifiers &= kKeyModifiers;
  if (key.length == 1) {
    NSString* lower = key.lowercaseString;
    if (![lower isEqualToString:key]) {
      return {lower, modifiers | NSEventModifierFlagShift};
    }
  }
  return {key, modifiers};
}

bool MenuHolds(NSMenu* menu, const KeyEquivalent& wanted) {
  for (NSMenuItem* item in menu.itemArray) {
    if (item.submenu) {
      if (item.submenu != NSApp.servicesMenu &&
          MenuHolds(item.submenu, wanted)) {
        return true;
      }
      continue;
    }
    if (item.separatorItem || item.keyEquivalent.length == 0) {
      continue;
    }
    const KeyEquivalent held =
        Normalized(item.keyEquivalent, item.keyEquivalentModifierMask);
    if (held.modifiers == wanted.modifiers &&
        [held.key isEqualToString:wanted.key]) {
      return true;
    }
  }
  return false;
}

}  // namespace

bool MainMenuHasAccelerator(const ui::Accelerator& accelerator) {
  NSMenu* main_menu = NSApp.mainMenu;
  if (!main_menu || accelerator.key_code() == ui::VKEY_UNKNOWN ||
      accelerator.IsMediaKey()) {
    return false;
  }
  KeyEquivalentAndModifierMask* equivalent =
      ui::GetKeyEquivalentAndModifierMaskFromAccelerator(accelerator);
  if (equivalent.keyEquivalent.length == 0) {
    return false;
  }
  return MenuHolds(
      main_menu,
      Normalized(equivalent.keyEquivalent,
                 static_cast<NSEventModifierFlags>(equivalent.modifierMask)));
}

ArktExtensionKeybindingRegistry::ArktExtensionKeybindingRegistry(
    BrowserWindowInterface* browser,
    ActionLookup action_lookup)
    : extensions::ExtensionKeybindingRegistry(
          browser->GetProfile(),
          TabListInterface::From(browser),
          extensions::ExtensionKeybindingRegistry::ALL_EXTENSIONS),
      profile_(browser->GetProfile()),
      action_lookup_(std::move(action_lookup)) {
  LOG(WARNING) << "ARKT: extension keybinding registry for window session id "
               << browser->GetSessionID().id() << " tab list="
               << (TabListInterface::From(browser) ? "yes" : "no")
               << " global registry="
               << (extensions::ExtensionCommandsGlobalRegistry::Get(profile_)
                       ? "yes"
                       : "no");
  Init();
}

ArktExtensionKeybindingRegistry::~ArktExtensionKeybindingRegistry() {
  OnWindowKeyChanged(false);
}

bool ArktExtensionKeybindingRegistry::HandleKeyDown(NSEvent* event) {
  if (event.type != NSEventTypeKeyDown || event.ARepeat) {
    return false;
  }
  input::NativeWebKeyboardEvent keyboard_event(
      (base::apple::OwnedNSEvent(event)));
  return HandleAccelerator(
      ui::GetAcceleratorFromNativeWebKeyboardEvent(keyboard_event));
}

bool ArktExtensionKeybindingRegistry::HandleAccelerator(
    const ui::Accelerator& accelerator) {
  if (shortcut_handling_suspended() || !accelerators_.contains(accelerator)) {
    return false;
  }
  if (MainMenuHasAccelerator(accelerator)) {
    LOG(WARNING) << "ARKT: extension shortcut "
                 << ui::Command::AcceleratorToString(accelerator)
                 << " left to the main menu";
    return false;
  }
  auto action = action_accelerators_.find(accelerator);
  if (action != action_accelerators_.end()) {
    ToolbarActionViewModel* model = action_lookup_.Run(action->second);
    const bool can_handle = model && model->CanHandleAccelerators();
    LOG(WARNING) << "ARKT: extension shortcut "
                 << ui::Command::AcceleratorToString(accelerator) << " action "
                 << action->second
                 << (can_handle ? " runs" : " has no action in this window");
    return can_handle && model->TryHandleAcceleratorPress();
  }
  const bool ran = NotifyEventTargets(accelerator);
  LOG(WARNING) << "ARKT: extension shortcut "
               << ui::Command::AcceleratorToString(accelerator)
               << (ran ? " dispatched" : " found no target");
  return ran;
}

void ArktExtensionKeybindingRegistry::OnWindowKeyChanged(bool key) {
  extensions::ExtensionCommandsGlobalRegistry* global =
      extensions::ExtensionCommandsGlobalRegistry::Get(profile_);
  if (!global) {
    return;
  }
  if (key) {
    global->set_registry_for_active_window(this);
  } else if (global->registry_for_active_window() == this) {
    global->set_registry_for_active_window(nullptr);
  }
}

bool ArktExtensionKeybindingRegistry::PopulateCommands(
    const extensions::Extension* extension,
    ui::CommandMap* commands) {
  extensions::CommandService* service =
      extensions::CommandService::Get(browser_context());
  const bool named = service->GetNamedCommands(
      extension->id(), extensions::CommandService::ACTIVE,
      extensions::CommandService::REGULAR, commands);
  // The action command, as Android's registry adds it (Chrome's Views
  // toolbar registers it from ExtensionActionDelegateDesktop instead).
  const extensions::ActionInfo* action_info =
      extensions::ActionInfo::GetExtensionActionInfo(extension);
  extensions::Command action_command;
  const bool action = action_info && service->GetExtensionActionCommand(
                                         extension->id(), action_info->type,
                                         extensions::CommandService::ACTIVE,
                                         &action_command, nullptr);
  if (action) {
    (*commands)[action_command.command_name()] = action_command;
  }
  return named || action;
}

bool ArktExtensionKeybindingRegistry::RegisterAccelerator(
    const ui::Accelerator& accelerator,
    const extensions::ExtensionId& extension_id,
    const std::string& command_name) {
  accelerators_.insert(accelerator);
  if (extensions::Command::IsActionRelatedCommand(command_name)) {
    action_accelerators_[accelerator] = extension_id;
  }
  return true;
}

void ArktExtensionKeybindingRegistry::UnregisterAccelerator(
    const ui::Accelerator& accelerator) {
  accelerators_.erase(accelerator);
  action_accelerators_.erase(accelerator);
}

bool ArktExtensionKeybindingRegistry::ShouldIgnoreCommand(
    const std::string& command) const {
  // Action commands are this registry's too.
  return false;
}

}  // namespace arkt
