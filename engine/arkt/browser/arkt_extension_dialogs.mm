#include "arkt/browser/arkt_extension_dialogs.h"

#import <AppKit/AppKit.h>

#include <map>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "arkt/browser/arkt_browser_window.h"
#import "arkt/browser/arkt_dialog_sheet.h"
#include "arkt/browser/arkt_extension_dialog_hook.h"
#include "base/i18n/number_formatting.h"
#include "base/logging.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/strings/string_split.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/extensions/extension_install_prompt_show_params.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/grit/generated_resources.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_delegate.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/browser/install_prompt_permissions.h"
#include "extensions/common/extension.h"
#include "extensions/common/extension_urls.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/models/dialog_model.h"
#include "ui/base/models/dialog_model_field.h"
#include "ui/base/models/dialog_model_host.h"
#include "ui/base/models/image_model.h"
#include "ui/base/mojom/dialog_button.mojom.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "ui/events/event.h"
#include "ui/events/keycodes/keyboard_codes.h"
#include "ui/gfx/image/image.h"
#include "ui/strings/grit/ui_strings.h"
#include "url/gurl.h"

using extensions::InstallPromptData;
using Result = extensions::ExtensionInstallPromptClient::Result;

namespace arkt {

namespace {

// Chrome keeps the install button disabled this long after the prompt shows
// (g_install_delay_in_ms in extension_install_dialog_view.cc), so a click
// meant for the page cannot land on it.
constexpr NSTimeInterval kInstallButtonDelay = 0.5;

// The Arkt window whose NSWindow is `parent`, or nullptr.
ArktBrowserWindow* ArktWindowFor(gfx::NativeWindow parent) {
  NSWindow* ns_window = parent.GetNativeNSWindow();
  if (!ns_window) {
    return nullptr;
  }
  ArktBrowserWindow* found = nullptr;
  GlobalBrowserCollection::GetInstance()->ForEach(
      [&](BrowserWindowInterface* browser) {
        ArktBrowserWindow* window = ArktBrowserWindow::FromBrowser(browser);
        if (window && window->host().window == ns_window) {
          found = window;
          return false;
        }
        return true;
      });
  return found;
}

NSImage* ToNSImage(const gfx::Image& image) {
  return image.IsEmpty() ? nil : image.ToNSImage();
}

NSString* ToNS(const std::u16string& text) {
  return base::SysUTF16ToNSString(text);
}

// ---------------------------------------------------------------------------
// Install, re-enable and permission-increase prompts (ExtensionInstallPrompt).

// Mirrors ExtensionInstallDialogView for the variants it renders: the same
// strings, buttons, delay and results, drawn as an ArktDialogSheet. Owns
// itself; deleted after the answer.
class InstallSheet final : public extensions::ExtensionRegistryObserver {
 public:
  InstallSheet(std::unique_ptr<ExtensionInstallPromptShowParams> show_params,
               extensions::ExtensionInstallPromptClient::DoneCallback done,
               std::unique_ptr<InstallPromptData> prompt,
               BrowserWindowInterface* browser)
      : profile_(show_params->profile()),
        show_params_(std::move(show_params)),
        done_callback_(std::move(done)),
        prompt_(std::move(prompt)),
        browser_(browser ? browser->GetWeakPtr() : nullptr) {
    registry_observation_.Observe(extensions::ExtensionRegistry::Get(profile_));
  }
  InstallSheet(const InstallSheet&) = delete;
  InstallSheet& operator=(const InstallSheet&) = delete;
  ~InstallSheet() override {
    // Only reached after Finish(); answer anyway if that ever changes.
    deleting_ = true;
    if (done_callback_) {
      Finish(Result::USER_CANCELED);
    }
    [sheet_ close];
  }

  void Show(NSWindow* parent) {
    sheet_ = [[ArktDialogSheet alloc] initWithContent:BuildContent()];
    base::WeakPtr<InstallSheet> weak = weak_factory_.GetWeakPtr();
    sheet_.onPrimary = ^{
      if (weak) {
        weak->Accept();
      }
    };
    sheet_.onCancel = ^{
      if (weak) {
        weak->Cancel();
      }
    };
    sheet_.onDismiss = sheet_.onCancel;
    sheet_.onLink = ^(NSInteger) {
      if (weak) {
        weak->OpenStorePage();
      }
    };
    LOG(WARNING) << "ARKT: install sheet shown type=" << prompt_->type()
                 << " permissions=" << prompt_->GetPermissionCount();
    [sheet_ beginOnWindow:parent];
  }

