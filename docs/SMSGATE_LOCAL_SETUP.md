# Local password-reset SMS through SMSGate

This setup uses the Windows development backend and SMSGate Local Server on an Android phone. The deployed Ubuntu server stays unchanged. Cloud mode is configured separately; use the Cloud endpoint/credentials, a target device ID, and the phone's matching encryption passphrase.

## 1. Prepare the phone

1. Connect the development PC and phone to the same trusted network.
2. Open SMSGate, enable Local Server, and start its service.
3. Grant SMS permission. With multiple SIMs, grant Phone / READ_PHONE_STATE permission too so SMSGate can select a SIM.
4. Confirm the selected SIM can send a normal SMS and has signal and SMS allowance.
5. Reserve the phone's address in the router when keeping this setup, so DHCP does not change it unexpectedly.

The phone used for the initial test was reachable at `192.168.1.3:8080`, with SIM 2 selected. Use your phone's current address if it changes. A browser Swagger error such as "Failed to fetch" is not proof of SMS delivery failure; test backend-to-phone connectivity separately.

## 2. Configure only the local backend

In `backend/.env`, add or update one active entry for each setting:

```dotenv
SMS_PROVIDER=smsgate
SMSGATE_MODE=local
SMSGATE_URL=http://192.168.1.3:8080/message
SMSGATE_USERNAME=sms
SMSGATE_PASSWORD="REPLACE_WITH_THE_LOCAL_SERVER_PASSWORD_FROM_THE_PHONE"
SMSGATE_SIM_NUMBER=2
SMSGATE_TIMEOUT_MS=10000
```

Replace the password placeholder privately in the file. Use the Local Server credentials, not Cloud Server credentials or an HRMS login. Do not put gateway credentials in Flutter, screenshots, Git, or chat. Keep `.env` private. Quote the password, particularly if it contains `#` or spaces, using dotenv-compatible escaping if it contains quotes.

`SMSGATE_URL` is the full send endpoint, including `/message`; it is not `/health`, `/docs`, or just the IP. `phoneNumbers` contains the recipient; `SMSGATE_SIM_NUMBER` chooses the sending SIM. SIM selection is optional; if omitted, the phone's SMSGate selection policy applies. Valid explicit SIM values are 1, 2, or 3.

Optional custom wording:

```dotenv
SMSGATE_PASSWORD_RESET_TEMPLATE="Your HRMS password reset code is {otp}. It expires in {minutes} minutes. Do not share this code."
```

HTTP is allowed only to private/loopback IPs (including Tailscale IPv4 addresses) or localhost. The local HTTP connection is not application-level encrypted: use a trusted private network and do not expose port 8080 publicly. Setting `SMSGATE_ENCRYPTION_PASSPHRASE` also encrypts message text and recipient fields in local mode; it must exactly match the phone's encryption passphrase. Local mode without that setting preserves the original plain local API format.

## 3. Restart the local backend

In Windows PowerShell, if the backend is managed by the existing PM2 process:

```powershell
pm2 restart hrms-backend
```

```powershell
curl.exe --fail --max-time 10 http://127.0.0.1:3000/health
curl.exe --fail --max-time 10 http://127.0.0.1:3000/health/db
```

The startup log reports `SMS OTP (smsgate) - enabled` if configuration is valid. This is a configuration check, not a delivery test. If running with `npm run dev` instead of PM2, restart that process instead; do not run a second backend on port 3000.

## 4. Test through HRMS

1. Run the Flutter app against the local backend, using the project's normal local API configuration. Do not point this test at `https://hrmsplaridel.site`.
2. Use an existing active local test account with a valid Philippine mobile number that you control. The phone number comes from that employee's contact number in HRMS, not from an SMSGate environment variable.
3. Open Forgot password and enter that account's email.
4. Check SMSGate message history and the receiving phone. `Pending` means accepted/queued, `Processed` means submitted by the device, and neither alone proves receipt.
5. Enter the received code and a new password in HRMS. This changes that local test account's password and revokes its existing sessions. Verify login with the new password.

The existing generic forgot-password response remains the same for unknown accounts and SMS request failures to prevent account enumeration. It is not a delivery receipt. Existing OTP hashing, expiry, failed-attempt limits, per-user resend cooldown, and HTTP rate limits remain in force. Do not repeatedly click send while a message is queued.

The backend sends an exact `validUntil` matching the OTP expiry, requests delivery reporting, and uses priority 100 for time-sensitive messages. The gateway acknowledges acceptance asynchronously. A later device/SIM failure is visible in SMSGate, not automatically reflected in the HRMS response. There is no automatic retry, provider fallback, or delivery webhook in this local integration; timeouts can occur after the gateway has accepted a message.

## 5. Troubleshoot

| Result | Action |
| --- | --- |
| Cannot connect | Keep the phone service running; check its current IP and shared network. |
| HTTP 401 | Verify Local Server credentials in the backend `.env`, then restart the backend. |
| READ_PHONE_STATE permission error | Allow Phone permission, restart the SMSGate service, and retry once. |
| Message accepted but failed on phone | Check its detailed failure reason, selected SIM, signal, SMS permission, and allowance. |
| No OTP for a particular employee | Verify their contact number and active account; wait for existing resend/rate-limit windows. |
| `SMS OTP (smsgate) - off` | Check the full endpoint, credentials, SIM number, and timeout (1–30000 milliseconds). |

## Switch back to UniSMS

```dotenv
SMS_PROVIDER=unisms
```

Retain the existing `UNISMS_API_SECRET_KEY` configuration, then restart the local backend. If `SMS_PROVIDER` is unset, UniSMS remains the default. Selecting SMSGate never silently uses UniSMS on failure. No additional dependency installation, database migration, or frontend change is required for this provider switch.

## References

- [SMSGate Local Server](https://docs.sms-gate.app/getting-started/local-server/)
- [SMSGate multi-SIM selection](https://docs.sms-gate.app/features/multi-sim/)
- [Message fields, priority, and expiry](https://docs.sms-gate.app/features/sending-messages/)
