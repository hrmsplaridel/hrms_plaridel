# DTR Assistant LLM Plan

## Goal

Build a scoped chatbot assistant for the HRMS DTR area. The assistant will answer questions about only:

- DTR and attendance
- Leave requests and leave balances
- Locator slips, pass slips, official business, and work-from-home records

The assistant should support both employee and admin/HR use cases, but with different permission modes. It must not become a general HRMS chatbot in the first version.

## Core Decision

Use the existing Node/Express backend for the LLM integration.

Do not add Python for the MVP. The backend already owns authentication, permissions, routes, database access, and an existing Ollama-based DocuTracker AI summary service. Keeping the DTR assistant in Node avoids running and securing a second service.

Python can be considered later only for heavier AI workflows such as OCR, document parsing, embeddings, or batch analysis.

## LLM Provider Strategy

Do not build an LLM from scratch.

Use a provider abstraction so the app can start with Ollama and optionally switch to a cloud provider later.

Recommended MVP provider:

- Ollama for local/private deployment

Future provider option:

- OpenAI or another cloud LLM provider for faster and higher-quality responses

Environment configuration:

```env
LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://127.0.0.1:11434
OLLAMA_MODEL=qwen2.5:7b

# Future cloud option
OPENAI_API_KEY=
OPENAI_MODEL=
```

For faster local testing, smaller Ollama models can be used:

- `llama3.2:3b`
- `qwen2.5:3b`
- `gemma2:2b`

If answer quality is weak, try stronger models:

- `qwen2.5:7b`
- `llama3.1:8b`

## Important Safety Rule

The LLM must not query the database directly.

The backend must:

1. Authenticate the user.
2. Determine the permission mode.
3. Load only allowed DTR, leave, and locator data.
4. Build a controlled prompt.
5. Send the prompt and safe context to the LLM.
6. Store audit records.
7. Return the answer.

The LLM explains the data. It does not decide who can see data.

## Permission Modes

Use one chatbot engine with multiple permission modes.

### Employee Mode

Employees can ask only about their own records.

Example questions:

- Why am I late today?
- Do I have missing logs this week?
- How many leave credits do I have?
- What is the status of my leave request?
- Was my locator slip approved?
- Why was this day marked absent, on leave, or on field?

### Admin/HR Mode

Admin/HR users can ask operational questions based on their role and scope.

Example questions:

- Who has missing logs today?
- Show employees with pending leave this week.
- Which locator slips are still pending?
- Who has repeated lateness this month?
- Summarize DTR issues for this department this week.

Admin/HR mode should be added after the employee MVP is stable.

## Backend Folder Structure

```txt
backend/src/
  routes/
    dtrAssistant.js

  services/
    llm/
      llmClient.js
      llmConfig.js
      llmErrors.js
      ollamaProvider.js
      openAiProvider.js

    dtrAssistant/
      dtrAssistantService.js
      dtrAssistantPrompt.js
      dtrAssistantContextService.js
      dtrAssistantDataService.js
      dtrAssistantPermissionService.js
      dtrAssistantAuditService.js

  utils/
    dateRangeParser.js
```

### File Responsibilities

`backend/src/routes/dtrAssistant.js`

- Defines assistant API routes.
- Applies authentication middleware.
- Passes the request to the assistant service.

`backend/src/services/llm/llmClient.js`

- Shared LLM entry point.
- Selects provider based on `LLM_PROVIDER`.
- Normalizes provider responses and errors.

`backend/src/services/llm/llmConfig.js`

- Reads LLM provider settings from environment variables.

`backend/src/services/llm/llmErrors.js`

- Defines provider unavailable, model unavailable, timeout, and malformed response errors.

`backend/src/services/llm/ollamaProvider.js`

- Calls Ollama `/api/chat`.
- Supports timeouts and model-not-found errors.

`backend/src/services/llm/openAiProvider.js`

- Placeholder for future cloud provider support.
- Should not be required for MVP.

`backend/src/services/dtrAssistant/dtrAssistantService.js`

- Main orchestrator.
- Receives the user message.
- Resolves user scope.
- Loads safe context.
- Builds prompt.
- Calls the LLM.
- Stores audit logs.

`backend/src/services/dtrAssistant/dtrAssistantPrompt.js`

- Contains system prompt and prompt formatting.
- Forces the assistant to answer only from provided data.

`backend/src/services/dtrAssistant/dtrAssistantContextService.js`

- Classifies what the user is asking about.
- Extracts date ranges such as today, yesterday, this week, this month, or specific dates.

`backend/src/services/dtrAssistant/dtrAssistantDataService.js`

- Contains safe SQL queries for DTR, leave, and locator records.
- Does not expose arbitrary SQL to the LLM.

`backend/src/services/dtrAssistant/dtrAssistantPermissionService.js`

- Determines whether the request is employee self-service, admin department scope, or admin all-records scope.

`backend/src/services/dtrAssistant/dtrAssistantAuditService.js`

- Stores assistant messages, runs, provider, model, and metadata.

`backend/src/utils/dateRangeParser.js`

- Parses common date phrases into concrete date ranges before querying.

## Backend API Plan

MVP endpoint:

```txt
POST /api/dtr-assistant/chat
```

Example request:

```json
{
  "message": "Why am I marked late yesterday?",
  "threadId": null,
  "context": {
    "mode": "employee"
  }
}
```

