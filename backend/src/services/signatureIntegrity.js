'use strict';
const { digest, sealManifest, verifyManifest, decryptSignature, securityError } = require('./signatureSecurity');
const SOURCE_TABLES = new Set(['leave_requests', 'locator_slips', 'applicants_profile_entries',
  'selection_lineup_entries', 'computation_of_points_entries', 'work_experience_sheet_entries',
  'turn_around_time_entries', 'idp_entries', 'action_brainstorming_coaching_entries']);
const LEAVE_FIELDS = ['id','employee_id','user_id','leave_type_id','start_date','end_date','total_days','number_of_days',
  'reason','details','employee_official_snapshot','employee_detail_schema_snapshot','attachment_path','attachment_name','attachment_mime_type','attachment_uploaded_at'];
const LOCATOR_FIELDS = ['id','employee_id','department_id','slip_date','am_in','am_out','pm_in','pm_out','request_type',
  'office','reason','additional_details','employee_detail_schema_snapshot','attachment_path','attachment_name','attachment_mime_type','attachment_uploaded_at'];
function projectContent(scope, source) {
  source = Object.fromEntries(Object.entries(source).map(([key,value]) => [key,
    key.endsWith('_at') && typeof value === 'string' && /^\d{4}-\d\d-\d\dT/.test(value)
      ? new Date(value).toISOString() : value]));
  const fields = scope === 'leave_requests' ? LEAVE_FIELDS : scope === 'locator_slips' ? LOCATOR_FIELDS : null;
  if (fields) return Object.fromEntries(fields.filter(key => source[key] !== undefined).map(key => [key, source[key]]));
  return Object.fromEntries(Object.entries(source).filter(([key]) => !['created_at','updated_at','deleted_at'].includes(key)));
}
async function loadContent(db, scope, recordId) {
  let result;
  if (scope === 'native_document') {
    result = await db.query(`/* signature-integrity-content */
      SELECT jsonb_build_object('id',d.id,'document_type',d.document_type,'document_number',d.document_number,
        'title',d.title,'description',d.description,'pages',c.pages,'page_size',c.page_size,
        'margins',c.margins,'format_version',c.format_version,'revision',c.revision) AS content
      FROM docutracker_documents d LEFT JOIN docutracker_document_contents c ON c.document_id=d.id
      WHERE d.id=$1::uuid`, [recordId]);
  } else {
    if (!SOURCE_TABLES.has(scope)) throw securityError('Unsupported signature document.');
    result = await db.query(`/* signature-integrity-content */ SELECT to_jsonb(s) AS content FROM "${scope}" s WHERE s.id=$1::uuid`, [recordId]);
  }
  if (!result.rows[0]?.content) throw securityError('Signed document was not found.');
  return projectContent(scope, result.rows[0].content);
}
function binding(context, row) {
  return { scope:context.scope, record_id:String(context.recordId), slot:String(context.slot), revision:Number(context.revision || 0),
    asset_id:String(row.signature_asset_id), signer_id:String(row.signed_by),
    signed_at:row.signed_at instanceof Date ? row.signed_at.toISOString() : new Date(row.signed_at).toISOString(),
    signer_name:row.signer_name_snapshot || null };
}
function subjectKey(context, row) { return digest(binding(context, row)); }
async function recordSignatureEvidence(db, { row, baseline = false, ...context }) {
  if (!row?.signature_asset_id || !row.signed_by || !row.signed_at) throw securityError('Signing identity or timestamp is missing.');
  const asset = (await db.query(`SELECT id,owner_user_id,mime_type,image_bytes FROM docutracker_signature_assets
    WHERE id=$1::uuid AND owner_user_id=$2::uuid`, [row.signature_asset_id,row.signed_by])).rows[0];
  if (!asset) throw securityError('Signature ownership verification failed.');
  const bytes = decryptSignature(asset.image_bytes, {assetId:asset.id,ownerId:asset.owner_user_id,mimeType:asset.mime_type}, {allowLegacy:true});
  const content = await loadContent(db,context.scope,context.recordId);
  const signing=require('./signatureAuthorization');
  const authorization = !baseline ? await signing.requireSigningAuthorization(db,row.signed_by,
    signing.signingDocumentBinding(context.scope,content,digest(bytes))) : null;
  const manifest = {...binding(context,row), content_digest:digest(content), image_digest:digest(bytes),
    assurance:baseline?'legacy_baseline':'confirmed', authorization_id:authorization?.id||null, recorded_at:new Date().toISOString()};
  const sealed = sealManifest(manifest);
  await db.query(`INSERT INTO signature_integrity_receipts(subject_key,sealed_manifest)
    VALUES($1,$2::jsonb) ON CONFLICT(subject_key) DO NOTHING`, [subjectKey(context,row),JSON.stringify(sealed)]);
  return manifest;
}
async function verifySignatureEvidence(db, context, row) {
  const stored = (await db.query(`SELECT sealed_manifest FROM signature_integrity_receipts WHERE subject_key=$1`,[subjectKey(context,row)])).rows[0];
  if (!stored) throw securityError('Signature integrity receipt is missing. Migrate legacy signatures or sign this revision again.');
  const manifest = verifyManifest(stored.sealed_manifest);
  if (digest(binding(context,row)) !== digest(Object.fromEntries(Object.keys(binding(context,row)).map(key=>[key,manifest[key]]))) ||
      manifest.content_digest !== digest(await loadContent(db,context.scope,context.recordId)) ||
      manifest.image_digest !== digest(Buffer.from(row.signature_image_base64 || '', 'base64'))) {
    throw securityError('Signature integrity verification failed. The document must be signed again.');
  }
  return manifest.assurance === 'legacy_baseline' ? 'legacy_baseline' : 'verified';
}
async function protectSignatureRows(db, {scope,recordId,revision}, rows) {
  return Promise.all(rows.map(async row => {
    if (!row.signature_asset_id || !row.signed_at) return row;
    try {
      return {...row,integrity_status:await verifySignatureEvidence(db,{scope,recordId,
        revision:row.revision ?? revision ?? 0,slot:scope==='native_document'?row.id:row.slot_key},row)};
    } catch(error) {
      if (error.code !== 'CONFLICT') throw error;
      return {...row,signature_image_base64:null,signature_asset_id:null,signed_at:null,locked_at:null,
        integrity_status:'invalid',integrity_message:'This signature could not be verified. Review the document and sign again.'};
    }
  }));
}
module.exports={SOURCE_TABLES,projectContent,loadContent,binding,recordSignatureEvidence,verifySignatureEvidence,protectSignatureRows};

async function assertStoredSignature(db, context, row) {
  const asset=(await db.query(`SELECT id,owner_user_id,mime_type,image_bytes FROM docutracker_signature_assets
    WHERE id=$1::uuid AND owner_user_id=$2::uuid`,[row.signature_asset_id,row.signed_by])).rows[0];
  if(!asset)throw securityError('Signature ownership verification failed.');
  const bytes=decryptSignature(asset.image_bytes,{assetId:asset.id,ownerId:asset.owner_user_id,mimeType:asset.mime_type},{allowLegacy:true});
  return verifySignatureEvidence(db,context,{...row,signature_image_base64:bytes.toString('base64')});
}
async function assertNativeDocumentSignatures(db, recordId) {
  const rows=(await db.query(`SELECT * FROM docutracker_signature_fields WHERE document_id=$1::uuid AND signed_at IS NOT NULL`,[recordId])).rows;
  for(const row of rows)await assertStoredSignature(db,{scope:'native_document',recordId,slot:row.id},row);
}
module.exports.assertStoredSignature=assertStoredSignature;
module.exports.assertNativeDocumentSignatures=assertNativeDocumentSignatures;
