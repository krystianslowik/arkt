#include "arkt/api/arkt_import_writer.h"

#include <algorithm>
#include <memory>
#include <optional>
#include <tuple>
#include <utility>

#include "base/barrier_closure.h"
#include "base/scoped_observation.h"
#include "base/task/cancelable_task_tracker.h"
#include "base/uuid.h"
#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/functional/callback_helpers.h"
#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/string_number_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/types/expected.h"
#include "chrome/browser/profiles/profile.h"
// Same as the password store factory below: these sit behind
// //chrome/browser, and the symbols are in the same framework.
#include "chrome/browser/bookmarks/bookmark_model_factory.h"  // nogncheck
#include "chrome/browser/history/history_service_factory.h"  // nogncheck
// The factory sits behind //chrome/browser, which reaches //arkt through
// patch 0001, so this target cannot depend on it; the symbol is in the same
// framework.
#include "chrome/browser/password_manager/factories/profile_password_store_factory.h"  // nogncheck
#include "components/bookmarks/browser/base_bookmark_model_observer.h"
#include "components/bookmarks/browser/bookmark_model.h"
#include "components/bookmarks/browser/bookmark_node.h"
#include "components/history/core/browser/history_backend.h"
#include "components/history/core/browser/history_db_task.h"
#include "components/history/core/browser/history_service.h"
#include "components/history/core/browser/history_types.h"
#include "components/keyed_service/core/service_access_type.h"
#include "components/password_manager/core/browser/password_form.h"
#include "components/password_manager/core/browser/password_store/password_store_consumer.h"
#include "components/password_manager/core/browser/password_store/password_store_interface.h"
#include "components/password_manager/core/browser/password_store/stored_credential.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/storage_partition.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"
#include "net/cookies/canonical_cookie.h"
#include "net/cookies/cookie_access_result.h"
#include "net/cookies/cookie_constants.h"
#include "net/cookies/cookie_inclusion_status.h"
#include "net/cookies/cookie_options.h"
#include "services/network/public/mojom/cookie_manager.mojom.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"
#include "url/third_party/mozilla/url_parse.h"

namespace arkt {
namespace {

// Overwrites `text` so the plaintext does not outlive the batch.
void Zero(std::string& text) {
  std::fill(text.begin(), text.end(), '\0');
  text.clear();
}

void Zero(std::u16string& text) {
  std::fill(text.begin(), text.end(), u'\0');
  text.clear();
}

void PostDone(ImportDone done, ImportCounts counts) {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(std::move(done), std::move(counts)));
}

using CookieKey = std::tuple<std::string, std::string, std::string>;

// The recency of an imported cookie: last access, else creation.
base::Time Stamp(const ImportCookie& cookie) {
  return cookie.last_access.is_null() ? cookie.creation : cookie.last_access;
}

// The source URL the cookie is created from: host without the leading dot,
// https for a secure cookie, the recorded port when it is valid.
GURL SourceURL(const ImportCookie& cookie) {
  std::string host = cookie.host_key;
  if (!host.empty() && host.front() == '.') {
    host.erase(0, 1);
  }
  const bool https = cookie.secure || cookie.source_scheme == 2;
  std::string spec = https ? "https://" : "http://";
  spec += host;
  const int default_port = https ? 443 : 80;
  if (cookie.source_port > 0 && cookie.source_port < 65536 &&
      cookie.source_port != default_port) {
    spec += ":" + base::NumberToString(cookie.source_port);
  }
  spec += "/";
  return GURL(spec);
}

net::CookieSameSite SameSite(int value) {
  switch (value) {
    case 0:
      return net::CookieSameSite::NO_RESTRICTION;
    case 1:
      return net::CookieSameSite::LAX_MODE;
    case 2:
      return net::CookieSameSite::STRICT_MODE;
    default:
      return net::CookieSameSite::UNSPECIFIED;
  }
}

net::CookieSourceScheme SourceScheme(int value) {
  switch (value) {
    case 1:
      return net::CookieSourceScheme::kNonSecure;
    case 2:
      return net::CookieSourceScheme::kSecure;
    default:
      return net::CookieSourceScheme::kUnset;
  }
}

int SourcePort(int value) {
  return value > 0 && value < 65536 ? value : url::PORT_UNSPECIFIED;
}

net::CookiePriority Priority(int value) {
  switch (value) {
    case 0:
      return net::COOKIE_PRIORITY_LOW;
    case 2:
      return net::COOKIE_PRIORITY_HIGH;
    default:
      return net::COOKIE_PRIORITY_MEDIUM;
  }
}

// State shared by the answers of one cookie batch.
struct CookieBatch : public base::RefCounted<CookieBatch> {
  ImportCounts counts;
  ImportDone done;
  raw_ptr<network::mojom::CookieManager> manager = nullptr;

