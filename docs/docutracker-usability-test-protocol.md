# DocuTracker moderated usability test protocol

**Status:** Protocol only. No sessions have been run for this guide. Every observation, score, and finding below is blank on purpose.

Use this guide with the controlled dev records already prepared. Do not invent what a participant did, said, hesitated over, how long they took, or how satisfied they were. Record only what happens in the session.

## How to read this guide

| Kind of content | What it is | What to do with it |
| --- | --- | --- |
| Predefined test task | The instruction the facilitator reads | Use it as written. Do not add the name of a button or menu. |
| Expected system behavior | How the prepared record is set up, and what the product is built to show | Use it to judge the outcome. It is not a participant result. |
| Observation to record | What the participant actually does and says | Write it during the session. Leave it blank until then. |
| Finding / result | A conclusion after one or more real sessions | Fill the final section only after moderated sessions. |

A facilitator assumption is not a finding.

## Prepared records

Do not change these records except when a task in this protocol asks the participant to act on them during a session.

| Record | Title in the setup | State | Who it is for | Test goal |
| --- | --- | --- | --- | --- |
| `DOC-2026-000042` | UT-REV-QUEUE-DEMO | In review. Current reviewer: Dann Zapitan. | Assigned reviewer | See whether the assigned reviewer can tell that the document needs their review, open it, understand its status, and carry out the correct review action. |
| `DOC-2026-000043` | UT-HR-AWAITING-RELEASE | Approved. Release is required. Not released. | Authorized HR/admin release user | See whether that user understands that workflow approval is finished and the document is still awaiting release, and can find and use Release Document. |
| `DOC-2026-000044` | UT-EMP-RELEASED-DEMO | Approved. Already released to Accounting. | Accounting employee with no review, signature, or release duty on this document | See whether that employee understands “Released to your department — view only” and that no further action is required. |

**Do not release `DOC-2026-000043` before the session.** Releasing it removes the awaiting-release state. If more than one release participant needs an unreleased record, prepare a separate controlled copy on purpose. Do not reuse `DOC-2026-000043` after it has been released in a session.

### Expected system behavior (not a result)

- `DOC-2026-000042` is in review and held by the assigned reviewer. The reviewer should be able to open it and see that it is their turn to review.
- `DOC-2026-000043` stays `approved` in stored workflow status. The screen should say that approval is complete and release is still required (“Approved — awaiting release”), not that the whole lifecycle is finished. Release Document is a separate action.
- `DOC-2026-000044` is `approved` and already released to Accounting. An Accounting employee with no other duty on it should see “Released to your department — view only” and “You can view this released document, but no action is required from you.”

## Protected record

`DOC-2026-000041` is a protected Memo signing acceptance sample. Do not modify it. Do not use it for usability tasks, including tasks that approve, return, reject, sign, release, or edit.

## Participant roles

Run each person only on the scenario that matches their role. Do not ask every role to do every task.

| Role | Scenario | Do not record |
| --- | --- | --- |
| Assigned reviewer | `DOC-2026-000042` | Passwords, or any login secret |
| HR/admin release user | `DOC-2026-000043` | Passwords, or any login secret |
| Normal employee in the receiving department (Accounting) | `DOC-2026-000044` | Passwords, or any login secret |

The facilitator signs the participant in before the tasks begin, or the participant signs in with credentials supplied outside this document. This guide does not contain usernames or passwords.

**Session header (fill at the session):**

| Field | Entry |
| --- | --- |
| Date | |
| Facilitator | |
| Participant label (for example P1, not an account name) | |
| Role | |
| Record used | |
| Intended receiving department for a release task, confirmed before the session | |

## Facilitator rules

- Read the instruction once. Repeat it if asked. Do not point, name a control, or open the document for the participant.
- Start the participant on the DocuTracker document list unless the task says they are already inside a document.
- If the participant cannot continue, note the assistance as Minor or Major and what you did. Do not demonstrate the rest of the task and then mark it successful.
- Stop a task that would change `DOC-2026-000041`.
- Write quotes only if the participant actually said them, and mark them as quotes.

## Tasks

Observation columns stay blank until the session. Allowed codes, when you fill them later:

- Completion status: Success / Partial / Failed
- Assistance required: None / Minor / Major

