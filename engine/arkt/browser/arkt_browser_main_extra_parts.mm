#include "arkt/browser/arkt_browser_main_extra_parts.h"

#import <AppKit/AppKit.h>

#include <memory>
#include <string>
#include <vector>

#include "arkt/browser/arkt_browser_window.h"
#include "arkt/browser/arkt_browser_window_factory_hook.h"
#include "arkt/browser/arkt_extensions_menu.h"
#import "arkt/browser/arkt_placeholder_window_host.h"
#include "arkt/browser/arkt_window_controller.h"
#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/strings/string_number_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_collection_observer.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/base_window.h"
#include "ui/gfx/native_ui_types.h"

namespace arkt {

namespace {

// Normal browser windows are ArktBrowserWindows (week-2 W5a). Without the
// switch the week-1 path runs: Chromium's window, with its active tab mounted
// in an ArktWindowController.
constexpr char kNativeWindowSwitch[] = "arkt-native-window";

bool NativeWindowEnabled() {
  return base::CommandLine::ForCurrentProcess()->HasSwitch(
      kNativeWindowSwitch);
}

constexpr int kMaxAttempts = 40;
constexpr base::TimeDelta kRetryDelay = base::Milliseconds(250);

// Keeps Arkt window controllers alive for the life of the process.
NSMutableArray* Controllers() {
  static base::NoDestructor<NSMutableArray*> controllers(
      [[NSMutableArray alloc] init]);
  return *controllers;
}

// One extensions menu per Arkt window, alive for the life of the process.
std::vector<std::unique_ptr<ArktExtensionsMenu>>& ExtensionsMenus() {
  static base::NoDestructor<std::vector<std::unique_ptr<ArktExtensionsMenu>>>
      menus;
  return *menus;
}

// --arkt-extensions-demo=<id> runs that action as a toolbar click without
// input (=list only logs the actions); --arkt-extensions-menu-dump logs the
// menu items and closes a shown menu after 3 s.
void ApplyExtensionsMenuSwitches(ArktExtensionsMenu* menu) {
  const base::CommandLine* command_line =
      base::CommandLine::ForCurrentProcess();
  menu->SetDump(command_line->HasSwitch("arkt-extensions-menu-dump"));
  std::string demo_id =
      command_line->GetSwitchValueASCII("arkt-extensions-demo");
  if (!demo_id.empty() && demo_id != "list") {
    menu->RunActionWhenAvailable(demo_id);
  }
}

void MountActiveTab(int attempt) {
  BrowserWindowInterface* browser =
      GlobalBrowserCollection::GetInstance()->GetLastActiveBrowser();
  content::WebContents* contents =
      browser && browser->GetTabStripModel()
          ? browser->GetTabStripModel()->GetActiveWebContents()
          : nullptr;
  if (!contents) {
    if (attempt + 1 >= kMaxAttempts) {
      LOG(ERROR) << "ARKT: no browser with an active tab after " << kMaxAttempts
                 << " attempts";
      return;
    }
    base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
        FROM_HERE, base::BindOnce(&MountActiveTab, attempt + 1), kRetryDelay);
    return;
  }

  // Hide Chrome's window first: hiding it after the reparent makes Chrome's
  // view host mark the WebContents NSView hidden.
  // Also clear its first responder so it no longer refers to the
  // RenderWidgetHostViewCocoa that now lives in our window. (Doubled keys were
  // a separate issue; see ArktWindow.)
  NSWindow* chrome_window =
      browser->GetWindow()->GetNativeWindow().GetNativeNSWindow();
  [chrome_window orderOut:nil];
  [chrome_window makeFirstResponder:nil];
  ArktWindowController* controller =
      [[ArktWindowController alloc] initWithWebContents:contents];
  [Controllers() addObject:controller];
  [controller showWindow:nil];
  // --arkt-animate-runs=N runs the Task 5 measured slide N times without input.
  int runs = 0;
  if (base::StringToInt(
          base::CommandLine::ForCurrentProcess()->GetSwitchValueASCII(
              "arkt-animate-runs"),
          &runs) &&
      runs > 0) {
    [controller scheduleAnimationRuns:runs afterDelay:5.0];
  }