 private:
  friend class base::RefCounted<CookieBatch>;
  ~CookieBatch() = default;
};

void Fail(CookieBatch& batch, const std::string& reason) {
  batch.counts.failed++;
  batch.counts.reasons[reason]++;
}

void FinishCookies(scoped_refptr<CookieBatch> batch) {
  // The store writes in batches of its own; flush so the cookies are on disk
  // when the shell hears back.
  network::mojom::CookieManager* manager = batch->manager;
  auto finish = [](scoped_refptr<CookieBatch> batch) {
    std::move(batch->done).Run(std::move(batch->counts));
  };
  manager->FlushCookieStore(mojo::WrapCallbackWithDropHandler(
      base::BindOnce(finish, batch), base::BindOnce(finish, batch)));
}

// The cookie manager dropped a callback unanswered: `pending` cookies are
// counted failed and the batch ends.
void AbandonBatch(scoped_refptr<CookieBatch> batch, size_t pending) {
  batch->counts.failed += static_cast<int>(pending);
  batch->counts.reasons["no answer from the cookie store"] +=
      static_cast<int>(pending);
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](scoped_refptr<CookieBatch> batch) {
                       std::move(batch->done).Run(std::move(batch->counts));
                     },
                     batch));
}

void WriteCookies(scoped_refptr<CookieBatch> batch,
                  std::vector<ImportCookie> cookies,
                  const std::vector<net::CanonicalCookie>& existing) {
  // What the profile already holds, by key: skip an import that is not newer
  // than the stored cookie's last use.
  std::map<CookieKey, base::Time> held;
  for (const net::CanonicalCookie& cookie : existing) {
    held[{cookie.Name(), cookie.Domain(), cookie.Path()}] =
        cookie.LastAccessDate();
  }

  std::vector<ImportCookie> to_write;
  to_write.reserve(cookies.size());
  const base::Time now = base::Time::Now();
  for (ImportCookie& cookie : cookies) {
    // An expired cookie would only be deleted again.
    if (cookie.expires <= now) {
      batch->counts.skipped++;
      Zero(cookie.value);
      continue;
    }
    auto it = held.find({cookie.name, cookie.host_key, cookie.path});
    if (it != held.end() && it->second >= Stamp(cookie)) {
      batch->counts.skipped++;
      Zero(cookie.value);
      continue;
    }
    to_write.push_back(std::move(cookie));
  }
  if (to_write.empty()) {
    FinishCookies(std::move(batch));
    return;
  }

  auto barrier = base::BarrierClosure(
      to_write.size(),
      base::BindOnce(&FinishCookies, batch));
  for (ImportCookie& cookie : to_write) {
    const GURL url = SourceURL(cookie);
    // The network service caps an expiry at 400 days after the creation date
    // (ValidateAndAdjustExpiryDate, inside CookieManager::SetCanonicalCookie),
    // so a cookie created long ago would expire on arrival. The creation date
    // moves forward just enough to keep the expiry, and never past now.
    base::Time creation =
        cookie.creation.is_null() ? now : std::min(cookie.creation, now);
    creation = std::min(std::max(creation, cookie.expires - base::Days(400)),
                        now);
    base::Time last_access = std::max(
        cookie.last_access.is_null() ? creation : cookie.last_access, creation);
    // FromStorage, not CreateSanitizedCookie: these cookies come from another
    // Chromium cookie store, as the ones SQLitePersistentCookieStore loads, and
    // carry their own source scheme and port. The host key is the stored
    // domain: a leading dot makes a domain cookie.
    std::unique_ptr<net::CanonicalCookie> canonical =
        net::CanonicalCookie::FromStorage(
            cookie.name, cookie.value, cookie.host_key, cookie.path, creation,
            cookie.expires, last_access, /*last_update=*/last_access,
            cookie.secure, cookie.http_only, SameSite(cookie.same_site),
            Priority(cookie.priority), /*partition_key=*/std::nullopt,
            SourceScheme(cookie.source_scheme), SourcePort(cookie.source_port),
            net::CookieSourceType::kOther,
            net::CanonicalCookieFromStorageCallSite::kCookieManager);
    Zero(cookie.value);
    if (!canonical) {
      Fail(*batch, "not canonical");
      barrier.Run();
      continue;
    }
    net::CookieOptions options;
    options.set_include_httponly();
    options.set_same_site_cookie_context(
        net::CookieOptions::SameSiteCookieContext::MakeInclusiveForSet());
    batch->manager->SetCanonicalCookie(
        *canonical, url, options,
        mojo::WrapCallbackWithDropHandler(
            base::BindOnce(
                [](scoped_refptr<CookieBatch> batch, base::OnceClosure done,
                   net::CookieAccessResult result) {
                  if (result.status.IsInclude()) {
                    batch->counts.written++;
                  } else {
                    Fail(*batch, "refused: " + result.status.GetDebugString());
                  }
                  std::move(done).Run();
                },
                batch, barrier),
            base::BindOnce(
                [](scoped_refptr<CookieBatch> batch, base::OnceClosure done) {
                  Fail(*batch, "no answer from the cookie store");
                  std::move(done).Run();
                },
                batch, barrier)));
  }
}

}  // namespace

