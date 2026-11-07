#include "arkt/api/arkt_page_info.h"

#include <algorithm>
#include <array>
#include <iterator>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/logging.h"
#include "base/scoped_observation.h"
#include "base/strings/escape.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/browsing_data/chrome_browsing_data_model_delegate.h"  // nogncheck
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"  // nogncheck
#include "chrome/browser/permissions/permission_decision_auto_blocker_factory.h"  // nogncheck
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ssl/chrome_security_state_util.h"  // nogncheck
#include "chrome/browser/ui/page_info/chrome_page_info_delegate.h"  // nogncheck
#include "components/browsing_data/content/browsing_data_model.h"
#include "components/content_settings/browser/page_specific_content_settings.h"
#include "components/content_settings/core/browser/content_settings_info.h"
#include "components/content_settings/core/browser/content_settings_observer.h"
#include "components/content_settings/core/browser/content_settings_registry.h"
#include "components/content_settings/core/browser/content_settings_type_set.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/common/content_settings.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "components/content_settings/core/common/content_settings_utils.h"
#include "components/page_info/page_info.h"
#include "components/page_info/page_info_ui.h"
#include "components/permissions/permission_decision_auto_blocker.h"
#include "components/security_state/core/security_state.h"
#include "components/strings/grit/components_strings.h"
#include "components/url_formatter/url_formatter.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "net/cert/cert_status_flags.h"
#include "net/cert/x509_certificate.h"
#include "ui/base/l10n/l10n_util.h"
#include "url/gurl.h"
#include "url/url_constants.h"

