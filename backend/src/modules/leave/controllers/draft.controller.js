'use strict';
module.exports = function createLeaveControllers({
  assertLeaveEmploymentEligibility,
  broadcastLeaveUpdated,
  computeEmployeeLeaveWorkingDays,
  computeNumberOfDaysSync,
  employeeLeaveDetailsFromPayload,
  ensureLeaveTypeIdByName,
  getLeaveTypeDefinition,
  getUserSexForLeaveValidation,
  insertLeaveRequestHistory,
  invalidProvidedDate,
  loadEmployeeOfficialSnapshot,
  mapLeaveRowToApi,
  normalizeEmployeeDetailSchema,
  pool,
  readAdoptionParentRole,
  readLeaveEventDates,
  readMaternityDeliveryType,
  serializeEmployeeDetailSchema,
  toIsoDateStr,
  validateEmployeeLeaveRequestWithRule,
}) {
  return {
    saveDraft: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      try {
        const { leave_type, start_date, end_date, reason, details, ...rest } = req.body || {};

        const startStr = toIsoDateStr(start_date);
        const endStr = toIsoDateStr(end_date);
        if (invalidProvidedDate(start_date, startStr)) {
          return res.status(400).json({ error: 'start_date must be a valid date' });
        }
        if (invalidProvidedDate(end_date, endStr)) {
          return res.status(400).json({ error: 'end_date must be a valid date' });
        }
        if (startStr && endStr && endStr < startStr) {
          return res.status(400).json({ error: 'end_date cannot be earlier than start_date' });
        }
        const days = computeNumberOfDaysSync(startStr, endStr);

        const client = await pool.connect();
        try {
          await client.query('BEGIN');
          const workingDayResult =
            startStr && endStr
              ? await computeEmployeeLeaveWorkingDays(client, userId, startStr, endStr)
              : { days: null };
          const effectiveDaysDraft = workingDayResult.days ?? days;
          const leaveTypeId = await ensureLeaveTypeIdByName(client, leave_type);
          if (!leaveTypeId) {
            await client.query('ROLLBACK');
            return res.status(400).json({ error: 'Invalid leave type' });
          }
          const leaveRule = await getLeaveTypeDefinition(client, leave_type);
          await assertLeaveEmploymentEligibility(client, leaveRule, userId);
          const customFieldSchema = normalizeEmployeeDetailSchema(
            leaveRule?.employee_detail_schema,
          );
          const payloadDetails = employeeLeaveDetailsFromPayload({
            details,
            rest,
            customFieldSchema,
            requireCustomFields: false,
          });
          const officialSnapshot = await loadEmployeeOfficialSnapshot(client, userId);
          const otherPurpose = (
            payloadDetails.other_purpose ||
            payloadDetails.otherPurpose ||
            ''
          ).toString();
          const maternityDeliveryType = readMaternityDeliveryType(payloadDetails);
          const adoptionParentRole = readAdoptionParentRole(payloadDetails);
          const eventDates = readLeaveEventDates(payloadDetails);
          const userSex = await getUserSexForLeaveValidation(client, userId);
          const validation = validateEmployeeLeaveRequestWithRule({
            rule: leaveRule,
            leaveType: leave_type,
            otherPurpose: otherPurpose || null,
            startDateStr: null,
            endDateStr: null,
            numberOfDays: null,
            hasAttachment: false,
            userSex,
            maternityDeliveryType,
            adoptionParentRole,
            eventDates,
            details: payloadDetails,
            enforceEventDateRules: false,
          });
          if (!validation.valid) {
            await client.query('ROLLBACK');
            return res.status(400).json({ error: validation.error });
          }
          const q = await client.query(
            `INSERT INTO leave_requests (
            employee_id,
            user_id,
            leave_type_id,
            start_date,
            end_date,
            total_days,
            number_of_days,
            reason,
            details,
            employee_official_snapshot,
            employee_detail_schema_snapshot,
            status,
            created_at,
            updated_at
          )
          VALUES (
            $1::uuid, $1::uuid, $2::uuid, $3::date, $4::date,
            $5::numeric, $5::numeric, $6::text, $7::jsonb, $8::jsonb, $9::jsonb,
            'draft', now(), now()
          )
          RETURNING *`,
            [
              userId,
              leaveTypeId,
              startStr,
              endStr,
              effectiveDaysDraft,
              reason || null,
              payloadDetails,
              officialSnapshot,
              serializeEmployeeDetailSchema(customFieldSchema),
            ],
          );

          const row = q.rows[0];
          // FIX #2: Only one history row on create (removed duplicate 'created' + 'saved_draft' pair).
          await insertLeaveRequestHistory(client, {
            leaveRequestId: row.id,
            action: 'saved_draft',
            fromStatus: null,
            toStatus: 'draft',
            actedBy: userId,
            remarks: reason || null,
            metadataJson: {
              revision: row.signature_revision,
              leave_type: leave_type || null,
              start_date: startStr,
              end_date: endStr,
              number_of_days: effectiveDaysDraft,
            },
          });
          const typeName = leave_type ? String(leave_type) : null;
          await client.query('COMMIT');
          const mapped = mapLeaveRowToApi({ ...row, leave_type_name: typeName });
          broadcastLeaveUpdated('saved_draft', mapped);
          res.status(201).json(mapped);
        } catch (e) {
          await client.query('ROLLBACK');
          throw e;
        } finally {
          client.release();
        }
      } catch (err) {
        console.error('[leave POST /draft]', err);
        if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to save draft' });
      }
    },
  };
};
