'use strict';
function createLeaveRuntime(dependencies) {
  const runtime = { ...dependencies };
  require('./infrastructure/initialize')(runtime);
  Object.assign(runtime, require('./services/events')(runtime));
  Object.assign(runtime, require('./services/signatories')(runtime));
  Object.assign(runtime, require('./policies/dates')(runtime));
  Object.assign(runtime, require('./policies/leaveTypes')(runtime));
  Object.assign(runtime, require('./policies/requestDetails')(runtime));
  Object.assign(runtime, require('./repositories/leaveRequests')(runtime));
  Object.assign(runtime, require('./infrastructure/attachments')(runtime));
  Object.assign(runtime, require('./controllers/typeErrors')(runtime));
  Object.assign(runtime, require('./services/workingDays')(runtime));
  Object.assign(runtime, require('./serializers/leaveTypes')(runtime));
  Object.assign(runtime, require('./serializers/leaveRequests')(runtime));
  Object.assign(runtime, require('./use-cases/leaveCredits')(runtime));
  Object.assign(runtime, require('./repositories/reviewQueries')(runtime));
  Object.assign(runtime, require('./services/annualEntitlements')(runtime));
  Object.assign(runtime, require('./repositories/leaveTypes')(runtime));
  Object.assign(runtime, require('./use-cases/finalizeApproval')(runtime));
  return runtime;
}
module.exports = { createLeaveRuntime };
