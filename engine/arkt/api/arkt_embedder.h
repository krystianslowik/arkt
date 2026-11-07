#ifndef ARKT_API_ARKT_EMBEDDER_H_
#define ARKT_API_ARKT_EMBEDDER_H_

#import <Foundation/Foundation.h>

#include <string>

#import "arkt/api/arkt_engine.h"

class BrowserWindowInterface;
class Profile;

namespace arkt {

class ArktBrowserWindow;

// The embedder seam (week-3 plan, Decisions 1, 2, 3 and 13; Task W3-3).
//
// The Swift app defines @objc(ArktShellEmbedder) in its main executable. The
// hook looks the class up through the Objective-C runtime; when it is absent
// (the GN-built Chromium.app) every function here is a no-op and the engine
// keeps its placeholder host.
//
// When it is present (or, without one, the built-in self-test embedder behind
// --arkt-facade-selftest, arkt_selftest_embedder.h):
// - StartEmbedder creates the facade, registers the lifetime keep-alive and
//   the quit seams, records the URL arguments as startup window requests and
//   calls -engineDidStart: on the embedder.
// - Until the embedder calls -embedderReady, engine-initiated windows are
//   queued: a URL argument is a recorded request (no Browser yet); a Browser
//   Chromium creates on its own (Dock reopen, a URL from another application)
//   has no seam before its window is built, so its window gets the
//   placeholder host, is held hidden and its host request is queued with the
//   kind known at creation. After -embedderReady the queue is replayed in
//   order: each request asks -hostForEngineWindowRequest:, a held window
//   moves to the embedder's host and is shown.
// - After -embedderReady an engine-initiated window asks the embedder for its
//   host inside Browser construction (Task W3-4); a nil or unusable answer
//   keeps the placeholder host.
// - After -embedderFailed a window Chromium creates is held and closed.

// The profile the hook started with (PostProfileInit, initial profile).
void SetEmbedderProfile(Profile* profile);

// The same profile, for the facade's import writes (#512); nil before the
// hook set it.
Profile* EmbedderProfile();

// Looks up the embedder class and, when it is present, starts the seam.
// Called once from PostBrowserStart.
void StartEmbedder();

// True when an embedder class was found.
bool HasEmbedder();

// The host for a new Arkt browser window, asked by the window factory inside
// Browser construction before the window exists: the host passed to
// -[ArktEngine createBrowserWithHost:], or, once the embedder is ready, its
// answer to -hostForEngineWindowRequest: (week-3 plan, Decision 2). nil means
// the placeholder host.
id<ArktWindowHost> HostForArktBrowserWindow(BrowserWindowInterface* browser);

// True when `host` implements what ArktBrowserWindow uses and returns a
// window and a card. Otherwise `missing` names the first gap.
bool IsUsableWindowHost(id host, std::string* missing);

// Called by the window factory for every Arkt browser window, inside Browser
// construction, before the window is shown.
void OnArktBrowserWindowCreated(BrowserWindowInterface* browser,
                                ArktBrowserWindow* window);

// True while the main thread is inside a nested run loop: a nested
// base::RunLoop, or a native loop such as NSMenu tracking or an NSAlert modal
// session (the main run loop is in a mode other than the default one).
bool IsInNestedLoop();

// For logs: whether a base::RunLoop is nested and the main run loop's mode.
std::string DescribeRunLoopNesting();

}  // namespace arkt

#endif  // ARKT_API_ARKT_EMBEDDER_H_
