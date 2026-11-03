'use strict';
function createLocatorRuntime(dependencies) {
  const runtime = { ...dependencies };
  Object.assign(runtime, require('./policies/types')(runtime));
  Object.assign(runtime, require('./policies/requests')(runtime));
  Object.assign(runtime, require('./serializers/types')(runtime));
  Object.assign(runtime, require('./repositories/types')(runtime));
  Object.assign(runtime, require('./services/events')(runtime));
  Object.assign(runtime, require('./infrastructure/attachments')(runtime));
  Object.assign(runtime, require('./serializers/requests')(runtime));
  Object.assign(runtime, require('./repositories/requests')(runtime));
  require('./infrastructure/initialize')(runtime);
  Object.assign(runtime, require('./services/submission')(runtime));
  Object.assign(runtime, require('./services/paperRecording')(runtime));
  return runtime;
}
module.exports = { createLocatorRuntime };
