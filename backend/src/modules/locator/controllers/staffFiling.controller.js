'use strict';
module.exports = function createLocatorControllers({
  LOCATOR_ATTACHMENT_SUBDIR,
  boolField,
  fs,
  locatorAttachmentDir,
  locatorSubmissionService,
  normalizeRequestType,
  parseLocatorDateOnly,
  path,
  pool,
  removeLocatorAttachmentFile,
  resolveLocatorShiftCoverage,
  runStaffBatch,
  validateLocatorRequiredFields,
  validateStaffBatch,
}) {
  return {
    listFilingEmployees: async (req, res) => {
      const date = String(req.query.slip_date || '');
      const paperDirectory = req.query.paper === 'true' && req.query.employee_ids == null;
      if (!paperDirectory && !parseLocatorDateOnly(date))
        return res.status(400).json({ error: 'Select a valid locator date.' });
      const offset = Math.max(0, Number.parseInt(req.query.offset, 10) || 0);
      const search = String(req.query.search || '')
        .trim()
        .slice(0, 100);
      let selectedIds = null;
      if (req.query.employee_ids != null) {
        try {
          const value = typeof req.query.employee_ids === 'string'
            ? JSON.parse(req.query.employee_ids) : req.query.employee_ids;
          selectedIds = validateStaffBatch(value);
        } catch (_) {
          return res.status(400).json({ error: 'Select between 1 and 100 employees with valid IDs.' });
        }
      }
      try {
        if (paperDirectory) {
          const result = await pool.query(
            `SELECT u.id,u.full_name,u.employment_type,d.name AS department_name,count(*) OVER()::int AS total
             FROM users u
             LEFT JOIN LATERAL (SELECT a.department_id FROM assignments a
               WHERE a.employee_id=u.id
               ORDER BY a.effective_from DESC,a.created_at DESC,a.id DESC LIMIT 1) a ON true
             LEFT JOIN departments d ON d.id=a.department_id
             WHERE u.id <> $1::uuid AND u.is_active=true AND u.role <> 'super_admin'
               AND COALESCE(u.employment_status,'active')='active'
               AND ($2::text='' OR u.full_name ILIKE '%' || $2 || '%' OR d.name ILIKE '%' || $2 || '%')
             ORDER BY u.full_name,u.id LIMIT 100 OFFSET $3`,
            [req.user.id,search,offset]
          );
          return res.json({ employees: result.rows, total: result.rows[0]?.total || 0 });
        }
        const result = await pool.query(
          `SELECT u.id,u.full_name,d.name AS department_name,count(*) OVER()::int AS total
      FROM users u JOIN LATERAL (SELECT a.department_id FROM assignments a
        WHERE a.employee_id=u.id AND a.effective_from <= $1::date AND (a.effective_to IS NULL OR a.effective_to >= $1::date)
        AND a.shift_id IS NOT NULL ORDER BY a.effective_from DESC,a.created_at DESC,a.id DESC LIMIT 1) a ON true
      LEFT JOIN departments d ON d.id=a.department_id
      WHERE u.id <> $2::uuid AND u.is_active=true AND u.role <> 'super_admin' AND COALESCE(u.employment_status,'active')='active'
        AND (u.date_hired IS NULL OR u.date_hired <= $1::date) AND (u.separation_date IS NULL OR u.separation_date >= $1::date)
        AND ($3::text='' OR u.full_name ILIKE '%' || $3 || '%' OR d.name ILIKE '%' || $3 || '%')
        AND ($5::uuid[] IS NULL OR u.id = ANY($5::uuid[]))
      ORDER BY u.full_name,u.id LIMIT 100 OFFSET $4`,
          [date, req.user.id, selectedIds ? '' : search, selectedIds ? 0 : offset, selectedIds]
        );
        res.json({ employees: result.rows, total: result.rows[0]?.total || 0 });
      } catch (error) {
        console.error('[locator staff employees]', error);
        res.status(500).json({ error: 'Unable to load employees.' });
      }
    },

    fileForEmployees: async (req, res) => {
      const sourcePath = req.file ? `${LOCATOR_ATTACHMENT_SUBDIR}/${req.file.filename}` : null;
      try {
        let ids = req.body.employee_ids;
        if (typeof ids === 'string') {
          try {
            ids = JSON.parse(ids);
          } catch (_) {
            ids = null;
          }
        }
        ids = validateStaffBatch(ids);
        if (ids.includes(req.user.id))
          return res.status(400).json({ error: 'Use My Requests to file your own locator.' });
        const slipDate = String(req.body.slip_date || '').trim();
        const requestType = normalizeRequestType(req.body.request_type);
        const fields = validateLocatorRequiredFields({
          slipDate,
          requestType,
          office: String(req.body.office || '').trim(),
          reason: String(req.body.reason || '').trim(),
          slots: {
            amIn: boolField(req.body.full_shift) || boolField(req.body.am_in),
            amOut: boolField(req.body.am_out),
            pmIn: boolField(req.body.pm_in),
            pmOut: boolField(req.body.pm_out),
          },
        });
        if (!fields.valid) return res.status(400).json({ error: fields.error });
        const results = await runStaffBatch(ids, async (employeeId) => {
          const employee = await pool.query(
            `SELECT id FROM users WHERE id=$1::uuid AND is_active=true
        AND COALESCE(employment_status,'active')='active' AND (date_hired IS NULL OR date_hired <= $2::date)
        AND (separation_date IS NULL OR separation_date >= $2::date)`,
            [employeeId, slipDate]
          );
          if (!employee.rows.length)
            throw Object.assign(new Error('Employee is inactive or unavailable on this date.'), {
              statusCode: 400,
            });
          const coverage = await resolveLocatorShiftCoverage(
            pool,
            employeeId,
            parseLocatorDateOnly(slipDate)
          );
          if (!coverage.can_file)
            throw Object.assign(new Error(coverage.error), { statusCode: 400 });
          const full = boolField(req.body.full_shift);
          let attachment = null;
          if (sourcePath) {
            const name = `${require('crypto').randomUUID()}${path.extname(req.file.filename)}`;
            fs.copyFileSync(
              path.join(locatorAttachmentDir, req.file.filename),
              path.join(locatorAttachmentDir, name)
            );
            attachment = {
              path: `${LOCATOR_ATTACHMENT_SUBDIR}/${name}`,
              name: req.file.originalname,
              mimeType: req.file.mimetype,
            };
          }
          try {
            return await locatorSubmissionService.submit({
              employeeUserId: employeeId,
              filedBy: req.user,
              autoApprove: true,
              approvalSignature: req.body.signature,
              additionalDetails: req.body.additional_details,
              slipDate,
              requestType,
              office: String(req.body.office || '').trim(),
              reason: String(req.body.reason || '').trim(),
              amIn: full || boolField(req.body.am_in),
              amOut: full ? !coverage.single_session : boolField(req.body.am_out),
              pmIn: full ? !coverage.single_session : boolField(req.body.pm_in),
              pmOut: full || boolField(req.body.pm_out),
              attachment,
            });
          } catch (error) {
            if (attachment) removeLocatorAttachmentFile(attachment.path);
            throw error;
          }
        });
        res
          .status(200)
          .json({
            results,
            created: results.filter((r) => r.request).length,
            failed: results.filter((r) => r.error).length,
          });
      } catch (error) {
        res
          .status(error.statusCode || 500)
          .json({ error: error.statusCode ? error.message : 'Unable to file locator requests.' });
      } finally {
        if (sourcePath) removeLocatorAttachmentFile(sourcePath);
      }
    },
  };
};