Example response:

```json
{
  "threadId": "uuid",
  "message": {
    "role": "assistant",
    "content": "You were marked late because your time-in was 8:17 AM and your shift starts at 8:00 AM.",
    "createdAt": "2026-06-12T08:00:00.000Z"
  },
  "sources": {
    "dtrSummaryIds": ["uuid"],
    "leaveRequestIds": [],
    "locatorSlipIds": []
  }
}
```

Optional history endpoint:

```txt
GET /api/dtr-assistant/threads/:id/messages
```

## Data Access Scope

The assistant can read only approved tables and only through backend service functions.

Allowed DTR-related data:

- `dtr_daily_summary`
- `dtr_logs`
- `biometric_attendance_logs`
- `shifts`
- `attendance_policies`
- `policy_assignments`

Allowed leave data:

- `leave_requests`
- `leave_balances`
- `leave_types`
- `leave_request_history`
- `leave_balance_ledger`

Allowed locator data:

- `locator_slips`
- `locator_request_types`

Related employee identity fields may be loaded only when required by the current permission mode.

## Prompt Rules

The system prompt should include:

```txt
You are an HRMS DTR assistant.
You only answer questions about DTR, attendance, leave, and locator records.
Use only the provided data.
If the provided data is not enough, say you cannot determine the answer.
Do not invent attendance logs, leave balances, locator approval status, or policy details.
Do not answer about recruitment, payroll, DocuTracker, user administration, or unrelated HRMS modules.
Do not reveal data the current user is not allowed to access.
Keep answers concise and practical.
```

## Database Migration

Place the migration under the DTR migration folder:

```txt
backend/scripts/migrations/dtr/create-dtr-assistant-chat-tables.sql
```

Suggested tables:

```txt
dtr_assistant_threads
  id
  user_id
  mode
  title
  created_at
  updated_at

dtr_assistant_messages
  id
  thread_id
  user_id
  role
  content
  metadata_json
  created_at

dtr_assistant_runs
  id
  thread_id
  user_id
  provider
  model
  permission_mode
  prompt_type
  input_metadata_json
  output_metadata_json
  created_at
```

## Frontend Folder Structure

```txt
frontend/lib/features/dtr/assistant/
  data/
    dtr_assistant_api.dart
    dtr_assistant_message_model.dart
    dtr_assistant_thread_model.dart

  presentation/
    pages/
      employee_dtr_assistant_page.dart
      admin_dtr_assistant_page.dart

    widgets/
      dtr_assistant_message_bubble.dart
      dtr_assistant_prompt_chips.dart
      dtr_assistant_input_bar.dart
      dtr_assistant_loading_message.dart
```

## Frontend UX Plan

Employee entry point:

- Add an "Ask Assistant" action inside the employee DTR area.
- Show suggested prompts for common employee questions.

Admin entry point:

- Add an "Ask Assistant" action inside the admin DTR dashboard after the employee MVP is stable.
- Show admin-only suggested prompts.

Suggested employee prompts:

- Why am I late today?
- Do I have missing logs this week?
- What is my leave balance?
- What is the status of my latest leave request?
- Was my locator slip approved?

Suggested admin prompts:

- Who has missing logs today?
- Show pending leave requests this week.
- Which locator slips are pending?
- Summarize DTR issues this week.

## MVP Scope

First implementation should include:

1. Shared LLM provider layer with Ollama support.
2. Employee DTR assistant endpoint.
3. Employee-safe DTR, leave, and locator data loaders.
4. Prompt builder.
5. Chat audit tables.
6. Flutter employee assistant page.
7. Basic tests with mocked LLM responses.

Admin mode should come after employee mode.

## Rollout Order

1. Add database migration for assistant threads, messages, and runs.
2. Add LLM provider layer using Ollama.
3. Add DTR assistant services.
4. Add employee chatbot API route.
5. Add backend tests with mocked LLM provider.
6. Add Flutter employee chatbot page.
7. Add admin permission mode and admin data loaders.
8. Add Flutter admin chatbot page.
9. Add optional OpenAI/cloud provider support.

## Performance Notes

Ollama can be slow when:

- The model is large.
- The machine has no GPU.
- The first request has to load the model.
- Multiple users ask questions at the same time.
- The prompt includes too much data.

To keep responses fast:

- Send only the relevant DTR, leave, and locator records.
- Use backend logic for exact calculations.
- Use the LLM mainly to explain results.
- Keep prompts short.
- Cache or reuse recent context when possible.
- Consider streaming responses later.

## Testing Plan

Backend tests should cover:

- Employee can only access own records.
- Admin cannot access broader data without the correct role.
- LLM unavailable returns a useful error.
- Model unavailable returns a useful error.
- Assistant refuses unrelated modules.
- Assistant does not answer when data is missing.
- Date ranges resolve correctly.
- Audit records are written.

Frontend tests or manual checks should cover:

- Loading state.
- Error state.
- Empty thread state.
- Suggested prompts.
- Long assistant response layout.
- Mobile and desktop layouts.

## Final Recommendation

Start with an employee-only DTR assistant powered by Ollama, but design the LLM layer so a cloud provider can be added later. After the employee assistant is stable and audited, expand the same engine to admin/HR mode with stricter permission checks and broader data loaders.