void ImportCookies(Profile* profile,
                   std::vector<ImportCookie> cookies,
                   ImportDone done) {
  auto batch = base::MakeRefCounted<CookieBatch>();
  batch->done = std::move(done);

  // A partitioned cookie written without its partition key would be readable
  // in every top-level context: skipped, whole.
  {
    std::vector<ImportCookie> unpartitioned;
    unpartitioned.reserve(cookies.size());
    for (ImportCookie& cookie : cookies) {
      if (cookie.partition_key.empty()) {
        unpartitioned.push_back(std::move(cookie));
      } else {
        batch->counts.skipped++;
        Zero(cookie.value);
      }
    }
    cookies = std::move(unpartitioned);
  }

  // Duplicates in the batch by (name, domain, path): the newest stamp wins,
  // the later entry on a tie.
  std::map<CookieKey, size_t> newest;
  for (size_t i = 0; i < cookies.size(); ++i) {
    const CookieKey key{cookies[i].name, cookies[i].host_key, cookies[i].path};
    auto [it, inserted] = newest.emplace(key, i);
    if (!inserted && Stamp(cookies[i]) >= Stamp(cookies[it->second])) {
      it->second = i;
    }
  }
  std::vector<ImportCookie> unique;
  unique.reserve(newest.size());
  for (size_t i = 0; i < cookies.size(); ++i) {
    const CookieKey key{cookies[i].name, cookies[i].host_key, cookies[i].path};
    if (newest.at(key) == i) {
      unique.push_back(std::move(cookies[i]));
    } else {
      batch->counts.skipped++;
      Zero(cookies[i].value);
    }
  }

  if (!profile) {
    for (ImportCookie& cookie : unique) {
      Zero(cookie.value);
      Fail(*batch, "no profile");
    }
  }
  if (unique.empty() || !profile) {
    PostDone(std::move(batch->done), std::move(batch->counts));
    return;
  }

  const size_t unique_size = unique.size();
  batch->manager =
      profile->GetDefaultStoragePartition()->GetCookieManagerForBrowserProcess();
  // Each answer is wrapped: if the cookie manager goes away without
  // answering (profile teardown), the batch fails instead of hanging.
  batch->manager->GetAllCookies(mojo::WrapCallbackWithDropHandler(
      base::BindOnce(
          [](scoped_refptr<CookieBatch> batch, std::vector<ImportCookie> cookies,
             const std::vector<net::CanonicalCookie>& existing) {
            WriteCookies(std::move(batch), std::move(cookies), existing);
          },
          batch, std::move(unique)),
      base::BindOnce(&AbandonBatch, batch, unique_size)));
}

