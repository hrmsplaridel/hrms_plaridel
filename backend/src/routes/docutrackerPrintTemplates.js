const express = require('express');
const multer = require('multer');
const { PDFDocument } = require('pdf-lib');
const { pool } = require('../config/db');
const { requireAdmin } = require('../middleware/rbac');
const { withHeavyWork } = require('../middleware/heavyWork');
const {
  mergeLocatorBackground,
  validateLocatorBackground,
} = require('../services/locatorPrintTemplates');
const { checkPrintBackgroundSize } = require('../services/printLayoutPageSettings');
const {
  normalizeDocuTrackerPrintLayout,
} = require('../services/docutrackerPrintLayout');
const {
  canUserPerformDocumentAction,
} = require('../services/docutrackerWorkflowService');
const {
  printSnapshotMeta,
  adoptTypePrintSnapshotForDraft,
} = require('../services/docutrackerPrintSnapshot');
const { sameEntityId } = require('../utils/sameEntityId');

function isUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    String(value || ''),
  );
}

/** Join target for a document's frozen print template (not the live type pointer). */
const DOCUMENT_PRINT_VERSION_JOIN = `
  CASE
    WHEN COALESCE(d.print_form_selection, 'unset') = 'custom'
      THEN d.print_template_version_id
    WHEN COALESCE(d.print_form_selection, 'unset') = 'official'
      THEN NULL
    WHEN d.document_type IN ('memo', 'purchaseRequest')
      THEN NULL
    ELSE dt.print_template_version_id
  END`;

async function canAccessDocumentPrint(docRow, user) {
  if (!docRow || !user?.id) return false;
  if (user.role === 'admin') return true;
  if (sameEntityId(docRow.created_by, user.id)) return true;
  // Type-level download permissions do not establish access to this document.
  return canUserPerformDocumentAction(pool, {
    user,
    document: docRow,
    action: 'view',
  });
}

async function loadDocumentPrintVersionRow(documentId) {
  const q = await pool.query(
    // The shared permission policy needs holder, workflow, department, source,
    // and release state. Keep its document row complete; responses below expose
    // only the explicit print metadata. Version art joins the document snapshot.
    `SELECT d.*, d.id AS document_id,
            COALESCE(dt.display_name, d.document_type) AS document_type_name,
            dt.print_template_version_id AS type_print_template_version_id,
            v.id AS version_id, v.background_pdf, v.background_name, v.print_layout
     FROM docutracker_documents d
     LEFT JOIN docutracker_document_types dt ON dt.document_type = d.document_type
     LEFT JOIN docutracker_print_template_versions v
       ON v.id = (${DOCUMENT_PRINT_VERSION_JOIN})
     WHERE d.id = $1::uuid`,
    [documentId],
  );
  return q.rows[0] || null;
}

async function documentPrintVersion(documentId, user) {
  if (!isUuid(documentId)) {
    throw Object.assign(new Error('Document not found'), { status: 404 });
  }
  let row = await loadDocumentPrintVersionRow(documentId);
  if (!row) {
    throw Object.assign(new Error('Document not found'), { status: 404 });
  }
  if (!(await canAccessDocumentPrint(row, user))) {
    throw Object.assign(new Error('Document not found or access denied'), {
      status: 404,
    });
  }
  // Drafts created before the type had a designed layout stay official/unset.
  // Adopt the live type custom layout once so fill/print match Design layout.
  if (!row.print_layout) {
    const adopted = await adoptTypePrintSnapshotForDraft(pool, row);
    if (adopted) {
      row = await loadDocumentPrintVersionRow(documentId);
      if (!row) {
        throw Object.assign(new Error('Document not found'), { status: 404 });
      }
    }
  }
  return row;
}

const router = express.Router();
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5242880, files: 1 },
});
const draftUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5242880, files: 2 },
});

function file(req, res, next) {
  upload.single('file')(req, res, (e) =>
    e ? res.status(400).json({ error: 'Use one file up to 5 MB' }) : next(),
  );
}
function draftFiles(req, res, next) {
  draftUpload.fields([
    { name: 'file', maxCount: 1 },
    { name: 'background', maxCount: 1 },
  ])(req, res, (e) =>
    e ? res.status(400).json({ error: 'Use files up to 5 MB' }) : next(),
  );
}

function metadata(v) {
  return {
    id: v?.id || null,
    document_type: v?.document_type || null,
    background_name: v?.background_name || null,
    has_background: !!v?.background_pdf,
    print_layout: v?.print_layout || null,
    created_at: v?.created_at || null,
  };
}

