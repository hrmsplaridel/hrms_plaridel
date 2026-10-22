'use strict';
module.exports = function createLeaveControllers({
  SYSTEM_LEAVE_TYPE_NAMES,
  defaultEntitlementBasisForLeaveType,
  defaultLedgerTypeForLeaveType,
  defaultSexEligibilityForLeaveType,
  leaveTypePayloadFromBody,
  leaveTypeRowToApi,
  normalizeEmployeeDetailSchema,
  pool,
  sendLeaveTypeWriteError,
  serializeEmployeeDetailSchema,
  workflowEngine,
}) {
  return {
    listTypes: async (req, res) => {
      try {
        const includeInactive =
          String(req.query.include_inactive || req.query.includeInactive || '').toLowerCase() ===
            'true' || req.query.include_inactive === '1';
        const q = await pool.query(
          `SELECT *
       FROM leave_types
       WHERE ($1::boolean = true OR is_active = true)
       ORDER BY is_system DESC, display_name NULLS LAST, description NULLS LAST, name`,
          [includeInactive],
        );
        res.json(q.rows.map(leaveTypeRowToApi));
      } catch (err) {
        console.error('[leave GET /types]', err);
        res.status(500).json({ error: 'Failed to fetch leave types' });
      }
    },

    createType: async (req, res) => {
      try {
        const payload = leaveTypePayloadFromBody(req.body || {});
        if (!payload.name || !payload.displayName) {
          return res.status(400).json({ error: 'Leave type name is required' });
        }
        if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(payload.name)) {
          return res.status(400).json({
            error:
              'Leave type key must start with a letter and contain only letters, numbers, or underscore.',
          });
        }
        const routing = require('../../../services/leaveRouting').normalizeRouting(req.body || {});
        const workflowId = await workflowEngine.selectedWorkflowId(
          pool,
          req.body?.approval_workflow_id,
        );
        const q = await pool.query(
          `INSERT INTO leave_types (
          name, display_name, description, is_active, is_system,
          employee_can_file, admin_only, allows_past_dates,
          requires_attachment, requires_attachment_when_over_days,
          max_days, minimum_advance_days, affects_dtr_normally, balance_ledger_type,
          entitlement_basis, sex_eligibility, employee_detail_schema, eligible_employment_types, approval_route, mayor_employment_types,
          admin_can_file, approval_workflow_id, minimum_service_months, first_year_allowance, created_at, updated_at
        )
        VALUES (
          $1, $2, $3, $4, false,
          $5, $6, $7,
          $8, $9,
          $10, $11, $12, $13,
          $14, $15, $16::jsonb, $17::text[], $18, $19::text[],
          $20, $21::uuid, $22, $23, now(), now()
        )
        RETURNING *`,
          [
            payload.name,
            payload.displayName,
            payload.description,
            payload.isActive,
            payload.employeeCanFile,
            payload.adminOnly,
            payload.allowsPastDates,
            payload.requiresAttachment,
            payload.requiresAttachmentWhenOverDays,
            payload.maxDays,
            payload.minimumAdvanceDays,
            payload.affectsDtrNormally,
            payload.balanceLedgerType,
            payload.entitlementBasis,
            payload.sexEligibility,
            serializeEmployeeDetailSchema(payload.employeeDetailSchema),
            payload.eligibleEmploymentTypes,
            routing.approval_route,
            routing.mayor_employment_types,
            payload.adminCanFile,
            workflowId,
            payload.minimumServiceMonths,
            payload.firstYearAllowance,
          ],
        );
        res.status(201).json(leaveTypeRowToApi(q.rows[0]));
      } catch (err) {
        console.error('[leave POST /types]', err);
        return sendLeaveTypeWriteError(res, err, 'create');
      }
    },

    updateType: async (req, res) => {
      try {
        const existingQ = await pool.query('SELECT * FROM leave_types WHERE id = $1::uuid', [
          req.params.id,
        ]);
        if (existingQ.rows.length === 0) {
          return res.status(404).json({ error: 'Leave type not found' });
        }
        const existing = existingQ.rows[0];
        const isSystem =
          existing.is_system === true || SYSTEM_LEAVE_TYPE_NAMES.includes(existing.name);
        if (isSystem) {
          const body = req.body || {};
          if (
            Object.keys(body).some(
              (key) => !['eligible_employment_types', 'minimum_service_months'].includes(key),
            )
          ) {
            return res
              .status(400)
              .json({
                error:
                  'Built-in leave rules are protected. Only employment-type and minimum-service eligibility can be configured.',
              });
          }
          if (!Object.keys(body).length) {
            return res.json(leaveTypeRowToApi(existing));
          }
          const payload = leaveTypePayloadFromBody(body, existing);
          const eligibility = payload.eligibleEmploymentTypes;
          const updated = await pool.query(
            `UPDATE leave_types SET eligible_employment_types = $1::text[], minimum_service_months = $3, updated_at = now()
         WHERE id = $2::uuid RETURNING *`,
            [eligibility, req.params.id, payload.minimumServiceMonths],
          );
          return res.json(leaveTypeRowToApi(updated.rows[0]));
        }
        const payload = leaveTypePayloadFromBody(req.body || {}, existing);
        const nextName = isSystem ? existing.name : payload.name;
        const nextActive = isSystem ? true : payload.isActive;
        const nextBalanceLedgerType = isSystem
          ? defaultLedgerTypeForLeaveType(nextName)
          : payload.balanceLedgerType;
        const nextEntitlementBasis = isSystem
          ? defaultEntitlementBasisForLeaveType(nextName)
          : payload.entitlementBasis;
        if (!nextName || !payload.displayName) {
          return res.status(400).json({ error: 'Leave type name is required' });
        }
        if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(nextName)) {
          return res.status(400).json({
            error:
              'Leave type key must start with a letter and contain only letters, numbers, or underscore.',
          });
        }
        const q = await pool.query(
          `UPDATE leave_types
       SET name = $1,
           display_name = $2,
           description = $3,
           is_active = $4,
           is_system = $5,
           employee_can_file = $6,
           admin_only = $7,
           allows_past_dates = $8,
           requires_attachment = $9,
           requires_attachment_when_over_days = $10,
           max_days = $11,
           minimum_advance_days = $12,
           affects_dtr_normally = $13,
           balance_ledger_type = $14,
           entitlement_basis = $15,
           sex_eligibility = $16,
           employee_detail_schema = $17::jsonb,
           eligible_employment_types = $19::text[],
           admin_can_file = $20,
           minimum_service_months = $21,
           first_year_allowance = $22,
           updated_at = now()
       WHERE id = $18::uuid
       RETURNING *`,
          [
            nextName,
            payload.displayName,
            payload.description,
            nextActive,
            isSystem,
            payload.employeeCanFile,
            payload.adminOnly,
            payload.allowsPastDates,
            payload.requiresAttachment,
            payload.requiresAttachmentWhenOverDays,
            payload.maxDays,
            payload.minimumAdvanceDays,
            payload.affectsDtrNormally,
            nextBalanceLedgerType,
            nextEntitlementBasis,
            isSystem ? defaultSexEligibilityForLeaveType(nextName) : payload.sexEligibility,
            serializeEmployeeDetailSchema(
              isSystem
                ? normalizeEmployeeDetailSchema(existing.employee_detail_schema)
                : payload.employeeDetailSchema,
            ),
            req.params.id,
            payload.eligibleEmploymentTypes,
            payload.adminCanFile,
            payload.minimumServiceMonths,
            payload.firstYearAllowance,
          ],
        );
        res.json(leaveTypeRowToApi(q.rows[0]));
      } catch (err) {
        console.error('[leave PUT /types/:id]', err);
        return sendLeaveTypeWriteError(res, err, 'update');
      }
    },
  };
};