namespace {

// Counts what the store holds after an import, for the log (counts only).
class StoreCounter : public password_manager::PasswordStoreConsumer {
 public:
  explicit StoreCounter(scoped_refptr<password_manager::PasswordStoreInterface>
                            store)
      : store_(std::move(store)) {}

  void Start() { store_->GetAutofillableLogins(weak_factory_.GetWeakPtr()); }

  void OnGetPasswordStoreResultsOrErrorFrom(
      password_manager::PasswordStoreInterface* store,
      base::expected<std::vector<password_manager::StoredCredential>,
                     password_manager::PasswordStoreBackendError> results)
      override {
    if (results.has_value()) {
      LOG(WARNING) << "ARKT: import passwords: the store holds "
                   << results->size() << " logins";
    } else {
      LOG(WARNING) << "ARKT: import passwords: the store could not be read";
    }
    delete this;
  }

 private:
  ~StoreCounter() override = default;
  scoped_refptr<password_manager::PasswordStoreInterface> store_;
  base::WeakPtrFactory<StoreCounter> weak_factory_{this};
};

// Writes imported logins after reading what the store holds: a login the
// store already has under the same (signon realm, username, action) is skipped
// unless the imported one is newer, and `written` counts what the store
// accepted, after it answered. Owns itself until it is done.
class LoginImport : public password_manager::PasswordStoreConsumer {
 public:
  LoginImport(scoped_refptr<password_manager::PasswordStoreInterface> store,
              std::vector<password_manager::StoredCredential> credentials,
              ImportCounts counts,
              ImportDone done)
      : store_(std::move(store)),
        credentials_(std::move(credentials)),
        counts_(std::move(counts)),
        done_(std::move(done)) {}

  void Start() { store_->GetAllLogins(weak_factory_.GetWeakPtr()); }

  void OnGetPasswordStoreResultsOrErrorFrom(
      password_manager::PasswordStoreInterface* store,
      base::expected<std::vector<password_manager::StoredCredential>,
                     password_manager::PasswordStoreBackendError> results)
      override {
    if (!results.has_value()) {
      counts_.failed += static_cast<int>(credentials_.size());
      counts_.reasons["password store unreadable"] +=
          static_cast<int>(credentials_.size());
      Finish();
      return;
    }
    std::map<std::tuple<std::string, std::u16string, std::string>, base::Time>
        held;
    for (const auto& login : *results) {
      held[{login.signon_realm, login.username_value, login.action.spec()}] =
          Stamp(login);
    }
    std::vector<password_manager::StoredCredential> to_write;
    for (auto& credential : credentials_) {
      auto it = held.find({credential.signon_realm, credential.username_value,
                           credential.action.spec()});
      if (it != held.end() && it->second >= Stamp(credential)) {
        counts_.skipped++;
        continue;
      }
      to_write.push_back(std::move(credential));
    }
    credentials_.clear();
    if (to_write.empty()) {
      Finish();
      return;
    }
    const int count = static_cast<int>(to_write.size());
    store_->AddLogins(std::move(to_write),
                      base::BindOnce(&LoginImport::OnAdded,
                                     weak_factory_.GetWeakPtr(), count));
  }

 private:
  ~LoginImport() override = default;

  // The later of last use and creation.
  static base::Time Stamp(const password_manager::StoredCredential& login) {
    return std::max(login.date_last_used, login.date_created);
  }

  void OnAdded(int count) {
    counts_.written += count;
    Finish();
  }

