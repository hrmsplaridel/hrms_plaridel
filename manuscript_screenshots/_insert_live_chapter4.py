"""Place the November 2026 live DocuTracker screenshots into Chapter IV.

Starts from the manuscript source and writes a new file. Does not edit Chapter V.
"""
from __future__ import annotations

import copy
import os
import shutil
from io import BytesIO

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.shared import Inches
from docx.text.paragraph import Paragraph
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = r"c:\Users\danza\Downloads\MANUSCRIPT-REVISION_SYSIGNITE-Final2.docx"
OUT = os.path.join(ROOT, "UNITY_PILLAR_Docutracker_Manuscript_Chapter4_Live_Screenshots.docx")
SHOTS = os.path.join(ROOT, "frontend", "test", "docutracker", "acceptance_screenshots")
OLD = os.path.join(HERE, "chapter4")
LEGACY = HERE
FIG_WIDTH = Inches(4.98)


def shot(*names: str) -> str:
    for name in names:
        for base in (SHOTS, OLD, LEGACY):
            path = os.path.join(base, name)
            if os.path.isfile(path) and os.path.getsize(path) > 8000:
                return path
    raise FileNotFoundError(names[0])


def fit_png(path: str) -> BytesIO:
    im = Image.open(path).convert("RGB")
    im.thumbnail((1440, 900), Image.Resampling.LANCZOS)
    buf = BytesIO()
    im.save(buf, format="PNG", optimize=True)
    buf.seek(0)
    return buf


def clear_drawings(paragraph) -> None:
    for run in list(paragraph.runs):
        for drawing in run._element.xpath(".//w:drawing"):
            drawing.getparent().remove(drawing)


def set_picture(paragraph, image_path: str) -> None:
    clear_drawings(paragraph)
    if not paragraph.runs:
        paragraph.add_run()
    run = paragraph.runs[0]
    for extra in paragraph.runs[1:]:
        extra._element.getparent().remove(extra._element)
    run.text = ""
    run.add_picture(fit_png(image_path), width=FIG_WIDTH)
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER


def set_desc(paragraph, text: str) -> None:
    if paragraph.runs:
        paragraph.runs[0].text = text
        for run in paragraph.runs[1:]:
            run.text = ""
    else:
        paragraph.add_run(text)


def insert_after(paragraph, text: str = "", *, bold: bool = False) -> Paragraph:
    new_p = copy.deepcopy(paragraph._p)
    for child in list(new_p):
        tag = child.tag
        if tag == qn("w:r") or tag.endswith("}r"):
            new_p.remove(child)
    paragraph._p.addnext(new_p)
    created = Paragraph(new_p, paragraph._parent)
    run = created.add_run(text)
    run.bold = bold
    if paragraph.runs:
        font = paragraph.runs[0].font
        if font.name:
            run.font.name = font.name
        if font.size:
            run.font.size = font.size
    return created


