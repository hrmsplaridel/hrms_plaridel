'use strict';

const { resolveDepartmentReviewers, replaceRequestReviewerSnapshot } = require('./departmentReviewerService');
const { resolveFinalLeaveReviewerConfiguration, resolveFinalLeaveReviewers } = require('./leaveFinalReviewerService');
const { createSignatureAsset } = require('./docutrackerDocumentBuilderService');
const { recordLocatorWorkflowEvent } = require('./locatorWorkflowHistory');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const LABELS = { applicant: 'Applicant', department_head: 'Head of Office', hr_approver: 'Noted' };
const PENDING = new Set(['pending', 'pending_department_head', 'pending_hr']);
function fail(code, message) { throw Object.assign(new Error(message), { code }); }

async function resolveOfficials(db, row) {
  const date = row.slip_date_text;
  const department = await resolveDepartmentReviewers(db, {
    departmentId: row.department_id, effectiveDate: date,
  });
  // Final review eligibility is configured for today, unlike the employee's
  // department assignment, which follows the requested locator date.
  const final = await resolveFinalLeaveReviewerConfiguration(db);
  return {
    applicant: { id: row.employee_id, name: row.employee_name },
    department_head: { id: department.primary?.reviewerId || null, name: department.primary?.reviewerName || '' },
    hr_approver: { id: final.primary?.id || null, name: final.primary?.name || '' },
  };
}

async function snapshotLocatorReviewers(db, options) {
  await replaceRequestReviewerSnapshot(db, options);
  const result = await db.query(
    `SELECT ls.*, ls.slip_date::text AS slip_date_text, u.full_name AS employee_name
     FROM locator_slips ls JOIN users u ON u.id = ls.employee_id WHERE ls.id = $1::uuid`,
    [options.requestId]
  );
  const officials = await resolveOfficials(db, result.rows[0]);
  await db.query('UPDATE locator_slips SET print_signatories = $2::jsonb WHERE id = $1::uuid',
    [options.requestId, JSON.stringify(officials)]);
}

async function loadContext(db, user, id, lock = false) {
  if (!UUID.test(id || '')) fail('NOT_FOUND', 'Locator slip not found');
  const result = await db.query(
    `SELECT ls.*, ls.slip_date::text AS slip_date_text, u.full_name AS employee_name,
       COALESCE(ls.request_type_label_snapshot, t.label) AS print_type_label,
       COALESCE(ls.request_type_location_label_snapshot, t.location_label) AS print_location_label,
       EXISTS (SELECT 1 FROM locator_slip_department_reviewers r
         WHERE r.locator_slip_id = ls.id AND r.reviewer_id = $2::uuid) AS is_reviewer
     FROM locator_slips ls JOIN users u ON u.id = ls.employee_id
     LEFT JOIN locator_request_types t ON t.code = ls.request_type
     WHERE ls.id = $1::uuid ${lock ? 'FOR UPDATE OF ls' : ''}`,
    [id, user.id]
  );
  const row = result.rows[0];
  if (!row) fail('NOT_FOUND', 'Locator slip not found');
  const owner = row.employee_id === user.id;
  const hr = ['hr', 'admin'].includes(user.role);
  const reviewer = row.is_reviewer || row.assigned_department_head_id === user.id;
  if (!owner && !hr && !reviewer && row.dept_head_reviewer_id !== user.id) {
    fail('NOT_FOUND', 'Locator slip not found');
  }
  // Legacy forms have no historical official snapshot. Resolve primary roles only,
  // never the routing fallback or the person who happened to approve.
  const officials = row.print_signatories || await resolveOfficials(db, row);
  if (!row.print_signatories) {
    const primary = await db.query(
      `SELECT reviewer_id, reviewer_name_snapshot FROM locator_slip_department_reviewers
       WHERE locator_slip_id = $1::uuid AND reviewer_role = 'primary' LIMIT 1`, [id]
    );
    if (primary.rows[0]) {
      officials.department_head = { id: primary.rows[0].reviewer_id, name: primary.rows[0].reviewer_name_snapshot };
    }
  }
  const finalReviewers = hr && !owner && PENDING.has(row.status)
    ? await resolveFinalLeaveReviewers(db) : [];
  return { ...row, officials, owner, hr, reviewer,
    canFinalReview: finalReviewers.some((r) => r.id === user.id) };
}

function canSign(context, user, slot) {
  const official = context.officials[slot];
  if (!official?.id || official.id !== user.id) return false;
  if (slot === 'applicant') return context.owner && PENDING.has(context.status);
  if (context.owner) return false;
  if (slot === 'department_head') {
    return (context.reviewer && context.status === 'pending_department_head') ||
      (['pending_hr', 'approved'].includes(context.status) && context.dept_head_reviewer_id === user.id);
  }
  if (slot === 'hr_approver') {
    return (context.canFinalReview && ['pending', 'pending_hr'].includes(context.status)) ||
      (context.hr && context.status === 'approved' && context.hr_reviewer_id === user.id);
  }
  return false;
}

function printableSignature(context, slot, signature) {
  const id = context.officials[slot]?.id;
  if (!id || signature?.signed_by !== id || signature.revision !== context.signature_revision) return null;
  if (!PENDING.has(context.status) && context.status !== 'approved') return null;
  if (slot === 'department_head' &&
      (!['pending_hr', 'approved'].includes(context.status) || context.dept_head_reviewer_id !== id)) return null;
  if (slot === 'hr_approver' && (context.status !== 'approved' || context.hr_reviewer_id !== id)) return null;
  return signature;
}

