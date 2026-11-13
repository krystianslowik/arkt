#include "arkt/browser/arkt_extensions_menu.h"

#import <AppKit/AppKit.h>

#include <string>
#include <utility>
#include <vector>

#include "arkt/browser/arkt_browser_window.h"
#include "arkt/browser/arkt_extensions_bridge.h"
#include "arkt/browser/arkt_extensions_container.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/themes/theme_service.h"
#include "chrome/browser/themes/theme_service_factory.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/extensions/extension_action_delegate.h"
#include "chrome/browser/ui/extensions/extension_action_view_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/common/extension.h"
#include "extensions/common/manifest_handlers/options_page_info.h"
#include "ui/base/models/image_model.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia.h"

// Receives menu item choices and forwards the item's extension id.
@interface ArktExtensionsMenuTarget : NSObject
@property(nonatomic, copy) void (^onChoose)(NSString* extensionId);
- (void)itemChosen:(NSMenuItem*)item;
@end

@implementation ArktExtensionsMenuTarget
@synthesize onChoose = _onChoose;

- (void)itemChosen:(NSMenuItem*)item {
  if (self.onChoose) {
    self.onChoose(item.representedObject);
  }
}
@end

namespace arkt {

namespace {

constexpr NSTimeInterval kDumpMenuCloseDelay = 3.0;
constexpr int kMenuIconSize = 16;

// Connects one ExtensionActionViewModel to Arkt's UI: popups open in the
// NSPopover at the window's Extensions button, and the action runs against
// the tab Arkt shows.
class ArktExtensionActionDelegate : public ExtensionActionDelegate {
 public:
  explicit ArktExtensionActionDelegate(ArktExtensionsMenu* menu)
      : menu_(menu) {}
  ArktExtensionActionDelegate(const ArktExtensionActionDelegate&) = delete;
  ArktExtensionActionDelegate& operator=(const ArktExtensionActionDelegate&) =
      delete;
  ~ArktExtensionActionDelegate() override = default;

  // ExtensionActionDelegate:
  void AttachToModel(ExtensionActionViewModel* model) override {
    model_ = model;
  }

  void DetachFromModel() override { model_ = nullptr; }

  // The window's ArktExtensionKeybindingRegistry lists the action command
  // with the extension's other commands and runs this action's
  // TryHandleAcceleratorPress (#598), as Android's registry does; Chrome's
  // desktop delegate registers it with the window's focus manager instead,
  // which an Arkt window does not have.
  void RegisterCommand() override {}

  void UnregisterCommand() override {}

  bool IsShowingPopup() const override {
    return model_ && IsShowingPopover(model_->GetId(), menu_);
  }

  void HidePopup() override {
    if (model_) {
      HidePopover(model_->GetId(), menu_);
    }
  }

  gfx::NativeView GetPopupNativeView() override {
    return model_ ? GetPopoverNativeView(model_->GetId(), menu_)
                  : gfx::NativeView();
  }

  void TriggerPopup(std::unique_ptr<extensions::ExtensionViewHost> host,
                    PopupShowAction show_action,
                    bool by_user,
                    ShowPopupCallback callback) override {
    LOG(WARNING) << "ARKT: TriggerPopup " << host->extension_id()
                 << " by_user=" << by_user << " url="
                 << host->initial_url().spec()
                 << " anchor=" << (__bridge void*)menu_->anchor();
    if (show_action == PopupShowAction::kShowAndInspect) {
      LOG(WARNING) << "ARKT: popup inspection not supported; showing only";
    }
    ShowPopover(std::move(host), menu_->anchor(), menu_, std::move(callback));
  }

  // Chrome shows the action's context menu when a click cannot run it
  // (disabled on this tab, #593).
  void ShowContextMenuAsFallback() override {
    if (model_) {
      menu_->ShowContextMenuForAction(model_->GetId());
    }
  }

  void CloseExtensionsMenuIfOpen() override { menu_->CloseForAction(); }

  content::WebContents* GetActiveWebContents() const override {
    return menu_->active_web_contents();
  }

