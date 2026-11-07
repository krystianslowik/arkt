#ifndef ARKT_BROWSER_ARKT_AUTOFILL_BUBBLE_HANDLER_H_
#define ARKT_BROWSER_ARKT_AUTOFILL_BUBBLE_HANDLER_H_

#include <memory>

#include "chrome/browser/ui/autofill/autofill_bubble_handler.h"
#include "components/signin/public/base/signin_buildflags.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"

class BrowserWindowInterface;

namespace arkt {

// The AutofillBubbleHandler of an Arkt window (#575). Arkt shows no autofill
// bubbles yet: every Show* logs "ARKT: autofill bubble <name> not shown".
//
// Two kinds of callers reach it. BrowserWindow::GetAutofillBubbleHandler()
// callers (mandatory re-auth, filled card, virtual card enroll, Autofill AI,
// omnibox) dereference the handler unchecked. AutofillBubbleHandler::Get()
// callers (save card, IBAN, offer, churned users, wallet reminder) look it up
// in the browser's unowned user data, as AutofillBubbleHandlerImpl registers
// itself, and one of them (churned users) dereferences it unchecked too.
//
// Most callers also dereference the returned bubble (SetBubbleView(*...)), and
// several CHECK it, so those methods return a shared no-op bubble. Only the
// omnibox, churned-users and wallet-reminder callers check for nullptr; they
// get nullptr, so their controllers never think a bubble is up.
//
// Save card, IBAN and the address bubbles are then told, in a posted task,
// that the bubble closed untouched, so a later prompt on the same tab can
// reach the handler. Offer, filled card, re-auth, virtual card and Autofill AI
// controllers keep the no-op bubble until their tab is hidden or closed.
class ArktAutofillBubbleHandler : public autofill::AutofillBubbleHandler {
 public:
  explicit ArktAutofillBubbleHandler(BrowserWindowInterface* browser);
  ArktAutofillBubbleHandler(const ArktAutofillBubbleHandler&) = delete;
  ArktAutofillBubbleHandler& operator=(const ArktAutofillBubbleHandler&) =
      delete;
  ~ArktAutofillBubbleHandler() override;

  // autofill::AutofillBubbleHandler:
  autofill::AutofillBubbleBase* ShowSaveCreditCardBubble(
      content::WebContents* web_contents,
      autofill::SaveCardBubbleController* controller,
      bool is_user_gesture) override;
  autofill::AutofillBubbleBase* ShowIbanBubble(
      content::WebContents* web_contents,
      autofill::IbanBubbleController* controller,
      bool is_user_gesture,
      autofill::IbanBubbleType bubble_type) override;
  autofill::AutofillBubbleBase* ShowOfferNotificationBubble(
      content::WebContents* web_contents,
      autofill::OfferNotificationBubbleController* controller,
      bool is_user_gesture) override;
  autofill::AutofillBubbleBase* ShowSaveAutofillAiDataBubble(
      content::WebContents* web_contents,
      autofill::AutofillAiImportDataController* controller) override;
  autofill::AutofillBubbleBase* ShowAutofillAiLocalSaveNotification(
      content::WebContents* web_contents,
      autofill::AutofillAiImportDataController* controller) override;
  autofill::AutofillBubbleBase* ShowSaveAddressProfileBubble(
      content::WebContents* web_contents,
      std::unique_ptr<autofill::SaveAddressBubbleController> controller,
      bool is_user_gesture) override;
#if BUILDFLAG(ENABLE_DICE_SUPPORT)
  autofill::AutofillBubbleBase* ShowAddressSignInPromo(
      content::WebContents* web_contents,
      const autofill::AutofillProfile& autofill_profile) override;
#endif  // BUILDFLAG(ENABLE_DICE_SUPPORT)
  autofill::AutofillBubbleBase* ShowUpdateAddressProfileBubble(
      content::WebContents* web_contents,
      std::unique_ptr<autofill::UpdateAddressBubbleController> controller,
      bool is_user_gesture) override;
  autofill::AutofillBubbleBase* ShowFilledCardInformationBubble(
      content::WebContents* web_contents,
      autofill::FilledCardInformationBubbleController* controller,
      bool is_user_gesture) override;
  autofill::AutofillBubbleBase* ShowVirtualCardEnrollBubble(
      content::WebContents* web_contents,
      autofill::VirtualCardEnrollBubbleController* controller,
      bool is_user_gesture) override;
  autofill::AutofillBubbleBase* ShowVirtualCardEnrollConfirmationBubble(
      content::WebContents* web_contents,
      autofill::VirtualCardEnrollBubbleController* controller) override;
  autofill::AutofillBubbleBase* ShowMandatoryReauthBubble(
      content::WebContents* web_contents,
      autofill::MandatoryReauthBubbleController* controller,
      bool is_user_gesture,
      autofill::MandatoryReauthBubbleType bubble_type) override;
  autofill::AutofillBubbleBase* ShowSaveCardConfirmationBubble(
      content::WebContents* web_contents,
      autofill::SaveCardBubbleController* controller) override;
  autofill::AutofillBubbleBase* ShowSaveIbanConfirmationBubble(
      content::WebContents* web_contents,
      autofill::IbanBubbleController* controller) override;
  autofill::AutofillBubbleBase* ShowOmniboxAutofillBubble(
      content::WebContents* web_contents,
      autofill::OmniboxAutofillBubbleController* controller) override;
  autofill::AutofillBubbleBase* ShowPaymentsChurnedUsersBubble(
      content::WebContents* web_contents,
      autofill::PaymentsChurnedUsersBubbleController* controller,
      bool is_user_gesture) override;
  autofill::AutofillBubbleBase* ShowPaymentsChurnedUsersConfirmationBubble(
      content::WebContents* web_contents,
      autofill::PaymentsChurnedUsersBubbleController* controller) override;
  autofill::AutofillBubbleBase* ShowWalletReminderNoticeBubble(
      content::WebContents* web_contents,
      autofill::WalletReminderNoticeBubbleController* controller,
      bool is_user_gesture) override;

 private:
  ui::ScopedUnownedUserData<autofill::AutofillBubbleHandler> scoped_user_data_;
};

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_AUTOFILL_BUBBLE_HANDLER_H_
