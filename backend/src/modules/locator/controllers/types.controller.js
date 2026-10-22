'use strict';
module.exports = function createLocatorControllers({
  broadcastLocatorTypeUpdated,
  locatorTypePayloadFromBody,
  mapLocatorTypeRow,
  pool,
  workflowEngine,
}) {
  return {
    listTypes: async (req, res) => {
      try {
        const includeInactive =
          req.query?.include_inactive === 'true' ||
          req.query?.includeInactive === 'true' ||
          req.query?.all === 'true';
        const rows = await pool.query(
          `SELECT *
       FROM locator_request_types
       WHERE ($1::boolean = true OR is_active = true)
       ORDER BY sort_order ASC, label ASC`,
          [includeInactive]
        );
        res.json(rows.rows.map(mapLocatorTypeRow));
      } catch (err) {
        console.error('[locator GET /types]', err);
        res.status(500).json({ error: 'Failed to fetch locator request types' });
      }
    },

    createType: async (req, res) => {
      try {
        const payload = locatorTypePayloadFromBody(req.body || {});
        const workflowId = await workflowEngine.selectedWorkflowId(
          pool,
          req.body?.approval_workflow_id
        );
        const inserted = await pool.query(
          `INSERT INTO locator_request_types (
         code, label, short_label, location_label, location_hint,
         dtr_slot_label, dtr_print_label, requires_attachment,
         coverage_mode, is_active, is_system, sort_order, filing_access, auto_approve_admin, approval_route, mayor_employment_types, employee_detail_schema, approval_workflow_id
       ) VALUES (
         $1::text, $2::text, $3::text, $4::text, $5::text,
         $6::text, $7::text, $8::boolean, $9::text, $10::boolean, false, $11::integer, $12::text, $13::boolean, $14::text, $15::text[], $16::jsonb, $17::uuid
       )
       RETURNING *`,
          [
            payload.code,
            payload.label,
            payload.short_label,
            payload.location_label,
            payload.location_hint,
            payload.dtr_slot_label,
            payload.dtr_print_label,
            payload.requires_attachment,
            payload.coverage_mode,
            payload.is_active,
            payload.sort_order,
            payload.filing_access,
            payload.auto_approve_admin,
            payload.approval_route,
            payload.mayor_employment_types,
            JSON.stringify(payload.employee_detail_schema),
            workflowId,
          ]
        );
        const item = mapLocatorTypeRow(inserted.rows[0]);
        broadcastLocatorTypeUpdated('created', inserted.rows[0]);
        res.status(201).json(item);
      } catch (err) {
        const message =
          err.code === '23505' ? 'A locator type with that code already exists.' : err.message;
        res.status(400).json({ error: message || 'Failed to create locator type' });
      }
    },

    updateType: async (req, res) => {
      try {
        const existingQ = await pool.query(
          'SELECT * FROM locator_request_types WHERE id = $1::uuid',
          [req.params.id]
        );
        const existing = existingQ.rows[0];
        if (!existing) return res.status(404).json({ error: 'Locator type not found' });
        const payload = locatorTypePayloadFromBody(req.body || {}, existing);
        const workflowId = await workflowEngine.selectedWorkflowId(
          pool,
          req.body?.approval_workflow_id === undefined
            ? existing.approval_workflow_id
            : req.body.approval_workflow_id
        );
        const updated = await pool.query(
          `UPDATE locator_request_types
       SET label = $1,
           short_label = $2,
           location_label = $3,
           location_hint = $4,
           dtr_slot_label = $5,
           dtr_print_label = $6,
           requires_attachment = $7,
           coverage_mode = $8,
           is_active = $9,
           sort_order = $10,
           filing_access = $12, auto_approve_admin = $13,
           approval_route = $14, mayor_employment_types = $15::text[],
           employee_detail_schema = $16::jsonb, approval_workflow_id = $17::uuid,
           updated_at = now()
       WHERE id = $11::uuid
       RETURNING *`,
          [
            payload.label,
            payload.short_label,
            payload.location_label,
            payload.location_hint,
            payload.dtr_slot_label,
            payload.dtr_print_label,
            payload.requires_attachment,
            payload.coverage_mode,
            payload.is_active,
            payload.sort_order,
            req.params.id,
            payload.filing_access,
            payload.auto_approve_admin,
            payload.approval_route,
            payload.mayor_employment_types,
            JSON.stringify(payload.employee_detail_schema),
            workflowId,
          ]
        );
        const item = mapLocatorTypeRow(updated.rows[0]);
        broadcastLocatorTypeUpdated('updated', updated.rows[0]);
        res.json(item);
      } catch (err) {
        res.status(400).json({ error: err.message || 'Failed to update locator type' });
      }
    },

    deleteType: async (req, res) => {
      try {
        const existingQ = await pool.query(
          'SELECT * FROM locator_request_types WHERE id = $1::uuid',
          [req.params.id]
        );
        const existing = existingQ.rows[0];
        if (!existing) return res.status(404).json({ error: 'Locator type not found' });
        const usedQ = await pool.query(
          'SELECT 1 FROM locator_slips WHERE request_type = $1::text LIMIT 1',
          [existing.code]
        );
        if (usedQ.rows.length > 0 || existing.is_system === true) {
          const updated = await pool.query(
            `UPDATE locator_request_types
         SET is_active = false, updated_at = now()
         WHERE id = $1::uuid
         RETURNING *`,
            [req.params.id]
          );
          const item = mapLocatorTypeRow(updated.rows[0]);
          broadcastLocatorTypeUpdated('deactivated', updated.rows[0], {
            deleted: false,
          });
          return res.json({ deleted: false, item });
        }
        await pool.query('DELETE FROM locator_request_types WHERE id = $1::uuid', [req.params.id]);
        broadcastLocatorTypeUpdated('deleted', existing, { deleted: true });
        res.json({ deleted: true });
      } catch (err) {
        res.status(400).json({ error: err.message || 'Failed to delete locator type' });
      }
    },
  };
};