 private:
  // Owns the view model that owns this delegate.
  raw_ptr<ArktExtensionsMenu> menu_;
  raw_ptr<ExtensionActionViewModel> model_ = nullptr;
};

gfx::ImageSkia ActionIcon(ExtensionActionViewModel* view_model,
                          content::WebContents* web_contents) {
  ui::ImageModel icon = view_model->GetIcon(
      web_contents, gfx::Size(kMenuIconSize, kMenuIconSize));
  if (icon.IsEmpty()) {
    return gfx::ImageSkia();
  }
  return icon.Rasterize(&web_contents->GetColorProvider());
}

NSImage* MenuIcon(ExtensionActionViewModel* view_model,
                  content::WebContents* web_contents) {
  gfx::ImageSkia image = ActionIcon(view_model, web_contents);
  if (image.isNull()) {
    return nil;
  }
  return gfx::Image(image).ToNSImage();
}

}  // namespace

ArktExtensionsMenu::ArktExtensionsMenu(BrowserWindowInterface* browser,
                                       content::WebContents* tab,
                                       NSView* anchor)
    : browser_(browser),
      tab_(tab ? tab->GetWeakPtr() : nullptr),
      anchor_(anchor) {
  target_ = [[ArktExtensionsMenuTarget alloc] init];
  base::WeakPtr<ArktExtensionsMenu> weak_this = weak_factory_.GetWeakPtr();
  target_.onChoose = ^(NSString* extension_id) {
    if (weak_this) {
      weak_this->ExecuteAction(
          base::SysNSStringToUTF8(extension_id),
          ToolbarActionViewModel::InvocationSource::kMenuEntry);
    }
  };
  browser_did_close_ = browser_->RegisterBrowserDidClose(base::BindRepeating(
      [](base::WeakPtr<ArktExtensionsMenu> menu, BrowserWindowInterface*) {
        if (menu) {
          menu->Shutdown();
        }
      },
      weak_this));

  if (ThemeService* theme =
          ThemeServiceFactory::GetForProfile(browser_->GetProfile())) {
    theme_observation_.Observe(theme);
  }
  if (ui::NativeTheme* native = ui::NativeTheme::GetInstanceForNativeUi()) {
    native_theme_observation_.Observe(native);
  }
  if (auto* permissions =
          extensions::PermissionsManager::Get(browser_->GetProfile())) {
    permissions_observation_.Observe(permissions);
  }
  model_ = ToolbarActionsModel::Get(browser_->GetProfile());
  if (!model_) {
    LOG(ERROR) << "ARKT: no toolbar actions model for this profile";
    return;
  }
  observation_.Observe(model_.get());
  if (model_->actions_initialized()) {
    OnToolbarModelInitialized();
  }
}

ArktExtensionsMenu::~ArktExtensionsMenu() {
  Shutdown();
}

void ArktExtensionsMenu::SetDump(bool dump) {
  dump_ = dump;
  DumpMenu();
}

void ArktExtensionsMenu::RunActionWhenAvailable(
    const extensions::ExtensionId& extension_id) {
  pending_action_id_ = extension_id;
  MaybeRunPendingAction();
}

void ArktExtensionsMenu::Show() {
  NSView* anchor = anchor_;
  // Already tracking: a second Show from inside the menu's loop would nest.
  if (!anchor || shown_menu_) {
    return;
  }
  NSMenu* menu = BuildMenu();
  LOG(WARNING) << "ARKT: extensions menu shown " << menu.numberOfItems
               << " items";
  if (dump_) {
    // Menu tracking runs a nested event loop; close it from that loop so
    // scripted runs never block on an open menu.
    [menu performSelector:@selector(cancelTracking)
               withObject:nil
               afterDelay:kDumpMenuCloseDelay
                  inModes:@[ NSRunLoopCommonModes ]];
  }
  shown_menu_ = menu;
  // Tracking runs a nested run loop in which Chromium keeps running tasks; a
  // window close there destroys this menu (the window owns it).
  base::WeakPtr<ArktExtensionsMenu> weak_this = weak_factory_.GetWeakPtr();
  [menu popUpMenuPositioningItem:nil
                      atLocation:NSMakePoint(0, NSMaxY(anchor.bounds) + 4)
                          inView:anchor];
  LOG(WARNING) << "ARKT: extensions menu closed";
  if (!weak_this) {
    return;
  }
  shown_menu_ = nil;
}

ArktExtensionsMenu::ActionInfo::ActionInfo() = default;
ArktExtensionsMenu::ActionInfo::ActionInfo(const ActionInfo&) = default;
ArktExtensionsMenu::ActionInfo::~ActionInfo() = default;

std::vector<ArktExtensionsMenu::ActionInfo> ArktExtensionsMenu::GetActions()
    const {
  std::vector<ActionInfo> actions;
  if (!model_ || !model_->actions_initialized()) {
    return actions;
  }
  content::WebContents* web_contents = active_web_contents();
  Profile* profile = browser_->GetProfile();
  const extensions::ExtensionSet& enabled =
      extensions::ExtensionRegistry::Get(profile)->enabled_extensions();
  for (const auto& id : OrderedActionIds()) {
    auto it = view_models_.find(id);
    if (it == view_models_.end()) {
      continue;
    }
    ExtensionActionViewModel* view_model = it->second.get();
    ActionInfo info;
    info.id = id;
    info.name = view_model->GetActionName();
    info.pinned = model_->IsActionPinned(id);
    if (web_contents) {
      info.icon = CachedIcon(id, view_model, web_contents);
      info.enabled = view_model->IsEnabled(web_contents);
    }
    if (const extensions::Extension* extension = enabled.GetByID(id)) {
      info.has_options_page =
          extensions::OptionsPageInfo::HasOptionsPage(extension);
      info.site_access =
          GetExtensionSiteAccess(profile, *extension, web_contents);
    }
    actions.push_back(std::move(info));
  }
  return actions;
}

std::vector<extensions::ExtensionId> ArktExtensionsMenu::OrderedActionIds()
    const {
  std::vector<extensions::ExtensionId> ids;
  if (!model_ || !model_->actions_initialized()) {
    return ids;
  }
  for (const auto& id : model_->pinned_action_ids()) {
    if (model_->action_ids().contains(id)) {
      ids.push_back(id);
    }
  }
  for (const auto& id : model_->action_ids()) {
    if (!model_->IsActionPinned(id)) {
      ids.push_back(id);
    }
  }
  return ids;
}

std::vector<ExtensionMenuItem> ArktExtensionsMenu::BuildContextMenu(
    const extensions::ExtensionId& extension_id) {
  context_menu_.reset();
  if (!browser_ || !view_models_.contains(extension_id)) {
    LOG(WARNING) << "ARKT: no extension action for a context menu "
                 << extension_id;
    return {};
  }
  context_menu_ = ArktExtensionContextMenu::Create(browser_, extension_id);
  if (!context_menu_) {
    return {};
  }
  LOG(WARNING) << "ARKT: extension context menu " << extension_id << " "
               << context_menu_->items().size() << " items";
  return context_menu_->items();
}

bool ArktExtensionsMenu::ExecuteContextCommand(
    const extensions::ExtensionId& extension_id,
    int command) {
  if (!context_menu_ || context_menu_->extension_id() != extension_id) {
    LOG(WARNING) << "ARKT: no context menu built for " << extension_id;
    return false;
  }
  return context_menu_->Execute(command);
}

void ArktExtensionsMenu::ShowContextMenuForAction(
    const extensions::ExtensionId& extension_id) {
  // Called from inside the action's ExecuteUserAction (and, through the
  // facade, while the shell's anchor is set for that one call): show the menu
  // on a later task, at the anchor of this moment, so its tracking loop does
  // not run under the view model.
  NSView* anchor = anchor_;
  if (!browser_ || !anchor) {
    return;
  }
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(
          [](base::WeakPtr<ArktExtensionsMenu> menu,
             extensions::ExtensionId extension_id, NSView* anchor) {
            if (menu) {
              menu->ShowContextMenuAt(extension_id, anchor);
            }
          },
          weak_factory_.GetWeakPtr(), extension_id, anchor));
}

