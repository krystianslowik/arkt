#ifndef ARKT_BROWSER_ARKT_EXTENSION_CONTEXT_MENU_H_
#define ARKT_BROWSER_ARKT_EXTENSION_CONTEXT_MENU_H_

#include <memory>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "extensions/common/extension_id.h"
#include "url/origin.h"

class BrowserWindowInterface;
class Profile;

@class ArktExtensionContextMenuTarget;
@class NSMenu;

namespace content {
class WebContents;
}

namespace extensions {
class Extension;
class ExtensionContextMenuModel;
}  // namespace extensions

namespace arkt {

// Pins, order, site access and the context menu of extension actions (#593),
// over Chromium's ToolbarActionsModel, PermissionsManager and
// ExtensionContextMenuModel. No Views: the model only needs the window's
// BrowserWindowInterface.

// The values of arkt_engine.h's ArktExtensionSiteAccess.
enum class ExtensionSiteAccess {
  kNone = 0,
  kOnClick = 1,
  kOnThisSite = 2,
  kOnAllSites = 3,
};

// The values of arkt_engine.h's ArktExtensionContextCommand.
enum class ExtensionContextCommand {
  kHeader = 0,
  kOptions = 1,
  kTogglePin = 2,
  kMoveUp = 3,
  kMoveDown = 4,
  kSiteAccessOnClick = 5,
  kSiteAccessOnThisSite = 6,
  kSiteAccessOnAllSites = 7,
  kManage = 8,
  kRemove = 9,
};

// The commands of the extension's own chrome.contextMenus items for its action
// (#915), arkt_engine.h's ArktExtensionContextCommandCustomFirst and
// CustomLast: item n of Chromium's ContextMenuMatcher (its command id
// IDC_EXTENSIONS_CONTEXT_CUSTOM_FIRST + n) is kExtensionContextCustomFirst + n.
// An ExtensionMenuItem's command holds such a value as ExtensionContextCommand.
inline constexpr int kExtensionContextCustomFirst = 1000;
inline constexpr int kExtensionContextCustomLast = 2000;

// Whether `command` is in that range.
bool IsExtensionContextCustomCommand(int command);

// One item of an extension action's context menu, as plain values.
struct ExtensionMenuItem {
  enum class Kind { kCommand, kSeparator, kSubmenu };
  ExtensionMenuItem();
  ExtensionMenuItem(const ExtensionMenuItem&);
  ExtensionMenuItem& operator=(const ExtensionMenuItem&);
  ~ExtensionMenuItem();
  Kind kind = Kind::kCommand;
  std::u16string title;
  ExtensionContextCommand command = ExtensionContextCommand::kHeader;
  bool enabled = false;
  bool checked = false;
  std::vector<ExtensionMenuItem> children;
};

// The profile's pinned actions in order (Chromium's toolbar pins, stored in
// the profile's extensions.pinned_extensions).
std::vector<extensions::ExtensionId> PinnedExtensionIds(Profile* profile);

// Pins (at the end) or unpins `id`. False, and nothing changed, when the
// profile has no such action, it is already in that state, the policy pins
// it, or the profile is off the record: ToolbarActionsModel DCHECKs or CHECKs
// each of those.
bool SetExtensionPinned(Profile* profile,
                        const extensions::ExtensionId& id,
                        bool pinned);

// Moves pinned `id` to `index` of the pinned order, clamped to the ends. False
// when it is not pinned, the policy pins it, the profile is off the record or
// it is already there.
bool MovePinnedExtension(Profile* profile,
                         const extensions::ExtensionId& id,
                         int index);

// The site access the context menu shows for `extension` on `web_contents`:
// kNone when the menu has no site access submenu there (no host permissions
// the user can change, or a page the extension may not run on).
ExtensionSiteAccess GetExtensionSiteAccess(
    Profile* profile,
    const extensions::Extension& extension,
    content::WebContents* web_contents);

// The context menu of one action in one window, as Chromium's
// ExtensionContextMenuModel had it when this object was made: the model
// captures the active tab's origin then, and its site access commands do
// nothing once the tab has moved to another origin. The items are the ones
// design/extensions fixes, with the model's enabled and checked state, and
// after the header the extension's own items for the action context (#915),
// between two separators, as the model's ContextMenuMatcher lists them:
// submenus, checkbox and radio items with their check marks, separators,
// enabled state, invisible ones left out.
class ArktExtensionContextMenu {
 public:
  // Null when the profile has no enabled extension `id`.
  static std::unique_ptr<ArktExtensionContextMenu> Create(
      BrowserWindowInterface* browser,
      const extensions::ExtensionId& id);
  ArktExtensionContextMenu(const ArktExtensionContextMenu&) = delete;
  ArktExtensionContextMenu& operator=(const ArktExtensionContextMenu&) = delete;
  ~ArktExtensionContextMenu();

  const extensions::ExtensionId& extension_id() const { return id_; }
  const std::vector<ExtensionMenuItem>& items() const { return items_; }

  // Runs a command the shell's menu offered: Options, Pin or Unpin, Move Up,
  // Move Down, the site access choices and the extension's own items. False
  // when it ran nothing (an unknown or disabled command, the extension gone,
  // Header, Manage and Remove, which are the shell's, or an extension item
  // chosen after another tab became active: chrome.contextMenus.onClicked
  // gets the tab the menu was built for or nothing).
  bool Execute(int command);

  // The menu as a native NSMenu, for the action's own fallback (a click while
  // the action is disabled on the tab), where no shell menu is involved:
  // there Manage and Remove run through Chromium's model
  // (chrome://extensions/?id=, and the uninstall dialog through the 0007
  // hook).
  NSMenu* BuildNativeMenu();

 private:
  ArktExtensionContextMenu(BrowserWindowInterface* browser,
                           const extensions::Extension& extension);
  void BuildItems(const extensions::Extension& extension);
  bool IsOffered(ExtensionContextCommand command) const;
  bool ExecuteCustom(int command);
  bool ExecuteFromNativeMenu(int command);

  raw_ptr<BrowserWindowInterface> browser_;
  raw_ptr<Profile> profile_;
  extensions::ExtensionId id_;
  bool is_pinned_ = false;
  // The active tab and its origin when the menu was built.
  base::WeakPtr<content::WebContents> web_contents_;
  url::Origin origin_;
  std::unique_ptr<extensions::ExtensionContextMenuModel> model_;
  std::vector<ExtensionMenuItem> items_;
  ArktExtensionContextMenuTarget* __strong target_;
  base::WeakPtrFactory<ArktExtensionContextMenu> weak_factory_{this};
};

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSION_CONTEXT_MENU_H_