 private:
  ArktDialogSheetContent* BuildContent() {
    ArktDialogSheetContent* content = [[ArktDialogSheetContent alloc] init];
    content.title = ToNS(prompt_->GetDialogTitle());
    content.icon = ToNSImage(prompt_->icon());

    if (prompt_->has_webstore_data()) {
      std::u16string users = prompt_->GetUserCount();
      if (prompt_->rating_count() > 0) {
        content.subtitle = ToNS(base::FormatDouble(prompt_->average_rating(),
                                                   1) +
                                u" " + prompt_->GetRatingCount() +
                                u"  ·  " + users);
      } else {
        content.subtitle = ToNS(users);
      }
      content.subtitleAccessibilityLabel = ToNS(users);
      content.footerLinkTitle =
          ToNS(l10n_util::GetStringUTF16(IDS_EXTENSION_PROMPT_STORE_LINK));
    } else if (prompt_->ShouldWithheldPermissionsOnDialogAccept()) {
      content.checkboxTitle = ToNS(l10n_util::GetStringUTF16(
          IDS_EXTENSION_PROMPT_GRANT_PERMISSIONS_CHECKBOX));
    }

    if (prompt_->GetPermissionCount() > 0) {
      content.listHeading = ToNS(prompt_->GetPermissionsHeading());
      extensions::InstallPromptPermissions permissions =
          prompt_->GetPermissions();
      NSMutableArray<ArktDialogSheetItem*>* items = [NSMutableArray array];
      for (size_t i = 0; i < permissions.permissions.size(); ++i) {
        ArktDialogSheetItem* item = [[ArktDialogSheetItem alloc] init];
        item.text = ToNS(permissions.permissions[i]);
        NSMutableArray<NSString*>* details = [NSMutableArray array];
        if (i < permissions.details.size()) {
          for (const std::u16string& line : base::SplitString(
                   permissions.details[i], u"\n", base::TRIM_WHITESPACE,
                   base::SPLIT_WANT_NONEMPTY)) {
            [details addObject:ToNS(line)];
          }
        }
        item.details = details;
        [items addObject:item];
      }
      content.listItems = items;
    }

    int buttons = prompt_->GetDialogButtons();
    if (buttons & static_cast<int>(ui::mojom::DialogButton::kOk)) {
      content.primaryTitle = ToNS(prompt_->GetAcceptButtonLabel());
    }
    content.cancelTitle = ToNS(prompt_->GetAbortButtonLabel());
    // Chrome makes Cancel the default button of every prompt this sheet
    // takes (OK only for the request and parent-permission variants, which
    // stay with Chrome's dialog), so Return never installs.
    // PARITY(NEEDS-RUNTIME-CHECK): Arc's Return key on this prompt.
    content.defaultButton = ArktDialogSheetDefaultCancel;
    content.primaryEnableDelay = kInstallButtonDelay;
    return content;
  }

  void Accept() {
    if (!done_callback_) {
      return;
    }
    registry_observation_.Reset();
    prompt_->OnDialogAccepted();
    auto result =
        prompt_->ShouldWithheldPermissionsOnDialogAccept() &&
                !prompt_->has_webstore_data() && !sheet_.checkboxChecked
            ? Result::ACCEPTED_WITH_WITHHELD_PERMISSIONS
            : Result::ACCEPTED;
    LOG(WARNING) << "ARKT: install sheet accepted";
    Finish(result);
  }

  void Cancel() {
    if (!done_callback_) {
      return;
    }
    LOG(WARNING) << "ARKT: install sheet canceled";
    Finish(Result::USER_CANCELED);
  }

  // The footer link: the item's Web Store page in a new tab, then cancel, as
  // ExtensionInstallDialogView::LinkClicked does.
  void OpenStorePage() {
    GURL url(extension_urls::GetWebstoreItemDetailURLPrefix() +
             prompt_->extension()->id());
    content::OpenURLParams params = content::OpenURLParams::CreateBrowserInitiated(
        url, WindowOpenDisposition::NEW_FOREGROUND_TAB,
        ui::PAGE_TRANSITION_LINK);
    if (content::WebContents* contents = show_params_->GetParentWebContents()) {
      contents->OpenURL(params, /*navigation_handle_callback=*/{});
    } else if (browser_) {
      browser_->OpenURL(params, /*navigation_handle_callback=*/{});
    }
    Cancel();
  }

  // Runs the prompt observers and the done callback once, closes the sheet
  // and deletes this object soon.
  void Finish(Result result) {
    registry_observation_.Reset();
    if (result == Result::USER_CANCELED) {
      prompt_->OnDialogCanceled();
    }
    [sheet_ close];
    std::move(done_callback_)
        .Run(extensions::ExtensionInstallPromptClient::DoneCallbackPayload(result));
    if (!deleting_) {
      deleting_ = true;
      base::SequencedTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE,
                                                                 this);
    }
  }