| Task ID | Participant role | Starting screen | Facilitator instruction | Expected successful outcome | Completion status: Success / Partial / Failed | Assistance required: None / Minor / Major | Time started | Time completed | Observed errors | Observed hesitation/confusion | Participant comments | Facilitator notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| UT-01 | Assigned reviewer | DocuTracker document list | “You have been assigned a document that requires your attention. Find it and determine what you need to do.” | The participant finds `DOC-2026-000042` without the facilitator navigating there. | | | | | | | | |
| UT-02 | Assigned reviewer | Wherever UT-01 ended | “What do you need to do with this document?” | The participant states that a review action is required from them. | | | | | | | | |
| UT-03 | Assigned reviewer | Wherever UT-02 ended | “Open the document and look through it until you can describe its current status.” | The participant opens `DOC-2026-000042` and describes it as in review and waiting on them. | | | | | | | | |
| UT-04 | Assigned reviewer | Inside `DOC-2026-000042` | “Do what you believe you are supposed to do as the reviewer. Stop when you think you are finished.” | The participant completes one review action the system allows the current holder to take. The facilitator did not name the control. | | | | | | | | |
| UT-05 | HR/admin release user | DocuTracker document list | “A document has finished its review but is not finished being distributed. Find that document.” | The participant finds `DOC-2026-000043` without the facilitator navigating there. | | | | | | | | |
| UT-06 | HR/admin release user | Inside `DOC-2026-000043`, or the list if they have not opened it | “In your own words, what is the difference between a document that is approved and a document that has been released?” | The participant explains that approval is complete and this document still has to be released before the receiving department gets it. | | | | | | | | |
| UT-07 | HR/admin release user | Inside `DOC-2026-000043` | “Distribute this document to the department that should receive it. Stop when you believe that is done.” | The participant releases `DOC-2026-000043` to the department written in the session header. The facilitator did not name the control. The record was not released before this task. | | | | | | | | |
| UT-08 | Receiving-department employee (Accounting) | DocuTracker document list | “A document was sent to your department. Find it.” | The participant finds `DOC-2026-000044` without the facilitator navigating there. | | | | | | | | |
| UT-09 | Receiving-department employee (Accounting) | Inside `DOC-2026-000044` | “Decide whether you need to do anything with this document. Tell me what you would do next.” | The participant states that they can view it and that no action is required. They do not start a review, signature, or release. | | | | | | | | |
| UT-10 | The participant for the scenario just used | The document from that scenario | “Show me where you would look to see what has already happened to this document and what its status is.” | The participant opens the history or status information for that record without the facilitator pointing to it. | | | | | | | | |

Copy UT-10 once per participant if more than one person is tested. Leave the copies blank until each session.

## Success criteria

Judge each task against these checks. Do not turn them into a pass rate until real sessions exist, and do not write a rate in this protocol in advance.

- The participant finds the correct record without the facilitator navigating.
- The participant correctly identifies the current status of that record.
- The participant correctly says whether they need to act.
- The reviewer completes an authorized review action on `DOC-2026-000042`.
- The release user can tell approval apart from release on `DOC-2026-000043`, and can release it during UT-07 only.
- The receiving employee understands view-only access on `DOC-2026-000044`.
- The participant does not attempt an action they are not allowed because the screen suggested that action was theirs.

Mark Success only when the expected outcome for that task happened. Mark Partial when part of it happened. Mark Failed when it did not. Record assistance separately.

## Questions after the tasks

Ask these after that participant’s tasks. Write the answer in their words. If they do not answer, leave the line blank. Do not paraphrase a silence into a finding.

| Question | Answer |
| --- | --- |
| What part was easiest to understand? | |
| Was anything difficult to find? | |
| Was the document's current status clear? | |
| Was it clear whether you needed to take action? | |
| Was any wording confusing? | |
| What would you improve? | |

### Ratings

Ask for a number from 1 (low) to 5 (high). Leave the score blank if you do not ask, or if the participant does not give a number. Do not choose a number for them.

| Topic | Score (1–5) |
| --- | --- |
| Ease of navigation | |
| Clarity of document status | |
| Clarity of required actions | |
| Ease of completing the assigned task | |
| Overall usability | |

## Findings

**Complete only after real moderated sessions.**

Do not fill this section from a heuristic review, a facilitator walkthrough, or an expectation about the screen.

| Item | Result |
| --- | --- |
| Participant count | |
| Successful tasks | |
| Partial tasks | |
| Failed tasks | |
| Recurring usability issues | |
| Severity | |
| Recommended change | |
| Evidence / participant observation | |

Add one row per issue after sessions, using the same columns. Evidence must point at a participant label and a task ID from a real session.

## Cleanup

- Do not run `backend/_tmp_ut_cleanup.js` until all usability sessions are finished.
- Preserve `DOC-2026-000041`.
- Clean up the temporary usability records and configuration only after testing is complete.
- Never convert facilitator assumptions into reported user findings.