void ArktExtensionsMenu::ShowContextMenuAt(
    const extensions::ExtensionId& extension_id,
    NSView* anchor) {
  if (!browser_ || !anchor || !anchor.window || fallback_menu_) {
    return;
  }
  fallback_menu_ = ArktExtensionContextMenu::Create(browser_, extension_id);
  if (!fallback_menu_) {
    return;
  }
  NSMenu* menu = fallback_menu_->BuildNativeMenu();
  LOG(WARNING) << "ARKT: extension context menu fallback " << extension_id
               << " " << menu.numberOfItems << " items";
  if (dump_) {
    for (NSInteger i = 0; i < menu.numberOfItems; ++i) {
      NSMenuItem* item = [menu itemAtIndex:i];
      LOG(WARNING) << "ARKT: fallback item " << i << " "
                   << base::SysNSStringToUTF8(item.title)
                   << " enabled=" << (item.enabled ? "1" : "0");
    }
    [menu performSelector:@selector(cancelTracking)
               withObject:nil
               afterDelay:kDumpMenuCloseDelay
                  inModes:@[ NSRunLoopCommonModes ]];
  }
  // Tracking runs a nested run loop in which Chromium keeps running tasks; a
  // window close there destroys this menu (the window owns it).
  base::WeakPtr<ArktExtensionsMenu> weak_this = weak_factory_.GetWeakPtr();
  [menu popUpMenuPositioningItem:nil
                      atLocation:NSMakePoint(0, NSMaxY(anchor.bounds) + 4)
                          inView:anchor];
  if (weak_this) {
    fallback_menu_.reset();
  }
}

