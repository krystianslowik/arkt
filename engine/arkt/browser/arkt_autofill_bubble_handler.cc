#include "arkt/browser/arkt_autofill_bubble_handler.h"

#include "base/logging.h"
#include "base/no_destructor.h"
#include "chrome/browser/ui/autofill/autofill_bubble_base.h"
#include "chrome/browser/ui/autofill/save_address_bubble_controller.h"
#include "chrome/browser/ui/autofill/update_address_bubble_controller.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"

namespace arkt {

namespace {

// Stands in for a bubble that was never shown. The controller keeps a raw
// pointer to it until it calls Hide(), and nothing ever closes it the way a
// real bubble closes, so it lives for the process: one shared instance can
// never dangle, whichever window or tab outlives the other.
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
  return NotShown("SaveCreditCard");
}

autofill::AutofillBubbleBase* ArktAutofillBubbleHandler::ShowIbanBubble(
    content::WebContents* web_contents,
    autofill::IbanBubbleController* controller,
    bool is_user_gesture,
    autofill::IbanBubbleType bubble_type) {
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
  // A real bubble owns the controller; with no bubble it goes now.
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
  return NotShown("SaveCardConfirmation");
}

autofill::AutofillBubbleBase*
ArktAutofillBubbleHandler::ShowSaveIbanConfirmationBubble(
    content::WebContents* web_contents,
    autofill::IbanBubbleController* controller) {
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