/** Official letterhead identity. This does not turn on a custom print layout. */
function officialLetterheadFields(letterhead) {
  const name =
    letterhead && letterhead.source_name
      ? String(letterhead.source_name).trim()
      : '';
  const connected = name.length > 0 && !!letterhead.has_pdf;
  return {
    official_letterhead_name: connected ? name : null,
    has_official_letterhead: connected,
  };
}

function failure(res, e) {
  return res
    .status(e.status || 500)
    .json({
      error: e.status ? e.message : 'Could not load or save printed form',
    });
}

function normalizeTypeKey(raw) {
  const value = String(raw || '').trim();
  if (!value || value.length > 80) {
    throw Object.assign(new Error('Document type is required'), { status: 400 });
  }
  if (!/^[A-Za-z][A-Za-z0-9_-]*$/.test(value)) {
    throw Object.assign(new Error('Document type value is invalid'), {
      status: 400,
    });
  }
  return value;
}

/** Built-in types keep code templates; custom print is still allowed as overlay. */
const BUILTIN_TYPES = new Set(['memo', 'purchaseRequest']);

async function ensureDocumentType(db, documentType, displayName) {
  const key = normalizeTypeKey(documentType);
  await db.query(
    `INSERT INTO docutracker_document_types (document_type, display_name, description)
     VALUES ($1, $2, $3)
     ON CONFLICT (document_type) DO NOTHING`,
    [
      key,
      (displayName || key).trim() || key,
      'Admin-configured DocuTracker document type',
    ],
  );
  return key;
}

async function typeVersion(db, documentType, lock = false) {
  const key = normalizeTypeKey(documentType);
  const q = await db.query(
    `SELECT dt.document_type, dt.display_name, dt.print_template_version_id,
            v.id, v.background_pdf, v.background_name, v.print_layout, v.created_at
     FROM docutracker_document_types dt
     LEFT JOIN docutracker_print_template_versions v
       ON v.id = dt.print_template_version_id
     WHERE dt.document_type = $1
     ${lock ? 'FOR UPDATE OF dt' : ''}`,
    [key],
  );
  if (!q.rows[0]) {
    throw Object.assign(new Error('Document type not found'), { status: 404 });
  }
  return q.rows[0];
}

async function checkOrientation(background, layout) {
  if (!background || !layout) return;
  const doc = await PDFDocument.load(background);
  const { width, height } = doc.getPage(0).getSize();
  checkPrintBackgroundSize(width, height, layout);
}

router.get('/types/:documentType', requireAdmin, async (req, res) => {
  try {
    const row = await typeVersion(pool, req.params.documentType);
    let letterhead = null;
    try {
      const q = await pool.query(
        `SELECT source_name,
                (background_pdf IS NOT NULL AND octet_length(background_pdf) > 0) AS has_pdf
         FROM docutracker_letterheads
         WHERE document_type = $1`,
        [row.document_type],
      );
      letterhead = q.rows[0] || null;
    } catch (e) {
      if (e.code !== '42P01') throw e;
    }
    res.json({
      ...metadata(row),
      ...officialLetterheadFields(letterhead),
    });
  } catch (e) {
    failure(res, e);
  }
});

router.post('/types/:documentType', requireAdmin, file, async (req, res) => {
  let client;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    const key = await ensureDocumentType(
      client,
      req.params.documentType,
      req.body.display_name,
    );
    const current = await typeVersion(client, key, true);
    const uploaded = req.file
      ? await validateLocatorBackground(req.file.buffer, req.file.mimetype)
      : null;
    const remove = req.body.remove_background === 'true';
    const printLayout = normalizeDocuTrackerPrintLayout(
      req.body.print_layout === undefined
        ? current.print_layout
        : req.body.print_layout,
    );
    if (!printLayout) {
      throw Object.assign(new Error('Custom printed layout is required'), {
        status: 400,
      });
    }
    const background = remove
      ? null
      : uploaded || current.background_pdf || null;
    if (background) {
      await validateLocatorBackground(background, 'application/pdf');
    }
    await checkOrientation(background, printLayout);
    const q = await client.query(
      `INSERT INTO docutracker_print_template_versions
        (document_type, background_pdf, background_name, created_by, print_layout)
       VALUES ($1, $2, $3, $4, $5::jsonb)
       RETURNING *`,
      [
        current.document_type,
        background,
        remove
          ? null
          : req.file
            ? req.file.originalname
            : current.background_name || null,
        req.user.id,
        JSON.stringify(printLayout),
      ],
    );
    await client.query(
      `UPDATE docutracker_document_types
       SET print_template_version_id = $1, updated_at = now()
       WHERE document_type = $2`,
      [q.rows[0].id, current.document_type],
    );
    await client.query('COMMIT');
    res.json(metadata(q.rows[0]));
  } catch (e) {
    if (client) await client.query('ROLLBACK');
    failure(res, e);
  } finally {
    client?.release();
  }
});