ArktExtensionsMenu::IconCacheEntry::IconCacheEntry() = default;
ArktExtensionsMenu::IconCacheEntry::IconCacheEntry(const IconCacheEntry&) =
    default;
ArktExtensionsMenu::IconCacheEntry::~IconCacheEntry() = default;

gfx::ImageSkia ArktExtensionsMenu::CachedIcon(
    const extensions::ExtensionId& id,
    ExtensionActionViewModel* view_model,
    content::WebContents* web_contents) const {
  auto it = icon_cache_.find(id);
  if (it != icon_cache_.end() &&
      it->second.web_contents.get() == web_contents) {
    return it->second.icon;
  }
  IconCacheEntry entry;
  entry.web_contents = web_contents->GetWeakPtr();
  entry.icon = ActionIcon(view_model, web_contents);
  icon_cache_[id] = entry;
  return entry.icon;
}

void ArktExtensionsMenu::OnActionIconUpdated(
    const extensions::ExtensionId& id) {
  icon_cache_.erase(id);
  NotifyChanged();
}

void ArktExtensionsMenu::SetAnchor(NSView* anchor) {
  anchor_ = anchor;
}

bool ArktExtensionsMenu::RunAction(
    const extensions::ExtensionId& extension_id) {
  if (!view_models_.contains(extension_id)) {
    LOG(WARNING) << "ARKT: no extension action " << extension_id;
    return false;
  }
  ExecuteAction(extension_id,
                ToolbarActionViewModel::InvocationSource::kToolbarButton);
  return true;
}

void ArktExtensionsMenu::SetOnChanged(base::RepeatingClosure on_changed) {
  on_changed_ = std::move(on_changed);
}

void ArktExtensionsMenu::NotifyChanged() {
  if (on_changed_) {
    on_changed_.Run();
  }
}

bool ArktExtensionsMenu::IsShowing() const {
  return shown_menu_ != nil;
}

void ArktExtensionsMenu::CloseIfOpen() {
  [shown_menu_ cancelTracking];
}

void ArktExtensionsMenu::CloseForAction() {
  ArktBrowserWindow* window = ArktBrowserWindow::FromBrowser(browser_);
  if (window && window->extensions_container()->menu() == this) {
    window->extensions_container()->CloseExtensionsMenuIfOpen();
    return;
  }
  CloseIfOpen();
}

