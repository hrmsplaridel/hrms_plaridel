'use strict';

const { resolveDepartmentReviewers, replaceRequestReviewerSnapshot } = require('./departmentReviewerService');
const { resolveFinalLeaveReviewerConfiguration, resolveEligibleFinalReviewers } = require('./leaveFinalReviewerService');
const { createSignatureAsset } = require('./docutrackerDocumentBuilderService');
const { recordLocatorWorkflowEvent } = require('./locatorWorkflowHistory');
const { resolveActiveMayor } = require('./officialSignatoryService');
const { canReadLocatorAsMayor } = require('./locatorMayorAccess');
const { todayInHrmsTimezone } = require('../utils/dateRangeParser');
const { selfFilingOfficial, requestPrintPolicy } = require('./workflowPrintPolicy');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const LABELS = { applicant: 'Applicant', department_head: 'Head of Office', hr_approver: 'Noted' };
const PENDING = new Set(['pending', 'pending_department_head', 'pending_hr','pending_mayor']);
function fail(code, message) {
  const statusCode = { FORBIDDEN: 403, NOT_FOUND: 404, VALIDATION: 400, CONFLICT: 409 }[code] || 500;
  throw Object.assign(new Error(message), { code, statusCode, payload: { error: message } });
}

async function substituteApplicantOfficial(db, row, officials, primaryConflicts = []) {
  const slots = ['department_head', 'hr_approver'].filter(slot => primaryConflicts.includes(slot) ||
    officials[slot]?.id && String(officials[slot].id) === String(row.employee_id));
  if (!slots.length) return officials;
  const lastSource = row.workflow_snapshot?.steps?.at(-1)?.assignee_source;
  const mayor = requestPrintPolicy(row) === 'mayor'
    ? ['active_mayor', 'manual_mayor'].includes(lastSource)
      ? officials.hr_approver
      : await resolveActiveMayor(db, todayInHrmsTimezone())
    : null;
  const result = { ...officials };
  for (const slot of slots) {
    result[slot] = await selfFilingOfficial(db, row, slot === 'department_head' ? 'department' : 'hr', {
      id: mayor?.id || mayor?.employee_id || null, employee_id: mayor?.id || mayor?.employee_id || null,
      name: mayor?.name || '', position_title: mayor?.position_title || 'Municipal Mayor',
    });
  }
  return result;
}

async function substitutePrimaryApplicantOfficial(db, row, officials) {
  const steps = row.workflow_snapshot?.steps;
  if (!require('./approvalWorkflows').isShared(row.workflow_snapshot) && requestPrintPolicy(row) === 'mayor') return officials;
  const conflicts = [];
  const first = steps[0];
  if (row.department_id || first?.assignee_source === 'department_reviewers') {
    const department = await resolveDepartmentReviewers(db, {
      departmentId: first.assignee_source === 'department_reviewers' ? first.department_id : row.department_id,
      effectiveDate: row.slip_date_text || todayInHrmsTimezone(),
    });
    if (String(department.primary?.reviewerId || '') === String(row.employee_id)) conflicts.push('department_head');
  }
  if (!require('./approvalWorkflows').isDepartmentOnlyWorkflow(row.workflow_snapshot) &&
      !['active_mayor', 'manual_mayor'].includes(steps.at(-1)?.assignee_source)) {
    const final = await resolveFinalLeaveReviewerConfiguration(db);
    if (String(final.primary?.id || '') === String(row.employee_id)) conflicts.push('hr_approver');
  }
  return substituteApplicantOfficial(db, row, officials, conflicts);
}

async function resolveMissingPositionTitles(db, officials, date) {
  const result = { ...officials };
  for (const slot of ['hr_approver', 'applicant', 'department_head']) {
    const person = result[slot];
    // A stored empty title is also a snapshot; only enrich older missing fields.
    if (!person?.id || person.position_title !== undefined) continue;
    const position = await db.query(
      `SELECT p.name AS position_title
       FROM assignments a JOIN positions p ON p.id = a.position_id
       WHERE a.employee_id = $1::uuid
         AND a.effective_from <= $2::date
         AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
       ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC LIMIT 1`,
      [person.id, date]
    );
    result[slot] = { ...person, position_title: position.rows[0]?.position_title || '' };
  }
  return result;
}

