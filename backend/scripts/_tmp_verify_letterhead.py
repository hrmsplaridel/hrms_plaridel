import hashlib
from pathlib import Path

root = Path(r"c:\Users\danza\hrms_plaridel\backend\scripts")
files = {
    "migration": root / "migrations/docutracker/migrate-docutracker-memo-letterhead-v1.sql",
    "init": root / "init-schema.sql",
    "rollup": root / "migrations/docutracker/docutracker-install-post-production-hardening.sql",
}
start = "CREATE TABLE IF NOT EXISTS docutracker_letterheads"
end = "WHERE docutracker_letterheads.source_name = 'HR_A4.pdf';"
for name, path in files.items():
    text = path.read_text(encoding="utf-8")
    count = text.count(start)
    a = text.find(start)
    b = text.find(end, a)
    block = text[a : b + len(end)].replace("\r\n", "\n")
    print(
        name,
        "count",
        count,
        "bytes",
        len(block.encode()),
        "sha256",
        hashlib.sha256(block.encode()).hexdigest(),
    )
