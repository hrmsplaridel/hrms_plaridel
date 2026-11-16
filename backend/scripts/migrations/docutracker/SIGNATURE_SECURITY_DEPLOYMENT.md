# Signature security deployment

This update encrypts signature assets, OJT interviewer signatures and paper-record image snapshots with AES-256-GCM. Each envelope is bound to its asset or form, owner and MIME type. Document-integrity receipts use a separate HKDF-derived HMAC key. Neither keys nor passwords are stored in the database or repository.

New electronic signatures and sensitive document approvals require the current password and acknowledgement. A confirmation is bound to the exact API request, expires after five minutes, and is consumed once in the signing transaction. Cancelling confirmation rolls the action back. Historical signatures receive a labelled migration baseline, not a claim of original cryptographic verification. Approved-paper copies remain distinguishable from personally confirmed signatures.

## Existing Ubuntu server

Build the updated application frontend before deployment. Keep the old frontend available for rollback. Older clients cannot complete the new signing confirmation.

1. Schedule a short maintenance window. Back up the database and stop `hrms-api` so an older process cannot write plaintext assets during conversion.
2. As the service account, generate the key file in a private directory outside the repository:

   ```bash
   node scripts/secure-signatures.js --create-key-file /etc/hrms/signature-security-keys.json
   ```

   The directory must already exist and allow the service account to create the file. The script refuses to overwrite an existing file and requests owner-only permissions on Linux. Restrict the directory and file to the service account, and make an encrypted backup of this key file separately from the database backup. Do not commit, share, log, or regenerate the key as part of ordinary deployment.

3. Add this path to the backend service environment or `.env`:

   ```dotenv
   SIGNATURE_SECURITY_KEY_FILE=/etc/hrms/signature-security-keys.json
   ```

   The script loads `backend/.env`; if systemd supplies the variable instead, run the script with the same variable supplied securely to that process. Never paste key material into shell commands.

4. Apply the schema migration to the confirmed database:

   ```bash
   psql -d YOUR_DATABASE -v ON_ERROR_STOP=1 -f scripts/migrations/20261116_signature_security.sql
   ```

5. Review the target and asset count, then convert the confirmed database:

   ```bash
   node scripts/secure-signatures.js
   node scripts/secure-signatures.js --apply --confirm-db YOUR_DATABASE
   ```

   Conversion and receipt creation use one transaction. An error rolls back the data conversion. Existing encrypted assets are checked and retained; existing receipts are never overwritten. No image bytes or keys are printed.

6. Deploy the rebuilt frontend and start the updated backend:

   ```bash
   sudo systemctl start hrms-api
   sudo systemctl status hrms-api --no-pager
   curl --fail http://127.0.0.1:3000/health
   curl --fail http://127.0.0.1:3000/health/db
   ```

   Check a historical signed form, My Signatures, a new signing confirmation, and a printed form. Keep HTTPS enabled through the proxy. Passwords and signature images must not travel over public plaintext HTTP.

## Fresh installation

The new definitions are included in `init-schema.sql`. Configure and securely back up the key file before the first signature is uploaded. There is no automatic plaintext-write fallback when keys are missing.

## Key rotation and recovery

The JSON keyring has `active` and `keys` fields. Add a fresh cryptographically random 32-byte Base64 key under a new ID, retaining all old keys, and select the new ID as active. New images, confirmations and receipts use the active key. The `--reencrypt` option with `--apply --confirm-db` re-encrypts images and paper snapshots with that active key. Old keys must still be retained for existing immutable receipts. Restart the service after changing its environment. Keep old keys and encrypted backups until a deliberate receipt re-attestation/retention procedure is implemented.

If a key is lost, its encrypted images cannot be recovered and its receipts cannot be verified. Restore the matching key backup. If a key is compromised, rotation alone cannot restore trust in signatures produced with that key; investigate and re-confirm affected documents.

To roll back the release, stop the service and restore the matching pre-upgrade database and application/frontend versions together. An older backend cannot read encrypted assets. Do not drop the key or convert images back to plaintext as an ordinary rollback shortcut.

This is application-level protection and evidence of signing through an authenticated account. It is not certificate-based PDF signing, independent proof of human identity, or protection against an attacker who controls both the running application and its keys. Canonical stored form contents are protected; independently changing print artwork or renderer versions is outside that content receipt. Authorized viewers can still copy visible signatures from forms and PDFs. Older backups remain sensitive and require their own encryption and access controls.
