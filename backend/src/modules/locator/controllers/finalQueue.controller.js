'use strict';
module.exports = function createLocatorControllers({
  canReadLocatorAsMayor,
  finalQueueVisibilitySql,
  mapLocatorRow,
  normalizeRequestType,
  parseLocatorAdminFilters,
  pool,
}) {
  return {
    listFinalReviewRequests: async (req, res) => {
      try {
        if (req.user?.role === 'mayor') {
          if (!(await canReadLocatorAsMayor(pool, req.user, 'mayor_direct')))
            return res
              .status(403)
              .json({ error: 'Only the active Mayor can review these locators.' });
        }
        const parsedFilters = parseLocatorAdminFilters(req.query);
        if (!parsedFilters.ok) {
          return res.status(400).json({ error: parsedFilters.error });
        }
        const { page, pageSize, statuses, departmentId, employeeId, from, to, search } =
          parsedFilters.filters;
        const requestTypeRaw = (req.query?.request_type || '').toString().trim();
        const requestType = requestTypeRaw ? normalizeRequestType(requestTypeRaw) : null;
        if (requestTypeRaw && !requestType) {
          return res.status(400).json({ error: 'Invalid request_type filter' });
        }

        const filterParams = [
          statuses,
          requestType,
          departmentId,
          employeeId,
          from,
          to,
          search,
          req.user?.id,
        ];
        const filterSql = `
      FROM locator_slips ls
      LEFT JOIN users u ON u.id = ls.employee_id
      LEFT JOIN departments d ON d.id = ls.department_id
      LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
      LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
      LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
      LEFT JOIN users corrector ON corrector.id = ls.retroactive_corrected_by
      LEFT JOIN users revoker ON revoker.id = ls.revoked_by
      WHERE ($1::text[] IS NULL OR ls.status = ANY($1::text[]))
        AND ((ls.workflow_snapshot IS NOT NULL AND (
          ls.status = '${req.user?.role === 'mayor' ? 'pending_mayor' : 'pending_hr'}'
          OR (ls.status NOT IN ('pending_department_head','pending_hr','pending_mayor','pending') AND EXISTS (
            SELECT 1 FROM locator_slip_history stage WHERE stage.locator_slip_id=ls.id
              AND (stage.from_status='${req.user?.role === 'mayor' ? 'pending_mayor' : 'pending_hr'}'
                OR stage.to_status='${req.user?.role === 'mayor' ? 'pending_mayor' : 'pending_hr'}')
          ))
        )) OR (ls.workflow_snapshot IS NULL AND (COALESCE(ls.final_review_route,'hr') = '${req.user?.role === 'mayor' ? 'mayor_direct' : 'hr'}' OR
          ('${req.user?.role === 'mayor' ? 'mayor' : 'staff'}' <> 'mayor' AND ls.final_review_route='mayor'))))
        AND ls.employee_id <> $8::uuid
        AND ${finalQueueVisibilitySql('locator', 'ls', '$8::uuid')}
        AND (
          ls.status IN ('pending', 'pending_hr', 'pending_mayor')
          OR ls.is_retroactive_correction = true
          OR EXISTS (
            SELECT 1 FROM locator_slip_history review_history
            WHERE review_history.locator_slip_id = ls.id
              AND (review_history.to_status IN ('pending', 'pending_hr','pending_mayor','approved')
                   OR review_history.from_status IN ('pending', 'pending_hr','pending_mayor'))
          )
        )
        AND ($2::text IS NULL OR ls.request_type = $2::text)
        AND ($3::uuid IS NULL OR ls.department_id = $3::uuid)
        AND ($4::uuid IS NULL OR ls.employee_id = $4::uuid)
        AND ($5::date IS NULL OR ls.slip_date >= $5::date)
        AND ($6::date IS NULL OR ls.slip_date <= $6::date)
        AND (
          $7::text IS NULL
          OR u.full_name ILIKE '%' || $7::text || '%'
          OR d.name ILIKE '%' || $7::text || '%'
          OR ls.office ILIKE '%' || $7::text || '%'
          OR ls.reason ILIKE '%' || $7::text || '%'
          OR COALESCE(ls.request_type_label_snapshot, lrt.label, '')
             ILIKE '%' || $7::text || '%'
        )`;
        const countResult = await pool.query(
          `SELECT COUNT(*)::integer AS total ${filterSql}`,
          filterParams
        );
        const total = Number(countResult.rows[0]?.total || 0);
        const pageCount = Math.max(1, Math.ceil(total / pageSize));
        const effectivePage = Math.min(page, pageCount);
        const offset = (effectivePage - 1) * pageSize;

        const [rows, departments, employees] = await Promise.all([
          pool.query(
            `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name,
              corrector.full_name AS retroactive_corrector_name,
              revoker.full_name AS revoked_by_name,
              lrt.label AS request_type_label,
              lrt.short_label AS request_type_short_label,
              lrt.location_label AS request_type_location_label,
              lrt.location_hint AS request_type_location_hint,
              lrt.dtr_slot_label AS request_type_dtr_slot_label,
              lrt.dtr_print_label AS request_type_dtr_print_label,
              lrt.requires_attachment AS request_type_requires_attachment,
              lrt.coverage_mode AS request_type_coverage_mode
       ${filterSql}
       ORDER BY ls.updated_at DESC, ls.created_at DESC, ls.id DESC
       LIMIT $9::integer OFFSET $10::integer`,
            [...filterParams, pageSize, offset]
          ),
          pool.query(
            `SELECT DISTINCT d.id, d.name
         FROM locator_slips ls
         JOIN departments d ON d.id = ls.department_id
         WHERE ls.employee_id <> $1::uuid AND ${finalQueueVisibilitySql('locator', 'ls', '$1::uuid')} AND d.name IS NOT NULL AND btrim(d.name) <> ''
         ORDER BY d.name`,
            [req.user?.id]
          ),
          pool.query(
            `SELECT u.id,
                u.full_name AS name,
                COALESCE(
                  array_agg(DISTINCT ls.department_id::text)
                    FILTER (WHERE ls.department_id IS NOT NULL),
                  ARRAY[]::text[]
                ) AS department_ids
         FROM locator_slips ls
         JOIN users u ON u.id = ls.employee_id
         WHERE ls.employee_id <> $1::uuid AND ${finalQueueVisibilitySql('locator', 'ls', '$1::uuid')} AND u.full_name IS NOT NULL AND btrim(u.full_name) <> ''
         GROUP BY u.id, u.full_name
         ORDER BY u.full_name`,
            [req.user?.id]
          ),
        ]);
        res.json({
          items: rows.rows.map(mapLocatorRow),
          pagination: {
            page: effectivePage,
            page_size: pageSize,
            total,
            page_count: pageCount,
          },
          filter_options: {
            departments: departments.rows.map((row) => ({
              id: row.id,
              name: row.name,
            })),
            employees: employees.rows.map((row) => ({
              id: row.id,
              name: row.name,
              department_ids: row.department_ids || [],
            })),
          },
        });
      } catch (err) {
        console.error('[locator GET /admin]', err);
        res.status(500).json({ error: 'Failed to fetch locator slips (admin)' });
      }
    },
  };
};