def main() -> None:
    shutil.copy2(SRC, OUT)
    doc = Document(OUT)
    p = doc.paragraphs

    # Fixed image paragraphs in the source manuscript. Set these before any inserts.
    placements = [
        (428, shot("01_Login_Page.png"), None),
        (
            433,
            shot("01-dashboard-summary.png"),
            (
                436,
                "Figure 21 shows the administrator DocuTracker home after sign-in. "
                "The summary presents document volume, overdue and escalated counts, and recent activity.",
            ),
        ),
        (
            438,
            shot("employee_04_my_documents_dashboard.png", "employee_01_home.png"),
            (
                441,
                "Figure 22 shows the employee portal dashboard for Dann Zapitan. "
                "The DocuTracker card summarizes drafts, pending, in-review, overdue, and approved documents, along with recent DocuTracker activity.",
            ),
        ),
        (
            443,
            shot("03-create-draft-type-selection.png"),
            (
                446,
                "Figure 23 shows the Create Draft type picker. The available native types in this screen are Memorandum and Purchase Request. The draft was not created during this capture.",
            ),
        ),
        (
            448,
            shot("04-create-draft-details.png"),
            (
                451,
                "Figure 24 shows the draft details step, including the optional attachment field. Accepted attachment types are PDF, JPG, JPEG, and PNG, with a maximum size of 10 MB.",
            ),
        ),
        (
            453,
            shot("20-workflow-editor.png"),
            (
                456,
                "Figure 25 shows the Purchase Request workflow editor. Each step names a primary assignee and the allowed actions: approve and continue, forward, reject, and return.",
            ),
        ),
        (
            458,
            shot("11-memo-overdue-detail.png"),
            (
                461,
                "Figure 26 shows a submitted memorandum that is overdue at the Mayor step. The content is read-only for this administrator because the current reviewer is the Mayor's Office.",
            ),
        ),
        (
            463,
            shot("02c-documents-list-filters.png"),
            (
                466,
                "Figure 27 shows the document list used for status monitoring. Each row shows the document type, status, deadline, and current assignee.",
            ),
        ),
        (
            468,
            shot("17-notifications.png"),
            (
                471,
                "Figure 28 shows the notifications drawer. DocuTracker overdue notices identify documents that need admin intervention, including items that could not be auto-routed.",
            ),
        ),
        (
            473,
            shot("23b-role-permission-matrix.png"),
            (
                476,
                "Figure 29 shows the System Access role matrix. Granted and restricted capabilities are set by role. Administrator status does not by itself grant workflow approval.",
            ),
        ),
        (
            478,
            shot("02b-documents-empty-search.png"),
            (
                481,
                "Figure 30 shows document search. A search that matches no title, number, sender, or assignee returns an empty result and can be cleared without changing stored records.",
            ),
        ),
        (
            483,
            shot("13-routing-history.png"),
            (
                486,
                "Figure 31 shows the document activity history. The recorded event identifies the action, the user, and the date and time. History is written by the system.",
            ),
        ),
        (
            488,
            shot("10-required-actions.png"),
            (
                491,
                "Figure 32 shows the Required actions queue. Overdue DocuTracker items are listed for review, separate from source-module items such as DTR leave.",
            ),
        ),
        (
            496,
            shot("01-dashboard-summary.png"),
            (
                499,
                "Figure 34 shows the same administrator monitoring summary used for day-to-day transaction awareness: document volume, overdue and escalated counts, and recent activity. A separate printable report generator is not part of this screen.",
            ),
        ),
    ]

    for img_i, path, desc in placements:
        set_picture(p[img_i], path)
        if desc:
            set_desc(p[desc[0]], desc[1])

    # Figure 33 has a caption and no image paragraph in the source.
    heading33 = p[492]
    img33 = insert_after(heading33, "")
    set_picture(img33, shot("employee_06_document_detail.png"))
    for para in doc.paragraphs:
        if para.text.strip().startswith("Figure 33"):
            set_desc(
                para,
                "Figure 33. Released Document Remaining in the Document List",
            )
            if para.runs:
                para.runs[0].bold = True
            break
    for para in doc.paragraphs:
        if para.text.strip().startswith("Figure 33 is reserved"):
            set_desc(
                para,
                "Figure 33 shows a released memorandum still listed for the employee after workflow processing. "
                "DocuTracker does not use a separate archive screen; completed records stay in the document list.",
            )
            break

    extras = [
        (
            "4.2.16 Memorandum Document",
            "Figure 35. Memorandum Document, View Only",
            "Figure 35 shows an existing memorandum opened view-only. The official template includes Prepared by, Noted by, and Approved by. Approved by stays unassigned until a distinct Municipal Mayor signatory is configured.",
            shot("05-memorandum-editor.png"),
        ),
        (
            "4.2.17 Purchase Request Form",
            "Figure 36. Purchase Request Form",
            "Figure 36 shows a one-page purchase request in the document editor, including the item table and the Requested by and Approved by areas.",
            shot("06-purchase-request-one-page.png"),
        ),
        (
            "4.2.18 Official Signatories",
            "Figure 37. Memorandum Official Signatories",
            "Figure 37 shows the Official Signatories screen for memorandums. Prepared by, Noted by, and Approved by remain on automatic resolution until all three assignments are configured.",
            shot("28-official-signatories.png"),
        ),
        (
            "4.2.19 Escalation Rules",
            "Figure 38. Escalation Rules",
            "Figure 38 shows the escalation rules for Memorandum and Purchase Request. Each rule escalates to the supervisor after 60 minutes, for up to three levels, and notifies the sender.",
            shot("27-escalation-rules.png"),
        ),
        (
            "4.2.20 Configuration Audit Log",
            "Figure 39. Configuration Audit Log",
            "Figure 39 shows the configuration audit log for access-rule changes, including the actor and the time of each recorded change.",
            shot("26-governance-audit-log.png"),
        ),
        (
            "4.2.21 Employee Access Directory",
            "Figure 40. Employee Access Directory",
            "Figure 40 shows the employee directory used when reviewing per-employee access exceptions. No exception was changed during this capture.",
            shot("24b-employee-directory.png"),
        ),
    ]

    anchor = next(
        para for para in doc.paragraphs if para.text.strip().startswith("4.3 Testing")
    )
    # Insert before 4.3 by chaining after the paragraph that currently precedes it,
    # then re-finding is unnecessary because insert_after places the new paragraph
    # immediately after the anchor predecessor and before 4.3.
    last = anchor._p.getprevious()
    # Walk from the element before 4.3.
    predecessor = None
    for para in doc.paragraphs:
        if para._p is anchor._p:
            break
        predecessor = para
    if predecessor is None:
        raise RuntimeError("Chapter 4.3 has no preceding paragraph")
    last_para = predecessor
    for heading, caption, desc, image in extras:
        h = insert_after(last_para, heading, bold=True)
        ip = insert_after(h, "")
        set_picture(ip, image)
        c = insert_after(ip, caption, bold=True)
        d = insert_after(c, desc)
        last_para = d

    # Chapter V stays text-only. Confirm it still has no drawings.
    in_ch5 = False
    ch5_drawings = 0
    for para in doc.paragraphs:
        text = para.text.strip()
        if text.startswith("CHAPTER V"):
            in_ch5 = True
        elif text.startswith("REFERENCES"):
            in_ch5 = False
        if in_ch5 and para._element.xpath(".//w:drawing"):
            ch5_drawings += 1

    doc.save(OUT)
    print("OUT", OUT)
    print("CHAPTER5_DRAWINGS", ch5_drawings)
    print("BYTES", os.path.getsize(OUT))


if __name__ == "__main__":
    main()