namespace arkt {

namespace {

// ArktSitePermissionKind order. The first four are listed for every site.
constexpr std::array<ContentSettingsType, 22> kKinds = {
    ContentSettingsType::GEOLOCATION,
    ContentSettingsType::MEDIASTREAM_CAMERA,
    ContentSettingsType::MEDIASTREAM_MIC,
    ContentSettingsType::NOTIFICATIONS,
    ContentSettingsType::POPUPS,
    ContentSettingsType::SOUND,
    ContentSettingsType::JAVASCRIPT,
    ContentSettingsType::IMAGES,
    ContentSettingsType::AUTOMATIC_DOWNLOADS,
    ContentSettingsType::CLIPBOARD_READ_WRITE,
    ContentSettingsType::MIDI_SYSEX,
    ContentSettingsType::SENSORS,
    ContentSettingsType::USB_GUARD,
    ContentSettingsType::SERIAL_GUARD,
    ContentSettingsType::HID_GUARD,
    ContentSettingsType::BLUETOOTH_GUARD,
    ContentSettingsType::FILE_SYSTEM_WRITE_GUARD,
    ContentSettingsType::WINDOW_MANAGEMENT,
    ContentSettingsType::LOCAL_FONTS,
    ContentSettingsType::IDLE_DETECTION,
    ContentSettingsType::BACKGROUND_SYNC,
    ContentSettingsType::MIXEDSCRIPT,
};
constexpr int kKindCount = static_cast<int>(kKinds.size());
constexpr int kCommonKinds = 4;

// How long a site data count is reused before a read counts again.
constexpr base::TimeDelta kSiteDataFreshness = base::Seconds(10);

bool IsKind(ContentSettingsType type) {
  return std::find(kKinds.begin(), kKinds.end(), type) != kKinds.end();
}

ContentSetting ToContentSetting(PermissionValue value) {
  switch (value) {
    case PermissionValue::kAllow:
      return CONTENT_SETTING_ALLOW;
    case PermissionValue::kAsk:
      return CONTENT_SETTING_ASK;
    case PermissionValue::kBlock:
      return CONTENT_SETTING_BLOCK;
  }
  return CONTENT_SETTING_ASK;
}

PermissionValue ToValue(ContentSetting setting) {
  switch (setting) {
    case CONTENT_SETTING_ALLOW:
      return PermissionValue::kAllow;
    case CONTENT_SETTING_BLOCK:
      return PermissionValue::kBlock;
    default:
      return PermissionValue::kAsk;
  }
}

// http and https pages have site settings; file is a local file; everything
// else (chrome, chrome-extension, devtools, view-source, about, data) is a
// page of the browser itself.
bool HasSiteSettings(const GURL& url) {
  return url.SchemeIsHTTPOrHTTPS();
}

Profile* ProfileOf(content::WebContents* contents) {
  return Profile::FromBrowserContext(contents->GetBrowserContext());
}

permissions::PermissionDecisionAutoBlocker* BlockerOf(Profile* profile) {
  return PermissionDecisionAutoBlockerFactory::GetForProfile(profile);
}

bool IsEmbargoed(permissions::PermissionDecisionAutoBlocker* blocker,
                 const GURL& url,
                 ContentSettingsType type) {
  return blocker &&
         permissions::PermissionDecisionAutoBlocker::IsEnabledForContentSetting(
             type) &&
         blocker->IsEmbargoed(url, type);
}

// One permission of `url`'s site, as page info and siteDetails read it: the
// site's exception, else the default; an embargo makes Ask read Block.
std::optional<SitePermissionValues> ReadPermission(
    HostContentSettingsMap* map,
    permissions::PermissionDecisionAutoBlocker* blocker,
    const GURL& url,
    int kind) {
  const ContentSettingsType type = kKinds[static_cast<size_t>(kind)];
  const content_settings::ContentSettingsInfo* info =
      content_settings::ContentSettingsRegistry::GetInstance()->Get(type);
  if (!info) {
    return std::nullopt;
  }
  content_settings::SettingInfo setting_info;
  ContentSetting setting = map->GetContentSetting(url, url, type, &setting_info);
  SitePermissionValues values;
  values.kind = kind;
  // Page info's own table has no insecure content row; its label is the
  // site settings one, as siteDetails shows it.
  values.title =
      type == ContentSettingsType::MIXEDSCRIPT
          ? l10n_util::GetStringUTF16(IDS_SITE_SETTINGS_TYPE_INSECURE_CONTENT)
          : PageInfoUI::PermissionTypeToUIString(type);
  values.is_default =
      setting_info.primary_pattern == ContentSettingsPattern::Wildcard() &&
      setting_info.secondary_pattern == ContentSettingsPattern::Wildcard();
  if (setting == CONTENT_SETTING_ASK && IsEmbargoed(blocker, url, type)) {
    setting = CONTENT_SETTING_BLOCK;
  }
  values.setting = ToValue(setting);
  for (ContentSetting option :
       {CONTENT_SETTING_ALLOW, CONTENT_SETTING_ASK, CONTENT_SETTING_BLOCK}) {
    if (info->IsSettingValid(option) || ToValue(option) == values.setting) {
      values.options.push_back(ToValue(option));
    }
  }
  return values;
}

std::u16string HostOf(const GURL& url) {
  return url_formatter::IDNToUnicode(url.host());
}

}  // namespace

PageInfoValues::PageInfoValues() = default;
PageInfoValues::PageInfoValues(const PageInfoValues&) = default;
PageInfoValues& PageInfoValues::operator=(const PageInfoValues&) = default;
PageInfoValues::~PageInfoValues() = default;

SitePermissionsValues::SitePermissionsValues() = default;
SitePermissionsValues::SitePermissionsValues(const SitePermissionsValues&) =
    default;
SitePermissionsValues& SitePermissionsValues::operator=(
    const SitePermissionsValues&) = default;
SitePermissionsValues::~SitePermissionsValues() = default;

PageConnection ReadConnection(content::WebContents* contents) {
  const GURL& url = contents->GetLastCommittedURL();
  if (url.SchemeIsFile()) {
    return PageConnection::kLocalFile;
  }
  if (!HasSiteSettings(url)) {
    return PageConnection::kInternalPage;
  }
  std::unique_ptr<security_state::VisibleSecurityState> state =
      chrome_security_state::GetVisibleSecurityState(contents);
  switch (chrome_security_state::GetSecurityLevel(contents)) {
    case security_state::SECURE:
      return PageConnection::kSecure;
    case security_state::DANGEROUS:
      if (state->malicious_content_status !=
          security_state::MALICIOUS_CONTENT_STATUS_NONE) {
        return PageConnection::kFlagged;
      }
      return net::IsCertStatusError(state->cert_status)
                 ? PageConnection::kCertificateError
                 : PageConnection::kNotSecure;
    default:
      if (url.SchemeIs(url::kHttpsScheme) &&
          (state->displayed_mixed_content || state->contained_mixed_form ||
           state->ran_mixed_content)) {
        return PageConnection::kNotFullySecure;
      }
      return PageConnection::kNotSecure;
  }
}

// A Chromium PageInfo for one tab's site, from its first change until its
// panel closes: PageInfo applies a change as its bubble does and decides the
// reload infobar on close. Its UI is never shown.
class PageInfoHub::Session : public content::WebContentsObserver {
 public:
  Session(PageInfoHub* hub,
          content::WebContents* contents,
          const url::Origin& origin)
      : content::WebContentsObserver(contents),
        hub_(hub),
        origin_(origin),
        page_info_(std::make_unique<PageInfo>(
            std::make_unique<ChromePageInfoDelegate>(contents),
            contents,
            contents->GetLastCommittedURL())) {
    page_info_->InitializeUiState(&ui_, base::DoNothing());
  }
  Session(const Session&) = delete;
  Session& operator=(const Session&) = delete;
  ~Session() override = default;

