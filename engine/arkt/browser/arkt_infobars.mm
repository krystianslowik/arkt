#include "arkt/browser/arkt_infobars.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <string>

#import "arkt/browser/arkt_infobar_view.h"
#include "base/feature_list.h"
#include "base/i18n/rtl.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/ui/ui_features.h"
#include "components/infobars/content/content_infobar_manager.h"
#include "components/infobars/core/confirm_infobar_delegate.h"
#include "components/infobars/core/infobar.h"
#include "components/infobars/core/infobar_delegate.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/cocoa/cocoa_base_utils.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/models/image_model.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_util_mac.h"
#include "components/strings/grit/components_strings.h"

namespace arkt {
namespace {

// What the click asked for (Cmd or middle click: a new tab), as Views
// derives it from the event flags.
WindowOpenDisposition CurrentDisposition() {
  NSEvent* event = NSApp.currentEvent;
  return event ? ui::WindowOpenDispositionFromNSEvent(event)
               : WindowOpenDisposition::CURRENT_TAB;
}

InfobarSink& Sink() {
  static base::NoDestructor<InfobarSink> sink;
  return *sink;
}

uint64_t NextInfobarId() {
  static uint64_t next_id = 0;
  return ++next_id;
}

InfobarKind KindFor(infobars::InfoBarDelegate::InfoBarIdentifier identifier) {
  switch (identifier) {
    case infobars::InfoBarDelegate::EXTENSION_DEV_TOOLS_INFOBAR_DELEGATE:
    case infobars::InfoBarDelegate::DEV_TOOLS_INFOBAR_DELEGATE:
    case infobars::InfoBarDelegate::DEV_TOOLS_REMOTE_DEBUGGING_INFOBAR_DELEGATE:
      return InfobarKind::kDebugger;
    case infobars::InfoBarDelegate::AUTOMATION_INFOBAR_DELEGATE:
      return InfobarKind::kAutomation;
    case infobars::InfoBarDelegate::PAGE_INFO_INFOBAR_DELEGATE:
      return InfobarKind::kReload;
    default:
      return InfobarKind::kOther;
  }
}

ArktInfobarButton* ButtonFor(ConfirmInfoBarDelegate* delegate,
                             ConfirmInfoBarDelegate::InfoBarButton type) {
  if (!(delegate->GetButtons() & type)) {
    return nil;
  }
  ArktInfobarButton* button = [[ArktInfobarButton alloc] init];
  button.title = base::SysUTF16ToNSString(delegate->GetButtonLabel(type));
  button.tooltip = base::SysUTF16ToNSString(delegate->GetButtonTooltip(type));
  button.enabled = delegate->GetButtonEnabled(type);
  // As ConfirmInfoBar: OK, or the only button, is the prominent one unless
  // the delegate says otherwise.
  const bool is_default = type == delegate->GetButtons() ||
                          type == ConfirmInfoBarDelegate::BUTTON_OK;
  ui::ButtonStyle style = delegate->GetButtonStyle(type).value_or(
      is_default ? ui::ButtonStyle::kProminent : ui::ButtonStyle::kTonal);
  button.prominent = style == ui::ButtonStyle::kProminent;
  return button;
}

ArktInfobarContent* ContentFor(ConfirmInfoBarDelegate* delegate,
                               const ui::ColorProvider* color_provider) {
  ArktInfobarContent* content = [[ArktInfobarContent alloc] init];
  // As ConfirmInfoBar::Create: the template with inline links when the
  // delegate has one and the feature is on, else the plain message.
  std::u16string message;
  NSMutableArray<NSValue*>* links = [NSMutableArray array];
  const std::u16string message_template = delegate->GetMessageTextTemplate();
  if (!message_template.empty() &&
      base::FeatureList::IsEnabled(features::kInfoBarInlineLinks)) {
    const std::vector<MessageSubstitution>& substitutions =
        delegate->GetMessageSubstitutions();
    std::vector<std::u16string> strings;
    for (const auto& substitution : substitutions) {
      strings.push_back(substitution.text);
    }
    std::vector<size_t> offsets;
    message =
        base::ReplaceStringPlaceholders(message_template, strings, &offsets);
    for (size_t i = 0; i < offsets.size() && i < substitutions.size(); ++i) {
      // Every substitution keeps its index, so a click reports the index
      // InlineSubstitutionLinkClicked expects; plain text gets an empty range.
      NSRange range = substitutions[i].is_link
                          ? NSMakeRange(offsets[i], substitutions[i].text.size())
                          : NSMakeRange(NSNotFound, 0);
      [links addObject:[NSValue valueWithRange:range]];
    }
  } else {
    message = delegate->GetMessageText();
  }
  content.message = base::SysUTF16ToNSString(message);
  content.messageLinkRanges = links;

  ui::ImageModel icon = delegate->GetIcon();
  if (!icon.IsEmpty() && color_provider) {
    gfx::ImageSkia image = icon.Rasterize(color_provider);
    if (!image.isNull()) {
      content.icon = gfx::NSImageFromImageSkia(image);
    }
  }

  const std::u16string link = delegate->GetLinkText();
  if (!link.empty()) {
    content.linkTitle = base::SysUTF16ToNSString(link);
    if (std::optional<std::u16string> label =
            delegate->GetLinkAccessibleText()) {
      content.linkAccessibilityLabel = base::SysUTF16ToNSString(*label);
    }
    content.linkBeforeButtons = delegate->ShouldShowLinkBeforeButton();
  }
  content.okButton = ButtonFor(delegate, ConfirmInfoBarDelegate::BUTTON_OK);
  content.cancelButton =
      ButtonFor(delegate, ConfirmInfoBarDelegate::BUTTON_CANCEL);
  if (delegate->IsCloseable()) {
    content.closeAccessibilityLabel =
        l10n_util::GetNSString(IDS_ACCNAME_CLOSE);
  }
  content.rightToLeft = base::i18n::IsRTL();
  content.identifier = [NSString
      stringWithFormat:@"infobar-%d", static_cast<int>(
                                          delegate->GetIdentifier())];
  return content;
}

}  // namespace

void SetInfobarSink(InfobarSink sink) {
  Sink() = std::move(sink);
}

ArktInfobarPresenter::ArktInfobarPresenter(
    content::WebContents* contents,
    base::RepeatingCallback<const ui::ColorProvider*()> color_provider,
    base::RepeatingClosure layout_changed)
    : manager_(infobars::ContentInfoBarManager::FromWebContents(contents)),
      contents_(contents ? contents->GetWeakPtr() : nullptr),
      color_provider_(std::move(color_provider)),
      layout_changed_(std::move(layout_changed)),
      stack_([[ArktInfobarStackView alloc] initWithFrame:NSZeroRect]) {
  if (!manager_) {
    return;
  }
  manager_->AddObserver(this);
  // Infobars added before the tab reached this window (a tab moved here
  // from another window, or created in the background).
  for (infobars::InfoBar* infobar : manager_->infobars()) {
    OnInfoBarAdded(infobar);
  }
}

ArktInfobarPresenter::~ArktInfobarPresenter() {
  if (manager_) {
    manager_->RemoveObserver(this);
  }
  [stack_ removeFromSuperview];
}

void ArktInfobarPresenter::OnInfoBarAdded(infobars::InfoBar* infobar) {
  // The manager appends; place the row at the infobar's place in it.
  size_t index = 0;
  for (infobars::InfoBar* other : manager_->infobars()) {
    if (other == infobar) {
      break;
    }
    for (const auto& row : rows_) {
      if (row.infobar == other) {
        ++index;
        break;
      }
    }
  }
  Add(infobar, index);
}

void ArktInfobarPresenter::Add(infobars::InfoBar* infobar, size_t index) {
  infobars::InfoBarDelegate* delegate = infobar->delegate();
  ConfirmInfoBarDelegate* confirm = delegate->AsConfirmInfoBarDelegate();
  if (!confirm) {
    // Tab sharing and the alternate-URL bar have their own Views; they are
    // recorded gaps (issue #122).
    LOG(WARNING) << "ARKT: infobar " << delegate->GetIdentifier()
                 << " not drawn (not a confirm infobar)";
    return;
  }
  ArktInfobarContent* content = ContentFor(
      confirm, color_provider_ ? color_provider_.Run() : nullptr);
  ArktInfobarView* row = [[ArktInfobarView alloc] initWithContent:content];
  base::WeakPtr<ArktInfobarPresenter> weak = weak_factory_.GetWeakPtr();
  // The pointer is only used while the row exists, and the row goes in
  // OnInfoBarRemoved, before the infobar is deleted; Act checks it again.
  infobars::InfoBar* raw = infobar;
  row.onOk = ^{
    if (weak) {
      weak->Act(raw, Action::kOk, 0);
    }
  };
  row.onCancel = ^{
    if (weak) {
      weak->Act(raw, Action::kCancel, 0);
    }
  };
  row.onLink = ^{
    if (weak) {
      weak->Act(raw, Action::kLink, 0);
    }
  };
  row.onMessageLink = ^(NSUInteger link_index) {
    if (weak) {
      weak->Act(raw, Action::kMessageLink, link_index);
    }
  };
  row.onClose = ^{
    if (weak) {
      weak->Act(raw, Action::kClose, 0);
    }
  };
  index = std::min(index, rows_.size());
  rows_.insert(rows_.begin() + index,
               Row{infobar, row, NextInfobarId(),
                   KindFor(delegate->GetIdentifier()), content});
  [stack_ insertRow:row atIndex:index];
  LOG(WARNING) << "ARKT: infobar " << confirm->GetIdentifier() << " shown"
               << " buttons=" << confirm->GetButtons()
               << " link=" << !confirm->GetLinkText().empty()
               << " closeable=" << confirm->IsCloseable()
               << " substitutions=" << content.messageLinkRanges.count
               << " icon=" << (content.icon != nil) << " rows=" << rows_.size()
               << " message=\"" << base::SysNSStringToUTF8(content.message)
               << "\"";
  Publish();
  layout_changed_.Run();
}

// The list the shell presents: the drawn infobars in the manager's order.
std::vector<PresentedInfobar> ArktInfobarPresenter::Presented() const {
  std::vector<PresentedInfobar> list;
  for (const Row& row : rows_) {
    PresentedInfobar infobar;
    infobar.id = row.id;
    infobar.kind = row.kind;
    infobar.content = row.content;
    list.push_back(infobar);
  }
  return list;
}

bool ArktInfobarPresenter::Perform(uint64_t id,
                                   InfobarAction action,
                                   size_t link_index) {
  for (const Row& row : rows_) {
    if (row.id == id) {
      if (!row.infobar->owner()) {
        return false;
      }
      Act(row.infobar, action, link_index);
      return true;
    }
  }
  return false;
}

// Called after every change of the list. The sink (the facade) reports the
// whole list to the shell and says whether the shell presents it; then the
// rows stay but are not drawn, and the stack keeps its height so the page
// still sits below the strip the shell draws over it.
void ArktInfobarPresenter::Publish() {
  bool presented = false;
  const InfobarSink& sink = Sink();
  if (!sink.is_null() && contents_) {
    presented = sink.Run(contents_.get(), weak_factory_.GetWeakPtr());
  }
  presented_ = presented;
  stack_.hidden = presented;
}

int ArktInfobarPresenter::Remove(infobars::InfoBar* infobar) {
  for (size_t i = 0; i < rows_.size(); ++i) {
    if (rows_[i].infobar == infobar) {
      ArktInfobarView* row = rows_[i].view;
      rows_.erase(rows_.begin() + i);
      [stack_ removeRow:row];
      return static_cast<int>(i);
    }
  }
  return -1;
}

void ArktInfobarPresenter::OnInfoBarRemoved(infobars::InfoBar* infobar,
                                            bool animate) {
  if (Remove(infobar) < 0) {
    return;
  }
  LOG(WARNING) << "ARKT: infobar " << infobar->delegate()->GetIdentifier()
               << " removed rows=" << rows_.size();
  Publish();
  layout_changed_.Run();
}

void ArktInfobarPresenter::OnInfoBarReplaced(infobars::InfoBar* old_infobar,
                                             infobars::InfoBar* new_infobar) {
  int index = Remove(old_infobar);
  Add(new_infobar, index < 0 ? rows_.size() : static_cast<size_t>(index));
  if (index >= 0) {
    Publish();
    layout_changed_.Run();
  }
}

void ArktInfobarPresenter::OnManagerWillBeDestroyed(
    infobars::InfoBarManager* manager) {
  manager_->RemoveObserver(this);
  manager_ = nullptr;
  while (!rows_.empty()) {
    Remove(rows_.back().infobar);
  }
  // The contents are going away: no layout call (it would read their view);
  // the bar just leaves the view hierarchy.
  [stack_ removeFromSuperview];
}

// As ConfirmInfoBar::OkButtonPressed / CancelButtonPressed, InfoBarView's
// LinkClicked and CloseButtonPressed, and the styled label's link callback.
void ArktInfobarPresenter::Act(infobars::InfoBar* infobar,
                               Action action,
                               size_t link_index) {
  bool drawn = false;
  for (const auto& row : rows_) {
    drawn |= row.infobar == infobar;
  }
  // Not drawn any more, or closing: don't call anything, it might access the
  // owner.
  if (!drawn || !infobar->owner()) {
    return;
  }
  ConfirmInfoBarDelegate* delegate =
      infobar->delegate()->AsConfirmInfoBarDelegate();
  LOG(WARNING) << "ARKT: infobar " << delegate->GetIdentifier() << " "
               << (action == Action::kOk       ? "ok"
                   : action == Action::kCancel ? "cancel"
                   : action == Action::kLink   ? "link"
                   : action == Action::kClose  ? "close"
                                               : "message-link");
  switch (action) {
    case Action::kOk:
      if (delegate->Accept()) {
        infobar->RemoveSelf();
      }
      return;
    case Action::kCancel:
      if (delegate->Cancel()) {
        infobar->RemoveSelf();
      }
      return;
    case Action::kLink:
      if (delegate->LinkClicked(CurrentDisposition())) {
        infobar->RemoveSelf();
      }
      return;
    case Action::kMessageLink:
      if (delegate->InlineSubstitutionLinkClicked(link_index,
                                                  CurrentDisposition())) {
        infobar->RemoveSelf();
      }
      return;
    case Action::kClose:
      delegate->InfoBarDismissed();
      infobar->RemoveSelf();
      return;
  }
}

}  // namespace arkt
