#include "arkt/api/arkt_reentrancy_probe.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <optional>
#include <string>
#include <vector>

#include "arkt/browser/arkt_browser_window.h"
#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/current_thread.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
// //chrome/browser/ui reaches //arkt through //chrome/browser, so this
// target cannot depend on it; the symbol is in the same framework.
#include "chrome/browser/ui/browser_tabstrip.h"  // nogncheck
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "url/gurl.h"

namespace arkt {
namespace {

NSString* const kPhaseNotification = @"ArktReentrancyProbePhase";

constexpr base::TimeDelta kHeartbeat = base::Milliseconds(20);
// How long the engine keeps a menu or alert it opened.
constexpr NSTimeInterval kOpenFor = 2.0;
constexpr base::TimeDelta kBetweenPhases = base::Seconds(2);
constexpr base::TimeDelta kActivationLead = base::Milliseconds(500);
// Phases whose nested loop Swift opens end after this long.
constexpr base::TimeDelta kSwiftPhaseLength = base::Milliseconds(3500);

const char kProbeTabURL[] =
    "data:text/html,<title>W3-3 probe tab</title><h1>W3-3 probe tab</h1>";

ArktBrowserWindow* ProbeWindow() {
  BrowserWindowInterface* browser =
      GlobalBrowserCollection::GetInstance()->GetLastActiveBrowser();
  return browser ? ArktBrowserWindow::FromBrowser(browser) : nullptr;
}

class Probe {
 public:
  void Start() {
    LOG(WARNING) << "ARKT: probe start";
    last_beat_ = base::TimeTicks::Now();
    heartbeat_.Start(FROM_HERE, kHeartbeat,
                     base::BindRepeating(&Probe::Beat, base::Unretained(this)));
    phases_ = {
        {"menu-in-chromium-task", true,
         base::BindRepeating(&Probe::OpenMenu, base::Unretained(this), false)},
        {"menu-in-chromium-task-tasks-allowed", true,
         base::BindRepeating(&Probe::OpenMenu, base::Unretained(this), true)},
        {"alert-in-chromium-task", true,
         base::BindRepeating(&Probe::OpenAlert, base::Unretained(this))},
        {"swift-alert-inside-batch", true,
         base::BindRepeating(&Probe::AddTabThenEnd, base::Unretained(this),
                             base::Milliseconds(200))},
        {"batch-during-swift-alert", true,
         base::BindRepeating(&Probe::AddTabThenEnd, base::Unretained(this),
                             base::Milliseconds(800))},
    };
    ScheduleNext(base::TimeDelta());
  }

 private:
  struct Phase {
    std::string name;
    bool needs_frontmost;
    base::RepeatingClosure run;
  };

  void Beat() {
    base::TimeTicks now = base::TimeTicks::Now();
    max_gap_ = std::max(max_gap_, now - last_beat_);
    last_beat_ = now;
  }

  void ScheduleNext(base::TimeDelta delay) {
    if (next_ >= phases_.size()) {
      heartbeat_.Stop();
      [NSApp deactivate];
      LOG(WARNING) << "ARKT: probe done";
      return;
    }
    base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
        FROM_HERE, base::BindOnce(&Probe::Activate, base::Unretained(this)),
        delay);
  }

  void Activate() {
    if (phases_[next_].needs_frontmost) {
      [NSApp activateIgnoringOtherApps:YES];
    }
    base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
        FROM_HERE, base::BindOnce(&Probe::RunPhase, base::Unretained(this)),
        kActivationLead);
  }

  void RunPhase() {
    const Phase& phase = phases_[next_++];
    phase_ = phase.name;
    phase_start_ = base::TimeTicks::Now();
    Beat();
    max_gap_ = base::TimeDelta();
    LOG(WARNING) << "ARKT: probe " << phase_ << " begin (app active "
                 << (NSApp.isActive ? "yes" : "no") << ")";
    Notify(@"begin");
    phase.run.Run();
  }

  void End() {
    Beat();
    LOG(WARNING) << "ARKT: probe " << phase_ << " end after "
                 << (base::TimeTicks::Now() - phase_start_).InMilliseconds()
                 << " ms; Chromium task heartbeat max gap "
                 << max_gap_.InMilliseconds() << " ms";
    Notify(@"end");
    ScheduleNext(kBetweenPhases);
  }

  void Notify(NSString* step) {
    [NSNotificationCenter.defaultCenter
        postNotificationName:kPhaseNotification
                      object:nil
                    userInfo:@{
                      @"phase" : base::SysUTF8ToNSString(phase_),
                      @"step" : step
                    }];
  }

  // A common-mode run-loop timer fires in tracking and modal modes whatever
  // else is blocked, so the close never depends on Chromium tasks.
  static void AfterOpenTime(void (^body)(void)) {
    NSTimer* timer = [NSTimer timerWithTimeInterval:kOpenFor
                                            repeats:NO
                                              block:^(NSTimer*) {
                                                body();
                                              }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
  }

  void OpenMenu(bool allow_application_tasks) {
    ArktBrowserWindow* window = ProbeWindow();
    if (!window) {
      LOG(ERROR) << "ARKT: probe " << phase_ << " has no window";
      End();
      return;
    }
    NSView* view = window->host().window.contentView;
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Arkt probe"];
    [menu addItemWithTitle:@"Probe item" action:nil keyEquivalent:@""];
    AfterOpenTime(^{
      [menu cancelTracking];
    });
    {
      std::optional<
          base::CurrentThread::ScopedAllowApplicationTasksInNativeNestedLoop>
          allow;
      if (allow_application_tasks) {
        allow.emplace();
      }
      [menu popUpMenuPositioningItem:nil
                          atLocation:NSMakePoint(NSMidX(view.bounds),
                                                 NSMidY(view.bounds))
                              inView:view];
    }
    End();
  }

  void OpenAlert() {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"W3-3 probe";
    AfterOpenTime(^{
      [NSApp stopModal];
      // stopModal takes effect once the modal loop handles an event.
      NSEvent* wake = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                         location:NSZeroPoint
                                    modifierFlags:0
                                        timestamp:0
                                     windowNumber:0
                                          context:nil
                                          subtype:0
                                            data1:0
                                            data2:0];
      [NSApp postEvent:wake atStart:YES];
    });
    [alert runModal];
    End();
  }

  // The engine adds a tab after `delay` (an engine-origin TabCreated batch);
  // the Swift half decides what runs around it.
  void AddTabThenEnd(base::TimeDelta delay) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
        FROM_HERE, base::BindOnce(&Probe::AddTab, base::Unretained(this)),
        delay);
    base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
        FROM_HERE, base::BindOnce(&Probe::End, base::Unretained(this)),
        kSwiftPhaseLength);
  }

  void AddTab() {
    ArktBrowserWindow* window = ProbeWindow();
    if (!window) {
      LOG(ERROR) << "ARKT: probe " << phase_ << " has no window for a tab";
      return;
    }
    LOG(WARNING) << "ARKT: probe " << phase_ << " engine adds a tab";
    chrome::AddTabAt(window->browser(), GURL(kProbeTabURL), -1, false);
  }

  std::vector<Phase> phases_;
  size_t next_ = 0;
  std::string phase_;
  base::TimeTicks phase_start_;
  base::RepeatingTimer heartbeat_;
  base::TimeTicks last_beat_;
  base::TimeDelta max_gap_;
};

}  // namespace

void StartReentrancyProbe() {
  static base::NoDestructor<Probe> probe;
  probe->Start();
}

}  // namespace arkt
