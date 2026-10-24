#ifndef ARKT_API_ARKT_SELFTEST_EMBEDDER_H_
#define ARKT_API_ARKT_SELFTEST_EMBEDDER_H_

#import <Foundation/Foundation.h>

#import "arkt/api/arkt_engine.h"

namespace arkt {

// The engine lane's check of the facade without the Swift app (week-3 plan,
// Task W3-4 step 4): with --arkt-facade-selftest and no ArktShellEmbedder
// class in the process (the GN-built Chromium.app), the hook uses this
// embedder instead. It supplies plain NSWindow hosts, opens one
// shell-initiated window after it is ready, mounts each window's active tab
// in its card, and logs every facade event as "ARKT selftest <event>".
//
// Switch values: none, ready at once; "hold", ready after 5 s (for the
// readiness queue, with --arkt-debug-reopen-before-ready); "fail",
// embedderFailed after 5 s. --arkt-facade-selftest-url=<url> sets the first
// tab of the shell-initiated window (a data: page otherwise).
inline constexpr char kFacadeSelfTestSwitch[] = "arkt-facade-selftest";

// The self-test embedder, or nil when the switch is absent.
id<ArktEngineEmbedder> CreateSelfTestEmbedder();

}  // namespace arkt

#endif  // ARKT_API_ARKT_SELFTEST_EMBEDDER_H_