  // The sidebar Extensions button shows every toolbar action of the profile.
  ExtensionsMenus().push_back(std::make_unique<ArktExtensionsMenu>(
      browser, contents, controller.extensionsButton));
  ArktExtensionsMenu* menu = ExtensionsMenus().back().get();
  controller.extensionsButtonAction = ^{
    menu->Show();
  };
  ApplyExtensionsMenuSwitches(menu);
  LOG(WARNING) << "ARKT: mounted active tab after " << attempt + 1
               << " attempt(s)";
}

std::unique_ptr<BrowserWindow, BrowserWindowDeleter> CreateArktBrowserWindow(
    BrowserWindowInterface* browser) {
  // Popups, app, DevTools and picture-in-picture windows stay Views windows.
  if (browser->GetType() != BrowserWindowInterface::Type::TYPE_NORMAL) {
    return nullptr;
  }
  ArktPlaceholderWindowHost* host = [[ArktPlaceholderWindowHost alloc] init];
  auto* window = new ArktBrowserWindow(browser, host);
  // The Browser is still being constructed here; attach the sidebar
  // Extensions menu once it exists. The menu follows the active tab.
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(
          [](base::WeakPtr<ArktBrowserWindow> window,
             ArktPlaceholderWindowHost* host) {
            if (!window) {
              return;
            }
            ExtensionsMenus().push_back(std::make_unique<ArktExtensionsMenu>(
                window->browser(), nullptr, host.extensionsButton));
            ArktExtensionsMenu* menu = ExtensionsMenus().back().get();
            host.extensionsButtonAction = ^{
              menu->Show();
            };
            ApplyExtensionsMenuSwitches(menu);
          },
          window->GetWeakPtr(), host));
  return std::unique_ptr<BrowserWindow, BrowserWindowDeleter>(window);
}

// Logs `ARKT: browsers normal=<n> arkt=<n> views=<n>` on every browser add and
// remove, so scripts can tell which window type each Browser got.
class BrowserCensus : public BrowserCollectionObserver {
 public:
  void Start() {
    observation_.Observe(GlobalBrowserCollection::GetInstance());
  }

  // BrowserCollectionObserver:
  void OnBrowserCreated(BrowserWindowInterface* browser) override {
    Log(nullptr);
  }
  void OnBrowserClosed(BrowserWindowInterface* browser) override {
    Log(browser);
  }

 private:
  // `closing` may still be listed while it is being removed; skip it.
  void Log(BrowserWindowInterface* closing) {
    int normal = 0;
    int arkt = 0;
    int views = 0;
    GlobalBrowserCollection::GetInstance()->ForEach(
        [&](BrowserWindowInterface* browser) {
          if (browser == closing) {
            return true;
          }
          if (browser->GetType() == BrowserWindowInterface::Type::TYPE_NORMAL) {
            normal++;
          }
          if (ArktBrowserWindow::FromBrowser(browser)) {
            arkt++;
          } else if (BrowserWindow* window = BrowserWindow::FromBrowser(browser);
                     window && window->AsBrowserView()) {
            views++;
          }
          return true;
        });
    LOG(WARNING) << "ARKT: browsers normal=" << normal << " arkt=" << arkt
                 << " views=" << views;
  }

  base::ScopedObservation<GlobalBrowserCollection, BrowserCollectionObserver>
      observation_{this};
};

BrowserCensus& Census() {
  static base::NoDestructor<BrowserCensus> census;
  return *census;
}

}  // namespace

ArktBrowserMainExtraParts::ArktBrowserMainExtraParts() = default;
ArktBrowserMainExtraParts::~ArktBrowserMainExtraParts() = default;

void ArktBrowserMainExtraParts::PreProfileInit() {
  // Profile init precedes the startup browser, so every normal Browser is
  // created through the override.
  if (NativeWindowEnabled()) {
    SetCreateBrowserWindowOverride(&CreateArktBrowserWindow);
    LOG(WARNING) << "ARKT: native window factory registered";
  }
}

void ArktBrowserMainExtraParts::PreBrowserStart() {
  Census().Start();
}

void ArktBrowserMainExtraParts::PostBrowserStart() {
  LOG(WARNING) << "ARKT: in-process hook alive";
  if (NativeWindowEnabled()) {
    return;
  }
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&MountActiveTab, 0));
}

}  // namespace arkt