  PageInfo* page_info() { return page_info_.get(); }
  const url::Origin& origin() const { return origin_; }

  // content::WebContentsObserver. The session ends with its contents, and
  // with the page it was opened for: a committed cross-document navigation
  // of the primary main frame (a reload, a link, back and forward, a
  // prerender or back-forward cache activation) needs no reload infobar, so
  // a later close of the panel adds none. Ending here skips OnUIClosing.
  void PrimaryPageChanged(content::Page& page) override {
    hub_->EndSession(web_contents());  // Deletes this.
  }

  void WebContentsDestroyed() override {
    hub_->EndSession(web_contents());  // Deletes this.
  }

 private:
  class SilentUI : public PageInfoUI {};

  raw_ptr<PageInfoHub> hub_;
  url::Origin origin_;
  SilentUI ui_;
  std::unique_ptr<PageInfo> page_info_;
};

// The content settings observation of one profile's map.
class PageInfoHub::SettingsWatcher : public content_settings::Observer {
 public:
  SettingsWatcher(PageInfoHub* hub, Profile* profile)
      : hub_(hub), profile_(profile) {
    if (HostContentSettingsMap* map =
            HostContentSettingsMapFactory::GetForProfile(profile)) {
      observation_.Observe(map);
    }
  }
  SettingsWatcher(const SettingsWatcher&) = delete;
  SettingsWatcher& operator=(const SettingsWatcher&) = delete;
  ~SettingsWatcher() override = default;

  void OnContentSettingChanged(
      const ContentSettingsPattern& primary_pattern,
      const ContentSettingsPattern& secondary_pattern,
      ContentSettingsTypeSet content_type_set) override {
    if (!content_type_set.ContainsAllTypes() &&
        !IsKind(content_type_set.GetType())) {
      return;
    }
    hub_->SettingChanged(profile_, primary_pattern, secondary_pattern);
  }

 private:
  raw_ptr<PageInfoHub> hub_;
  raw_ptr<Profile> profile_;
  base::ScopedObservation<HostContentSettingsMap, content_settings::Observer>
      observation_{this};
};

struct PageInfoHub::SiteDataCache {
  // A tab that read a count older than the freshness window: told when the
  // new count differs from the one it read.
  struct Waiting {
    base::WeakPtr<content::WebContents> contents;
    url::Origin origin;
    std::optional<SiteDataCount> read;
  };

