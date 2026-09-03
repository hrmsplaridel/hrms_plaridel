function locatorAttachmentLifecycleError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

async function safeRollback(client) {
  try {
    await client.query('ROLLBACK');
  } catch (_) {}
}

async function safeRemove(removeFile, filePath, logger) {
  if (!filePath) return;
  try {
    await Promise.resolve(removeFile(filePath));
  } catch (error) {
    logger.error('[locator attachment cleanup]', error);
  }
}

async function replaceLocatorAttachment({
  dbPool,
  slipId,
  employeeId,
  attachment,
  canModifyStatus,
  recordHistory,
  removeFile,
  logger = console,
}) {
  let client;
  let transactionStarted = false;
  let committed = false;
  let oldAttachmentPath = null;

  try {
    client = await dbPool.connect();
    await client.query('BEGIN');
    transactionStarted = true;

    const current = await client.query(
      `SELECT id, status, employee_id, attachment_name, attachment_path
       FROM locator_slips
       WHERE id = $1::uuid AND employee_id = $2::uuid
       FOR UPDATE`,
      [slipId, employeeId]
    );
    const row = current.rows[0];
    if (!row) {
      throw locatorAttachmentLifecycleError(404, 'Locator slip not found');
    }
    if (!canModifyStatus(row.status)) {
      throw locatorAttachmentLifecycleError(
        409,
        'Attachments are locked after submission. They can only be changed after the request is returned for correction.'
      );
    }

    oldAttachmentPath = row.attachment_path || null;
    await client.query(
      `UPDATE locator_slips
       SET attachment_name = $1,
           attachment_path = $2,
           attachment_mime_type = $3,
           attachment_uploaded_at = now(),
           updated_at = now()
       WHERE id = $4::uuid`,
      [attachment.name, attachment.path, attachment.mimeType, slipId]
    );
    if (recordHistory) {
      await recordHistory(client, {
        locatorSlipId: slipId,
        action: 'attachment_replaced',
        fromStatus: row.status,
        toStatus: row.status,
        actorId: employeeId,
        actorRole: 'employee',
        metadata: {
          previous_attachment_name: row.attachment_name || null,
          attachment_name: attachment.name,
        },
      });
    }
    await client.query('COMMIT');
    committed = true;
  } catch (error) {
    if (client && transactionStarted && !committed) {
      await safeRollback(client);
    }
    if (!committed) {
      await safeRemove(removeFile, attachment.path, logger);
    }
    throw error;
  } finally {
    client?.release();
  }

  if (oldAttachmentPath && oldAttachmentPath !== attachment.path) {
    await safeRemove(removeFile, oldAttachmentPath, logger);
  }
  return {
    attachment_name: attachment.name,
    attachment_path: attachment.path,
    attachment_mime_type: attachment.mimeType,
  };
}

async function deleteLocatorAttachment({
  dbPool,
  slipId,
  employeeId,
  canModifyStatus,
  recordHistory,
  removeFile,
  logger = console,
}) {
  let client;
  let transactionStarted = false;
  let committed = false;
  let oldAttachmentPath = null;

  try {
    client = await dbPool.connect();
    await client.query('BEGIN');
    transactionStarted = true;

    const current = await client.query(
      `SELECT id, status, employee_id, attachment_name, attachment_path
       FROM locator_slips
       WHERE id = $1::uuid AND employee_id = $2::uuid
       FOR UPDATE`,
      [slipId, employeeId]
    );
    const row = current.rows[0];
    if (!row) {
      throw locatorAttachmentLifecycleError(404, 'Locator slip not found');
    }
    if (!canModifyStatus(row.status)) {
      throw locatorAttachmentLifecycleError(
        409,
        'Attachments are locked after submission. They can only be changed after the request is returned for correction.'
      );
    }

    oldAttachmentPath = row.attachment_path || null;
    await client.query(
      `UPDATE locator_slips
       SET attachment_name = NULL,
           attachment_path = NULL,
           attachment_mime_type = NULL,
           attachment_uploaded_at = NULL,
           updated_at = now()
       WHERE id = $1::uuid`,
      [slipId]
    );
    if (recordHistory) {
      await recordHistory(client, {
        locatorSlipId: slipId,
        action: 'attachment_removed',
        fromStatus: row.status,
        toStatus: row.status,
        actorId: employeeId,
        actorRole: 'employee',
        metadata: { attachment_name: row.attachment_name || null },
      });
    }
    await client.query('COMMIT');
    committed = true;
  } catch (error) {
    if (client && transactionStarted && !committed) {
      await safeRollback(client);
    }
    throw error;
  } finally {
    client?.release();
  }

  await safeRemove(removeFile, oldAttachmentPath, logger);
}

module.exports = {
  deleteLocatorAttachment,
  locatorAttachmentLifecycleError,
  replaceLocatorAttachment,
};
