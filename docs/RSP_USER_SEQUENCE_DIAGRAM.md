# RSP Module — User (Applicant) Sequence Diagram

Public applicant / user flows in **HRMS Plaridel** for Recruitment, Selection, and Placement (RSP), based on the landing page, `ApplicationFlowPage`, `TrackApplicationPage`, `RecruitmentRepo`, and public backend routes (no admin JWT).

---

## Participants

| Actor / Component | Role |
|-------------------|------|
| **Applicant** | Public user (no login required for recruitment) |
| **Landing UI** | `LandingPage`, `JobVacanciesSection` |
| **Flow UI** | `ApplicationFlowPage`, `TrackApplicationPage` |
| **API Client** | `ApiClient` (unauthenticated for most RSP public endpoints) |
| **Backend** | Express: `rspJobVacancies`, `rspApplications`, `rspExamQuestions`, `rspEmailVerificationPublic`, `rspExamTimeLimits` |
| **PostgreSQL** | `recruitment_applications`, `recruitment_exam_results`, `recruitment_exam_questions`, `job_vacancy_announcement` |
| **File storage** | `uploads/rsp-attachments/{applicationId}/` |
| **Email** | EmailJS (optional Step 1 OTP; HR notification on new application) |
| **HR Admin** | Approves documents, grades BEI, schedules interview, hires (external to user UI) |

---

## Application flow steps (UI)

| Step | Screen | When available |
|------|--------|----------------|
| 1 | Basic info + documents (or track-only status) | Apply now / Continue / Track |
| 2 | Document review pending | After Step 1 submit (`submitted`) |
| 3 | BEI (8 narrative questions) | After HR `document_approved` |
| 4 | General Exam (MCQ) | During exam sequence |
| 5 | Mathematics Exam (MCQ) | During exam sequence |
| 6 | General Information Exam (MCQ) | During exam sequence |
| 7 | Screening result | After `POST exam-results`; polls until BEI graded |
| 8 | Final hiring status | Passed exam + HR updates (interview, registered) |

---

## 1. Browse vacancies (landing page)

```mermaid
sequenceDiagram
    autonumber
    actor User as Applicant
    participant Landing as Landing UI
    participant Repo as JobVacancyAnnouncementRepo
    participant API as API Client
    participant BE as Backend
    participant DB as PostgreSQL

    User->>Landing: Open HRMS landing page
    Landing->>Repo: fetch()
    Repo->>API: GET /api/rsp/job-vacancies
    API->>BE: (public, no JWT)
    BE->>DB: SELECT job_vacancy_announcement<br/>+ slot counts
    DB-->>Landing: vacancies[], headlines
    Landing-->>User: Job Vacancies section

    alt Apply now (specific position)
        User->>Landing: Tap Apply now
        Landing->>Flow: Navigate ApplicationFlowPage(selectedPositionHeadline)
    else Track / Job application menu
        User->>Landing: Track application / Job application
        Landing->>Flow: ApplicationFlowPage() or TrackApplicationPage
    end
```

---

## 2. Track application by email

```mermaid
sequenceDiagram
    autonumber
    actor User as Applicant
    participant UI as TrackApplicationPage<br/>or Flow Step 1 preview
    participant Repo as RecruitmentRepo
    participant API as API Client
    participant BE as Backend
    participant DB as PostgreSQL

    User->>UI: Enter email → Check status
    UI->>Repo: getApplicationByEmail(email)
    Repo->>API: GET /api/rsp/applications/by-email?email=
    API->>BE: (public)
    BE->>DB: SELECT latest application + exam row
    DB-->>UI: application, examResult (bei_grading_complete)

    UI-->>User: RspApplicationStatusTimeline

    loop Auto-refresh every 30s
        UI->>Repo: getApplicationByEmail(email)
        Repo->>API: GET by-email
        BE-->>UI: updated status (e.g. document_approved)
    end

    opt Continue to exams (when allowed)
        User->>UI: Continue
        UI->>UI: _resumeStepForTrackingOnlyEntry → Steps 3–8
    end
```

---

## 3. Step 1 — Apply (basic info, email OTP, documents)

