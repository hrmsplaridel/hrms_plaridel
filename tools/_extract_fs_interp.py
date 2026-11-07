from docx import Document

doc = Document(r"c:\Users\danza\Downloads\MANUSCRIPT-REVISION_SYSIGNITE-Final2 (1).docx")
for i in range(573, 642):
    t = (doc.paragraphs[i].text or "").strip()
    if t:
        print(f"P{i}: {t}\n")

# Also dump table overall means more carefully
print("==== TABLE OVERALLS ====")
for ti in [6, 7, 8, 9, 10, 11, 12]:
    table = doc.tables[ti]
    print(f"\nTABLE {ti}")
    for row in table.rows:
        cells = [c.text.strip().replace("\n", " ") for c in row.cells]
        print(" | ".join(cells))
