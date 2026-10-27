#ifndef ARKT_API_ARKT_IMPORT_WRITER_H_
#define ARKT_API_ARKT_IMPORT_WRITER_H_

#include <map>
#include <string>
#include <vector>

#include "base/functional/callback_forward.h"
#include "base/time/time.h"

class Profile;

namespace arkt {

// Imported data as plain values, filled by the facade from the shell's
// records (#512). Secrets are in `value` and `password`; the writer zeroes
// them when it is done with them.
struct ImportCookie {
  std::string host_key;
  std::string name;
  std::string path;
  std::string value;
  base::Time expires;
  base::Time creation;
  base::Time last_access;
  bool secure = false;
  bool http_only = false;
  // Chromium's enum values: samesite -1..2, priority 0..2, source scheme 0..2.
  int same_site = -1;
  int priority = 1;
  int source_scheme = 0;
  int source_port = -1;
};

struct ImportLogin {
  std::string origin_url;
  std::string action_url;
  std::string signon_realm;
  std::u16string username;
  std::u16string password;
  base::Time date_created;
  base::Time date_last_used;
};

// written + skipped + failed is the batch size. `reasons` counts failures by
// reason; it never holds a host, a name or a value.
struct ImportCounts {
  int written = 0;
  int skipped = 0;
  int failed = 0;
  std::map<std::string, int> reasons;
};

using ImportDone = base::OnceCallback<void(ImportCounts)>;

// Writes through the profile's CookieManager (SetCanonicalCookie, HttpOnly and
// an inclusive SameSite context). `done` runs after every write answered and
// the cookie store was flushed to disk, never inside the call.
void ImportCookies(Profile* profile,
                   std::vector<ImportCookie> cookies,
                   ImportDone done);

// Writes through the profile's password store (AddLogins). `done` runs after
// the store applied them, never inside the call.
void ImportLogins(Profile* profile,
                  std::vector<ImportLogin> logins,
                  ImportDone done);

}  // namespace arkt

#endif  // ARKT_API_ARKT_IMPORT_WRITER_H_