```mermaid
sequenceDiagram
    autonumber
    actor User as Applicant
    participant UI as ApplicationFlowPage<br/>(Step 1)
    participant Prefs as SharedPreferences<br/>(local draft)
    participant Repo as RecruitmentRepo
    participant API as API Client
    participant BE as Backend
    participant DB as PostgreSQL
    participant FS as File storage
    participant Mail as EmailJS

    User->>UI: Fill name, sex, email, phone
    UI->>Repo: fetchRspEmailVerificationConfig()
    Repo->>API: GET /api/rsp/email-verification/config
    BE-->>UI: requiresOtpForNewApplication?

    opt Email OTP required
        User->>UI: Send code
        UI->>Repo: sendRspApplicantEmailOtp(email, fullName)
        Repo->>API: POST /api/rsp/email-verification/send
        BE->>Mail: 6-digit OTP email
        User->>UI: Enter code → Verify
        UI->>Repo: verifyRspApplicantEmailOtp(email, code)
        Repo->>API: POST /api/rsp/email-verification/verify
        BE-->>UI: emailVerificationToken
    end

    User->>UI: Attach 4 PDFs (application letter, resume, TOR, eligibility)
    User->>UI: Submit application

    UI->>Repo: insertApplication(app, emailVerificationToken?)
    Repo->>API: POST /api/rsp/applications
    BE->>DB: check vacancy slot cap
    BE->>DB: INSERT recruitment_applications (status: submitted)
    BE-->>Mail: notify HR (async, optional)
    BE-->>UI: application id

    loop Each document kind
        UI->>Repo: uploadTypedDocument(id, kind, pdf bytes)
        Repo->>API: POST …/attachment-file?kind=…
        BE->>FS: save PDF under rsp-attachments/{id}/
        BE->>DB: UPDATE doc_*_path columns
    end

    UI->>Prefs: clear Step 1 draft
    UI->>UI: _step = 2 (Document review pending)
```

---

## 4. Step 2 — Wait for document approval

```mermaid
sequenceDiagram
    autonumber
    actor User as Applicant
    participant UI as ApplicationFlowPage<br/>(Step 2)
    participant Repo as RecruitmentRepo
    participant BE as Backend
    participant HR as HR Administrator

    User->>UI: View "Under review" / timeline
    loop Poll by email (30s) or manual refresh
        UI->>Repo: getApplicationByEmail(email)
        Repo->>BE: GET /api/rsp/applications/by-email
        BE-->>UI: status
    end

    HR->>BE: PUT …/status document_approved
    Note over HR,BE: Admin action (not user)

    UI-->>User: Status → Approved — may take exams
    User->>UI: Continue to exam
    UI->>UI: _step = 3
```

---

## 5. Steps 3–6 — Screening exams (BEI + MCQ)

```mermaid
sequenceDiagram
    autonumber
    actor User as Applicant
    participant UI as ApplicationFlowPage<br/>(Steps 3–6)
    participant Repo as RecruitmentRepo
    participant BE as Backend
    participant DB as PostgreSQL

    User->>UI: Step 3 — BEI
    UI->>Repo: getExamQuestions('bei')
    Repo->>BE: GET /api/rsp/exam-questions/bei
    BE->>DB: SELECT recruitment_exam_questions
    BE-->>UI: 8 questions
    User->>UI: Type narrative answers (stored locally until submit)

    User->>UI: Step 4 — General Exam
    UI->>Repo: getExamTimeLimits() + getExamQuestionsWithOptions('general')
    BE-->>UI: questions + timer (e.g. 45 min)
    User->>UI: Answer MCQs (client timer; auto-advance on expiry)

    User->>UI: Step 5 — Mathematics Exam
    UI->>BE: GET exam-questions/math + time limits
    User->>UI: Answer MCQs

    User->>UI: Step 6 — General Information Exam
    UI->>BE: GET exam-questions/general_info
    User->>UI: Answer MCQs → Submit all exams
```

---

## 6. Submit exam results (Step 7)

```mermaid
sequenceDiagram
    autonumber
    actor User as Applicant
    participant UI as ApplicationFlowPage
    participant Repo as RecruitmentRepo
    participant BE as Backend
    participant DB as PostgreSQL
    participant HR as HR Administrator

    User->>UI: Submit combined screening (Steps 3–6)
    UI->>UI: Score MCQ sections (client)<br/>Package answers_json (bei + general + math + general_info)

    UI->>Repo: submitExamResult(applicationId, scorePercent, passed, answersJson)
    Repo->>BE: POST /api/rsp/applications/exam-results
    BE->>DB: UPSERT recruitment_exam_results
    alt BEI scores not complete on server
        BE->>DB: application status = exam_taken<br/>passed = false until HR grades BEI
    else All sections scored
        BE->>DB: status = passed | failed
    end
    BE-->>UI: ok
    UI->>UI: _step = 7 (Result)

    opt BEI grading pending
        loop Poll by email
            UI->>Repo: getApplicationByEmail(email)
            BE-->>UI: bei_grading_complete, passed
        end
        HR->>BE: PUT exam-results (BEI scores) — admin
    end

    UI-->>User: Pass/fail + overall score
```