router.get(
  '/types/:documentType/background',
  requireAdmin,
  async (req, res) => {
    try {
      const row = await typeVersion(pool, req.params.documentType);
      if (!row.background_pdf) {
        return res.status(404).json({ error: 'No background uploaded' });
      }
      res
        .set('Content-Type', 'application/pdf')
        .set('Cache-Control', 'no-store')
        .send(row.background_pdf);
    } catch (e) {
      failure(res, e);
    }
  },
);

router.post(
  '/types/:documentType/preview',
  requireAdmin,
  file,
  withHeavyWork(async (req, res) => {
    try {
      const version = await typeVersion(pool, req.params.documentType);
      if (!req.file) {
        throw Object.assign(new Error('Generated PDF required'), {
          status: 400,
        });
      }
      const bytes = await mergeLocatorBackground(
        version.background_pdf,
        req.file.buffer,
        version.print_layout,
      );
      res
        .set('Content-Type', 'application/pdf')
        .set('Cache-Control', 'no-store')
        .send(bytes);
    } catch (e) {
      failure(res, e);
    }
  }),
);

router.post(
  '/preview',
  requireAdmin,
  draftFiles,
  withHeavyWork(async (req, res) => {
    try {
      const current = req.body.document_type
        ? await typeVersion(pool, req.body.document_type).catch(() => null)
        : null;
      const printLayout = normalizeDocuTrackerPrintLayout(
        req.body.print_layout,
      );
      if (!printLayout) {
        throw Object.assign(new Error('Custom printed layout is required'), {
          status: 400,
        });
      }
      const overlay = req.files?.file?.[0];
      if (!overlay) {
        throw Object.assign(new Error('Generated PDF required'), {
          status: 400,
        });
      }
      const uploaded = req.files?.background?.[0];
      const background =
        req.body.remove_background === 'true'
          ? null
          : uploaded
            ? await validateLocatorBackground(
                uploaded.buffer,
                uploaded.mimetype,
              )
            : current?.background_pdf || null;
      const bytes = await mergeLocatorBackground(
        background,
        overlay.buffer,
        printLayout,
      );
      res
        .set('Content-Type', 'application/pdf')
        .set('Cache-Control', 'no-store')
        .send(bytes);
    } catch (e) {
      failure(res, e);
    }
  }),
);

router.get('/letterheads/:documentType', async (req, res) => {
  try {
    const key = normalizeTypeKey(req.params.documentType);
    const q = await pool.query(
      `SELECT letterhead_png
       FROM docutracker_letterheads
       WHERE document_type = $1`,
      [key],
    );
    const png = q.rows[0]?.letterhead_png;
    if (!png || !png.length) {
      return res.status(404).json({ error: 'No letterhead for this document type' });
    }
    res
      .set('Content-Type', 'image/png')
      .set('Cache-Control', 'private, max-age=86400')
      .send(png);
  } catch (e) {
    failure(res, e);
  }
});

router.get('/documents/:id', async (req, res) => {
  try {
    const row = await documentPrintVersion(req.params.id, req.user);
    const snapshot = printSnapshotMeta(row);
    res.json({
      document_id: row.document_id,
      document_type: row.document_type,
      document_type_name: row.document_type_name,
      version_id: row.version_id || null,
      has_custom_print: !!row.print_layout,
      has_background: !!row.background_pdf,
      background_name: row.background_name || null,
      print_layout: row.print_layout || null,
      print_form_selection: snapshot.print_form_selection,
      print_snapshot_legacy: snapshot.print_snapshot_legacy,
    });
  } catch (e) {
    failure(res, e);
  }
});

router.post(
  '/documents/:id/render',
  file,
  withHeavyWork(async (req, res) => {
    try {
      const row = await documentPrintVersion(req.params.id, req.user);
      if (!row.print_layout) {
        throw Object.assign(
          new Error('This document type has no custom printed form.'),
          { status: 404 },
        );
      }
      if (!req.file) {
        throw Object.assign(new Error('Generated PDF required'), {
          status: 400,
        });
      }
      if ((req.body.version_id || null) !== (row.version_id || null)) {
        throw Object.assign(
          new Error('Printed form settings changed. Please retry.'),
          { status: 409 },
        );
      }
      const bytes = await mergeLocatorBackground(
        row.background_pdf,
        req.file.buffer,
        row.print_layout,
      );
      res
        .set('Content-Type', 'application/pdf')
        .set('Cache-Control', 'no-store')
        .send(bytes);
    } catch (e) {
      failure(res, e);
    }
  }),
);

module.exports = router;
module.exports.BUILTIN_PRINT_TYPES = BUILTIN_TYPES;
module.exports.officialLetterheadFields = officialLetterheadFields;