  std::unique_ptr<BrowsingDataModel> model;
  base::TimeTicks built;
  bool building = false;
  std::vector<Waiting> waiting;
};

namespace {

// As chrome://settings/content/siteDetails totals it: every entry for the
// origin, and its first-party cookies.
SiteDataCount CountSiteData(const BrowsingDataModel& model,
                            const url::Origin& origin) {
  SiteDataCount count;
  for (const BrowsingDataModel::BrowsingDataEntryView& entry : model) {
    if (!entry.Matches(origin)) {
      continue;
    }
    count.bytes += static_cast<int64_t>(entry.data_details->storage_size);
    if (!entry.GetThirdPartyPartitioningSite().has_value()) {
      count.cookies += static_cast<int64_t>(entry.data_details->cookie_count);
    }
  }
  return count;
}

}  // namespace

PageInfoHub::PageInfoHub(ChangedCallback changed, TabsCallback tabs)
    : changed_(std::move(changed)), tabs_(std::move(tabs)) {}

PageInfoHub::~PageInfoHub() = default;

void PageInfoHub::Watch(Profile* profile) {
  if (watchers_.count(profile)) {
    return;
  }
  watchers_[profile] = std::make_unique<SettingsWatcher>(this, profile);
  profile_observations_.AddObservation(profile);
}

void PageInfoHub::OnProfileWillBeDestroyed(Profile* profile) {
  watchers_.erase(profile);
  site_data_.erase(profile);
  profile_observations_.RemoveObservation(profile);
}

std::optional<PageInfoValues> PageInfoHub::Read(
    content::WebContents* contents) {
  if (!contents) {
    return std::nullopt;
  }
  const GURL url = contents->GetLastCommittedURL();
  if (!url.is_valid() || url.is_empty()) {
    return std::nullopt;
  }
  PageInfoValues values;
  values.connection = ReadConnection(contents);
  if (values.connection == PageConnection::kLocalFile) {
    values.origin = "file://";
    values.host = base::UTF8ToUTF16(base::UnescapeURLComponent(
        url.ExtractFileName(),
        base::UnescapeRule::SPACES | base::UnescapeRule::PATH_SEPARATORS |
            base::UnescapeRule::URL_SPECIAL_CHARS_EXCEPT_PATH_SEPARATORS));
    return values;
  }
  if (values.connection == PageConnection::kInternalPage) {
    values.origin = url.spec();
    values.host = base::UTF8ToUTF16(url.spec());
    return values;
  }
  const url::Origin origin = url::Origin::Create(url);
  values.origin = origin.Serialize();
  values.host = HostOf(url);
  if (values.connection == PageConnection::kSecure) {
    std::unique_ptr<security_state::VisibleSecurityState> state =
        chrome_security_state::GetVisibleSecurityState(contents);
    if (const net::X509Certificate* certificate = state->certificate.get()) {
      values.issued_to = certificate->subject().common_name;
      values.issued_by = certificate->issuer().organization_names.empty()
                             ? certificate->issuer().common_name
                             : certificate->issuer().organization_names.front();
      values.valid_until = certificate->valid_expiry();
    }
  }

  Profile* profile = ProfileOf(contents);
  Watch(profile);
  HostContentSettingsMap* map =
      HostContentSettingsMapFactory::GetForProfile(profile);
  permissions::PermissionDecisionAutoBlocker* blocker = BlockerOf(profile);
  auto* in_use = content_settings::PageSpecificContentSettings::GetForFrame(
      contents->GetPrimaryMainFrame());
  for (int kind = 0; kind < kKindCount; ++kind) {
    std::optional<SitePermissionValues> permission =
        ReadPermission(map, blocker, url, kind);
    if (!permission) {
      continue;
    }
    const ContentSettingsType type = kKinds[static_cast<size_t>(kind)];
    // As page info lists them after the common ones: an exception, an
    // embargo, a permission in use, or sound once the tab played audio.
    const bool listed =
        kind < kCommonKinds || !permission->is_default ||
        IsEmbargoed(blocker, url, type) || (in_use && in_use->IsInUse(type)) ||
        (type == ContentSettingsType::SOUND && contents->WasEverAudible());
    if (listed) {
      values.permissions.push_back(std::move(*permission));
    }
  }
  values.site_data = SiteData(profile, origin, contents);
  return values;
}

std::vector<SitePermissionsValues> PageInfoHub::SitesWithPermissions(
    Profile* profile) {
  std::vector<SitePermissionsValues> sites;
  if (!profile) {
    return sites;
  }
  HostContentSettingsMap* map =
      HostContentSettingsMapFactory::GetForProfile(profile);
  if (!map) {
    return sites;
  }
  permissions::PermissionDecisionAutoBlocker* blocker = BlockerOf(profile);
  std::map<std::string, std::vector<int>> kinds_by_origin;
  std::map<std::string, GURL> url_by_origin;
  for (int kind = 0; kind < kKindCount; ++kind) {
    for (const ContentSettingPatternSource& source :
         map->GetSettingsForOneType(kKinds[static_cast<size_t>(kind)])) {
      if (content_settings::GetSettingSourceFromProviderType(source.source) !=
              content_settings::SettingSource::kUser ||
          source.primary_pattern == ContentSettingsPattern::Wildcard() ||
          source.secondary_pattern != ContentSettingsPattern::Wildcard()) {
        continue;
      }
      const GURL url = source.primary_pattern.ToRepresentativeUrl();
      if (!HasSiteSettings(url)) {
        continue;
      }
      const std::string origin = url::Origin::Create(url).Serialize();
      std::vector<int>& kinds = kinds_by_origin[origin];
      if (std::find(kinds.begin(), kinds.end(), kind) == kinds.end()) {
        kinds.push_back(kind);
      }
      url_by_origin.emplace(origin, url);
    }
  }
  for (auto& [origin, kinds] : kinds_by_origin) {
    const GURL& url = url_by_origin[origin];
    SitePermissionsValues site;
    site.origin = origin;
    site.host = HostOf(url);
    std::sort(kinds.begin(), kinds.end());
    for (int kind : kinds) {
      std::optional<SitePermissionValues> permission =
          ReadPermission(map, blocker, url, kind);
      if (permission && !permission->is_default) {
        site.permissions.push_back(std::move(*permission));
      }
    }
    if (!site.permissions.empty()) {
      sites.push_back(std::move(site));
    }
  }
  std::stable_sort(sites.begin(), sites.end(),
                   [](const SitePermissionsValues& a,
                      const SitePermissionsValues& b) { return a.host < b.host; });
  return sites;
}

PageInfoHub::Session* PageInfoHub::SessionFor(content::WebContents* contents,
                                              const url::Origin& origin) {
  auto it = sessions_.find(contents);
  if (it != sessions_.end() && !it->second->origin().IsSameOriginWith(origin)) {
    // The tab went to another site since: the old site's session ends
    // without a reload infobar on the new page.
    sessions_.erase(it);
    it = sessions_.end();
  }
  if (it == sessions_.end()) {
    it = sessions_
             .emplace(contents,
                      std::make_unique<Session>(this, contents, origin))
             .first;
  }
  return it->second.get();
}

void PageInfoHub::EndSession(content::WebContents* contents) {
  sessions_.erase(contents);
}

void PageInfoHub::BeginChanging() {
  ++collecting_;
}

void PageInfoHub::EndChanging() {
  --collecting_;
  if (collecting_ > 0) {
    return;
  }
  std::vector<content::WebContents*> touched = std::move(touched_);
  touched_.clear();
  for (content::WebContents* contents : touched) {
    changed_.Run(contents);
  }
}

void PageInfoHub::SettingChanged(
    Profile* profile,
    const ContentSettingsPattern& primary_pattern,
    const ContentSettingsPattern& secondary_pattern) {
  for (content::WebContents* contents : tabs_.Run()) {
    if (!contents || ProfileOf(contents) != profile) {
      continue;
    }
    const GURL& url = contents->GetLastCommittedURL();
    if (!HasSiteSettings(url) || !primary_pattern.Matches(url) ||
        !secondary_pattern.Matches(url)) {
      continue;
    }
    if (collecting_ > 0) {
      if (std::find(touched_.begin(), touched_.end(), contents) ==
          touched_.end()) {
        touched_.push_back(contents);
      }
      continue;
    }
    // A change made elsewhere (Chromium's settings pages, an extension) can
    // come as one notification per type: the tabs it touched are reported
    // once, from a posted task.
    external_.push_back(contents->GetWeakPtr());
    if (!external_posted_) {
      external_posted_ = true;
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, base::BindOnce(&PageInfoHub::ReportExternal,
                                    weak_factory_.GetWeakPtr()));
    }
  }
}

