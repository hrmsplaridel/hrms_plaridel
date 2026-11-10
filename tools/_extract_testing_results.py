from docx import Document
from pathlib import Path

doc_path = Path(r"c:\Users\danza\Downloads\MANUSCRIPT-REVISION_SYSIGNITE-Final2 (1).docx")
doc = Document(str(doc_path))

keywords = [
    "functional suitability",
    "usability",
    "performance efficiency",
    "pilot",
    "strongly agree",
    "pooled mean",
    "iso",
    "testing and results",
    "evaluation",
]

paras = []
for i, p in enumerate(doc.paragraphs):
    t = (p.text or "").strip()
    if not t:
        continue
    low = t.lower()
    if any(k in low for k in keywords):
        paras.append((i, t))

print(f"matched paragraphs: {len(paras)}")
for i, t in paras:
    print(f"\n--- P{i} ---")
    print(t[:1200])

print("\n\n===== TABLES =====")
for ti, table in enumerate(doc.tables):
    rows_preview = []
    hit = False
    for row in table.rows[:8]:
        cells = [c.text.strip().replace("\n", " ") for c in row.cells]
        joined = " | ".join(cells)
        rows_preview.append(joined)
        low = joined.lower()
        if any(k in low for k in keywords + ["mean", "sd", "criterion", "indicator"]):
            hit = True
    if hit:
        print(f"\n=== TABLE {ti} ===")
        for r in rows_preview:
            print(r[:300])
