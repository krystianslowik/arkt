#include "arkt/browser/arkt_extensions_menu.h"

#import <AppKit/AppKit.h>

#include <string>
#include <utility>
#include <vector>

#include "arkt/browser/arkt_extensions_bridge.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/extensions/extension_action_delegate.h"
#include "chrome/browser/ui/extensions/extension_action_view_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "content/public/browser/web_contents.h"
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

  void RegisterCommand() override {
    static bool logged = false;
    if (!logged) {
      logged = true;
      LOG(WARNING) << "ARKT: extension action keyboard commands not supported";
    }
  }

  void UnregisterCommand() override {}

  bool IsShowingPopup() const override {
    return model_ && IsShowingPopover(model_->GetId());
  }

  void HidePopup() override {
    if (model_) {
      HidePopover(model_->GetId());
    }
  }

  gfx::NativeView GetPopupNativeView() override {
    return model_ ? GetPopoverNativeView(model_->GetId()) : gfx::NativeView();
  }

  void TriggerPopup(std::unique_ptr<extensions::ExtensionViewHost> host,
                    PopupShowAction show_action,
                    bool by_user,
                    ShowPopupCallback callback) override {
    LOG(WARNING) << "ARKT: TriggerPopup " << host->extension_id()
                 << " by_user=" << by_user << " url="
                 << host->initial_url().spec();
    if (show_action == PopupShowAction::kShowAndInspect) {
      LOG(WARNING) << "ARKT: popup inspection not supported; showing only";
    }
    ShowPopover(std::move(host), menu_->anchor(), std::move(callback));
  }

  void ShowContextMenuAsFallback() override {
    LOG(WARNING) << "ARKT: action disabled on this tab; no context menu yet";
  }

  void CloseExtensionsMenuIfOpen() override { menu_->CloseIfOpen(); }

  content::WebContents* GetActiveWebContents() const override {
    return menu_->active_web_contents();
  }

 private:
  // Owns the view model that owns this delegate.
  raw_ptr<ArktExtensionsMenu> menu_;
  raw_ptr<ExtensionActionViewModel> model_ = nullptr;
};

NSImage* MenuIcon(ExtensionActionViewModel* view_model,
                  content::WebContents* web_contents) {
  ui::ImageModel icon = view_model->GetIcon(
      web_contents, gfx::Size(kMenuIconSize, kMenuIconSize));
  if (icon.IsEmpty()) {
    return nil;
  }
  gfx::ImageSkia image = icon.Rasterize(&web_contents->GetColorProvider());
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
  if (!anchor) {
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
  [menu popUpMenuPositioningItem:nil
                      atLocation:NSMakePoint(0, NSMaxY(anchor.bounds) + 4)
                          inView:anchor];
  shown_menu_ = nil;
  LOG(WARNING) << "ARKT: extensions menu closed";
}

bool ArktExtensionsMenu::IsShowing() const {
  return shown_menu_ != nil;
}

void ArktExtensionsMenu::CloseIfOpen() {
  [shown_menu_ cancelTracking];
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
  SyncViewModels();
  LogActions();
  DumpMenu();
  MaybeRunPendingAction();
}

void ArktExtensionsMenu::OnToolbarActionRemoved(
    const ToolbarActionsModel::ActionId& id) {
  SyncViewModels();
  LogActions();
  DumpMenu();
}

void ArktExtensionsMenu::OnToolbarActionUpdated(
    const ToolbarActionsModel::ActionId& id) {
  DumpMenu();
}

void ArktExtensionsMenu::OnToolbarModelInitialized() {
  SyncViewModels();
  LogActions();
  DumpMenu();
  MaybeRunPendingAction();
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
    it = view_models_.erase(it);
  }
  for (const auto& id : ids) {
    if (!view_models_.contains(id)) {
      view_models_[id] = ExtensionActionViewModel::Create(
          id, browser_, std::make_unique<ArktExtensionActionDelegate>(this));
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
    for (const auto& id : model_->action_ids()) {
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
  for (auto& [id, view_model] : view_models_) {
    view_model->HidePopup();
  }
  view_models_.clear();
  observation_.Reset();
  model_ = nullptr;
  browser_ = nullptr;
  browser_did_close_ = {};
}

}  // namespace arkt
