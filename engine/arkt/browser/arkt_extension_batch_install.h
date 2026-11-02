#ifndef ARKT_BROWSER_ARKT_EXTENSION_BATCH_INSTALL_H_
#define ARKT_BROWSER_ARKT_EXTENSION_BATCH_INSTALL_H_

#include <string>
#include <vector>

#include "base/functional/callback.h"

class Profile;

namespace arkt {

// How one id of a batch ended (#513).
struct ExtensionInstallOutcome {
  enum class Status { kInstalled, kAlreadyInstalled, kFailed };
  std::string id;
  Status status = Status::kFailed;
  // kFailed only: a short sentence without the id or the name.
  std::string reason;
};

// Installs Chrome Web Store extensions by id into `profile` with ONE native
// confirmation for the whole batch (no patch: a WebstoreStandaloneInstaller
// subclass whose per-extension prompt is replaced by the batch sheet).
//
// - An id `profile` already has is kAlreadyInstalled and left alone.
// - Every other id's Web Store listing is fetched; once all fetches are done,
//   one sheet on the key window lists the names of the extensions found. On
//   accept they are installed without a further prompt; on decline (or with
//   no window to ask in) they fail with "not confirmed". The sheet shows each
//   extension's name with the permission warnings Chrome's own install prompt
//   shows (PermissionMessages), and scrolls when the list is long.
// - A bad id, a listing the store does not return (missing item or
//   unreachable store, which the fetch cannot tell apart), a listing that has
//   not answered after 30 s and an install error fail only their own id.
//
// `done` runs from a posted task, never inside this call, with one outcome per
// distinct id in the order the ids first appear; also for an empty batch.
void InstallWebstoreExtensions(
    Profile* profile,
    std::vector<std::string> ids,
    base::OnceCallback<void(std::vector<ExtensionInstallOutcome>)> done);

// Ends every batch in progress early (the import was cancelled): sheets close,
// fetches stop, ids not being installed yet fail with "cancelled", and each
// batch's `done` runs as usual. Does nothing when no batch is running.
void CancelWebstoreExtensionInstalls();

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSION_BATCH_INSTALL_H_
