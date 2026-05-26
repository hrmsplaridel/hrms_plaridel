# Philippines address data (PSGC)

Province → City/Municipality → Barangay dropdowns use files in this folder.

- `index.json` — province names and city lists (loaded at app startup)
- `provinces/<slug>.json` — barangays per city (loaded when user picks a province)

## Regenerate data

```bash
node backend/scripts/build-ph-psgc-assets.js
```

Source: [jgngo/psgc-data](https://github.com/jgngo/psgc-data) (Philippine Standard Geographic Code).