void PageInfoHub::ReportExternal() {
  external_posted_ = false;
  std::vector<base::WeakPtr<content::WebContents>> external =
      std::move(external_);
  external_.clear();
  std::vector<content::WebContents*> reported;
  for (const base::WeakPtr<content::WebContents>& contents : external) {
    if (contents && std::find(reported.begin(), reported.end(),
                              contents.get()) == reported.end()) {
      reported.push_back(contents.get());
      changed_.Run(contents.get());
    }
  }
}

void PageInfoHub::SetPermission(content::WebContents* contents,
                                int kind,
                                PermissionValue value,
                                const std::string& origin_string) {
  if (!contents || kind < 0 || kind >= kKindCount) {
    return;
  }
  const GURL target_url(origin_string);
  if (!HasSiteSettings(target_url)) {
    return;
  }
  const url::Origin target = url::Origin::Create(target_url);
  Profile* profile = ProfileOf(contents);
  Watch(profile);
  HostContentSettingsMap* map =
      HostContentSettingsMapFactory::GetForProfile(profile);
  permissions::PermissionDecisionAutoBlocker* blocker = BlockerOf(profile);
  const GURL url = target.GetURL();
  std::optional<SitePermissionValues> current =
      ReadPermission(map, blocker, url, kind);
  if (!current || current->setting == value ||
      std::find(current->options.begin(), current->options.end(), value) ==
          current->options.end()) {
    return;
  }
  const ContentSettingsType type = kKinds[static_cast<size_t>(kind)];
  const ContentSetting chosen = ToContentSetting(value);
  // The default removes the exception, as choosing it in siteDetails does.
  std::optional<PermissionSetting> setting;
  if (chosen != map->GetDefaultContentSetting(type, nullptr)) {
    setting = PermissionSetting(chosen);
  }
  const GURL& page = contents->GetLastCommittedURL();
  const bool own_site =
      HasSiteSettings(page) && url::Origin::Create(page).IsSameOriginWith(target);
  BeginChanging();
  if (own_site) {
    SessionFor(contents, target)
        ->page_info()
        ->OnSitePermissionChanged(type, setting,
                                  /*requesting_origin=*/std::nullopt,
                                  /*is_one_time=*/false);
  } else {
    // Another site (Settings' per-site list): the same writes without a
    // reload infobar, which belongs to that site's own tab.
    if (blocker && chosen != CONTENT_SETTING_BLOCK) {
      blocker->RemoveEmbargoAndResetCounts(url, type);
    }
    map->SetNarrowestContentSetting(url, url, type, setting);
  }
  EndChanging();
}

