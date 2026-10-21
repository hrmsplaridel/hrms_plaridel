# DocuTracker Purchase Request — requirements note

**Status:** Requirements pending from HR / Procurement — implementation on hold.

**Date recorded:** 20 October 2026.

This note records discovery only. It is not an implementation plan and it does not authorize changes.

## Implementation hold

Do not change the current Purchase Request workflow, template, permissions, schema, or Release configuration until the actual municipal Purchase Request form and HR/Procurement answers are provided.

Do not create migrations, new Purchase Request fields, new workflow steps, signature rules, automatic calculations, Purchase Request numbering, or Release behavior unless those requirements are confirmed.

## What is currently in the system

The existing Purchase Request implementation is a placeholder. It must not be treated as the municipality's official Purchase Request process.

- Three specific-user workflow steps (labeled 1st Step, 2nd Step, and Final Step).
- No official Department Head / Budget / Procurement / Mayor routing has been confirmed.
- No required e-signatures.
- Free-form Quill document.
- Fixed 3-row purchase-item table.
- Manually entered costs and totals.
- Typed signature lines, not signature blocks.
- No official PR number. Documents still use `DOC-YYYY-NNNNNN`. The stored type prefix `PR` is unused.
- Release / Distribution is disabled (`requires_release` is false).
- No existing Purchase Request records.

An unused code example still mentions Requesting Department → Procurement → Accounting → Approving Officer. That example is not the saved workflow and is not the official process.

## Questions still awaiting HR / Procurement

### Request creation

- Who may create a Purchase Request?
- Every employee, or only designated employees?
- Is the requesting department captured automatically?

### Workflow / signatures

- Who reviews or signs first?
- Department Head?
- Budget?
- Procurement?
- Mayor / HOPE (Head of the Procuring Entity)?
- What is the exact order?
- Is each step Review, Certification, Recommendation, Approval, or Noted?
- Which steps require an e-signature?
- Who acts as backup if the primary signer is unavailable?

### Official form

- Obtain the actual blank Purchase Request form.
- Confirm every printed field.
- Confirm paper size.
- Confirm header, footer, and logos.
- Confirm signature blocks and printed position titles.

### Purchase items

- Are multiple items allowed?
- Is there a maximum number of rows, or is the list unlimited?
- Which columns are required?
- Quantity, unit, unit cost, and total cost?
- Should line totals calculate automatically?
- Should the grand total calculate automatically?
- Is there a purpose or justification field?

### Numbering

- Is there an official PR number separate from `DOC-YYYY-NNNNNN`?
- Who issues it?
- When is it assigned?
- What is the exact format?

### Release / distribution

- Does final approval require Release Document?
- Which office receives it?
- Does the requesting department receive a copy?
- Who may release it?

### Access

- Who can view a Purchase Request while it is in process?
- Who can view it after completion?
- Should the receiving office get view-only access?

## When requirements arrive

Map the confirmed process in this order:

official Purchase Request form → structured fields → line-item calculations → signatories → workflow → permissions → official PDF → numbering → release/distribution.

Reuse existing DocuTracker infrastructure where it matches the confirmed process:

- department primary and backup reviewers
- no-self-review
- single active reviewer
- Admin Recovery
- escalation
- signer identity snapshots
- the structured-form approach used by Memo
- Release / Distribution
- Required Actions
- audit and history

Do not copy the Memo visual layout into Purchase Request. The official Purchase Request form has its own structure.
