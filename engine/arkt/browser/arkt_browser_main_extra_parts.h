#ifndef ARKT_BROWSER_ARKT_BROWSER_MAIN_EXTRA_PARTS_H_
#define ARKT_BROWSER_ARKT_BROWSER_MAIN_EXTRA_PARTS_H_

#include "chrome/browser/chrome_browser_main_extra_parts.h"

namespace arkt {

class ArktBrowserMainExtraParts : public ChromeBrowserMainExtraParts {
 public:
  ArktBrowserMainExtraParts();
  ArktBrowserMainExtraParts(const ArktBrowserMainExtraParts&) = delete;
  ArktBrowserMainExtraParts& operator=(const ArktBrowserMainExtraParts&) =
      delete;
  ~ArktBrowserMainExtraParts() override;

  // ChromeBrowserMainExtraParts:
  void PreProfileInit() override;
  void PostProfileInit(Profile* profile, bool is_initial_profile) override;
  void PreBrowserStart() override;
  void PostBrowserStart() override;
};

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_BROWSER_MAIN_EXTRA_PARTS_H_