void PageInfoHub::ResetPermissions(content::WebContents* contents,
                                   const std::string& origin_string) {
  if (!contents) {
    return;
  }
  const GURL target_url(origin_string);
  if (!HasSiteSettings(target_url)) {
    return;
  }
  const url::Origin target = url::Origin::Create(target_url);
  Profile* profile = ProfileOf(contents);
  Watch(profile);
  HostContentSettingsMap* map =
      HostContentSettingsMapFactory::GetForProfile(profile);
  permissions::PermissionDecisionAutoBlocker* blocker = BlockerOf(profile);
  const GURL url = target.GetURL();
  std::vector<ContentSettingsType> types;
  for (int kind = 0; kind < kKindCount; ++kind) {
    std::optional<SitePermissionValues> permission =
        ReadPermission(map, blocker, url, kind);
    const ContentSettingsType type = kKinds[static_cast<size_t>(kind)];
    if (permission &&
        (!permission->is_default || IsEmbargoed(blocker, url, type))) {
      types.push_back(type);
    }
  }
  if (types.empty()) {
    return;
  }
  const GURL& page = contents->GetLastCommittedURL();
  const bool own_site =
      HasSiteSettings(page) && url::Origin::Create(page).IsSameOriginWith(target);
  BeginChanging();
  for (ContentSettingsType type : types) {
    if (own_site) {
      SessionFor(contents, target)
          ->page_info()
          ->OnSitePermissionChanged(type, std::nullopt,
                                    /*requesting_origin=*/std::nullopt,
                                    /*is_one_time=*/false);
      continue;
    }
    if (blocker) {
      blocker->RemoveEmbargoAndResetCounts(url, type);
    }
    map->SetNarrowestContentSetting(url, url, type, std::nullopt);
  }
  EndChanging();
}

