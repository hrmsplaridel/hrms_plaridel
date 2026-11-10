# System backups

Superadmins can open **System Administration > Backups** to create a backup, review history, and configure a daily schedule. System Health shows the latest backup status. The schedule defaults to disabled, 02:00 Asia/Manila, with seven-day retention. Enable it after reviewing the storage destination. Scheduling runs while the API is online; a missed time is caught up on the next startup/tick on that day. A failed scheduled attempt is not retried repeatedly that day; use Back up now to retry. Manual starts have a one-minute cooldown.

## Storage and prerequisites

- Install matching PostgreSQL client tools (`pg_dump`, `pg_restore`) and `tar` on the API server. Use a pg_dump version compatible with the database server. Executables may be configured with `PG_DUMP_PATH`, `PG_RESTORE_PATH`, and `BACKUP_TAR_PATH`.
- New backups also require `age` and `BACKUP_AGE_RECIPIENT` (a public `age1...` key). Set `BACKUP_AGE_PATH` if it is not on the service PATH. Missing configuration blocks new backups; encryption failure never falls back to plaintext. The recovery private key is never accepted through the app or stored in backup metadata. Follow [encrypted backup setup and recovery](BACKUP_ENCRYPTION_SETUP.md).
- Set `BACKUP_DIR` to a private directory outside `UPLOAD_DIR`. Default: `backend/.backups`, excluded from Git. The process account must be able to read uploads and write backups. No public download or restore endpoint is exposed.
- Use a persistent directory shared by API instances on the same deployment. PostgreSQL advisory locking prevents simultaneous jobs; multiple hosts with separate storage directories are not supported.
- Restrict Windows directory ACLs to the service account and authorized operators. POSIX directories/files are created with modes 0700/0600; existing directory permissions are not changed. Use encrypted storage and a secure off-server copy appropriate for HR records.
- Database connection credentials come from `DATABASE_URL`, are supplied through child environment variables, and are not passed as command arguments or returned in API errors. Unsupported connection URL options fail the backup rather than silently changing connection behavior.

Each successful UUID-named directory contains:

1. `database.dump.age`: encrypted PostgreSQL custom-format database export, including database-stored attachment data.
2. `uploads.tar.gz.age`: encrypted configured local uploads directory, including local employee and document attachments.
3. `manifest.json`: format 2 metadata, public encryption recipient, timestamps, ciphertext sizes and SHA-256 hashes, scope, and completion status. It contains no private recovery key.

The database and upload archives are checked before encryption. Private temporary plaintext files are removed after encryption; failed jobs attempt to remove partial artifacts. This is not a guarantee of secure erasure of filesystem remnants, and a compromised running server can still access the live database and uploads. Secure the host and use encrypted storage too.

Existing format 1 backups remain readable and are labeled **Not encrypted · older backup**. They are not automatically converted or removed by the upgrade. Normal configured retention still applies after a later successful backup. Encryption status is separate from external storage: the app displays **Off-server copy: not verified**, because it cannot establish that an operator copied a folder onto a physically separate device.

History/settings are stored atomically in private `state.json`. Back up this metadata too when copying the backup root. Settings changes and backup start/outcome events are also recorded in `audit_logs`. No schema migration is required.

## Retention and recovery limits

Retention accepts 1–90 days and runs only after a successful new backup. The most recent successful copy is never pruned. Cleanup only unlinks known artifact names in validated UUID directories; it does not recursively remove arbitrary paths. Failed/interrupted jobs are marked failed and never counted as successful. Interrupted directories may require operator cleanup after inspection. History preserves successful backups and the latest 100 other outcomes.

Archive list checks and hashes are not a complete production restore rehearsal. Database export is transactionally consistent within PostgreSQL, but the separate uploads archive is not a coordinated database/filesystem snapshot. For guaranteed cross-resource consistency, stop writes during backup or use coordinated infrastructure snapshots. Externally stored files, PostgreSQL cluster roles, server configuration, secrets, and executable code are excluded. Archive tools preserve filesystem links rather than copying external link targets; avoid symlinks to external attachment stores or back those stores up separately.

A backup on the same server does not protect against server/disk loss. Copy completed folders to off-server storage, verify hashes, and test recovery in an isolated environment. `node backend/scripts/copy-encrypted-backup.js <backup-folder> <destination-root>` verifies format 2 source and copied ciphertext hashes and refuses to overwrite an existing copy. It does not prove physical separation; choose an external device or another machine, then disconnect offline media. Back up the private recovery key separately from the encrypted files; losing it makes those backups unrecoverable.

Restore is deliberately not available in the app. An operator should provision an isolated target with required roles/extensions, verify manifest hashes, decrypt `.age` files on the recovery machine, restore the recovered custom dump with `pg_restore`, extract recovered uploads into a clean target, and verify the app before planning a production restore. Never test restoration over the live database. Legacy plaintext backups skip the decryption step.

## Validation on 2026-10-04

- Service and HTTP tests cover authorization, overlapping jobs, schedule catch-up, optimistic settings revisions, tool failures/redaction, retention, interrupted state, corrupt metadata, and missing backup files.
- Opt-in integration test `BACKUP_INTEGRATION=1 node --test test/systemBackups.integration.test.js` requires a localhost database and creates/removes only a uniquely named disposable schema. It exports and restores test data and round-trips a synthetic upload file using real tools.
- A complete local development database/uploads backup was created successfully (21,926,568 bytes). This was not a full-database restore rehearsal.

For deployment, install the tools and configure private persistent storage on Ubuntu separately. Local Windows configuration and backups are not copied to Ubuntu automatically. Rebuild/reload the frontend after deployment. Automatic scheduling stays off until a superadmin enables it.
