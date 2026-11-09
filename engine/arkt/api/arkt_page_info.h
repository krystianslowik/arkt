#ifndef ARKT_API_ARKT_PAGE_INFO_H_
#define ARKT_API_ARKT_PAGE_INFO_H_

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_multi_source_observation.h"
#include "base/time/time.h"
#include "chrome/browser/profiles/profile_observer.h"  // nogncheck
#include "components/content_settings/core/common/content_settings_pattern.h"
#include "url/origin.h"

class BrowsingDataModel;
class Profile;

namespace content {
class WebContents;
}

namespace arkt {

// Page info and per-site permissions (#583), as plain values for the facade.
// Reads go straight to the profile's HostContentSettingsMap and the tab's
// security state, the way chrome://settings/content/siteDetails reads them;
// changes go through Chromium's own PageInfo, so embargo, constraints and the
// reload infobar stay Chromium's.

// The values mirror ArktPageConnection, ArktPermissionSetting and
// ArktSitePermissionKind in arkt_engine.h.
enum class PageConnection {
  kSecure = 0,
  kNotSecure = 1,
  kNotFullySecure = 2,
  kCertificateError = 3,
  kFlagged = 4,
  kLocalFile = 5,
  kInternalPage = 6,
};

enum class PermissionValue {
  kAllow = 0,
  kAsk = 1,
  kBlock = 2,
};

struct SitePermissionValues {
  int kind = 0;
  std::u16string title;
  PermissionValue setting = PermissionValue::kAsk;
  bool is_default = true;
  std::vector<PermissionValue> options;
};

struct SiteDataCount {
  int64_t cookies = 0;
  int64_t bytes = 0;
};

struct PageInfoValues {
  PageInfoValues();
  PageInfoValues(const PageInfoValues&);
  PageInfoValues& operator=(const PageInfoValues&);
  ~PageInfoValues();

  std::string origin;
  std::u16string host;
  PageConnection connection = PageConnection::kInternalPage;
  std::optional<std::string> issued_to;
  std::optional<std::string> issued_by;
  std::optional<base::Time> valid_until;
  std::optional<SiteDataCount> site_data;
  std::vector<SitePermissionValues> permissions;
};

struct SitePermissionsValues {
  SitePermissionsValues();
  SitePermissionsValues(const SitePermissionsValues&);
  SitePermissionsValues& operator=(const SitePermissionsValues&);
  ~SitePermissionsValues();

  std::string origin;
  std::u16string host;
  std::vector<SitePermissionValues> permissions;
};

// The connection of the contents' last committed page.
PageConnection ReadConnection(content::WebContents* contents);

// One per facade. Owns the site data counts, the settings observation of each
// profile it has read, the tabs whose page info panel is open, and the open
// page info sessions (one Chromium PageInfo per tab with a change, until its
// panel closes). Site data is counted only for a tab whose panel is open
// (#782): BrowsingDataModel::BuildFromDisk reads the whole profile.
class PageInfoHub : public ProfileObserver {
 public:
  // A tab's page info changed: its site's settings, or the site data count
  // it waited for.
  using ChangedCallback = base::RepeatingCallback<void(content::WebContents*)>;
  // Every tab contents the facade knows, to match a settings change against.
  using TabsCallback =
      base::RepeatingCallback<std::vector<content::WebContents*>()>;

  PageInfoHub(ChangedCallback changed, TabsCallback tabs);
  PageInfoHub(const PageInfoHub&) = delete;
  PageInfoHub& operator=(const PageInfoHub&) = delete;
  ~PageInfoHub() override;

  // Page info of the contents' last committed page, or nullopt without one.
  std::optional<PageInfoValues> Read(content::WebContents* contents);
  // Every site of `profile` with a user exception, sorted by host.
  std::vector<SitePermissionsValues> SitesWithPermissions(Profile* profile);

  void SetPermission(content::WebContents* contents,
                     int kind,
                     PermissionValue value,
                     const std::string& origin);
  void ResetPermissions(content::WebContents* contents,
                        const std::string& origin);
  // The tab's panel opened: its reads count site data until it closes. Starts
  // the count when the profile's is stale or missing.
  void PageInfoOpened(content::WebContents* contents);
  void PageInfoClosed(content::WebContents* contents);
  void OpenSiteSettings(content::WebContents* contents,
                        const std::string& origin);

  // ProfileObserver:
  void OnProfileWillBeDestroyed(Profile* profile) override;

 private:
  class Session;
  class SettingsWatcher;
  struct SiteDataCache;

  void Watch(Profile* profile);
  Session* SessionFor(content::WebContents* contents,
                      const url::Origin& origin);
  void EndSession(content::WebContents* contents);
  // Whether the tab's panel is open; drops the entries of destroyed tabs.
  bool IsOpen(content::WebContents* contents);
  std::optional<SiteDataCount> SiteData(Profile* profile,
                                        const url::Origin& origin,
                                        content::WebContents* contents);
  void SiteDataBuilt(Profile* profile,
                     std::unique_ptr<BrowsingDataModel> model);
  // Between the two, the settings observation collects the tabs a change
  // touches instead of reporting them; the last End reports each once.
  void BeginChanging();
  void EndChanging();
  // A setting of `profile` changed for the patterns.
  void SettingChanged(Profile* profile,
                      const ContentSettingsPattern& primary_pattern,
                      const ContentSettingsPattern& secondary_pattern);
  // Reports the tabs that changes made outside this hub touched.
  void ReportExternal();

  ChangedCallback changed_;
  TabsCallback tabs_;
  std::map<content::WebContents*, std::unique_ptr<Session>> sessions_;
  std::vector<base::WeakPtr<content::WebContents>> open_;
  std::map<Profile*, std::unique_ptr<SiteDataCache>> site_data_;
  std::map<Profile*, std::unique_ptr<SettingsWatcher>> watchers_;
  int collecting_ = 0;
  std::vector<content::WebContents*> touched_;
  std::vector<base::WeakPtr<content::WebContents>> external_;
  bool external_posted_ = false;
  base::ScopedMultiSourceObservation<Profile, ProfileObserver>
      profile_observations_{this};
  base::WeakPtrFactory<PageInfoHub> weak_factory_{this};
};

}  // namespace arkt

#endif  // ARKT_API_ARKT_PAGE_INFO_H_
