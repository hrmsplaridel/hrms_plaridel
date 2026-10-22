'use strict';
module.exports = function createLocatorComponent({ mapLocatorRow }) {
  async function fetchLocatorSlipDetails(db, id) {
    const result = await db.query(
      `SELECT ls.*,
            ls.slip_date::text AS slip_date_text,
            u.full_name AS employee_name,
            d.name AS department_name,
            assigned_dh.full_name AS assigned_department_head_name,
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
     FROM locator_slips ls
     LEFT JOIN users u ON u.id = ls.employee_id
     LEFT JOIN departments d ON d.id = ls.department_id
     LEFT JOIN users assigned_dh ON assigned_dh.id = ls.assigned_department_head_id
     LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
     LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
     LEFT JOIN users corrector ON corrector.id = ls.retroactive_corrected_by
     LEFT JOIN users revoker ON revoker.id = ls.revoked_by
     LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
     WHERE ls.id = $1::uuid`,
      [id]
    );
    return result.rows[0] ? mapLocatorRow(result.rows[0]) : null;
  }
  return { fetchLocatorSlipDetails };
};