async function resolveOfficials(db, row) {
  const date = row.slip_date_text;
  const department = await resolveDepartmentReviewers(db, {
    departmentId: row.department_id, effectiveDate: date,
  });
  // Final review eligibility is configured for today, unlike the employee's
  // department assignment, which follows the requested locator date.
  const final = row.final_review_route && row.final_review_route!=='hr'
    ? await resolveActiveMayor(db,todayInHrmsTimezone()).then(m=>({primary:m?{id:m.employee_id,name:m.name,position_title:m.position_title}:null}))
    : await resolveFinalLeaveReviewerConfiguration(db);
  const officials = await substituteApplicantOfficial(db, row, {
    applicant: { id: row.employee_id, name: row.employee_name },
    department_head: row.final_review_route==='mayor_direct' && !row.workflow_snapshot?.steps?.includes('department')?{id:null,name:''}:{
      id: department.primary?.reviewerId || null, name: department.primary?.reviewerName || '',
      ...(department.primary?.position_title ? { position_title: department.primary.position_title } : {}),
    },
    hr_approver: { id: final.primary?.id || null, name: final.primary?.name || '',
      position_title: final.primary?.position_title || '' },
  });
  const shared=await require('./approvalWorkflows').printOfficials(db,'locator',row);
  if(shared)Object.assign(officials,shared);
  return resolveMissingPositionTitles(db, await substitutePrimaryApplicantOfficial(db, row, officials), date);
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
       (v.background_pdf IS NOT NULL) AS has_print_background,
       v.print_layout,
       EXISTS (SELECT 1 FROM locator_slip_department_reviewers r
         WHERE r.locator_slip_id = ls.id AND r.reviewer_id = $2::uuid) AS is_reviewer
     FROM locator_slips ls JOIN users u ON u.id = ls.employee_id
     LEFT JOIN locator_request_types t ON t.code = ls.request_type
     LEFT JOIN locator_print_template_versions v ON v.id = ls.print_template_version_id
     WHERE ls.id = $1::uuid ${lock ? 'FOR UPDATE OF ls' : ''}`,
    [id, user.id]
  );
  const row = result.rows[0];
  if (!row) fail('NOT_FOUND', 'Locator slip not found');
  const owner = row.employee_id === user.id;
  const sharedAccess=require('./approvalWorkflows').isShared(row.workflow_snapshot) &&
    await require('./sharedWorkflowInbox').canRead(db,'locator',row,user);
  if(require('./approvalWorkflows').isShared(row.workflow_snapshot) && PENDING.has(row.status) && !sharedAccess) {
    fail('NOT_FOUND', 'Locator slip not found');
  }
  const hr = sharedAccess || ['hr', 'admin'].includes(user.role) ||
    await canReadLocatorAsMayor(db, user, row.final_review_route);
  const reviewer = row.is_reviewer || row.assigned_department_head_id === user.id;
  if (!owner && !hr && !reviewer && row.dept_head_reviewer_id !== user.id) {
    fail('NOT_FOUND', 'Locator slip not found');
  }
  if (row.paper_approval_record) {
    const paper=row.paper_approval_record;
    const people={applicant:paper.applicant,department_head:paper.department_reviewer,hr_approver:paper.final_approver};
    const officials=Object.fromEntries(Object.entries(people).map(([slot,p])=>[slot,{id:p?.user_id||null,name:p?.name||'',position_title:p?.position_title||''}]));
    return {...row,officials,owner,hr,reviewer:false,canFinalReview:false};
  }
  // Legacy forms have no historical official snapshot. Resolve primary roles only,
  // never the routing fallback or the person who happened to approve.
  let officials = { ...(row.print_signatories || await resolveOfficials(db, row)) };
  const shared=await require('./approvalWorkflows').printOfficials(db,'locator',row);
  if(shared)Object.assign(officials,shared);
  if (!row.print_signatories && !shared) {
    const primary = await db.query(
      `SELECT reviewer_id, reviewer_name_snapshot FROM locator_slip_department_reviewers
       WHERE locator_slip_id = $1::uuid AND reviewer_role = 'primary' LIMIT 1`, [id]
    );
    if (primary.rows[0]) {
      officials.department_head = { id: primary.rows[0].reviewer_id, name: primary.rows[0].reviewer_name_snapshot };
    }
  }
  // Also correct older snapshots that printed the applicant as their own
  // official. Reads keep Mayor snapshots frozen; pending handovers are recorded
  // explicitly during valid signing/approval, never while previewing a form.
  officials = await substituteApplicantOfficial(db, row, officials);
  officials = await substitutePrimaryApplicantOfficial(db, row, officials);
  officials = await resolveMissingPositionTitles(db, officials, row.slip_date_text);
  const finalReviewers = hr && !owner && PENDING.has(row.status)
    ? await resolveEligibleFinalReviewers(db, row.employee_id, 'locator', id) : [];
  return { ...row, officials, owner, hr, reviewer,
    activeReviewer: finalReviewers.find((r) => r.id === user.id),
    canFinalReview: finalReviewers.some((r) => r.id === user.id) };
}

function canSign(context, user, slot) {
  if (slot === 'applicant') return context.owner && PENDING.has(context.status);
  if (context.owner) return false;
  if (slot === 'department_head') {
    return Boolean(context.reviewer) && context.status === 'pending_department_head';
  }
  if (slot === 'hr_approver') {
    return Boolean(context.canFinalReview) && ['pending', 'pending_hr','pending_mayor'].includes(context.status);
  }
  return false;
}

function printableSignature(context, slot, signature) {
  const id = context.officials[slot]?.id;
  if (!id || signature?.signed_by !== id || signature.revision !== context.signature_revision) return null;
  if (!PENDING.has(context.status) && context.status !== 'approved') return null;
  if (slot === 'department_head' &&
      (!['pending_hr', 'pending_mayor', 'approved'].includes(context.status) || context.dept_head_reviewer_id !== id)) return null;
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
    const paper=context.paper_approval_record;
    const copies=paper&&context.status==='approved'?Object.values(require('../modules/leave/services/paperSignatures').paperSignaturePayload(paper)):[];
    const result = paper?{rows:copies}:await db.query(
      `SELECT s.*, a.mime_type, encode(a.image_bytes, 'base64') AS signature_image_base64
       FROM docutracker_locator_signatures s
       JOIN docutracker_signature_assets a ON a.id = s.signature_asset_id
       WHERE s.locator_slip_id = $1::uuid AND s.revision = $2`, [id, context.signature_revision]
    );
    const signatures = Object.entries(LABELS).map(([slot, label]) => {
      const official = context.officials[slot];
      const engine=require('./approvalWorkflows');
      const sharedPending=engine.isShared(context.workflow_snapshot) && !context.workflow_snapshot.outcome &&
        ['pending','pending_hr','pending_mayor'].includes(context.status) && slot==='hr_approver';
      const stored=result.rows.find((s) => s.slot_key === slot);
      const signature=sharedPending?engine.currentStepSignature(context,stored):stored;
      return {
        ...signature, slot_key: slot, label,
        assigned_signer_id: official?.id || null, assigned_signer_name: official?.name || '',
        ...(sharedPending?{
          label:`${engine.stepLabel(context.workflow_snapshot.steps[context.workflow_snapshot.current_step])} Signature`,
          assigned_signer_id:signature?.assigned_signer_id || context.activeReviewer?.id || null,
          assigned_signer_name:signature?.signer_name_snapshot || context.activeReviewer?.name || '',
        }:{}),
        can_sign: !paper && canSign(context, user, slot), can_assign: false, assignment_source: paper?'approved_paper_copy':'automatic',
      };
    });
    const workflowSignatures=paper?[]:await require('./approvalWorkflows').decisionSignatures(db,context,{includeLegacy:true});
    return {
      source_module: module, source_table: table, source_record_id: id,
      source_status: context.status, workflow_snapshot:context.workflow_snapshot || null, signatures:[...signatures,...workflowSignatures],
      print_form: {
        employee_detail_schema_snapshot: context.employee_detail_schema_snapshot || [],
        additional_details: context.additional_details || {},
        final_review_route: context.final_review_route || 'hr',
        print_template_version_id: context.print_template_version_id || null,
        has_print_background: context.has_print_background === true,
        print_layout: context.print_layout || null,
        employee_name: context.officials.applicant?.name || context.employee_name,
        slip_date: context.slip_date_text, office: context.office, reason: context.reason,
        request_type_label: context.print_type_label, location_label: context.print_location_label,
        am_in: context.am_in, am_out: context.am_out, pm_in: context.pm_in, pm_out: context.pm_out,
        ...(paper?{paper_approval_record:require('../modules/leave/services/paperSignatures').publicPaperRecord(paper)}:{}),
      },
      print_signatories: Object.fromEntries(Object.keys(LABELS).map((slot) => {
        const shared=require('./approvalWorkflows').isShared(context.workflow_snapshot);
        const manual = context.workflow_snapshot?.steps?.at(-1)?.assignee_source === 'manual_mayor';
        // Replacement blocks may use the Mayor's completed decision, never the
        // backup's ink or an unsigned/manual Mayor slot.
        const confirmed = workflowSignatures.find(s => s.signed_by === context.officials[slot]?.id &&
          ((slot === 'department_head' && s.slot_key === 'workflow_step_1') || context.status === 'approved'));
        const signature = paper ? copies.find(s=>s.slot_key===slot) : shared && slot !== 'applicant'
          ? (manual && context.officials[slot]?.id === context.officials.hr_approver?.id ? null : confirmed)
          : printableSignature(context, slot, result.rows.find((s) => s.slot_key === slot));
        return [slot, {
          name: context.officials[slot]?.name || '',
          position_title: context.officials[slot]?.position_title || '',
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
    await persistLocatorSignature(db, user, id, slot, input);
    await db.query('COMMIT');
  } catch (error) {
    try { await db.query('ROLLBACK'); } catch (_) { /* Preserve the original failure. */ }
    throw storageError(error);
  } finally { db.release(); }
  return getLocatorSourceSignatures(pool, user, module, table, id);
}

// Called only after this actor has supplied (or already saved) a valid signature,
// with the pending request locked by loadContext inside the caller's transaction.
async function reassignPendingMayor(db, user, context, slot) {
  if (context.final_review_route !== 'mayor_direct' || slot !== 'hr_approver' ||
      (context.workflow_snapshot && require('./approvalWorkflows').stepKind(context.workflow_snapshot.steps[context.workflow_snapshot.current_step]) !== 'mayor')) return;
  if (!context.canFinalReview || context.owner ||
      !['pending', 'pending_hr', 'pending_mayor'].includes(context.status)) {
    fail('FORBIDDEN', 'Only the current Mayor can sign this pending locator');
  }
  // Hold authority until commit: deactivation/role changes must not race signing.
  const locked = await db.query(
    `SELECT id FROM users WHERE id = $1::uuid AND role='mayor' AND is_active=true FOR SHARE`, [user.id]
  );
  const mayor = locked.rows.length ? await resolveActiveMayor(db, todayInHrmsTimezone()) : null;
  if (!mayor || String(mayor.employee_id) !== String(user.id)) {
    fail('FORBIDDEN', 'The current Mayor has changed. Refresh this locator before signing.');
  }
  if (String(context.final_reviewer_user_id || '') === String(user.id) &&
      String(context.print_signatories?.hr_approver?.id || '') === String(user.id)) return;

  const approver = { id: mayor.employee_id, name: mayor.name, position_title: mayor.position_title || 'Municipal Mayor' };
  const officials = { ...(context.print_signatories || context.officials), hr_approver: approver };
  await db.query(
    `UPDATE locator_slips SET final_reviewer_user_id = $2::uuid, print_signatories = $3::jsonb
     WHERE id = $1::uuid`, [context.id, mayor.employee_id, JSON.stringify(officials)]
  );
  await recordLocatorWorkflowEvent(db, { locatorSlipId: context.id, action: 'mayor_reassigned',
    fromStatus: context.status, toStatus: context.status, actorId: user.id, actorRole: user.role,
    metadata: { reason: 'current_mayor_handover', revision: context.signature_revision,
      previous_final_reviewer_user_id: context.final_reviewer_user_id || null,
      previous_printed_approver: context.print_signatories?.hr_approver || null,
      new_final_reviewer_user_id: mayor.employee_id, new_printed_approver: approver } });
  context.final_reviewer_user_id = mayor.employee_id;
  context.print_signatories = officials;
  context.officials = { ...context.officials, hr_approver: approver };
}

// Called inside the submission/decision transaction, before the workflow moves.
async function persistLocatorSignature(db, user, id, slot, input, { requireInput = false } = {}) {
    if (!Object.hasOwn(LABELS, slot)) fail('NOT_FOUND', 'Signature field not found');
    const context = await loadContext(db, user, id, true);
    if (!canSign(context, user, slot)) fail('FORBIDDEN', 'Only an eligible reviewer or applicant can sign at this stage');
    if (typeof input === 'string') {
      try { input = JSON.parse(input); } catch (_) { fail('VALIDATION', 'Invalid signature input'); }
    }
    if (!input) {
      if (!requireInput) {
        const existing = await db.query(
          `SELECT id FROM docutracker_locator_signatures
           WHERE locator_slip_id = $1::uuid AND revision = $2 AND slot_key = $3 AND signed_by = $4::uuid`,
          [id, context.signature_revision, slot, user.id]
        );
        if (existing.rowCount) {
          await reassignPendingMayor(db, user, context, slot);
          return;
        }
      }
      fail('CONFLICT', 'Add your signature before submitting or approving this locator request.');
    }
    if (typeof input !== 'object' || Array.isArray(input)) fail('VALIDATION', 'Invalid signature input');
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
    await reassignPendingMayor(db, user, context, slot);
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
}

module.exports = { snapshotLocatorReviewers, getLocatorSourceSignatures, signLocatorSourceSlot, persistLocatorSignature, canSign, printableSignature };
