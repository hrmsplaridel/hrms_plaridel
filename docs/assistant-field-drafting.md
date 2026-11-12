# Shared Leave and Locator drafting

The assistant distinguishes field explanations, personal drafts, and rewrites. This behavior uses the live Leave/Locator type and field definitions, including writable custom fields. It is not specific to Wellness Leave.

An example conversation:

1. Ask about the reason field for Wellness Leave, or the reason/destination/custom field for a Locator type.
2. Say **“tabangi ko paghimo sa sentence”**. If details are missing, the assistant asks one question instead of repeating field instructions and character limits.
3. Supply your actual details, such as **“Para makapahulay.”** or **“I will submit payroll documents at the Municipal Treasury Office.”**
4. Use **Mas pormal**, **Mas mubo**, or the translation suggestion to rewrite those same facts.
5. **Copy sentence** copies only the proposed wording. When the relevant form field is open, **Use this suggestion** remains a separate explicit action. Drafting does not submit or approve a request.

The assistant retains field and draft context within the current user's conversation. A new request type, conversation, user, or unrelated record question must not reuse another draft's details. Active-field application also checks the form binding and unchanged field value.

Drafting follows the selected model profile in standalone chat, open forms, and custom text fields. Qwen uses local Ollama; Groq uses the configured Groq model. Selecting Groq requires both `DTR_ASSISTANT_ALLOW_EXTERNAL_LLM=true` and the current external-processing consent. A rejected or unavailable Groq answer uses the factual fallback; it does not silently switch to a different model. Successful drafts identify the actual provider/model, and fallbacks identify HRMS as their source.

Model requests use a JSON schema. Ollama drafting disables thinking; see its [structured outputs](https://docs.ollama.com/capabilities/structured-outputs) and [thinking controls](https://docs.ollama.com/capabilities/thinking). Groq GPT-OSS uses strict structured output, low reasoning effort, and a minimum completion budget of 768 tokens so reasoning does not exhaust the answer budget; reasoning is excluded from the returned text. See Groq's [structured outputs](https://console.groq.com/docs/structured-outputs) and [reasoning documentation](https://console.groq.com/docs/reasoning). The existing bounded drafting deadline remains in place.

External drafting sends the supplied facts, necessary field instructions/examples, requested language, and previous draft when rewriting. It does not load unrelated employee records into the prompt. The existing disclosure log records hashed user identity and data categories without employee text. Destination names, dates and negation remain subject to grounding checks. The vocabulary allows common English/Bisaya/Tagalog visit and rest variants; it is a conservative validator, not a complete semantic or translation verifier.

Generated wording is checked for the configured length, unsupported facts, missing substantive details, and changed negation. Invalid, incomplete, or unavailable model output uses a factual fallback. Destination fields preserve the supplied destination rather than adding a reason prefix. Examples remain examples and are not treated as the employee's personal facts. Automated grounding checks reduce unsupported output; employees should still review the wording.

Repeating a field label, such as “General Reason / Remarks para sa Wellness” or a configured custom field label, retains the same draft facts instead of routing to a status lookup. Changing type/field/form binding does not reuse the old facts. Visit-only details produce wording such as “Ang akong tuyo mao ang pagbisita sa Barangay Mohon.” This wording does not assert eligibility for Wellness Leave or invent a purpose for the visit.

Groq configuration for evaluation:

```dotenv
GROQ_MODEL=openai/gpt-oss-120b
DTR_ASSISTANT_ALLOW_EXTERNAL_LLM=true
DTR_ASSISTANT_ALLOW_DIRECT_LLM=false
```

Configure `GROQ_API_KEY` privately and retain `GROQ_BASE_URL=https://api.groq.com/openai/v1`. The default model is now GPT-OSS 120B; an explicit model selection in the environment still takes precedence. Groq documents available [production models](https://console.groq.com/docs/models) and the old Llama defaults' [retirement](https://console.groq.com/docs/deprecations). Fresh example environments leave external processing disabled until configured.

On November 11, 2026, four identical synthetic scenarios were checked against both providers: a Bisaya Barangay visit, formal rest wording, an English Locator purpose, and a custom visit activity. Qwen `qwen3:4b` took approximately 4.5–6.0 seconds per scenario on the local machine; Groq `openai/gpt-oss-120b` took approximately 0.95–2.49 seconds. Groq produced the natural Barangay Mohon rewrite, but its rest wording still required the factual fallback. Qwen also used fallbacks, including two deadline timeouts. These eight requests establish connectivity and exercise the validation/fallback path; they do not establish general accuracy or production latency. No employee records were used.

Verification:

- `cd backend` then `npm run test:dtr-assistant`
- `cd frontend` then `flutter test test/dtr/assistant --concurrency=2`

The provider/routing update is backend-only and requires no database migration or additional frontend rebuild if the existing drafting controls are already deployed. Configure the server environment separately from the local environment. Restart the backend through its actual process manager; Ubuntu production uses `hrms-api` under systemd.
