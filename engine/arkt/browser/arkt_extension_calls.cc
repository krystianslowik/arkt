#include "arkt/browser/arkt_extension_calls.h"

#include "extensions/browser/activity.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/process_manager.h"
#include "extensions/common/extension.h"

namespace arkt {

bool IsExtensionApiCallInFlight(content::BrowserContext* context,
                                std::string_view function) {
  if (!context) {
    return false;
  }
  extensions::ExtensionRegistry* registry =
      extensions::ExtensionRegistry::Get(context);
  extensions::ProcessManager* process_manager =
      extensions::ProcessManager::Get(context);
  if (!registry || !process_manager) {
    return false;
  }
  for (const auto& extension : registry->enabled_extensions()) {
    for (const auto& keepalive :
         process_manager->GetServiceWorkerKeepaliveDataForRecords(
             extension->id())) {
      if (keepalive.activity_type == extensions::Activity::API_FUNCTION &&
          keepalive.extra_data == function) {
        return true;
      }
    }
    for (const auto& [type, extra_data] :
         process_manager->GetLazyKeepaliveActivities(extension.get())) {
      if (type == extensions::Activity::API_FUNCTION &&
          extra_data == function) {
        return true;
      }
    }
  }
  return false;
}

}  // namespace arkt
