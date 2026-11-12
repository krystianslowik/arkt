#include "arkt/browser/arkt_extension_context_menu.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <utility>

#include "base/logging.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/strcat.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/browser/extensions/extension_context_menu_model.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "components/url_formatter/url_formatter.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/permissions_manager.h"
#include "extensions/common/extension.h"
#include "extensions/common/permissions/permissions_data.h"
#include "ui/base/models/menu_model.h"

// Receives native menu choices and forwards the item's command.
@interface ArktExtensionContextMenuTarget : NSObject
@property(nonatomic, copy) void (^onChoose)(NSInteger command);
- (void)itemChosen:(NSMenuItem*)item;
@end

@implementation ArktExtensionContextMenuTarget
@synthesize onChoose = _onChoose;

- (void)itemChosen:(NSMenuItem*)item {
  if (self.onChoose) {
    self.onChoose(item.tag);
  }
}
@end

namespace arkt {

namespace {

using extensions::ExtensionContextMenuModel;
using UserSiteAccess = extensions::PermissionsManager::UserSiteAccess;

// The design's titles (design/extensions, "The context menu"); the shell adds
// no copy of its own. The site item's title is the model's ("On <site>").
constexpr char16_t kOptionsTitle[] = u"Options...";
constexpr char16_t kPinTitle[] = u"Pin";
constexpr char16_t kUnpinTitle[] = u"Unpin";
constexpr char16_t kMoveUpTitle[] = u"Move Up";
constexpr char16_t kMoveDownTitle[] = u"Move Down";
constexpr char16_t kSiteAccessTitle[] = u"This Can Read and Change Site Data";
constexpr char16_t kOnClickTitle[] = u"When You Click the Extension";
constexpr char16_t kOnSitePrefix[] = u"On ";
constexpr char16_t kOnAllSitesTitle[] = u"On All Sites";
constexpr char16_t kManageTitle[] = u"Manage Extension...";
constexpr char16_t kRemoveTitle[] = u"Remove from Arkt...";

ToolbarActionsModel* InitializedModel(Profile* profile) {
  ToolbarActionsModel* model =
      profile ? ToolbarActionsModel::Get(profile) : nullptr;
  return model && model->actions_initialized() ? model : nullptr;
}

// Whether the user may change `id`'s pin state or place.
bool CanChangePin(Profile* profile,
                  ToolbarActionsModel* model,
                  const extensions::ExtensionId& id) {
  return !profile->IsOffTheRecord() && model->HasAction(id) &&
         !model->IsActionForcePinned(id);
}

std::optional<size_t> PinnedIndex(ToolbarActionsModel* model,
                                  const extensions::ExtensionId& id) {
  const auto& pinned = model->pinned_action_ids();
  auto it = std::ranges::find(pinned, id);
  if (it == pinned.end()) {
    return std::nullopt;
  }
  return static_cast<size_t>(it - pinned.begin());
}

// The window's active tab, as ExtensionContextMenuModel finds it.
content::WebContents* ActiveWebContents(BrowserWindowInterface* browser) {
  TabStripModel* tabs = browser ? browser->GetTabStripModel() : nullptr;
  return tabs ? tabs->GetActiveWebContents() : nullptr;
}

int SiteCommandId(ExtensionContextCommand command) {
  switch (command) {
    case ExtensionContextCommand::kSiteAccessOnClick:
      return ExtensionContextMenuModel::PAGE_ACCESS_RUN_ON_CLICK;
    case ExtensionContextCommand::kSiteAccessOnThisSite:
      return ExtensionContextMenuModel::PAGE_ACCESS_RUN_ON_SITE;
    case ExtensionContextCommand::kSiteAccessOnAllSites:
      return ExtensionContextMenuModel::PAGE_ACCESS_RUN_ON_ALL_SITES;
    default:
      return -1;
  }
}

ExtensionMenuItem CommandItem(std::u16string title,
                              ExtensionContextCommand command,
                              bool enabled,
                              bool checked = false) {
  ExtensionMenuItem item;
  item.title = std::move(title);
  item.command = command;
  item.enabled = enabled;
  item.checked = checked;
  return item;
}

ExtensionMenuItem Separator() {
  ExtensionMenuItem item;
  item.kind = ExtensionMenuItem::Kind::kSeparator;
  return item;
}

// Finds `command_id` in `model` and its submenus.
bool FindCommand(ui::MenuModel* model,
                 int command_id,
                 ui::MenuModel** found_model,
                 size_t* found_index) {
  for (size_t i = 0; i < model->GetItemCount(); ++i) {
    if (model->GetTypeAt(i) == ui::MenuModel::TYPE_SUBMENU) {
      if (FindCommand(model->GetSubmenuModelAt(i), command_id, found_model,
                      found_index)) {
        return true;
      }
    } else if (model->GetCommandIdAt(i) == command_id) {
      *found_model = model;
      *found_index = i;
      return true;
    }
  }
  return false;
}

NSMenu* NativeMenu(const std::vector<ExtensionMenuItem>& items,
                   NSString* title,
                   ArktExtensionContextMenuTarget* target) {
  NSMenu* menu = [[NSMenu alloc] initWithTitle:title];
  menu.autoenablesItems = NO;
  for (const auto& item : items) {
    if (item.kind == ExtensionMenuItem::Kind::kSeparator) {
      [menu addItem:[NSMenuItem separatorItem]];
      continue;
    }
    NSString* item_title = base::SysUTF16ToNSString(item.title);
    NSMenuItem* entry = [[NSMenuItem alloc] initWithTitle:item_title
                                                   action:nil
                                            keyEquivalent:@""];
    entry.enabled = item.enabled;
    if (item.kind == ExtensionMenuItem::Kind::kSubmenu) {
      entry.submenu = NativeMenu(item.children, item_title, target);
    } else {
      entry.tag = static_cast<NSInteger>(item.command);
      entry.state = item.checked ? NSControlStateValueOn : NSControlStateValueOff;
      entry.target = target;
      entry.action = @selector(itemChosen:);
    }
    [menu addItem:entry];
  }
  return menu;
}

}  // namespace

ExtensionMenuItem::ExtensionMenuItem() = default;
ExtensionMenuItem::ExtensionMenuItem(const ExtensionMenuItem&) = default;
ExtensionMenuItem& ExtensionMenuItem::operator=(const ExtensionMenuItem&) =
    default;
ExtensionMenuItem::~ExtensionMenuItem() = default;

std::vector<extensions::ExtensionId> PinnedExtensionIds(Profile* profile) {
  ToolbarActionsModel* model = InitializedModel(profile);
  return model ? model->pinned_action_ids()
               : std::vector<extensions::ExtensionId>();
}

bool SetExtensionPinned(Profile* profile,
                        const extensions::ExtensionId& id,
                        bool pinned) {
  ToolbarActionsModel* model = InitializedModel(profile);
  if (!model || !CanChangePin(profile, model, id) ||
      model->IsActionPinned(id) == pinned) {
    return false;
  }
  model->SetActionVisibility(id, pinned);
  return true;
}

bool MovePinnedExtension(Profile* profile,
                         const extensions::ExtensionId& id,
                         int index) {
  ToolbarActionsModel* model = InitializedModel(profile);
  if (!model || !CanChangePin(profile, model, id)) {
    return false;
  }
  std::optional<size_t> from = PinnedIndex(model, id);
  if (!from) {
    return false;
  }
  const size_t last = model->pinned_action_ids().size() - 1;
  const size_t to = std::min(static_cast<size_t>(std::max(index, 0)), last);
  if (to == *from) {
    return false;
  }
  model->MovePinnedAction(id, to);
  return true;
}

ExtensionSiteAccess GetExtensionSiteAccess(
    Profile* profile,
    const extensions::Extension& extension,
    content::WebContents* web_contents) {
  if (!profile || !web_contents) {
    return ExtensionSiteAccess::kNone;
  }
  // The conditions under which ExtensionContextMenuModel::InitMenu adds its
  // site access submenu.
  auto* permissions = extensions::PermissionsManager::Get(profile);
  const GURL& url = web_contents->GetLastCommittedURL();
  if (!permissions->CanAffectExtension(extension) &&
      !permissions->HasActiveTabAndCanAccess(extension, url)) {
    return ExtensionSiteAccess::kNone;
  }
  if (!permissions->CanUserSelectSiteAccess(extension, url,
                                            UserSiteAccess::kOnClick) ||
      extension.permissions_data()->IsRestrictedUrl(url, nullptr)) {
    return ExtensionSiteAccess::kNone;
  }
  switch (permissions->GetUserSiteAccess(extension, url)) {
    case UserSiteAccess::kOnClick:
      return ExtensionSiteAccess::kOnClick;
    case UserSiteAccess::kOnSite:
      return ExtensionSiteAccess::kOnThisSite;
    case UserSiteAccess::kOnAllSites:
      return ExtensionSiteAccess::kOnAllSites;
  }
  return ExtensionSiteAccess::kNone;
}

// static
std::unique_ptr<ArktExtensionContextMenu> ArktExtensionContextMenu::Create(
    BrowserWindowInterface* browser,
    const extensions::ExtensionId& id) {
  if (!browser || !browser->GetProfile()) {
    return nullptr;
  }
  const extensions::Extension* extension =
      extensions::ExtensionRegistry::Get(browser->GetProfile())
          ->enabled_extensions()
          .GetByID(id);
  if (!extension) {
    return nullptr;
  }
  return base::WrapUnique(new ArktExtensionContextMenu(browser, *extension));
}

ArktExtensionContextMenu::ArktExtensionContextMenu(
    BrowserWindowInterface* browser,
    const extensions::Extension& extension)
    : browser_(browser),
      profile_(browser->GetProfile()),
      id_(extension.id()) {
  ToolbarActionsModel* toolbar = InitializedModel(profile_);
  is_pinned_ = toolbar && toolbar->IsActionPinned(id_);
  if (content::WebContents* active = ActiveWebContents(browser_)) {
    origin_ = url::Origin::Create(active->GetLastCommittedURL());
  }
  // Chromium's toolbar context menu: the toolbar source with the pin item,
  // no popup delegate (Inspect Popup is not offered).
  model_ = std::make_unique<ExtensionContextMenuModel>(
      &extension, browser_, is_pinned_, /*delegate=*/nullptr,
      /*can_show_icon_in_toolbar=*/true,
      ExtensionContextMenuModel::ContextMenuSource::kToolbarAction);
  BuildItems(extension);
}

ArktExtensionContextMenu::~ArktExtensionContextMenu() = default;

void ArktExtensionContextMenu::BuildItems(
    const extensions::Extension& extension) {
  items_.clear();
  ExtensionMenuItem header;
  header.title = base::UTF8ToUTF16(extension.name());
  header.command = ExtensionContextCommand::kHeader;
  items_.push_back(header);

  items_.push_back(
      CommandItem(kOptionsTitle, ExtensionContextCommand::kOptions,
                  model_->GetIndexOfCommandId(ExtensionContextMenuModel::OPTIONS)
                      .has_value()));

  const bool has_toggle =
      model_->GetIndexOfCommandId(ExtensionContextMenuModel::TOGGLE_VISIBILITY)
          .has_value();
  items_.push_back(CommandItem(
      is_pinned_ ? kUnpinTitle : kPinTitle, ExtensionContextCommand::kTogglePin,
      has_toggle &&
          model_->IsCommandIdEnabled(
              ExtensionContextMenuModel::TOGGLE_VISIBILITY)));

  ToolbarActionsModel* toolbar = InitializedModel(profile_);
  if (std::optional<size_t> place =
          toolbar ? PinnedIndex(toolbar, id_) : std::nullopt) {
    const bool movable = CanChangePin(profile_, toolbar, id_);
    const size_t count = toolbar->pinned_action_ids().size();
    items_.push_back(CommandItem(kMoveUpTitle, ExtensionContextCommand::kMoveUp,
                                 movable && *place > 0));
    items_.push_back(CommandItem(kMoveDownTitle,
                                 ExtensionContextCommand::kMoveDown,
                                 movable && *place + 1 < count));
  }

  if (std::optional<size_t> index = model_->GetIndexOfCommandId(
          ExtensionContextMenuModel::PAGE_ACCESS_SUBMENU)) {
    ui::MenuModel* submenu = model_->GetSubmenuModelAt(*index);
    // The site as the model names it (its GetCurrentSite), in the design's
    // "On <host>" (Chromium's Mac string reads "Always on <host>").
    content::WebContents* active = ActiveWebContents(browser_);
    const std::u16string site =
        active ? url_formatter::IDNToUnicode(url_formatter::StripWWW(
                     active->GetLastCommittedURL().GetHost()))
               : std::u16string();
    ExtensionMenuItem holder;
    holder.kind = ExtensionMenuItem::Kind::kSubmenu;
    holder.title = kSiteAccessTitle;
    holder.enabled = true;
    for (ExtensionContextCommand command :
         {ExtensionContextCommand::kSiteAccessOnClick,
          ExtensionContextCommand::kSiteAccessOnThisSite,
          ExtensionContextCommand::kSiteAccessOnAllSites}) {
      ui::MenuModel* owner = nullptr;
      size_t at = 0;
      const int command_id = SiteCommandId(command);
      if (!FindCommand(submenu, command_id, &owner, &at)) {
        continue;
      }
      std::u16string title =
          command == ExtensionContextCommand::kSiteAccessOnClick
              ? std::u16string(kOnClickTitle)
          : command == ExtensionContextCommand::kSiteAccessOnAllSites
              ? std::u16string(kOnAllSitesTitle)
              : base::StrCat({kOnSitePrefix, site});
      holder.children.push_back(CommandItem(
          std::move(title), command, model_->IsCommandIdEnabled(command_id),
          model_->IsCommandIdChecked(command_id)));
    }
    items_.push_back(holder);
  }

  items_.push_back(Separator());
  items_.push_back(
      CommandItem(kManageTitle, ExtensionContextCommand::kManage, true));
  if (model_->GetIndexOfCommandId(ExtensionContextMenuModel::UNINSTALL)) {
    items_.push_back(
        CommandItem(kRemoveTitle, ExtensionContextCommand::kRemove, true));
  }
}

bool ArktExtensionContextMenu::IsOffered(
    ExtensionContextCommand command) const {
  for (const auto& item : items_) {
    if (item.kind == ExtensionMenuItem::Kind::kCommand &&
        item.command == command) {
      return item.enabled;
    }
    for (const auto& child : item.children) {
      if (child.command == command) {
        return child.enabled;
      }
    }
  }
  return false;
}

bool ArktExtensionContextMenu::Execute(int raw_command) {
  if (raw_command < static_cast<int>(ExtensionContextCommand::kHeader) ||
      raw_command > static_cast<int>(ExtensionContextCommand::kRemove)) {
    return false;
  }
  const auto command = static_cast<ExtensionContextCommand>(raw_command);
  if (!IsOffered(command) || !extensions::ExtensionRegistry::Get(profile_)
                                  ->enabled_extensions()
                                  .GetByID(id_)) {
    LOG(WARNING) << "ARKT: extension context command " << raw_command
                 << " not offered for " << id_;
    return false;
  }
  LOG(WARNING) << "ARKT: extension context command " << raw_command << " for "
               << id_;
  switch (command) {
    case ExtensionContextCommand::kOptions:
      model_->ExecuteCommand(ExtensionContextMenuModel::OPTIONS, 0);
      return true;
    case ExtensionContextCommand::kTogglePin:
      // Straight to the toolbar model: the menu model's TOGGLE_VISIBILITY
      // also notifies the Views element tracker.
      return SetExtensionPinned(profile_, id_, !is_pinned_);
    case ExtensionContextCommand::kMoveUp:
    case ExtensionContextCommand::kMoveDown: {
      ToolbarActionsModel* toolbar = InitializedModel(profile_);
      std::optional<size_t> place =
          toolbar ? PinnedIndex(toolbar, id_) : std::nullopt;
      if (!place) {
        return false;
      }
      const int delta = command == ExtensionContextCommand::kMoveUp ? -1 : 1;
      return MovePinnedExtension(profile_, id_,
                                 static_cast<int>(*place) + delta);
    }
    case ExtensionContextCommand::kSiteAccessOnClick:
    case ExtensionContextCommand::kSiteAccessOnThisSite:
    case ExtensionContextCommand::kSiteAccessOnAllSites: {
      const int command_id = SiteCommandId(command);
      // As the model does (it ignores the choice then too): the tab must still
      // be on the origin the menu was built for.
      content::WebContents* active = ActiveWebContents(browser_);
      if (!active || !origin_.IsSameOriginWith(active->GetLastCommittedURL())) {
        LOG(WARNING) << "ARKT: site access choice after the tab left "
                     << origin_.Serialize();
        return false;
      }
      if (!model_->IsCommandIdEnabled(command_id)) {
        return false;
      }
      model_->ExecuteCommand(command_id, 0);
      return true;
    }
    case ExtensionContextCommand::kHeader:
    case ExtensionContextCommand::kManage:
    case ExtensionContextCommand::kRemove:
      return false;
  }
  return false;
}

bool ArktExtensionContextMenu::ExecuteFromNativeMenu(int raw_command) {
  if (raw_command == static_cast<int>(ExtensionContextCommand::kManage)) {
    model_->ExecuteCommand(ExtensionContextMenuModel::MANAGE_EXTENSIONS, 0);
    return true;
  }
  if (raw_command == static_cast<int>(ExtensionContextCommand::kRemove) &&
      IsOffered(ExtensionContextCommand::kRemove)) {
    model_->ExecuteCommand(ExtensionContextMenuModel::UNINSTALL, 0);
    return true;
  }
  return Execute(raw_command);
}

NSMenu* ArktExtensionContextMenu::BuildNativeMenu() {
  if (!target_) {
    target_ = [[ArktExtensionContextMenuTarget alloc] init];
  }
  // A choice arrives inside the menu's tracking loop, where Chromium tasks
  // run: the window may have replaced or dropped this menu by then.
  base::WeakPtr<ArktExtensionContextMenu> weak_this =
      weak_factory_.GetWeakPtr();
  target_.onChoose = ^(NSInteger command) {
    if (weak_this) {
      weak_this->ExecuteFromNativeMenu(static_cast<int>(command));
    }
  };
  NSString* title =
      items_.empty() ? @"" : base::SysUTF16ToNSString(items_.front().title);
  return NativeMenu(items_, title, target_);
}

}  // namespace arkt
