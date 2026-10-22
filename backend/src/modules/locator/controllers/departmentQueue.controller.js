'use strict';
module.exports = function createLocatorControllers({
  isDepartmentHead,
  mapLocatorRow,
  parseLocatorHistoryFilters,
  pool,
}) {
  return {
    listDepartmentRequests: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      const client = await pool.connect();
      try {
        const deptInfo = await isDepartmentHead(client, userId);
        const parsedFilters = parseLocatorHistoryFilters(req.query, {
          departmentHead: true,
        });
        if (!parsedFilters.ok) {
          return res.status(400).json({ error: parsedFilters.error });
        }
        const { page, pageSize, statuses, from, to, search } = parsedFilters.filters;
        const filterParams = [userId, deptInfo.departmentId, statuses, from, to, search];
        const filterSql = `
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users assigned_dh ON assigned_dh.id = ls.assigned_department_head_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.employee_id <> $1::uuid
         AND (
           (
             ls.status = 'pending_department_head'
             AND (
               ls.assigned_department_head_id = $1::uuid
               OR EXISTS (
                 SELECT 1 FROM locator_slip_department_reviewers lsr
                 WHERE lsr.locator_slip_id = ls.id
                   AND lsr.reviewer_id = $1::uuid
               )
               OR (
                 ls.assigned_department_head_id IS NULL
                 AND ls.department_id = $2::uuid
               )
             )
           )
           OR ls.dept_head_reviewer_id = $1::uuid
         )
         AND ($3::text[] IS NULL OR ls.status = ANY($3::text[]))
         AND ($4::date IS NULL OR ls.slip_date >= $4::date)
         AND ($5::date IS NULL OR ls.slip_date <= $5::date)
         AND (
           $6::text IS NULL
           OR u.full_name ILIKE '%' || $6::text || '%'
           OR d.name ILIKE '%' || $6::text || '%'
           OR ls.office ILIKE '%' || $6::text || '%'
           OR ls.reason ILIKE '%' || $6::text || '%'
           OR COALESCE(ls.request_type_label_snapshot, lrt.label, '')
              ILIKE '%' || $6::text || '%'
         )`;
        const countResult = await client.query(
          `SELECT COUNT(*)::integer AS total ${filterSql}`,
          filterParams
        );
        const total = Number(countResult.rows[0]?.total || 0);
        const pageCount = Math.max(1, Math.ceil(total / pageSize));
        const effectivePage = Math.min(page, pageCount);
        const offset = (effectivePage - 1) * pageSize;
        const rows = await client.query(
          `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              assigned_dh.full_name AS assigned_department_head_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name,
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
       LIMIT $7::integer OFFSET $8::integer`,
          [...filterParams, pageSize, offset]
        );
        res.json({
          items: rows.rows.map(mapLocatorRow),
          pagination: {
            page: effectivePage,
            page_size: pageSize,
            total,
            page_count: pageCount,
          },
        });
      } catch (err) {
        console.error('[locator GET /department-head]', err);
        res.status(500).json({ error: 'Failed to fetch department-head locator slips' });
      } finally {
        client.release();
      }
    },
  };
};