  void Finish() {
    (new StoreCounter(store_))->Start();
    std::move(done_).Run(std::move(counts_));
    delete this;
  }

  scoped_refptr<password_manager::PasswordStoreInterface> store_;
  std::vector<password_manager::StoredCredential> credentials_;
  ImportCounts counts_;
  ImportDone done_;
  base::WeakPtrFactory<LoginImport> weak_factory_{this};
};

}  // namespace

void ImportLogins(Profile* profile,
                  std::vector<ImportLogin> logins,
                  ImportDone done) {
  ImportCounts counts;
  // Duplicates in the batch by (signon_realm, username, action): the later
  // entry wins.
  using LoginKey = std::tuple<std::string, std::u16string, std::string>;
  std::map<LoginKey, size_t> last;
  for (size_t i = 0; i < logins.size(); ++i) {
    last[{logins[i].signon_realm, logins[i].username, logins[i].action_url}] = i;
  }

  std::vector<password_manager::StoredCredential> credentials;
  for (size_t i = 0; i < logins.size(); ++i) {
    ImportLogin& login = logins[i];
    const LoginKey key{login.signon_realm, login.username, login.action_url};
    if (last.at(key) != i) {
      counts.skipped++;
      Zero(login.password);
      continue;
    }
    const GURL url(login.origin_url);
    if (!url.is_valid() || login.signon_realm.empty()) {
      counts.failed++;
      counts.reasons["invalid url or signon realm"]++;
      Zero(login.password);
      continue;
    }
    password_manager::StoredCredential credential;
    credential.signon_realm = login.signon_realm;
    credential.url = url;
    credential.action = GURL(login.action_url);
    credential.username_value = login.username;
    credential.password_value =
        password_manager::PasswordString(std::move(login.password));
    credential.date_created = login.date_created;
    credential.date_last_used = login.date_last_used;
    credential.date_password_modified = login.date_created;
    credential.in_store = password_manager::PasswordForm::Store::kProfileStore;
    credentials.push_back(std::move(credential));
  }
  scoped_refptr<password_manager::PasswordStoreInterface> store =
      profile ? ProfilePasswordStoreFactory::GetForProfile(
                    profile, ServiceAccessType::EXPLICIT_ACCESS)
              : nullptr;
  if (!store) {
    counts.failed += static_cast<int>(credentials.size());
    counts.reasons["no password store"] +=
        static_cast<int>(credentials.size());
    PostDone(std::move(done), std::move(counts));
    return;
  }
  if (credentials.empty()) {
    // Nothing to write: log what the store holds, for a check after a
    // relaunch.
    (new StoreCounter(store))->Start();
    PostDone(std::move(done), std::move(counts));
    return;
  }
  (new LoginImport(std::move(store), std::move(credentials), std::move(counts),
                   std::move(done)))
      ->Start();
}

namespace {

// Runs on the history thread after every write queued before it, then calls
// back on the main thread.
class HistoryBarrier : public history::HistoryDBTask {
 public:
  explicit HistoryBarrier(base::OnceClosure reached)
      : reached_(std::move(reached)) {}

  bool RunOnDBThread(history::HistoryBackend*,
                     history::HistoryDatabase*) override {
    return true;
  }
  void DoneRunOnMainThread() override { std::move(reached_).Run(); }

 private:
  base::OnceClosure reached_;
};

// Owns one history batch until the history thread has caught up.
class HistoryImport {
 public:
  HistoryImport(ImportCounts counts, ImportDone done)
      : counts_(std::move(counts)), done_(std::move(done)) {}

  void Start(history::HistoryService* service) {
    service->ScheduleDBTask(
        FROM_HERE,
        std::make_unique<HistoryBarrier>(
            base::BindOnce(&HistoryImport::Finish, base::Unretained(this))),
        &tracker_);
  }

 private:
  void Finish() {
    std::move(done_).Run(std::move(counts_));
    base::SequencedTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE, this);
  }

  ImportCounts counts_;
  ImportDone done_;
  base::CancelableTaskTracker tracker_;
};

