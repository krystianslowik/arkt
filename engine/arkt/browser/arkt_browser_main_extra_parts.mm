#include "arkt/browser/arkt_browser_main_extra_parts.h"

#import <AppKit/AppKit.h>

#include <memory>
#include <string>
#include <vector>

#include "arkt/browser/arkt_extensions_menu.h"
#include "arkt/browser/arkt_window_controller.h"
#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/string_number_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/base_window.h"
#include "ui/gfx/native_ui_types.h"

namespace arkt {

namespace {

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
  // --arkt-extensions-demo=<id> runs that action as a toolbar click without
  // input (=list only logs the actions); --arkt-extensions-menu-dump logs the
  // menu items and closes a shown menu after 3 s.
  ExtensionsMenus().push_back(std::make_unique<ArktExtensionsMenu>(
      browser, contents, controller.extensionsButton));
  ArktExtensionsMenu* menu = ExtensionsMenus().back().get();
  controller.extensionsButtonAction = ^{
    menu->Show();
  };
  const base::CommandLine* command_line =
      base::CommandLine::ForCurrentProcess();
  menu->SetDump(command_line->HasSwitch("arkt-extensions-menu-dump"));
  std::string demo_id =
      command_line->GetSwitchValueASCII("arkt-extensions-demo");
  if (!demo_id.empty() && demo_id != "list") {
    menu->RunActionWhenAvailable(demo_id);
  }
  LOG(WARNING) << "ARKT: mounted active tab after " << attempt + 1
               << " attempt(s)";
}

}  // namespace

ArktBrowserMainExtraParts::ArktBrowserMainExtraParts() = default;
ArktBrowserMainExtraParts::~ArktBrowserMainExtraParts() = default;

void ArktBrowserMainExtraParts::PostBrowserStart() {
  LOG(WARNING) << "ARKT: in-process hook alive";
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&MountActiveTab, 0));
}

}  // namespace arkt
