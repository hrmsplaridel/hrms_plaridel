# Shared Leave and Locator drafting

The assistant distinguishes field explanations, personal drafts, and rewrites. This behavior uses the live Leave/Locator type and field definitions, including writable custom fields. It is not specific to Wellness Leave.

An example conversation:

1. Ask about the reason field for Wellness Leave, or the reason/destination/custom field for a Locator type.
2. Say **“tabangi ko paghimo sa sentence”**. If details are missing, the assistant asks one question instead of repeating field instructions and character limits.
3. Supply your actual details, such as **“Para makapahulay.”** or **“I will submit payroll documents at the Municipal Treasury Office.”**
4. Use **Mas pormal**, **Mas mubo**, or the translation suggestion to rewrite those same facts.
5. **Copy sentence** copies only the proposed wording. When the relevant form field is open, **Use this suggestion** remains a separate explicit action. Drafting does not submit or approve a request.

The assistant retains field and draft context within the current user's conversation. A new request type, conversation, user, or unrelated record question must not reuse another draft's details. Active-field application also checks the form binding and unchanged field value.

Model requests use a JSON schema and disable thinking for short drafting tasks. Ollama documents [structured outputs](https://docs.ollama.com/capabilities/structured-outputs) and [thinking controls](https://docs.ollama.com/capabilities/thinking). Other assistant calls keep their existing thinking settings. The existing bounded drafting deadline remains in place.

Generated wording is checked for the configured length, unsupported facts, missing substantive details, and changed negation. Invalid, incomplete, or unavailable model output uses a factual fallback. Destination fields preserve the supplied destination rather than adding a reason prefix. Examples remain examples and are not treated as the employee's personal facts. Automated grounding checks reduce unsupported output; employees should still review the wording.

Verification:

- `cd backend` then `npm run test:dtr-assistant`
- `cd frontend` then `flutter test test/dtr/assistant --concurrency=2`

Deploy the matching backend and rebuilt frontend. No database migration is required. Restart the backend through its actual process manager; Ubuntu production uses `hrms-api` under systemd.
