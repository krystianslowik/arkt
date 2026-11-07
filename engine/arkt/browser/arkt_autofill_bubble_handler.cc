#include "arkt/browser/arkt_autofill_bubble_handler.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/location.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/ui/autofill/autofill_bubble_base.h"
#include "chrome/browser/ui/autofill/payments/iban_bubble_controller.h"
#include "chrome/browser/ui/autofill/payments/save_card_bubble_controller.h"
#include "chrome/browser/ui/autofill/save_address_bubble_controller.h"
#include "chrome/browser/ui/autofill/update_address_bubble_controller.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/autofill/core/browser/ui/payments/payments_ui_closed_reasons.h"

namespace arkt {

namespace {

// Stands in for a bubble that was never shown. A controller keeps a raw
// pointer to it until it calls Hide() or hears the bubble closed, so it lives
// for the process: one shared instance can never dangle, whichever window or
// tab outlives the other.
class NoOpAutofillBubble : public autofill::AutofillBubbleBase {
 public:
  void Hide() override {}
  bool IsMouseHovered() const override { return false; }
};

autofill::AutofillBubbleBase* NotShown(const char* name) {
  static base::NoDestructor<NoOpAutofillBubble> bubble;
  LOG(WARNING) << "ARKT: autofill bubble " << name << " not shown";
  return bubble.get();
}

// Tells a payments controller its bubble closed untouched, so it lets go of
// the no-op bubble and a later prompt on the tab can show. Posted: the caller
// stores the returned bubble and CHECKs it after Show* returns. The callback
// holds the controller weakly.
void PostClosed(base::OnceCallback<void(autofill::PaymentsUiClosedReason)>
                    on_bubble_closed) {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(std::move(on_bubble_closed),
                     autofill::PaymentsUiClosedReason::kNotInteracted));
}

// The address bubbles own their controller. Closing it tells its delegate
// (the tab's AddressBubblesController, held weakly) that the bubble closed,
// after the caller has stored the returned bubble.
template <typename Controller>
void PostAddressClosed(std::unique_ptr<Controller> controller) {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](std::unique_ptr<Controller> controller) {
                       controller->OnBubbleClosed();
                     },
                     std::move(controller)));
}

// For the callers that check the result: no bubble at all.
autofill::AutofillBubbleBase* NotShownNull(const char* name) {
  LOG(WARNING) << "ARKT: autofill bubble " << name << " not shown";
  return nullptr;
}

}  // namespace

ArktAutofillBubbleHandler::ArktAutofillBubbleHandler(
    BrowserWindowInterface* browser)
    : scoped_user_data_(browser->GetUnownedUserDataHost(), *this) {}

ArktAutofillBubbleHandler::~ArktAutofillBubbleHandler() = default;

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowSaveCreditCardBubble(
    content::WebContents* web_contents,
    autofill::SaveCardBubbleController* controller,
    bool is_user_gesture) {
  PostClosed(controller->GetOnBubbleClosedCallback());
  return NotShown("SaveCreditCard");
}

autofill::AutofillBubbleBase* ArktAutofillBubbleHandler::ShowIbanBubble(
    content::WebContents* web_contents,
    autofill::IbanBubbleController* controller,
    bool is_user_gesture,
    autofill::IbanBubbleType bubble_type) {
  PostClosed(controller->GetOnBubbleClosedCallback());
  return NotShown("Iban");
}

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowOfferNotificationBubble(
    content::WebContents* web_contents,
    autofill::OfferNotificationBubbleController* controller,
    bool is_user_gesture) {
  return NotShown("OfferNotification");
}

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowSaveAutofillAiDataBubble(
    content::WebContents* web_contents,
    autofill::AutofillAiImportDataController* controller) {
  return NotShown("SaveAutofillAiData");
}

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowAutofillAiLocalSaveNotification(
    content::WebContents* web_contents,
    autofill::AutofillAiImportDataController* controller) {
  return NotShown("AutofillAiLocalSaveNotification");
}

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowSaveAddressProfileBubble(
    content::WebContents* web_contents,
    std::unique_ptr<autofill::SaveAddressBubbleController> controller,
    bool is_user_gesture) {
  PostAddressClosed(std::move(controller));
  return NotShown("SaveAddressProfile");
}

#if BUILDFLAG(ENABLE_DICE_SUPPORT)
autofill::AutofillBubbleBase* ArktAutofillBubbleHandler::ShowAddressSignInPromo(
    content::WebContents* web_contents,
    const autofill::AutofillProfile& autofill_profile) {
  return NotShown("AddressSignInPromo");
}
#endif  // BUILDFLAG(ENABLE_DICE_SUPPORT)

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowUpdateAddressProfileBubble(
    content::WebContents* web_contents,
    std::unique_ptr<autofill::UpdateAddressBubbleController> controller,
    bool is_user_gesture) {
  PostAddressClosed(std::move(controller));
  return NotShown("UpdateAddressProfile");
}

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowFilledCardInformationBubble(
    content::WebContents* web_contents,
    autofill::FilledCardInformationBubbleController* controller,
    bool is_user_gesture) {
  return NotShown("FilledCardInformation");
}

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowVirtualCardEnrollBubble(
    content::WebContents* web_contents,
    autofill::VirtualCardEnrollBubbleController* controller,
    bool is_user_gesture) {
  return NotShown("VirtualCardEnroll");
}

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowVirtualCardEnrollConfirmationBubble(
    content::WebContents* web_contents,
    autofill::VirtualCardEnrollBubbleController* controller) {
  return NotShown("VirtualCardEnrollConfirmation");
}

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowMandatoryReauthBubble(
    content::WebContents* web_contents,
    autofill::MandatoryReauthBubbleController* controller,
    bool is_user_gesture,
    autofill::MandatoryReauthBubbleType bubble_type) {
  return NotShown("MandatoryReauth");
}

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowSaveCardConfirmationBubble(
    content::WebContents* web_contents,
    autofill::SaveCardBubbleController* controller) {
  PostClosed(controller->GetOnBubbleClosedCallback());
  return NotShown("SaveCardConfirmation");
}

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowSaveIbanConfirmationBubble(
    content::WebContents* web_contents,
    autofill::IbanBubbleController* controller) {
  PostClosed(controller->GetOnBubbleClosedCallback());
  return NotShown("SaveIbanConfirmation");
}

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowOmniboxAutofillBubble(
    content::WebContents* web_contents,
    autofill::OmniboxAutofillBubbleController* controller) {
  return NotShownNull("OmniboxAutofill");
}

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowPaymentsChurnedUsersBubble(
    content::WebContents* web_contents,
    autofill::PaymentsChurnedUsersBubbleController* controller,
    bool is_user_gesture) {
  return NotShownNull("PaymentsChurnedUsers");
}

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowPaymentsChurnedUsersConfirmationBubble(
    content::WebContents* web_contents,
    autofill::PaymentsChurnedUsersBubbleController* controller) {
  return NotShownNull("PaymentsChurnedUsersConfirmation");
}

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowWalletReminderNoticeBubble(
    content::WebContents* web_contents,
    autofill::WalletReminderNoticeBubbleController* controller,
    bool is_user_gesture) {
  return NotShownNull("WalletReminderNotice");
}

}  // namespace arkt