bool HistoryAccepts(const GURL& url) {
  return url.is_valid() &&
         (url.SchemeIsHTTPOrHTTPS() || url.SchemeIs(url::kFtpScheme) ||
          url.SchemeIsFile());
}

}  // namespace

void ImportHistory(Profile* profile,
                   std::vector<ImportHistoryEntry> entries,
                   base::Time after,
                   ImportDone done) {
  ImportCounts counts;
  history::HistoryService* service =
      profile ? HistoryServiceFactory::GetForProfile(
                    profile, ServiceAccessType::EXPLICIT_ACCESS)
              : nullptr;
  const base::Time oldest =
      base::Time::Now() -
      base::Days(history::HistoryBackend::kExpireDaysThreshold);
  int submitted = 0;
  for (const ImportHistoryEntry& entry : entries) {
    const int visits = static_cast<int>(entry.visits.size());
    if (!service) {
      counts.failed += visits;
      counts.reasons["no history service"] += visits;
      continue;
    }
    const GURL url(entry.url);
    if (!url.is_valid()) {
      counts.failed += visits;
      counts.reasons["invalid url"] += visits;
      continue;
    }
    if (!HistoryAccepts(url)) {
      counts.skipped += visits;
      continue;
    }
    for (const ImportVisit& visit : entry.visits) {
      // Older than the watermark: imported before. Older than the retention
      // window: Chromium's expirer would delete it again.
      if ((!after.is_null() && visit.time <= after) || visit.time < oldest) {
        counts.skipped++;
        continue;
      }
      const int core =
          visit.transition >= 0 && visit.transition <= ui::PAGE_TRANSITION_LAST_CORE
              ? visit.transition
              : static_cast<int>(ui::PAGE_TRANSITION_LINK);
      const ui::PageTransition transition = ui::PageTransitionFromInt(core);
      history::HistoryAddPageArgs args(
          url, visit.time, /*context_id=*/0, /*nav_entry_id=*/0,
          /*local_navigation_id=*/std::nullopt, /*referrer=*/GURL(),
          history::RedirectList(), transition,
          /*hidden=*/!ui::PageTransitionIsMainFrame(transition),
          history::SOURCE_OS_MIGRATION_IMPORTED,
          history::VisitResponseCodeCategory::kNot404,
          /*did_replace_entry=*/false,
          /*consider_for_ntp_most_visited=*/false,
          history::VisitContextEphemerality::kNotEphemeral,
          entry.title.empty() ? std::nullopt
                              : std::optional<std::u16string>(entry.title));
      service->AddPage(std::move(args));
      counts.written++;
      submitted++;
      if (visit.time > counts.latest_visit) {
        counts.latest_visit = visit.time;
      }
    }
  }
  if (submitted == 0) {
    PostDone(std::move(done), std::move(counts));
    return;
  }
  (new HistoryImport(std::move(counts), std::move(done)))->Start(service);
}