void PageInfoHub::PageInfoClosed(content::WebContents* contents) {
  auto it = sessions_.find(contents);
  if (it == sessions_.end()) {
    return;
  }
  std::unique_ptr<Session> session = std::move(it->second);
  sessions_.erase(it);
  const GURL& page = contents->GetLastCommittedURL();
  if (HasSiteSettings(page) &&
      url::Origin::Create(page).IsSameOriginWith(session->origin())) {
    // PageInfo adds Chromium's reload infobar when a change needs it.
    session->page_info()->OnUIClosing(/*reload_prompt=*/nullptr);
  }
}

void PageInfoHub::OpenSiteSettings(content::WebContents* contents,
                                   const std::string& origin_string) {
  const GURL url(origin_string);
  if (!contents || !HasSiteSettings(url)) {
    return;
  }
  ChromePageInfoDelegate(contents).ShowSiteSettings(
      url::Origin::Create(url).GetURL());
}

std::optional<SiteDataCount> PageInfoHub::SiteData(
    Profile* profile,
    const url::Origin& origin,
    content::WebContents* contents) {
  std::unique_ptr<SiteDataCache>& cache = site_data_[profile];
  if (!cache) {
    cache = std::make_unique<SiteDataCache>();
  }
  const bool fresh = cache->model && base::TimeTicks::Now() - cache->built <
                                         kSiteDataFreshness;
  std::optional<SiteDataCount> count;
  if (cache->model) {
    count = CountSiteData(*cache->model, origin);
  }
  if (!fresh) {
    cache->waiting.push_back({contents->GetWeakPtr(), origin, count});
    if (!cache->building) {
      cache->building = true;
      BrowsingDataModel::BuildFromDisk(
          profile, ChromeBrowsingDataModelDelegate::CreateForProfile(profile),
          base::BindOnce(&PageInfoHub::SiteDataBuilt,
                         weak_factory_.GetWeakPtr(), profile));
    }
  }
  return count;
}

void PageInfoHub::SiteDataBuilt(Profile* profile,
                                std::unique_ptr<BrowsingDataModel> model) {
  auto it = site_data_.find(profile);
  if (it == site_data_.end()) {
    return;
  }
  SiteDataCache& cache = *it->second;
  cache.model = std::move(model);
  cache.built = base::TimeTicks::Now();
  cache.building = false;
  std::vector<SiteDataCache::Waiting> waiting = std::move(cache.waiting);
  cache.waiting.clear();
  std::vector<content::WebContents*> reported;
  for (const SiteDataCache::Waiting& tab : waiting) {
    if (!tab.contents || std::find(reported.begin(), reported.end(),
                                   tab.contents.get()) != reported.end()) {
      continue;
    }
    const SiteDataCount count = CountSiteData(*cache.model, tab.origin);
    if (tab.read && tab.read->cookies == count.cookies &&
        tab.read->bytes == count.bytes) {
      continue;
    }
    reported.push_back(tab.contents.get());
    changed_.Run(tab.contents.get());
  }
}

}  // namespace arkt
