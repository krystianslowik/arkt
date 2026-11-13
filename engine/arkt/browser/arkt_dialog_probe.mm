#import "arkt/browser/arkt_dialog_probe.h"

#import <AppKit/AppKit.h>

#include <memory>
#include <string>
#include <vector>

#import "arkt/browser/arkt_infobar_view.h"
#include "base/files/file_path.h"
#include "base/functional/callback_helpers.h"
#include "base/logging.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/stringprintf.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/profiles/profile.h"
#include "components/constrained_window/constrained_window_views.h"
#include "components/infobars/content/content_infobar_manager.h"
#include "components/infobars/core/confirm_infobar_delegate.h"
#include "components/infobars/core/infobar.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/models/dialog_model.h"

namespace arkt {

namespace {

// A plain confirm infobar, drawn by ArktInfobarPresenter as any other.
class TestInfobarDelegate : public ConfirmInfoBarDelegate {
 public:
  explicit TestInfobarDelegate(int number) : number_(number) {}

  infobars::InfoBarDelegate::InfoBarIdentifier GetIdentifier() const override {
    return TEST_INFOBAR;
  }
  std::u16string GetMessageText() const override {
    return u"Arkt test infobar " + base::NumberToString16(number_);
  }
  int GetButtons() const override { return BUTTON_OK; }
  bool ShouldExpire(const NavigationDetails& details) const override {
    return false;
  }

 private:
  const int number_;
};

std::string ScreenRect(NSRect rect) {
  return base::StringPrintf("%d,%d %dx%d", static_cast<int>(NSMinX(rect)),
                            static_cast<int>(NSMinY(rect)),
                            static_cast<int>(NSWidth(rect)),
                            static_cast<int>(NSHeight(rect)));
}

NSRect OnScreen(NSView* view) {
  return [view.window convertRectToScreen:[view convertRect:view.bounds
                                                     toView:nil]];
}

}  // namespace

void SetTestInfobarsForSelfTest(content::WebContents* contents, int count) {
  auto* manager =
      contents ? infobars::ContentInfoBarManager::FromWebContents(contents)
               : nullptr;
  if (!manager) {
    LOG(WARNING) << "ARKT selftest infobars: no infobar manager";
    return;
  }
  std::vector<infobars::InfoBar*> old;
  for (infobars::InfoBar* infobar : manager->infobars()) {
    if (infobar->delegate()->GetIdentifier() ==
        infobars::InfoBarDelegate::TEST_INFOBAR) {
      old.push_back(infobar);
    }
  }
  for (infobars::InfoBar* infobar : old) {
    manager->RemoveInfoBar(infobar);
  }
  for (int i = 1; i <= count; ++i) {
    manager->AddInfoBar(std::make_unique<infobars::InfoBar>(
        std::make_unique<TestInfobarDelegate>(i)));
  }
  LOG(WARNING) << "ARKT selftest infobars removed=" << old.size()
               << " added=" << count << " now=" << manager->infobars().size();
}

void ShowTabModalForSelfTest(content::WebContents* contents) {
  if (!contents) {
    return;
  }
  views::Widget* widget = constrained_window::ShowWebModal(
      ui::DialogModel::Builder()
          .SetTitle(u"Arkt tab-modal probe")
          .AddParagraph(ui::DialogModelLabel(
              u"A Chromium tab-modal dialog, shown as the extension dialogs "
              u"are."))
          .AddOkButton(base::DoNothing())
          .Build(),
      contents);
  LOG(WARNING) << "ARKT selftest tab-modal shown=" << (widget ? "yes" : "no");
}

void LogDialogGeometryForSelfTest(content::WebContents* contents) {
  NSView* page = contents ? contents->GetNativeView().GetNativeNSView() : nil;
  NSWindow* window = page.window;
  if (!window) {
    LOG(WARNING) << "ARKT selftest geometry: the page is not in a window";
    return;
  }
  ArktInfobarStackView* stack = nil;
  for (NSView* view in page.superview.subviews) {
    if ([view isKindOfClass:[ArktInfobarStackView class]]) {
      stack = static_cast<ArktInfobarStackView*>(view);
    }
  }
  const NSRect page_rect = OnScreen(page);
  const NSRect holder_rect = OnScreen(page.superview);
  LOG(WARNING) << "ARKT selftest geometry window " << window.windowNumber
               << " rows=" << (stack ? stack.rows.count : 0)
               << " rows hidden (shell draws them)="
               << (stack.hidden ? "yes" : "no") << " rows frame "
               << (stack ? ScreenRect(OnScreen(stack)) : "none") << " page "
               << ScreenRect(page_rect) << " holder "
               << ScreenRect(holder_rect);
  for (NSWindow* child in window.childWindows) {
    const NSRect frame = child.frame;
    // Screen points grow upwards: below the rows means a top edge at or
    // under the page's top edge (the rows' bottom edge).
    const bool below = NSMaxY(frame) <= NSMaxY(page_rect) + 0.5;
    const double centre_offset = NSMidX(frame) - NSMidX(holder_rect);
    LOG(WARNING) << "ARKT selftest geometry child window " << child.windowNumber
                 << " "
                 << base::SysNSStringToUTF8(NSStringFromClass([child class]))
                 << " visible=" << (child.visible ? "yes" : "no") << " frame "
                 << ScreenRect(frame) << " top=" << NSMaxY(frame)
                 << " page_top=" << NSMaxY(page_rect)
                 << " gap=" << NSMaxY(page_rect) - NSMaxY(frame)
                 << " centre_offset=" << centre_offset
                 << " below_rows=" << (below ? "yes" : "no");
  }
  if (NSWindow* sheet = window.attachedSheet) {
    LOG(WARNING) << "ARKT selftest geometry sheet " << sheet.windowNumber << " "
                 << base::SysNSStringToUTF8(NSStringFromClass([sheet class]))
                 << " frame " << ScreenRect(sheet.frame);
  }
}

void SetFileChooserFolderForSelfTest(content::WebContents* contents,
                                     const base::FilePath& folder) {
  if (!contents || folder.empty()) {
    return;
  }
  Profile::FromBrowserContext(contents->GetBrowserContext())
      ->set_last_selected_directory(folder);
  LOG(WARNING) << "ARKT selftest file chooser folder " << folder.value();
}

void CheckFilePanelsForSelfTest(content::WebContents* contents) {
  NSView* page = contents ? contents->GetNativeView().GetNativeNSView() : nil;
  NSWindow* tab_window = page.window;
  int panels = 0;
  for (NSWindow* window in [NSApp.windows copy]) {
    if (![window isKindOfClass:[NSSavePanel class]] || !window.visible) {
      continue;
    }
    ++panels;
    NSSavePanel* panel = static_cast<NSSavePanel*>(window);
    NSWindow* parent = panel.sheetParent;
    LOG(WARNING) << "ARKT selftest file panel "
                 << base::SysNSStringToUTF8(NSStringFromClass([panel class]))
                 << " window " << panel.windowNumber
                 << " sheet=" << (panel.sheet ? "yes" : "no") << " parent "
                 << (parent ? parent.windowNumber : -1) << " tab window "
                 << tab_window.windowNumber << " attached to tab window="
                 << (tab_window && tab_window.attachedSheet == panel ? "yes"
                                                                     : "no")
                 << " app modal=" << (NSApp.modalWindow == panel ? "yes" : "no")
                 << " folder "
                 << base::SysNSStringToUTF8(panel.directoryURL.path);
    [panel cancel:nil];
  }
  LOG(WARNING) << "ARKT selftest file panels=" << panels << " (cancelled)";
}

}  // namespace arkt
