# HRMS Plaridel

Flutter frontend (`frontend/`, web/desktop/mobile) + Node/Express/PostgreSQL API (`backend/`).
Also follow `.agents/rules/tdd-and-scope.md` (tests first, requested scope only).

## Rules
Use skills: lean-tokens, hrms-ui, hrms-workflows, hrms-security, hrms-pagination, hrms-bug-hunting, hrms-data-optimization, hrms-refactoring, hrms-structure.

## Commands
- Frontend lint/typecheck: `cd frontend && flutter analyze` (or a path: `flutter analyze lib/features/<f>`)
- Frontend tests: `cd frontend && flutter test test/<path>` (full: `flutter test`)
- Backend has no linter/typechecker; syntax check: `node --check <file>.js`
- Backend tests: `cd backend && node --test test/<name>.test.js`
- Backend module suites: `npm run test:leave-management | test:locator-management | test:dtr-management | test:print-layout | test:department-management | test:position-management | test:dtr-assistant`
- Backend dev server: `cd backend && npm run dev`; preflight: `npm run preflight`

## Don'ts
- Never read or print `.env` files or credentials.
- No migrations or DB writes against production without explicit approval.
