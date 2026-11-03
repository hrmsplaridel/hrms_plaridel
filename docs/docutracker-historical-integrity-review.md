# DocuTracker historical content integrity review

Read-only review of native DocuTracker documents, completed 22 Oct 2026. No document, signature, attachment, activity history, release record, or usability-test record was changed. No historical repair was attempted.

The review covered documents with an empty `source_module`. RSP and Learning & Development records were not in this set.

## Scope

| Result | Count |
| --- | --- |
| Native documents examined | 21 |
| Documents that had left draft | 13 |
| Documents with a history row that set status to `approved` | 8 |
| Released documents | 1 (`DOC-2026-000044`) |
| Confirmed post-submission content changes | 2 |
| Confirmed changes after final approval or release | 0 |
| Documents needing manual review | 3 |

## Confirmed findings

These are writes stored after the document's `submitted` history time. They are not proof that the saved text differs from an earlier body, because older memo versions were not kept.

### DOC-2026-000009

Memo. Current status: overdue. Not released.

The memo content row was created on 28 Aug 2026, after submission and return on 27 Aug 2026, and last saved on 30 Aug 2026 by Kristoffer Zapitan at revision 4. No content row existed at submission. A later `approved` history event on 21 Sep 2026 left the status `in_review`, so this save is not a post-approval change.

Eight "Moved signed field" events and one signature replacement on 30 Aug 2026 by System Admin are the signing workflow. They are not counted as title or body edits.

### DOC-2026-000011

Memo. Current status: overdue. Not released.

Kristoffer Zapitan uploaded `Polished-Parents-Consent_Panag-ilhanay_2026.pdf` (file version 1) about one minute after submission on 3 Sep 2026. The memo body was saved before submission and was not saved again. The later `approved` history event left the status `in_review`.

## Suspected findings

These are not confirmed content edits. Four attachment rows share one timestamp, 22 Jul 2026, 11:18 PM. That fits a bulk file-history load rather than four separate uploads. The original attach time is not stored.

| Document | Type | Current status | Released | Why it needs review |
| --- | --- | --- | --- | --- |
| DOC-2026-000003 | Memo | Approved | No | Shared file timestamp falls after approval |
| DOC-2026-000006 | Memo | Approved | No | Shared file timestamp falls after submission and before final approval |
| DOC-2026-000008 | Memo | Approved | No | Shared file timestamp falls after approval |

## What the history does not prove

- Memo builder saves do not write an activity entry and do not keep earlier page revisions. Only the latest content timestamp and revision number remain.
- A `metadata_updated` event does not name the changed field unless the remark says a signed field was moved. Every post-submission remark of that kind in this review was a signature move.
- Removing an attachment does not store a removal time.
- `DOC-2026-000001` and `DOC-2026-000003` have no `submitted` history row. Their `sent_time` was used as the submission anchor.
- `DOC-2026-000002` was returned and submitted again. It has no stored memo body, so that resubmission shows no content edit.
- `DOC-2026-000041` through `DOC-2026-000044` were only read. `DOC-2026-000041` is still a draft. `DOC-2026-000043` and `DOC-2026-000044` have no post-submission page or attachment write. Their signatures fall in the same second as submission and approval, and the released document's signature is timestamped before release.

This review does not establish that every approved or released document still matches the version that was submitted.
