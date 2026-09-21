async function closeEmployeeAssignmentsForSeparation(db, employeeId, lastDay) {
  await db.query(
    `UPDATE assignments
        SET is_active = false,
            updated_at = now()
      WHERE employee_id = $1::uuid
        AND is_active = true
        AND effective_from > $2::date`,
    [employeeId, lastDay]
  );
  await db.query(
    `UPDATE assignments
        SET effective_to = $2::date,
            updated_at = now()
      WHERE employee_id = $1::uuid
        AND effective_from <= $2::date
        AND (effective_to IS NULL OR effective_to > $2::date)`,
    [employeeId, lastDay]
  );
  await db.query(
    `UPDATE policy_assignments
        SET is_active = false,
            updated_at = now()
      WHERE employee_id = $1::uuid
        AND is_active = true
        AND effective_from > $2::date`,
    [employeeId, lastDay]
  );
  await db.query(
    `UPDATE policy_assignments
        SET effective_to = $2::date,
            updated_at = now()
      WHERE employee_id = $1::uuid
        AND effective_from <= $2::date
        AND (effective_to IS NULL OR effective_to > $2::date)`,
    [employeeId, lastDay]
  );
}

module.exports = { closeEmployeeAssignmentsForSeparation };