  // extensions::ExtensionRegistryObserver:
  void OnExtensionUninstalled(content::BrowserContext* browser_context,
                              const extensions::Extension* extension,
                              extensions::UninstallReason reason) override {
    if (extension && prompt_->extension() &&
        extension->id() == prompt_->extension()->id()) {
      Cancel();
    }
  }

  void OnShutdown(extensions::ExtensionRegistry* registry) override {
    registry_observation_.Reset();
    Cancel();
  }

  raw_ptr<Profile> profile_;
  std::unique_ptr<ExtensionInstallPromptShowParams> show_params_;
  extensions::ExtensionInstallPromptClient::DoneCallback done_callback_;
  std::unique_ptr<InstallPromptData> prompt_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  ArktDialogSheet* __strong sheet_ = nil;
  bool deleting_ = false;
  base::ScopedObservation<extensions::ExtensionRegistry,
                          extensions::ExtensionRegistryObserver>
      registry_observation_{this};
  base::WeakPtrFactory<InstallSheet> weak_factory_{this};
};

bool ShowInstallDialog(
    std::unique_ptr<ExtensionInstallPromptShowParams>& show_params,
    extensions::ExtensionInstallPromptClient::DoneCallback& done_callback,
    std::unique_ptr<InstallPromptData>& prompt) {
  if (!show_params || !prompt || !prompt->extension()) {
    return false;
  }
  // The justification field (request prompt) and the parent-permission flow
  // stay with Chrome's dialog.
  if (prompt->type() == InstallPromptData::EXTENSION_REQUEST_PROMPT ||
      prompt->requires_parent_permission()) {
    return false;
  }
  gfx::NativeWindow parent = show_params->GetParentWindow();
  ArktBrowserWindow* window = parent ? ArktWindowFor(parent) : nullptr;
  if (!window) {
    return false;
  }

  // As ShowExtensionInstallDialogImpl: a prompt for a background tab brings
  // that tab to the front first.
  content::WebContents* contents = show_params->GetParentWebContents();
  BrowserWindowInterface* browser = window->browser();
  if (contents && contents->GetDelegate() &&
      browser->GetTabStripModel()->GetActiveWebContents() != contents) {
    contents->GetDelegate()->ActivateContents(contents);
  }

  auto* sheet = new InstallSheet(std::move(show_params),
                                 std::move(done_callback), std::move(prompt),
                                 browser);
  sheet->Show(window->host().window);
  return true;
}

// ---------------------------------------------------------------------------
// ui::DialogModel dialogs (post-install, uninstall and the other extension
// dialogs shown through extensions::ShowDialog without a Views container).

class ModelSheet final : public ui::DialogModelHost,
                         public ui::DialogModelFieldHost {
 public:
  explicit ModelSheet(std::unique_ptr<ui::DialogModel> model)
      : model_(std::move(model)) {
    model_->set_host(DialogModelHost::GetPassKey(), this);
  }
  ModelSheet(const ModelSheet&) = delete;
  ModelSheet& operator=(const ModelSheet&) = delete;
  ~ModelSheet() { DestroyModel(); }

  void Show(NSWindow* parent) {
    sheet_ = [[ArktDialogSheet alloc] initWithContent:BuildContent(parent)];
    base::WeakPtr<ModelSheet> weak = weak_factory_.GetWeakPtr();
    sheet_.onPrimary = ^{
      if (weak) {
        weak->Primary();
      }
    };
    sheet_.onCancel = ^{
      if (weak) {
        weak->Cancel();
      }
    };
    sheet_.onDismiss = ^{
      if (weak) {
        weak->Dismiss();
      }
    };
    sheet_.onLink = ^(NSInteger index) {
      if (weak) {
        weak->Link(index);
      }
    };
    sheet_.onCheckbox = ^(BOOL checked) {
      if (weak) {
        weak->Checked(checked);
      }
    };
    LOG(WARNING) << "ARKT: dialog sheet shown "
                 << model_->internal_name(DialogModelHost::GetPassKey());
    [sheet_ beginOnWindow:parent];
  }

  // ui::DialogModelHost:
  void Close() override {
    if (closed_) {
      return;
    }
    closed_ = true;
    [sheet_ close];
    LOG(WARNING) << "ARKT: dialog sheet closed";
    DestroyModel();
    base::SequencedTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE,
                                                               this);
  }

