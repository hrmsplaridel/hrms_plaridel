# DocuTracker Restriction Test Matrix

This matrix is used for P1 sign-off and evidence gathering.

## Accounts

- `A1`: Admin
- `E1`: Employee under test
- `E2`: Other employee

## Scope

- UI visibility restrictions
- Permission matrix correctness for selected employee
- Action gating (`approve`, `forward`, `return`)
- Workflow integrity (holder + status checks)

## Test Cases

| Case | Scenario | Steps | Expected Result | Evidence |
|---|---|---|---|---|
| R1 | Deny view for E1 on Leave/DTR | A1 sets E1 `view=false` for `dtr`; E1 opens DocuTracker list | No Leave source-backed documents visible to E1 | Screenshot: permission edit + E1 list |
| R2 | Allow view for E1 on Leave/DTR | A1 sets E1 `view=true` for `dtr`; E1 files leave; refresh list | E1 sees own Leave request mapped in DocuTracker | Screenshot: leave submission + DocuTracker row |
| R3 | Cross-employee isolation | E2 files leave; E1 refreshes list | E1 does not see E2 private source-backed record unless explicitly allowed | Screenshot: E2 submission + E1 filtered list |
| R4 | Deny approve/forward actions | A1 sets E1 `approve=false`, `forward=false`; E1 attempts actions | Action denied (403/validation) and no state change | API response screenshot/log + unchanged UI state |
| R5 | Re-allow approve/forward actions | A1 sets E1 `approve=true`, `forward=true`; E1 retries on valid holder/status | Actions succeed only on valid status and holder | Screenshot/API response + updated status/history |
| R6 | Selected employee matrix correctness | In setup screen, switch selected user E1/E2 | Toggles reflect selected employee, not admin defaults | Screenshot of both user selections |
| R7 | Missing-table resilience | Keep one source table unavailable; open documents list | Banner shown; available source modules still load | Screenshot: warning banner + loaded documents |

## Workflow Integrity Checks

- Non-holder cannot transition even when explicitly granted action.
- Invalid transitions are blocked (`forward` from `pending`, etc.).
- Last-step `approve` closes document (`approved`, holder cleared).
- `return` sends document to previous valid assignee.

## Evidence Packaging

For each case store:

1. Screenshot before action.
2. Screenshot after action.
3. API response or backend log snippet for pass/fail.
4. Final result (`PASS` or `FAIL`) and notes.
