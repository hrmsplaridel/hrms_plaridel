# DTR Assistant — Intent Evaluation Harness

This measures how accurately the chatbot routes a message to the right intent,
using the deterministic layer (`scoreEmployeeAssistantIntent`: rules + fuzzy
matcher). That layer runs *before* any LLM call, so almost every
"the bot misunderstood me" complaint originates there — this is the number to
track across commits.

## Commands

```bash
npm run eval:intents              # full report (text)
npm run eval:intents -- --json    # machine-readable JSON
npm run eval:intents -- --failures
npm run eval:intents -- --filter=dtr
```

Exit code is `0` only when every golden case passes, so you can wire it into
CI / a pre-commit check.

## Reading the report

- **Overall accuracy** — the headline number. Track it per commit.
- **By language** — surfaces Tagalog/Bisaya/English gaps (your fuzzy profiles
  are English-heavy, so watch the `tl` / `bisaya` rows).
- **By decision source** — how the bot *decided*. `rules_fuzzy` and `rules` are
  the precise path; `fuzzy_override` is where the fuzzy matcher overruled a
  rule (a frequent source of bugs); `unclear`/`fuzzy` is where rules found
  nothing and the fuzzy matcher guessed.
- **Per intent** — worst intents first, so you know exactly where to focus.

## The golden set (`eval-intents.data.js`)

Each entry is `[message, expectedIntent, language]`.

- `expectedIntent = null` means **out-of-domain** — the bot must *not* route it
  to a real intent. (This is how you catch "what is the capital of France" →
  `locator_types` leaks.)
- `language` is `'en' | 'tl' | 'bisaya' | 'mix'`, optional but useful for
  per-language accuracy.

Keep it balanced: a few cases per intent across all three languages.

## Closing the loop with feedback

```bash
npm run eval:export-feedback      # dumps recent thumbs-down rows
npm run eval:export-feedback -- --limit 100
npm run eval:export-feedback -- --rating up
```

This prints each thumbs-down with the classified intent, the assistant's reply,
and the user's comment. **Limitation:** the `dtr_assistant_feedback` table does
not store the original user message, so each row needs a human to reconstruct
the phrasing before adding it to the golden set.

Workflow:
1. `npm run eval:export-feedback`
2. For each row, reconstruct the user's original phrasing and append a
   `[message, expectedIntent, language]` entry to `eval-intents.data.js`.
3. `npm run eval:intents` — watch the number move.

## Baseline (first run, 2026-06-20)

- Overall: **89.9%** (71/79) on 79 golden cases.
- Weakest spots: `fuzzy_override` source (58%), out-of-domain detection,
  `dtr_missing_log_reason`, `pending_leave_requests`, `locator_approval_tracker`.

These are the candidates for the next workstream (improving accuracy), which
the harness now makes measurable.