---

## 7. Steps 7–8 — Final interview & hiring (read HR updates)

```mermaid
sequenceDiagram
    autonumber
    actor User as Applicant
    participant UI as ApplicationFlowPage<br/>(Steps 7–8)
    participant Repo as RecruitmentRepo
    participant BE as Backend
    participant HR as HR Administrator

    Note over User,HR: User does not schedule interview;<br/>polls public by-email API

    loop Status refresh
        UI->>Repo: getApplicationByEmail(email)
        Repo->>BE: GET /api/rsp/applications/by-email
        BE-->>UI: final_interview_at, final_interview_passed,<br/>hired_user_id, hr_account_setup_done, status
    end

    HR->>BE: PUT final-interview (schedule)
    UI-->>User: Show interview date/time (Step 7)

    HR->>BE: PUT final-interview-outcome (pass/fail)
    UI-->>User: Final interview result

    HR->>BE: POST /api/employees + PUT hired-link
    BE->>BE: status = registered
    UI->>UI: _step = 8

    HR->>BE: POST send-hire-email (credentials)
    UI-->>User: Hiring complete — link to LoginPage

    opt Account setup monitoring
        HR->>BE: PUT hr-account-setup-monitoring
        UI-->>User: Step 8 shows account ready message
    end
```

---

## 8. End-to-end user lifecycle (summary)

```mermaid
sequenceDiagram
    autonumber
    actor User as Applicant
    participant UI as RSP User UI
    participant BE as Backend API
    participant HR as HR Admin

    User->>UI: View vacancies (landing)
    UI->>BE: GET job-vacancies

    User->>UI: Apply → Step 1 submit + PDFs
    UI->>BE: POST applications + attachment-file

    User->>UI: Step 2 — wait
    loop Poll by-email
        UI->>BE: GET by-email
    end
    HR->>BE: document_approved

    User->>UI: Steps 3–6 exams
    UI->>BE: GET exam-questions, exam-time-limits
    User->>UI: Submit screening
    UI->>BE: POST exam-results
    HR->>BE: Grade BEI (if needed)

    User->>UI: Step 7 — result + final interview info
    HR->>BE: final-interview, outcome, hire, email

    User->>UI: Step 8 — registered / login
```

---

## Status reference (applicant-visible)

| Status | Applicant experience |
|--------|----------------------|
| `submitted` | Step 2: documents under HR review |
| `document_approved` | May continue to BEI / MCQ exams |
| `document_declined` | Cannot proceed; contact HR |
| `exam_taken` | Exam submitted; waiting for HR BEI grading |
| `passed` / `failed` | Screening result on Step 7 |
| `registered` | Hired; Step 8 / employee account linked |

---

## Key public API endpoints (no admin JWT)

| Action | Method | Path |
|--------|--------|------|
| List vacancies | GET | `/api/rsp/job-vacancies` |
| Email OTP config | GET | `/api/rsp/email-verification/config` |
| Send OTP | POST | `/api/rsp/email-verification/send` |
| Verify OTP | POST | `/api/rsp/email-verification/verify` |
| Create application | POST | `/api/rsp/applications` |
| Track by email | GET | `/api/rsp/applications/by-email?email=` |
| Upload document PDF | POST | `/api/rsp/applications/:id/attachment-file?kind=` |
| Exam questions | GET | `/api/rsp/exam-questions/:type` (`bei`, `general`, `math`, `general_info`) |
| Exam time limits | GET | `/api/rsp/exam-time-limits` |
| Submit screening | POST | `/api/rsp/applications/exam-results` |

Admin-only actions (shown as external messages in diagrams): `PUT …/status`, BEI grading, final interview, hire link, hire email.

---

## Visual diagram

Rendered overview PNG:

`docs/rsp-user-sequence-diagram.png`

(Re-export Mermaid blocks via [mermaid.live](https://mermaid.live) for SVG/PDF.)
