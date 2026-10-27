#include "arkt/api/arkt_import_writer.h"

#include <algorithm>
#include <memory>
#include <optional>
#include <tuple>
#include <utility>

#include "base/barrier_closure.h"
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
// The factory sits behind //chrome/browser, which reaches //arkt through
// patch 0001, so this target cannot depend on it; the symbol is in the same
// framework.
#include "chrome/browser/password_manager/factories/profile_password_store_factory.h"  // nogncheck
#include "components/keyed_service/core/service_access_type.h"
#include "components/password_manager/core/browser/password_form.h"
#include "components/password_manager/core/browser/password_store/password_store_consumer.h"
#include "components/password_manager/core/browser/password_store/password_store_interface.h"
#include "components/password_manager/core/browser/password_store/stored_credential.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/storage_partition.h"
#include "net/cookies/canonical_cookie.h"
#include "net/cookies/cookie_access_result.h"
#include "net/cookies/cookie_constants.h"
#include "net/cookies/cookie_inclusion_status.h"
#include "net/cookies/cookie_options.h"
#include "services/network/public/mojom/cookie_manager.mojom.h"
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
  manager->FlushCookieStore(base::BindOnce(
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
            batch, barrier));
  }
}

}  // namespace

void ImportCookies(Profile* profile,
                   std::vector<ImportCookie> cookies,
                   ImportDone done) {
  auto batch = base::MakeRefCounted<CookieBatch>();
  batch->done = std::move(done);

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

  batch->manager =
      profile->GetDefaultStoragePartition()->GetCookieManagerForBrowserProcess();
  batch->manager->GetAllCookies(base::BindOnce(
      [](scoped_refptr<CookieBatch> batch, std::vector<ImportCookie> cookies,
         const std::vector<net::CanonicalCookie>& existing) {
        WriteCookies(std::move(batch), std::move(cookies), existing);
      },
      batch, std::move(unique)));
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
  counts.written = static_cast<int>(credentials.size());

  scoped_refptr<password_manager::PasswordStoreInterface> store =
      profile ? ProfilePasswordStoreFactory::GetForProfile(
                    profile, ServiceAccessType::EXPLICIT_ACCESS)
              : nullptr;
  if (!store || credentials.empty()) {
    if (store) {
      // Nothing to write: log what the store holds, for a check after a
      // relaunch.
      (new StoreCounter(store))->Start();
    }
    if (!store && !credentials.empty()) {
      counts.failed += counts.written;
      counts.reasons["no password store"] += counts.written;
      counts.written = 0;
    }
    PostDone(std::move(done), std::move(counts));
    return;
  }
  store->AddLogins(
      std::move(credentials),
      base::BindOnce(
          [](scoped_refptr<password_manager::PasswordStoreInterface> store,
             ImportDone done, ImportCounts counts) {
            (new StoreCounter(store))->Start();
            std::move(done).Run(std::move(counts));
          },
          store, std::move(done), std::move(counts)));
}

}  // namespace arkt
