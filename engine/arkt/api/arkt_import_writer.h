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
  // The top_frame_site_key; non-empty means partitioned, which is skipped.
  std::string partition_key;
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

// One visit of an imported history entry; `transition` is Chromium's core
// page transition type (0 link ... 10 keyword generated).
struct ImportVisit {
  base::Time time;
  int transition = 0;
};

struct ImportHistoryEntry {
  std::string url;
  std::u16string title;
  std::vector<ImportVisit> visits;
};

struct ImportBookmark {
  std::string url;
  std::u16string title;
  // Empty when the source had none.
  std::string guid;
  base::Time date_added;
  // Folder titles below the Imported folder, outermost first.
  std::vector<std::u16string> folder_path;
};

// written + skipped + failed is the batch size (visits for a history batch).
// `reasons` counts failures by reason; it never holds a host, a name or a
// value.
struct ImportCounts {
  int written = 0;
  int skipped = 0;
  int failed = 0;
  std::map<std::string, int> reasons;
  // History only: the newest visit time written; null when none was.
  base::Time latest_visit;
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

// Writes every visit through the profile's HistoryService (AddPage per
// visit, source SOURCE_OS_MIGRATION_IMPORTED). A visit at or before `after`
// (when it is not null), older than the history retention window, or of a
// URL the history refuses (not http, https, ftp or file) is skipped. `done`
// runs after the history thread processed the writes, never inside the call.
void ImportHistory(Profile* profile,
                   std::vector<ImportHistoryEntry> entries,
                   base::Time after,
                   ImportDone done);

// Writes under "Other bookmarks" / "Imported" in the profile's BookmarkModel,
// folders kept. A bookmark whose guid the model holds, or whose url and title
// the target folder holds, is skipped. `done` runs after the write, never
// inside the call, and waits for the model to load.
void ImportBookmarks(Profile* profile,
                     std::vector<ImportBookmark> bookmarks,
                     ImportDone done);

}  // namespace arkt

#endif  // ARKT_API_ARKT_IMPORT_WRITER_H_
