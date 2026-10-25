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
//
// Task W3-5: a page whose title becomes "arkt-selftest <command> [argument]"
// (set over CDP) runs a facade call on its tab and logs the outcome: close
// honour|skip, close-other <session id>, state, navigate <url>, reload
// [<session id>], activate <session id>, devtools (Chromium's Developer
// Tools command through the host), and pending (a createTab deferred inside
// an NSMenu, then navigate, activate and close on its handle before the
// insert has run). W3-5b adds history, goto <offset>, duplicate, actions,
// run <action id> (anchored to a view above the card), eval (test API
// values, with and without a user gesture), hold (a beforeunload handler
// with a user gesture, through the test API) and answer <session id>
// accept|cancel. Words starting with '#' are ignored.
//
// Task W3-8: with --arkt-menu-probe[=<options>] the embedder waits for
// NSApplicationDidFinishLaunchingNotification, replaces Chromium's main menu
// with an Arkt-shaped one (App menu with Quit, a File menu with Cmd-W
// "Archive Tab" and Shift-Cmd-W "Close Window" targeting the embedder) and
// only then becomes ready. Options, comma separated: "filetag" tags the File
// menu IDC_FILE_MENU, "bookmarks" adds a hidden item tagged
// IDC_BOOKMARKS_MENU. The command menu-check resolves Cmd-W, Shift-Cmd-W,
// Cmd-Q and Cmd-T through Chromium's key-equivalent search and logs the
// items, the command each maps to and the menu state afterwards.
inline constexpr char kFacadeSelfTestSwitch[] = "arkt-facade-selftest";
inline constexpr char kMenuProbeSwitch[] = "arkt-menu-probe";

// The self-test embedder, or nil when the switch is absent.
id<ArktEngineEmbedder> CreateSelfTestEmbedder();

}  // namespace arkt

#endif  // ARKT_API_ARKT_SELFTEST_EMBEDDER_H_
