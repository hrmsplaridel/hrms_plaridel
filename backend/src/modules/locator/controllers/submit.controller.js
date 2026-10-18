'use strict';
module.exports = function createLocatorControllers({
  LOCATOR_ATTACHMENT_SUBDIR,
  boolField,
  locatorSubmissionService,
  normalizeRequestType,
  removeLocatorAttachmentFile,
}) {
  return {
    submitRequest: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });

      const slipDate = (req.body?.slip_date || '').toString().trim();
      const office = (req.body?.office || '').toString().trim();
      const reason = (req.body?.reason || '').toString().trim();
      const requestType = normalizeRequestType(req.body?.request_type);
      const amIn = req.body?.am_in === true;
      const amOut = req.body?.am_out === true;
      const pmIn = req.body?.pm_in === true;
      const pmOut = req.body?.pm_out === true;

      try {
        const mapped = await locatorSubmissionService.submit({
          signature: req.body?.signature,
          additionalDetails: req.body?.additional_details,
          employeeUserId: userId,
          slipDate,
          office,
          reason,
          requestType,
          amIn,
          amOut,
          pmIn,
          pmOut,
        });
        res.status(201).json(mapped);
      } catch (err) {
        if (err?.statusCode && err?.payload) {
          return res.status(err.statusCode).json(err.payload);
        }
        console.error('[locator POST /submit]', err);
        res.status(500).json({ error: 'Failed to submit locator slip' });
      }
    },

    submitWithAttachment: async (req, res) => {
      const userId = req.user?.id;
      const relPath = req.file ? `${LOCATOR_ATTACHMENT_SUBDIR}/${req.file.filename}` : null;
      if (!userId) {
        removeLocatorAttachmentFile(relPath);
        return res.status(401).json({ error: 'Not authenticated' });
      }
      if (!req.file) return res.status(400).json({ error: 'Attachment is required.' });

      const slipDate = (req.body?.slip_date || '').toString().trim();
      const office = (req.body?.office || '').toString().trim();
      const reason = (req.body?.reason || '').toString().trim();
      const requestType = normalizeRequestType(req.body?.request_type);
      const amIn = boolField(req.body?.am_in);
      const amOut = boolField(req.body?.am_out);
      const pmIn = boolField(req.body?.pm_in);
      const pmOut = boolField(req.body?.pm_out);
      const cleanup = () => {
        removeLocatorAttachmentFile(relPath);
      };

      try {
        const mapped = await locatorSubmissionService.submit({
          signature: req.body?.signature,
          additionalDetails: req.body?.additional_details,
          employeeUserId: userId,
          slipDate,
          office,
          reason,
          requestType,
          amIn,
          amOut,
          pmIn,
          pmOut,
          attachment: {
            name: req.file.originalname || 'attachment',
            path: relPath,
            mimeType: req.file.mimetype || null,
          },
        });
        res.status(201).json(mapped);
      } catch (err) {
        cleanup();
        if (err?.statusCode && err?.payload) {
          return res.status(err.statusCode).json(err.payload);
        }
        console.error('[locator POST /submit-with-attachment]', err);
        res.status(500).json({ error: 'Failed to submit locator slip with attachment' });
      }
    },
  };
};