ExtensionActionViewModel* ArktExtensionsMenu::GetViewModel(
    const extensions::ExtensionId& extension_id) const {
  auto it = view_models_.find(extension_id);
  return it != view_models_.end() ? it->second.get() : nullptr;
}

bool ArktExtensionsMenu::HasAnyActions() const {
  return !view_models_.empty();
}

void ArktExtensionsMenu::HideActivePopup() {
  for (auto& [id, view_model] : view_models_) {
    if (view_model->IsShowingPopup()) {
      view_model->HidePopup();
    }
  }
}

content::WebContents* ArktExtensionsMenu::active_web_contents() const {
  if (tab_) {
    return tab_.get();
  }
  // No fixed tab (native window): the browser's active tab.
  return browser_ && browser_->GetTabStripModel()
             ? browser_->GetTabStripModel()->GetActiveWebContents()
             : nullptr;
}

NSView* ArktExtensionsMenu::anchor() const {
  return anchor_;
}

void ArktExtensionsMenu::OnToolbarActionAdded(
    const ToolbarActionsModel::ActionId& id) {
  icon_cache_.clear();
  SyncViewModels();
  LogActions();
  DumpMenu();
  NotifyChanged();
  MaybeRunPendingAction();
}

void ArktExtensionsMenu::OnToolbarActionRemoved(
    const ToolbarActionsModel::ActionId& id) {
  icon_cache_.clear();
  SyncViewModels();
  LogActions();
  DumpMenu();
  NotifyChanged();
}

void ArktExtensionsMenu::OnToolbarActionUpdated(
    const ToolbarActionsModel::ActionId& id) {
  // Icon, badge or enabled state, for one tab or all of them.
  icon_cache_.erase(id);
  DumpMenu();
  NotifyChanged();
}

void ArktExtensionsMenu::OnToolbarPinnedActionsChanged() {
  // Pinned, unpinned or moved, here or on chrome://extensions: the order and
  // the pin state of the list changed (#593).
  DumpMenu();
  NotifyChanged();
}

void ArktExtensionsMenu::OnUserPermissionsSettingsChanged(
    const extensions::PermissionsManager::UserPermissionsSettings& settings) {
  NotifyChanged();
}

void ArktExtensionsMenu::OnExtensionPermissionsUpdated(
    const extensions::Extension& extension,
    const extensions::PermissionSet& permissions,
    extensions::PermissionsManager::UpdateReason reason) {
  if (view_models_.contains(extension.id())) {
    NotifyChanged();
  }
}

void ArktExtensionsMenu::OnToolbarModelInitialized() {
  icon_cache_.clear();
  SyncViewModels();
  LogActions();
  DumpMenu();
  NotifyChanged();
  MaybeRunPendingAction();
}

void ArktExtensionsMenu::OnThemeChanged() {
  OnColorsChanged();
}

void ArktExtensionsMenu::OnNativeThemeUpdated(ui::NativeTheme* observed_theme) {
  OnColorsChanged();
}

void ArktExtensionsMenu::OnColorsChanged() {
  if (icon_cache_.empty()) {
    return;
  }
  icon_cache_.clear();
  NotifyChanged();
}

void ArktExtensionsMenu::OnToolbarActionsModelShutdown() {
  Shutdown();
}

void ArktExtensionsMenu::SyncViewModels() {
  if (!model_ || !model_->actions_initialized()) {
    return;
  }
  const auto& ids = model_->action_ids();
  for (auto it = view_models_.begin(); it != view_models_.end();) {
    if (ids.contains(it->first)) {
      ++it;
      continue;
    }
    // A view model must not be destroyed while its popup is showing.
    it->second->HidePopup();
    icon_subscriptions_.erase(it->first);
    it = view_models_.erase(it);
  }
  for (const auto& id : ids) {
    if (!view_models_.contains(id)) {
      view_models_[id] = ExtensionActionViewModel::Create(
          id, browser_, std::make_unique<ArktExtensionActionDelegate>(this));
      // The icon loads after the view model exists; the list shows the new
      // one once it has (Chrome's toolbar button repaints).
      icon_subscriptions_[id] =
          view_models_[id]->RegisterIconUpdateObserver(base::BindRepeating(
              &ArktExtensionsMenu::OnActionIconUpdated,
              weak_factory_.GetWeakPtr(), id));
    }
  }
}