function assertSource(module, table) {
  if (module !== 'dtr' || table !== 'locator_slips') fail('NOT_FOUND', 'Linked locator not found');
}

function storageError(error) {
  if (['42P01', '42703'].includes(error?.code)) {
    return Object.assign(new Error('Locator e-signatures are not initialized. Apply the 20261001_locator_signatures.sql migration.'), { code: 'UNAVAILABLE' });
  }
  return error;
}

async function getLocatorSourceSignatures(db, user, module, table, id) {
  assertSource(module, table);
  try {
    const context = await loadContext(db, user, id);
    const result = await db.query(
      `SELECT s.*, a.mime_type, encode(a.image_bytes, 'base64') AS signature_image_base64
       FROM docutracker_locator_signatures s
       JOIN docutracker_signature_assets a ON a.id = s.signature_asset_id
       WHERE s.locator_slip_id = $1::uuid AND s.revision = $2`, [id, context.signature_revision]
    );
    const signatures = Object.entries(LABELS).map(([slot, label]) => {
      const official = context.officials[slot];
      const signature = result.rows.find((s) => s.slot_key === slot);
      return {
        ...signature, slot_key: slot, label,
        assigned_signer_id: official?.id || null, assigned_signer_name: official?.name || '',
        can_sign: canSign(context, user, slot), can_assign: false, assignment_source: 'automatic',
      };
    });
    return {
      source_module: module, source_table: table, source_record_id: id,
      source_status: context.status, signatures,
      print_form: {
        employee_name: context.officials.applicant?.name || context.employee_name,
        slip_date: context.slip_date_text, office: context.office, reason: context.reason,
        request_type_label: context.print_type_label, location_label: context.print_location_label,
        am_in: context.am_in, am_out: context.am_out, pm_in: context.pm_in, pm_out: context.pm_out,
      },
      print_signatories: Object.fromEntries(Object.keys(LABELS).map((slot) => {
        const signature = printableSignature(context, slot, result.rows.find((s) => s.slot_key === slot));
        return [slot, {
          name: context.officials[slot]?.name || '',
          signature_image_base64: signature?.signature_image_base64 || null,
        }];
      })),
    };
  } catch (error) {
    throw storageError(error);
  }
}

async function signLocatorSourceSlot(pool, user, module, table, id, slot, input) {
  assertSource(module, table);
  if (!Object.hasOwn(LABELS, slot)) fail('NOT_FOUND', 'Signature field not found');
  const db = await pool.connect();
  try {
    await db.query('BEGIN');
    const context = await loadContext(db, user, id, true);
    if (!canSign(context, user, slot)) fail('FORBIDDEN', 'Only the named official can sign at this review stage');
    const active = await db.query('SELECT full_name FROM users WHERE id = $1::uuid AND is_active = true', [user.id]);
    if (!active.rowCount) fail('FORBIDDEN', 'Only an active signer can sign');
    let assetId = String(input.signature_asset_id || '').trim();
    if (assetId) {
      if (!UUID.test(assetId)) fail('VALIDATION', 'Saved signature is invalid');
      const owned = await db.query('SELECT id FROM docutracker_signature_assets WHERE id = $1::uuid AND owner_user_id = $2::uuid', [assetId, user.id]);
      if (!owned.rowCount) fail('FORBIDDEN', 'Saved signature not found');
    } else {
      assetId = (await createSignatureAsset(db, user, input)).id;
    }
    // Freeze legacy names when first signed so future configuration cannot relabel ink.
    if (!context.print_signatories) {
      await db.query('UPDATE locator_slips SET print_signatories = $2::jsonb WHERE id = $1::uuid', [id, JSON.stringify(context.officials)]);
    }
    await db.query(
      `INSERT INTO docutracker_locator_signatures
       (locator_slip_id, revision, slot_key, signature_asset_id, signed_by, signer_name_snapshot)
       VALUES ($1::uuid, $2, $3, $4::uuid, $5::uuid, $6)
       ON CONFLICT (locator_slip_id, revision, slot_key) DO UPDATE SET
         signature_asset_id = EXCLUDED.signature_asset_id, signed_by = EXCLUDED.signed_by,
         signer_name_snapshot = EXCLUDED.signer_name_snapshot, signed_at = now()`,
      [id, context.signature_revision, slot, assetId, user.id, active.rows[0].full_name]
    );
    await recordLocatorWorkflowEvent(db, { locatorSlipId: id, action: 'signed',
      fromStatus: context.status, toStatus: context.status, actorId: user.id, actorRole: user.role,
      metadata: { slot_key: slot, signature_asset_id: assetId, revision: context.signature_revision } });
    await db.query('COMMIT');
  } catch (error) {
    try { await db.query('ROLLBACK'); } catch (_) { /* Preserve the original failure. */ }
    throw storageError(error);
  } finally { db.release(); }
  return getLocatorSourceSignatures(pool, user, module, table, id);
}

module.exports = { snapshotLocatorReviewers, getLocatorSourceSignatures, signLocatorSourceSlot, canSign, printableSignature };
