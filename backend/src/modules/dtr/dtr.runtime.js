'use strict';
function createDtrRuntime(dependencies) {
  const runtime = { ...dependencies };
  Object.assign(runtime, require('./policies/calendar')(runtime));
  Object.assign(runtime, require('./policies/reportQueries')(runtime));
  Object.assign(runtime, require('./policies/locatorLabels')(runtime));
  Object.assign(runtime, require('./repositories/attendancePolicies')(runtime));
  Object.assign(runtime, require('./repositories/holidays')(runtime));
  Object.assign(runtime, require('./services/shifts')(runtime));
  Object.assign(runtime, require('./serializers/assignments')(runtime));
  Object.assign(runtime, require('./repositories/assignments')(runtime));
  Object.assign(runtime, require('./repositories/coverage')(runtime));
  Object.assign(runtime, require('./services/attendanceRemarks')(runtime));
  Object.assign(runtime, require('./serializers/audit')(runtime));
  Object.assign(runtime, require('./services/reportHolidays')(runtime));
  Object.assign(runtime, require('./services/reportLeave')(runtime));
  Object.assign(runtime, require('./services/reportAbsences')(runtime));
  Object.assign(runtime, require('./services/reportPolicies')(runtime));
  Object.assign(runtime, require('./services/penalties')(runtime));
  Object.assign(runtime, require('./services/reportCutoff')(runtime));
  Object.assign(runtime, require('./services/reportRows')(runtime));
  Object.assign(runtime, require('./services/reportLocators')(runtime));
  Object.assign(runtime, require('./use-cases/completeReport')(runtime));
  Object.assign(runtime, require('./controllers/list.controller')(runtime));
  return runtime;
}
module.exports = { createDtrRuntime };
