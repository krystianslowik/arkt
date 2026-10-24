#ifndef ARKT_API_ARKT_EMBEDDER_H_
#define ARKT_API_ARKT_EMBEDDER_H_

#include <string>

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
// When it is present:
// - StartEmbedder creates the facade, registers the lifetime keep-alive and
//   the quit seams, records the URL arguments as startup window requests and
//   calls -engineDidStart: on the embedder.
// - Until the embedder calls -embedderReady, engine-initiated windows are
//   queued: a URL argument is a recorded request (no Browser yet); a Browser
//   Chromium creates on its own (Dock reopen, a URL from another application)
//   has no seam before its window is built, so its window is held hidden and
//   its host request is queued. After -embedderReady the queue is replayed in
//   order and each request asks -hostForEngineWindowRequest:. Until host mode
//   lands (Task W3-4) the placeholder host stays in use and the embedder's
//   answer is only logged.

// The profile the hook started with (PostProfileInit, initial profile).
void SetEmbedderProfile(Profile* profile);

// Looks up the embedder class and, when it is present, starts the seam.
// Called once from PostBrowserStart.
void StartEmbedder();

// True when an embedder class was found.
bool HasEmbedder();

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