void ArktExtensionsMenu::LogActions() const {
  if (!model_ || !model_->actions_initialized()) {
    return;
  }
  LOG(WARNING) << "ARKT: toolbar actions " << model_->action_ids().size();
  for (const auto& id : model_->action_ids()) {
    auto it = view_models_.find(id);
    LOG(WARNING) << "ARKT action " << id << " "
                 << (it != view_models_.end()
                         ? base::UTF16ToUTF8(it->second->GetActionName())
                         : std::string("?"));
  }
}

NSMenu* ArktExtensionsMenu::BuildMenu() {
  NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Extensions"];
  menu.autoenablesItems = NO;
  content::WebContents* web_contents = active_web_contents();
  if (model_ && model_->actions_initialized()) {
    for (const auto& id : OrderedActionIds()) {
      auto it = view_models_.find(id);
      if (it == view_models_.end()) {
        continue;
      }
      ExtensionActionViewModel* view_model = it->second.get();
      NSMenuItem* item = [[NSMenuItem alloc]
          initWithTitle:base::SysUTF16ToNSString(view_model->GetActionName())
                 action:@selector(itemChosen:)
          keyEquivalent:@""];
      item.target = target_;
      item.representedObject = base::SysUTF8ToNSString(id);
      item.enabled = web_contents && view_model->IsEnabled(web_contents);
      if (web_contents) {
        item.image = MenuIcon(view_model, web_contents);
      }
      [menu addItem:item];
    }
  }
  if (menu.numberOfItems == 0) {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"No extensions"
                                                  action:nil
                                           keyEquivalent:@""];
    item.enabled = NO;
    [menu addItem:item];
  }
  return menu;
}

void ArktExtensionsMenu::DumpMenu() {
  if (!dump_) {
    return;
  }
  NSMenu* menu = BuildMenu();
  std::vector<std::string> lines;
  for (NSInteger i = 0; i < menu.numberOfItems; ++i) {
    NSMenuItem* item = [menu itemAtIndex:i];
    lines.push_back("ARKT: menu item " + base::NumberToString(i) + " " +
                    base::SysNSStringToUTF8(item.title) +
                    " enabled=" + (item.enabled ? "1" : "0"));
  }
  // Actions update often (badges, icons); log only when the menu changes.
  if (lines == last_dump_) {
    return;
  }
  for (const auto& line : lines) {
    LOG(WARNING) << line;
  }
  last_dump_ = std::move(lines);
}

void ArktExtensionsMenu::MaybeRunPendingAction() {
  if (pending_action_id_.empty() || !view_models_.contains(pending_action_id_)) {
    return;
  }
  extensions::ExtensionId id = std::move(pending_action_id_);
  pending_action_id_.clear();
  ExecuteAction(id, ToolbarActionViewModel::InvocationSource::kToolbarButton);
}

void ArktExtensionsMenu::ExecuteAction(
    const extensions::ExtensionId& extension_id,
    ToolbarActionViewModel::InvocationSource source) {
  auto it = view_models_.find(extension_id);
  if (it == view_models_.end()) {
    LOG(ERROR) << "ARKT: no extension action " << extension_id;
    return;
  }
  LOG(WARNING) << "ARKT: run action " << extension_id << " source "
               << static_cast<int>(source);
  it->second->ExecuteUserAction(source);
}

void ArktExtensionsMenu::Shutdown() {
  CloseIfOpen();
  for (auto& [id, view_model] : view_models_) {
    view_model->HidePopup();
  }
  icon_subscriptions_.clear();
  view_models_.clear();
  icon_cache_.clear();
  context_menu_.reset();
  fallback_menu_.reset();
  on_changed_.Reset();
  observation_.Reset();
  permissions_observation_.Reset();
  theme_observation_.Reset();
  native_theme_observation_.Reset();
  model_ = nullptr;
  browser_ = nullptr;
  browser_did_close_ = {};
}

}  // namespace arkt
