#ifndef ARKT_API_ARKT_ENGINE_FACADE_H_
#define ARKT_API_ARKT_ENGINE_FACADE_H_

#import <Foundation/Foundation.h>

#import "arkt/api/arkt_engine.h"

class BrowserWindowInterface;

namespace arkt {

// What the facade reports back to the embedder seam (arkt_embedder.mm).
class FacadeDelegate {
 public:
  virtual ~FacadeDelegate() = default;
  // -[ArktEngine embedderReady] and -[ArktEngine embedderFailed].
  virtual void OnEmbedderReady() = 0;
  virtual void OnEmbedderFailed() = 0;
  // -[ArktEngine createBrowserWithHost:]: a TYPE_NORMAL Browser for the
  // initial profile in `host`'s window, created synchronously.
  virtual BrowserWindowInterface* CreateBrowserForHost(
      id<ArktWindowHost> host) = 0;
};

// The facade object handed to -[ArktEngineEmbedder engineDidStart:]
// (arkt_engine.h). Created once; it observes every Arkt browser window from
// then on and delivers its events in batches from posted tasks, never from
// inside a Chromium notification (Decision 3).
//
// Scope (Tasks W3-3 to W3-5): browsers, shell-created browsers
// (createBrowserWithHost:), tabs with stable containers, navigation and
// history, duplication, both close modes with every close reason, all event
// kinds, extension actions of embedder windows, and the test API behind
// --arkt-engine-test-api. Calls on a handle whose deferred insert is pending
// queue behind it.
id<ArktEngine> CreateEngineFacade(FacadeDelegate* delegate);

// The facade's handle for `browser`, or nil if it is not an Arkt browser
// window the facade knows.
id<ArktBrowserHandle> BrowserHandleFor(BrowserWindowInterface* browser);

// A window held hidden before -embedderReady is not listed and not announced
// until replay has given it the embedder's host and released it; the seam
// then calls this (WindowOpened, then TabCreated for its tabs).
void AdoptHeldBrowser(BrowserWindowInterface* browser);

// From the quit start on, tabs that close report ArktCloseReasonAppTerminating
// (Decision 12); a cancelled quit clears it.
void SetFacadeTerminating(bool terminating);

}  // namespace arkt

#endif  // ARKT_API_ARKT_ENGINE_FACADE_H_
