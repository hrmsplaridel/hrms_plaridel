const {
  locatorAttachmentRequiredError,
  parseLocatorDateOnly,
  validateLocatorRequiredFields,
} = require('./locatorFilingRules');

function locatorSubmissionError(statusCode, payload) {
  const error = new Error(payload?.error || 'Failed to submit locator request');
  error.statusCode = statusCode;
  error.payload = payload;
  return error;
}

function assertDependency(name, value) {
  if (typeof value !== 'function') {
    throw new TypeError('Locator submission service requires ' + name);
  }
}

function createLocatorSubmissionService({
  dbPool,
  getDepartmentHeadForEmployee,
  getEmployeeDepartment,
  validateWorkingDay,
  getLocatorTypeByCode,
  findConflicts,
  fetchSlipDetails,
  mapInsertedRow,
  notifyAfterSubmit,
  broadcastSubmitted,
  logger = console,
}) {
  if (!dbPool?.connect || !dbPool?.query) {
    throw new TypeError('Locator submission service requires a database pool');
  }
  assertDependency('getDepartmentHeadForEmployee', getDepartmentHeadForEmployee);
  assertDependency('getEmployeeDepartment', getEmployeeDepartment);
  assertDependency('validateWorkingDay', validateWorkingDay);
  assertDependency('getLocatorTypeByCode', getLocatorTypeByCode);
  assertDependency('findConflicts', findConflicts);
  assertDependency('fetchSlipDetails', fetchSlipDetails);
  assertDependency('mapInsertedRow', mapInsertedRow);
  assertDependency('notifyAfterSubmit', notifyAfterSubmit);
  assertDependency('broadcastSubmitted', broadcastSubmitted);

  async function submit({
    employeeUserId,
    slipDate,
    office,
    reason,
    requestType,
    amIn,
    amOut,
    pmIn,
    pmOut,
    attachment = null,
  }) {
    const fieldValidation = validateLocatorRequiredFields({
      slipDate,
      requestType,
      office,
      reason,
      slots: { amIn, amOut, pmIn, pmOut },
    });
    if (!fieldValidation.valid) {
      throw locatorSubmissionError(400, { error: fieldValidation.error });
    }

    const slipDateInfo = parseLocatorDateOnly(slipDate);
    const attachmentPath = (attachment?.path || '').toString().trim() || null;
    const client = await dbPool.connect();
    let insertedRow = null;
    let submitStatus = null;
    let departmentHeadUserId = null;

    try {
      await client.query('BEGIN');

      const deptInfo = await getDepartmentHeadForEmployee(client, employeeUserId);
      const ownDept = await getEmployeeDepartment(client, employeeUserId);
      submitStatus = deptInfo ? 'pending_department_head' : 'pending_hr';
      departmentHeadUserId = deptInfo?.departmentHeadUserId || null;
      const departmentId = deptInfo?.departmentId || ownDept?.departmentId || null;

      const workingDayCheck = await validateWorkingDay(
        client,
        employeeUserId,
        slipDateInfo
      );
      if (!workingDayCheck.ok) {
        throw locatorSubmissionError(400, { error: workingDayCheck.error });
      }

      const locatorType = await getLocatorTypeByCode(client, requestType, {
        activeOnly: true,
      });
      if (!locatorType) {
        throw locatorSubmissionError(400, { error: 'Invalid request_type' });
      }
      const attachmentError = locatorAttachmentRequiredError(
        locatorType,
        Boolean(attachmentPath)
      );
      if (attachmentError) {
        throw locatorSubmissionError(400, { error: attachmentError });
      }

      const conflictCheck = await findConflicts(client, {
        employeeId: employeeUserId,
        slipDate,
        slots: { amIn, amOut, pmIn, pmOut },
        phase: 'submission',
      });
      if (!conflictCheck.ok) {
        throw locatorSubmissionError(409, {
          error:
            conflictCheck.message ||
            'Locator request conflicts with an existing record.',
          code: conflictCheck.code || 'locator_conflict',
          conflicts: conflictCheck.conflicts || {},
        });
      }

      const inserted = await client.query(
        `INSERT INTO locator_slips (
           employee_id,
           department_id,
           slip_date,
           am_in,
           am_out,
           pm_in,
           pm_out,
           request_type,
           office,
           reason,
           attachment_name,
           attachment_path,
           attachment_mime_type,
           attachment_uploaded_at,
           status,
           created_at,
           updated_at
         ) VALUES (
           $1::uuid,
           $2::uuid,
           $3::date,
           $4::boolean,
           $5::boolean,
           $6::boolean,
           $7::boolean,
           $8::text,
           $9::text,
           $10::text,
           $11::text,
           $12::text,
           $13::text,
           CASE WHEN $12::text IS NULL THEN NULL ELSE now() END,
           $14::text,
           now(),
           now()
         )
         RETURNING *`,
        [
          employeeUserId,
          departmentId,
          slipDate,
          amIn,
          amOut,
          pmIn,
          pmOut,
          requestType,
          office,
          reason,
          attachmentPath
            ? (attachment?.name || 'attachment').toString()
            : null,
          attachmentPath,
          attachmentPath ? attachment?.mimeType || null : null,
          submitStatus,
        ]
      );
      insertedRow = inserted.rows[0];
      if (!insertedRow?.id) {
        throw new Error('Locator request insert did not return a saved record.');
      }
      await client.query('COMMIT');
    } catch (error) {
      try {
        await client.query('ROLLBACK');
      } catch (_) {}
      throw error;
    } finally {
      client.release();
    }

    let savedSlip = insertedRow;
    try {
      savedSlip = mapInsertedRow(insertedRow) || insertedRow;
    } catch (error) {
      logger.error('[locator submission mapping]', error);
    }
    try {
      savedSlip =
        (await fetchSlipDetails(dbPool, insertedRow.id)) || savedSlip;
    } catch (error) {
      logger.error('[locator submission details]', error);
    }

    try {
      await notifyAfterSubmit(dbPool, {
        slipId: insertedRow.id,
        status: submitStatus,
        employeeUserId,
        employeeName: savedSlip?.employee_name || 'Employee',
        slipDate,
        amIn,
        amOut,
        pmIn,
        pmOut,
        requestType,
        departmentHeadUserId,
      });
    } catch (error) {
      logger.error('[locator notification]', error);
    }

    try {
      broadcastSubmitted(savedSlip || insertedRow);
    } catch (error) {
      logger.error('[locator websocket]', error);
    }

    return savedSlip;
  }

  return { submit };
}

module.exports = {
  createLocatorSubmissionService,
  locatorSubmissionError,
};
