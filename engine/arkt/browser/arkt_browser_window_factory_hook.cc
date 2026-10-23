#include "arkt/browser/arkt_browser_window_factory_hook.h"

namespace arkt {

namespace {
CreateBrowserWindowFn g_create_browser_window = nullptr;
}  // namespace

void SetCreateBrowserWindowOverride(CreateBrowserWindowFn fn) {
  g_create_browser_window = fn;
}

CreateBrowserWindowFn GetCreateBrowserWindowOverride() {
  return g_create_browser_window;
}

}  // namespace arkt
