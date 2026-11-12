from docx import Document
from docx.oxml.ns import qn
from docx.text.paragraph import Paragraph
from docx.table import Table
import hashlib

doc = Document(r"c:\Users\danza\Downloads\MANUSCRIPT-REVISION_SYSIGNITE-Final2 (1).docx")

rid_map = {}
for rel in doc.part.rels.values():
    if "image" in rel.reltype:
        blob = rel.target_part.blob
        rid_map[rel.rId] = (
            hashlib.md5(blob).hexdigest(),
            rel.target_ref,
            len(blob),
        )

target = "b440ab470efdd54d424ae530da5646a9"


def iter_block_items(parent):
    for child in parent.element.body.iterchildren():
        if child.tag == qn("w:p"):
            yield Paragraph(child, parent)
        elif child.tag == qn("w:tbl"):
            yield Table(child, parent)


recent_text = []
for block in iter_block_items(doc):
    if isinstance(block, Paragraph):
        t = (block.text or "").strip()
        if t:
            recent_text.append(t)
            recent_text = recent_text[-8:]
        for blip in block._p.xpath('.//*[local-name()="blip"]'):
            embed = blip.get(qn("r:embed"))
            if embed in rid_map and rid_map[embed][0] == target:
                print("DUP IMAGE near:")
                for x in recent_text[-6:]:
                    print(" ", x[:200])
                print(" ->", rid_map[embed][1], embed)
                print()
    else:
        for row in block.rows:
            for cell in row.cells:
                for p in cell.paragraphs:
                    for blip in p._p.xpath('.//*[local-name()="blip"]'):
                        embed = blip.get(qn("r:embed"))
                        if embed in rid_map and rid_map[embed][0] == target:
                            print(
                                "DUP in table near",
                                (p.text or "")[:80],
                                rid_map[embed][1],
                            )
