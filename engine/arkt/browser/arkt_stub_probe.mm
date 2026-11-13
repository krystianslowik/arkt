#import "arkt/browser/arkt_stub_probe.h"

#import <AppKit/AppKit.h>

#include <map>
#include <memory>
#include <optional>
#include <vector>

#include "arkt/browser/arkt_browser_window.h"
#include "base/files/file_path.h"
#include "base/functional/callback_helpers.h"
#include "base/logging.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/download/download_core_service.h"          // nogncheck
#include "chrome/browser/download/download_core_service_factory.h"  // nogncheck
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_tabstrip.h"  // nogncheck
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_bubble_type.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_context.h"
#include "chrome/browser/ui/find_bar/find_bar.h"
#include "chrome/browser/ui/location_bar/location_bar.h"
#include "chrome/browser/ui/side_panel/side_panel_entry_id.h"
#include "chrome/browser/ui/side_panel/side_panel_entry_key.h"
#include "chrome/browser/ui/side_panel/side_panel_ui.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/download/public/common/download_url_parameters.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/download_manager.h"
#include "content/public/browser/web_contents.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"

namespace arkt {

namespace {

BrowserWindowInterface* BrowserOf(content::WebContents* contents) {
  tabs::TabInterface* tab =
      contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  return tab ? tab->GetBrowserWindowInterface() : nullptr;
}

int DownloadsOf(Profile* profile) {
  DownloadCoreService* service =
      DownloadCoreServiceFactory::GetForBrowserContext(profile);
  return service ? service->BlockingShutdownCount() : -1;
}

// The open incognito windows of `profile`'s original profile.
std::vector<BrowserWindowInterface*> IncognitoWindowsOf(Profile* profile) {
  std::vector<BrowserWindowInterface*> found;
  Profile* original = profile->GetOriginalProfile();
  GlobalBrowserCollection::GetInstance()->ForEach(
      [&](BrowserWindowInterface* each) {
        Profile* each_profile = each->GetProfile();
        if (each_profile->IsOffTheRecord() &&
            each_profile->GetOriginalProfile() == original) {
          found.push_back(each);
        }
        return true;
      });
  return found;
}

constexpr net::NetworkTrafficAnnotationTag kSelfTestDownloadAnnotation =
    net::DefineNetworkTrafficAnnotation("arkt_selftest_download", R"(
      semantics {
        sender: "Arkt self-test"
        description:
          "Self-test only (--arkt-facade-selftest): a download from a local "
          "fixture server, to check closing an incognito window while it runs."
        trigger: "A self-test command."
        data: "The URL of the fixture download."
        destination: LOCAL
      }
      policy {
        cookies_allowed: NO
        setting: "Only in self-test runs."
        policy_exception_justification: "Test only."
      })");

void Called(const char* name) {
  LOG(WARNING) << "ARKT selftest stub-call " << name << " returned";
}

}  // namespace

void CallStubsForSelfTest(content::WebContents* contents) {
  BrowserWindowInterface* browser = BrowserOf(contents);
  ArktBrowserWindow* window =
      browser ? ArktBrowserWindow::FromBrowser(browser) : nullptr;
  if (!window) {
    LOG(WARNING) << "ARKT selftest stubs: no Arkt window";
    return;
  }
  const GURL url = contents->GetLastCommittedURL();

  // BrowserWindow (arkt_browser_window.mm). OpenEyeDropper and
  // ConfirmBrowserCloseWithPendingDownloads are no longer stubs (#589).
  window->Deactivate();
  Called("Deactivate");
  window->DisableTabStripEditingForTesting();
  Called("DisableTabStripEditingForTesting");
  window->SetFocusToLocationBar(/*is_user_initiated=*/true);
  Called("SetFocusToLocationBar");
  window->FocusToolbar();
  Called("FocusToolbar");
  window->FocusAppMenu();
  Called("FocusAppMenu");
  window->ShowUpdateChromeDialog();
  Called("ShowUpdateChromeDialog");
  window->ShowIntentPickerBubble({}, /*show_stay_in_chrome=*/true,
                                 /*show_remember_selection=*/true,
                                 apps::IntentPickerBubbleType::kLinkCapturing,
                                 std::nullopt, base::DoNothing());
  Called("ShowIntentPickerBubble");
  window->ShowBookmarkBubble(url, /*already_bookmarked=*/false);
  Called("ShowBookmarkBubble");
  ShowTranslateBubbleResult translate = window->ShowTranslateBubble(
      contents, translate::TRANSLATE_STEP_BEFORE_TRANSLATE, "fr", "en",
      translate::TranslateErrors::NONE, /*is_user_gesture=*/true);
  LOG(WARNING) << "ARKT selftest stub-call ShowTranslateBubble returned "
               << static_cast<int>(translate);
  window->ShowAppMenu();
  Called("ShowAppMenu");
  window->ShowAvatarBubbleFromAvatarButton(/*is_source_accelerator=*/true);
  Called("ShowAvatarBubbleFromAvatarButton");
  window->ShowHatsDialog("arkt-selftest", std::nullopt, std::nullopt,
                         base::DoNothing(), base::DoNothing(), {}, {});
  Called("ShowHatsDialog");
  window->ShowCaretBrowsingDialog();
  Called("ShowCaretBrowsingDialog");
  window->CreateTabSearchBubble();
  Called("CreateTabSearchBubble");
  window->ShowIncognitoClearBrowsingDataDialog();
  Called("ShowIncognitoClearBrowsingDataDialog");
  window->ShowIncognitoHistoryDisclaimerDialog();
  Called("ShowIncognitoHistoryDisclaimerDialog");
  window->ShowChromeLabs();
  Called("ShowChromeLabs");

  // The window's parts (arkt_browser_window_parts.mm).
  ExclusiveAccessBubbleParams params;
  params.type =
      EXCLUSIVE_ACCESS_BUBBLE_TYPE_BROWSER_FULLSCREEN_EXIT_INSTRUCTION;
  bool hidden_reported = false;
  window->GetExclusiveAccessContext()->UpdateExclusiveAccessBubble(
      params,
      base::BindOnce([](bool* reported,
                        ExclusiveAccessBubbleHideReason) { *reported = true; },
                     &hidden_reported));
  LOG(WARNING) << "ARKT selftest stub-call UpdateExclusiveAccessBubble "
                  "returned hide_callback_run="
               << (hidden_reported ? "yes" : "no");
  LocationBar* location_bar = window->GetLocationBar();
  location_bar->FocusLocation(/*is_user_initiated=*/true,
                              /*clear_focus_if_failed=*/false);
  Called("LocationBar::FocusLocation");
  location_bar->FocusSearch();
  Called("LocationBar::FocusSearch");
  LOG(WARNING) << "ARKT selftest stub-call LocationBar::GetChipController "
                  "returned "
               << (location_bar->GetChipController() ? "non-null" : "null");
  std::unique_ptr<FindBar> find_bar = window->CreateFindBar();
  find_bar->Show(/*animate=*/false, /*focus=*/true);
  find_bar->Hide(/*animate=*/false);
  Called("FindBar::Show");
  SidePanelUI* side_panel = SidePanelUI::From(browser);
  if (side_panel) {
    side_panel->Show(SidePanelEntryId::kReadAnything, std::nullopt,
                     /*suppress_animations=*/true);
    Called("SidePanelUI::Show(id)");
    const SidePanelEntryKey key(SidePanelEntryId::kBookmarks);
    side_panel->Show(key, std::nullopt, /*suppress_animations=*/true);
    Called("SidePanelUI::Show(key)");
    side_panel->ShowFrom(key, gfx::Rect(0, 0, 10, 10));
    Called("SidePanelUI::ShowFrom");
    side_panel->Toggle(key, SidePanelOpenTrigger::kToolbarButton);
    Called("SidePanelUI::Toggle");
  } else {
    LOG(WARNING) << "ARKT selftest stubs: no SidePanelUI";
  }
  LOG(WARNING) << "ARKT selftest stubs done tab alive="
               << (contents->IsCrashed() ? "no" : "yes");
}

void RunStubCommandForSelfTest(content::WebContents* contents,
                               const std::string& name) {
  BrowserWindowInterface* browser = BrowserOf(contents);
  if (!browser) {
    LOG(WARNING) << "ARKT selftest stub-command: no window";
    return;
  }
  const std::map<std::string, int> kCommands = {
      {"focus-location", IDC_FOCUS_LOCATION},
      {"focus-search", IDC_FOCUS_SEARCH},
      {"focus-toolbar", IDC_FOCUS_TOOLBAR},
      {"focus-menu-bar", IDC_FOCUS_MENU_BAR},
      {"app-menu", IDC_SHOW_APP_MENU},
      {"bookmark", IDC_BOOKMARK_THIS_TAB},
      {"tab-search", IDC_TAB_SEARCH},
      {"avatar", IDC_SHOW_AVATAR_MENU},
      {"caret", IDC_CARET_BROWSING_TOGGLE},
      {"translate", IDC_SHOW_TRANSLATE},
      {"find", IDC_FIND},
      {"chrome-labs", IDC_SHOW_CHROME_LABS},
      {"upgrade", IDC_UPGRADE_DIALOG},
      {"reading-mode", IDC_SHOW_READING_MODE_SIDE_PANEL},
      {"incognito-window", IDC_NEW_INCOGNITO_WINDOW},
  };
  auto it = kCommands.find(name);
  if (it == kCommands.end()) {
    LOG(WARNING) << "ARKT selftest stub-command " << name << " unknown";
    return;
  }
  const bool supported = chrome::SupportsCommand(browser, it->second);
  const bool enabled = chrome::IsCommandEnabled(browser, it->second);
  LOG(WARNING) << "ARKT selftest stub-command " << name << " id=" << it->second
               << " supported=" << (supported ? "yes" : "no")
               << " enabled=" << (enabled ? "yes" : "no");
  if (enabled) {
    chrome::ExecuteCommand(browser, it->second);
  }
  LOG(WARNING) << "ARKT selftest stub-command " << name
               << " done tab alive=" << (contents->IsCrashed() ? "no" : "yes");
}

void OpenIncognitoForSelfTest(content::WebContents* contents, const GURL& url) {
  BrowserWindowInterface* browser = BrowserOf(contents);
  if (!browser) {
    LOG(WARNING) << "ARKT selftest incognito: no window";
    return;
  }
  Profile* incognito =
      browser->GetProfile()->GetOriginalProfile()->GetPrimaryOTRProfile(
          /*create_if_needed=*/true);
  BrowserWindowInterface* window = chrome::OpenEmptyWindow(
      incognito, /*should_trigger_session_restore=*/false);
  if (!window) {
    LOG(WARNING) << "ARKT selftest incognito: no window created";
    return;
  }
  chrome::AddSelectedTabWithURL(window, url, ui::PAGE_TRANSITION_TYPED);
  LOG(WARNING) << "ARKT selftest incognito opened arkt_window="
               << (ArktBrowserWindow::FromBrowser(window) ? "yes" : "no")
               << " tabs=" << window->GetTabStripModel()->count();
}

void StartIncognitoDownloadForSelfTest(content::WebContents* contents,
                                       const GURL& url,
                                       const std::string& file) {
  BrowserWindowInterface* browser = BrowserOf(contents);
  if (!browser || file.empty()) {
    LOG(WARNING) << "ARKT selftest incognito-download: no window or file";
    return;
  }
  Profile* incognito =
      browser->GetProfile()->GetOriginalProfile()->GetPrimaryOTRProfile(
          /*create_if_needed=*/true);
  auto parameters = std::make_unique<download::DownloadUrlParameters>(
      url, kSelfTestDownloadAnnotation);
  parameters->set_file_path(base::FilePath(file));
  incognito->GetDownloadManager()->DownloadUrl(
      std::move(parameters), /*blob_url_loader_factory=*/nullptr);
  LOG(WARNING) << "ARKT selftest incognito-download started";
}

void CloseIncognitoForSelfTest(content::WebContents* contents) {
  BrowserWindowInterface* browser = BrowserOf(contents);
  if (!browser) {
    LOG(WARNING) << "ARKT selftest incognito-close: no window";
    return;
  }
  std::vector<BrowserWindowInterface*> windows =
      IncognitoWindowsOf(browser->GetProfile());
  LOG(WARNING) << "ARKT selftest incognito-close windows=" << windows.size();
  for (BrowserWindowInterface* window : windows) {
    LOG(WARNING) << "ARKT selftest incognito-close downloads="
                 << DownloadsOf(window->GetProfile());
    window->GetWindow()->Close();
  }
}

void LogIncognitoForSelfTest(content::WebContents* contents) {
  BrowserWindowInterface* browser = BrowserOf(contents);
  if (!browser) {
    LOG(WARNING) << "ARKT selftest incognito-state: no window";
    return;
  }
  std::vector<BrowserWindowInterface*> windows =
      IncognitoWindowsOf(browser->GetProfile());
  Profile* original = browser->GetProfile()->GetOriginalProfile();
  Profile* incognito = original->HasPrimaryOTRProfile()
                           ? original->GetPrimaryOTRProfile(
                                 /*create_if_needed=*/false)
                           : nullptr;
  LOG(WARNING) << "ARKT selftest incognito-state windows=" << windows.size()
               << " downloads=" << (incognito ? DownloadsOf(incognito) : 0);
  for (BrowserWindowInterface* window : windows) {
    ArktBrowserWindow* arkt_window = ArktBrowserWindow::FromBrowser(window);
    LOG(WARNING) << "ARKT selftest incognito-state window closing="
                 << (arkt_window && arkt_window->IsAttemptingToClose() ? "yes"
                                                                       : "no")
                 << " visible="
                 << (window->GetWindow()->IsVisible() ? "yes" : "no")
                 << " tabs=" << window->GetTabStripModel()->count();
  }
}

}  // namespace arkt
