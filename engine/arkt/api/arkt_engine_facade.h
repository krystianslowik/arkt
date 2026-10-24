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
};

// The facade object handed to -[ArktEngineEmbedder engineDidStart:]
// (arkt_engine.h). Created once; it observes every Arkt browser window from
// then on and delivers its events in batches from posted tasks, never from
// inside a Chromium notification (Decision 3).
//
// Week-3 scope of this first cut (Task W3-3): browsers, tab lists, tab
// creation, activation, navigation and closes with the nesting guard, and the
// TabCreated, TabClosed, ActiveTabChanged, WindowOpened and WindowClosed
// events. Host mode, per-tab state events, tab containers, history,
// duplication, extension actions and the test API are Tasks W3-4 and W3-5;
// until then those calls are logged and answer with empty values.
id<ArktEngine> CreateEngineFacade(FacadeDelegate* delegate);

// The facade's handle for `browser`, or nil if it is not an Arkt browser
// window the facade knows.
id<ArktBrowserHandle> BrowserHandleFor(BrowserWindowInterface* browser);

// From the quit start on, tabs that close report ArktCloseReasonAppTerminating
// (Decision 12); a cancelled quit clears it.
void SetFacadeTerminating(bool terminating);

}  // namespace arkt

#endif  // ARKT_API_ARKT_ENGINE_FACADE_H_