namespace {

const bookmarks::BookmarkNode* FindFolder(const bookmarks::BookmarkNode* parent,
                                          const std::u16string& title) {
  for (const auto& child : parent->children()) {
    if (child->is_folder() && child->GetTitle() == title) {
      return child.get();
    }
  }
  return nullptr;
}

const bookmarks::BookmarkNode* FindOrAddFolder(
    bookmarks::BookmarkModel* model,
    const bookmarks::BookmarkNode* parent,
    const std::u16string& title) {
  if (const bookmarks::BookmarkNode* found = FindFolder(parent, title)) {
    return found;
  }
  return model->AddFolder(parent, parent->children().size(), title);
}

bool HoldsBookmark(const bookmarks::BookmarkNode* folder,
                   const GURL& url,
                   const std::u16string& title) {
  for (const auto& child : folder->children()) {
    if (child->is_url() && child->url() == url && child->GetTitle() == title) {
      return true;
    }
  }
  return false;
}

void WriteBookmarks(bookmarks::BookmarkModel* model,
                    const std::vector<ImportBookmark>& batch,
                    ImportCounts& counts) {
  const bookmarks::BookmarkNode* imported =
      FindOrAddFolder(model, model->other_node(), u"Imported");
  for (const ImportBookmark& bookmark : batch) {
    const GURL url(bookmark.url);
    if (!url.is_valid()) {
      counts.failed++;
      counts.reasons["invalid url"]++;
      continue;
    }
    std::optional<base::Uuid> uuid;
    if (!bookmark.guid.empty()) {
      base::Uuid parsed = base::Uuid::ParseCaseInsensitive(bookmark.guid);
      if (parsed.is_valid()) {
        uuid = parsed;
      }
    }
    if (uuid &&
        model->GetNodeByUuid(
            *uuid, bookmarks::BookmarkModel::NodeTypeForUuidLookup::
                       kLocalOrSyncableNodes)) {
      counts.skipped++;
      continue;
    }
    // The folder is looked up without creating it: a path that does not exist
    // holds no duplicate.
    const bookmarks::BookmarkNode* folder = imported;
    for (const std::u16string& name : bookmark.folder_path) {
      folder = folder ? FindFolder(folder, name) : nullptr;
    }
    if (folder && HoldsBookmark(folder, url, bookmark.title)) {
      counts.skipped++;
      continue;
    }
    folder = imported;
    for (const std::u16string& name : bookmark.folder_path) {
      folder = FindOrAddFolder(model, folder, name);
    }
    model->AddURL(folder, folder->children().size(), bookmark.title, url,
                  /*meta_info=*/nullptr,
                  bookmark.date_added.is_null()
                      ? std::nullopt
                      : std::optional<base::Time>(bookmark.date_added),
                  uuid);
    counts.written++;
  }
}

// Waits for the bookmark model to load, writes, answers and deletes itself.
class BookmarkImport : public bookmarks::BaseBookmarkModelObserver {
 public:
  BookmarkImport(bookmarks::BookmarkModel* model,
                 std::vector<ImportBookmark> batch,
                 ImportDone done)
      : model_(model), batch_(std::move(batch)), done_(std::move(done)) {
    observation_.Observe(model_);
  }

  void BookmarkModelChanged() override {
    if (model_ && model_->loaded() && !finished_) {
      // Not from inside the observer notification.
      finished_ = true;
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE,
          base::BindOnce(&BookmarkImport::Write, base::Unretained(this)));
    }
  }

  void BookmarkModelBeingDeleted() override {
    observation_.Reset();
    model_ = nullptr;
    if (!finished_) {
      finished_ = true;
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE,
          base::BindOnce(&BookmarkImport::Write, base::Unretained(this)));
    }
  }

  void Start() {
    if (model_->loaded()) {
      BookmarkModelChanged();
    }
  }

 private:
  void Write() {
    ImportCounts counts;
    if (model_) {
      WriteBookmarks(model_, batch_, counts);
    } else {
      counts.failed = static_cast<int>(batch_.size());
      counts.reasons["bookmark model went away"] = counts.failed;
    }
    observation_.Reset();
    std::move(done_).Run(std::move(counts));
    delete this;
  }

  raw_ptr<bookmarks::BookmarkModel> model_;
  std::vector<ImportBookmark> batch_;
  ImportDone done_;
  bool finished_ = false;
  base::ScopedObservation<bookmarks::BookmarkModel,
                          bookmarks::BookmarkModelObserver>
      observation_{this};
};

}  // namespace

void ImportBookmarks(Profile* profile,
                     std::vector<ImportBookmark> bookmarks,
                     ImportDone done) {
  bookmarks::BookmarkModel* model =
      profile ? BookmarkModelFactory::GetForBrowserContext(profile) : nullptr;
  if (!model) {
    ImportCounts counts;
    counts.failed = static_cast<int>(bookmarks.size());
    counts.reasons["no bookmark model"] = counts.failed;
    PostDone(std::move(done), std::move(counts));
    return;
  }
  (new BookmarkImport(model, std::move(bookmarks), std::move(done)))->Start();
}

}  // namespace arkt