  void OnDialogButtonChanged() override {
    if (closed_) {
      return;
    }
    auto key = DialogModelHost::GetPassKey();
    if (ui::DialogModel::Button* ok = model_->ok_button(key)) {
      [sheet_ setPrimaryTitle:ToNS(ok->label()) enabled:ok->is_enabled()];
    }
    if (ui::DialogModel::Button* cancel = model_->cancel_button(key)) {
      [sheet_ setCancelTitle:ToNS(cancel->label())
                     enabled:cancel->is_enabled()];
    }
  }

 private:
  ArktDialogSheetContent* BuildContent(NSWindow* parent) {
    auto key = DialogModelHost::GetPassKey();
    ArktDialogSheetContent* content = [[ArktDialogSheetContent alloc] init];
    content.title = ToNS(model_->title(key));

    bool dark = [[parent.effectiveAppearance
        bestMatchFromAppearancesWithNames:@[
          NSAppearanceNameAqua, NSAppearanceNameDarkAqua
        ]] isEqualToString:NSAppearanceNameDarkAqua];
    const ui::ImageModel& icon =
        dark && !model_->dark_mode_icon(key).IsEmpty()
            ? model_->dark_mode_icon(key)
            : model_->icon(key);
    if (icon.IsImage()) {
      content.icon = ToNSImage(icon.GetImage());
    }

    NSMutableArray<ArktDialogSheetParagraph*>* paragraphs =
        [NSMutableArray array];
    for (const auto& field : model_->fields(key)) {
      if (!field->is_visible()) {
        continue;
      }
      switch (field->type()) {
        case ui::DialogModelField::kParagraph: {
          auto* paragraph = static_cast<ui::DialogModelParagraph*>(field.get());
          if (!paragraph->header().empty()) {
            ArktDialogSheetParagraph* header =
                [[ArktDialogSheetParagraph alloc] init];
            header.text = ToNS(paragraph->header());
            [paragraphs addObject:header];
          }
          [paragraphs addObject:ParagraphFor(paragraph->label(),
                                             paragraphs.count)];
          break;
        }
        case ui::DialogModelField::kCheckbox:
          if (!checkbox_) {
            checkbox_ = static_cast<ui::DialogModelCheckbox*>(field.get());
            content.checkboxTitle = ToNS(LabelText(checkbox_->label()));
            content.checkboxChecked = checkbox_->is_checked();
            break;
          }
          [[fallthrough]];
        default:
          // Custom Views fields (the sign-in promo footnote) and the field
          // types extension dialogs do not use are not shown.
          LOG(WARNING) << "ARKT: dialog field not shown, type "
                       << field->type();
          break;
      }
    }
    content.paragraphs = paragraphs;

    ui::DialogModel::Button* ok = model_->ok_button(key);
    ui::DialogModel::Button* cancel = model_->cancel_button(key);
    if (ok) {
      content.primaryTitle =
          ToNS(ok->label().empty() ? l10n_util::GetStringUTF16(IDS_APP_OK)
                                   : ok->label());
    }
    if (cancel) {
      content.cancelTitle = ToNS(cancel->label().empty()
                                     ? l10n_util::GetStringUTF16(IDS_APP_CANCEL)
                                     : cancel->label());
    }
    if (!ok && !cancel) {
      // The desktop post-install dialog is a bubble with only a close button;
      // a sheet needs a button to leave it.
      content.primaryTitle = ToNS(l10n_util::GetStringUTF16(IDS_APP_OK));
      dismiss_only_ = true;
    }

    // As views::DialogDelegate: OK is the default unless the model overrides
    // it.
    const std::optional<ui::mojom::DialogButton>& override_default =
        model_->override_default_button(key);
    if (override_default.has_value()) {
      content.defaultButton =
          *override_default == ui::mojom::DialogButton::kOk
              ? ArktDialogSheetDefaultPrimary
              : (*override_default == ui::mojom::DialogButton::kCancel
                     ? ArktDialogSheetDefaultCancel
                     : ArktDialogSheetDefaultNone);
    } else {
      content.defaultButton =
          ok || dismiss_only_ ? ArktDialogSheetDefaultPrimary
                              : ArktDialogSheetDefaultNone;
    }
    if (ok && !ok->is_enabled()) {
      content.primaryEnableDelay = 0;
    }
    return content;
  }

  // The label's text with its replacements; the first link replacement
  // becomes the paragraph's link.
  ArktDialogSheetParagraph* ParagraphFor(const ui::DialogModelLabel& label,
                                         NSUInteger index) {
    ArktDialogSheetParagraph* paragraph =
        [[ArktDialogSheetParagraph alloc] init];
    paragraph.secondary = label.is_secondary();
    if (label.replacements().empty()) {
      paragraph.text = ToNS(label.GetString());
      return paragraph;
    }
    std::vector<std::u16string> texts;
    for (const auto& replacement : label.replacements()) {
      texts.push_back(replacement.text());
    }
    std::vector<size_t> offsets;
    std::u16string text =
        l10n_util::GetStringFUTF16(label.message_id(), texts, &offsets);
    paragraph.text = ToNS(text);
    for (size_t i = 0; i < label.replacements().size() && i < offsets.size();
         ++i) {
      const auto& replacement = label.replacements()[i];
      if (replacement.callback().has_value()) {
        paragraph.linkRange =
            NSMakeRange(offsets[i], replacement.text().size());
        links_[index] = *replacement.callback();
        break;
      }
    }
    return paragraph;
  }

  std::u16string LabelText(const ui::DialogModelLabel& label) {
    if (label.replacements().empty()) {
      return label.GetString();
    }
    std::vector<std::u16string> texts;
    for (const auto& replacement : label.replacements()) {
      texts.push_back(replacement.text());
    }
    return l10n_util::GetStringFUTF16(label.message_id(), texts, nullptr);
  }

  void Primary() {
    if (closed_) {
      return;
    }
    if (dismiss_only_) {
      Dismiss();
      return;
    }
    base::WeakPtr<ModelSheet> weak = weak_factory_.GetWeakPtr();
    bool close = model_->OnDialogAcceptAction(DialogModelHost::GetPassKey());
    AfterAction(weak, close);
  }

  void Cancel() {
    if (closed_) {
      return;
    }
    base::WeakPtr<ModelSheet> weak = weak_factory_.GetWeakPtr();
    bool close = model_->OnDialogCancelAction(DialogModelHost::GetPassKey());
    AfterAction(weak, close);
  }

  void Dismiss() {
    if (closed_) {
      return;
    }
    base::WeakPtr<ModelSheet> weak = weak_factory_.GetWeakPtr();
    model_->OnDialogCloseAction(DialogModelHost::GetPassKey());
    AfterAction(weak, true);
  }

  // A model callback may close the host itself (and so delete the model).
  void AfterAction(const base::WeakPtr<ModelSheet>& weak, bool close) {
    if (!weak || closed_) {
      return;
    }
    if (close) {
      Close();
    } else {
      [sheet_ rearm];
    }
  }

  void Link(NSInteger index) {
    auto it = links_.find(index);
    if (closed_ || it == links_.end()) {
      return;
    }
    // Copy: the callback may close the dialog and destroy `links_`.
    ui::DialogModelLabel::Callback callback = it->second;
    callback.Run(ui::KeyEvent(ui::EventType::kKeyPressed, ui::VKEY_RETURN,
                              ui::EF_NONE));
  }

  void Checked(bool checked) {
    if (!closed_ && checkbox_) {
      checkbox_->OnChecked(DialogModelFieldHost::GetPassKey(), checked);
    }
  }

  void DestroyModel() {
    if (!model_) {
      return;
    }
    checkbox_ = nullptr;
    links_.clear();
    // Runs the dialog's destroying callback (the post-install hint, the
    // uninstall result) before the model goes away, as Views hosts do.
    model_->OnDialogDestroying(DialogModelHost::GetPassKey());
    model_.reset();
  }

  std::unique_ptr<ui::DialogModel> model_;
  ArktDialogSheet* __strong sheet_ = nil;
  raw_ptr<ui::DialogModelCheckbox> checkbox_ = nullptr;
  std::map<NSInteger, ui::DialogModelLabel::Callback> links_;
  bool dismiss_only_ = false;
  bool closed_ = false;
  base::WeakPtrFactory<ModelSheet> weak_factory_{this};
};

bool ShowModalDialog(gfx::NativeWindow parent,
                     std::unique_ptr<ui::DialogModel>& dialog_model) {
  if (!dialog_model || !parent) {
    return false;
  }
  ArktBrowserWindow* window = ArktWindowFor(parent);
  if (!window) {
    return false;
  }
  auto* sheet = new ModelSheet(std::move(dialog_model));
  sheet->Show(window->host().window);
  return true;
}

}  // namespace

void RegisterExtensionDialogSheets() {
  ExtensionDialogHooks hooks;
  hooks.show_install_dialog = &ShowInstallDialog;
  hooks.show_modal_dialog = &ShowModalDialog;
  SetExtensionDialogHooks(hooks);
  LOG(WARNING) << "ARKT: extension dialog sheets registered";
}

}  // namespace arkt
