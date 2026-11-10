"""Insert the remaining November 2026 screens into the Chapter IV-only file.

Replaces the login image and the review figure, then adds the screens that
were still missing. Does not restore archiving and does not add Chapter V.
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

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(ROOT, "UNITY_PILLAR_Docutracker_Chapter4_Screens_Only.docx")
TEMP = r"c:\Users\danza\AppData\Local\Temp\cursor\screenshots"
SHOTS = os.path.join(ROOT, "frontend", "test", "docutracker", "acceptance_screenshots")
FIG_WIDTH = Inches(4.98)

COPIES = {
    "00-login.png": "00-login.png",
    "emp-02-docutracker-required.png": "41-employee-required-actions.png",
    "emp-07-more-actions.png": "29-employee-review-actions.png",
    "emp-08-sign-and-approve.png": "30-sign-and-approve-dialog.png",
    "emp-09-return-dialog.png": "31-return-dialog.png",
    "emp-10-reject-dialog.png": "32-reject-dialog.png",
    "emp-12-released-and-awaiting-list.png": "33-list-released-awaiting.png",
    "emp-13-released-detail.png": "34-released-detail.png",
    "emp-14-awaiting-release.png": "35-awaiting-release.png",
    "admin-01-workflow-catalog-memo.png": "36-workflow-catalog-memo.png",
    "admin-02-memo-workflow-editor.png": "37-memo-workflow-editor.png",
    "admin-03-memo-workflow-steps.png": "38-memo-workflow-steps.png",
    "admin-05-effective-access-preview.png": "39-effective-access-preview.png",
}


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
    created.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY if text and not bold else paragraph.alignment
    return created


def main() -> None:
    os.makedirs(SHOTS, exist_ok=True)
    for src_name, dest_name in COPIES.items():
        src = os.path.join(TEMP, src_name)
        dest = os.path.join(SHOTS, dest_name)
        if not os.path.isfile(src):
            raise FileNotFoundError(src)
        shutil.copy2(src, dest)

    doc = Document(DOC)
    paragraphs = doc.paragraphs
    set_picture(paragraphs[14], os.path.join(SHOTS, "00-login.png"))
    set_picture(paragraphs[44], os.path.join(SHOTS, "29-employee-review-actions.png"))
    set_desc(
        paragraphs[47],
        "Figure 26 shows Purchase Test 1 while it is the current reviewer's turn. "
        "The purchase request is on the final step and is past its deadline. "
        "The first step was approved by Dann Zapitan, and the current assignee is Tope Zapitan. "
        "Approve and Complete is available. More opens Download Attachment, Return to Previous Step, "
        "and Reject and Stop. Those dialogs were opened and cancelled, and the document stayed overdue.",
    )

    extras = [
        (
            "4.2.21 Signature Confirmation",
            "Figure 40. Sign and Approve Dialog",
            "Figure 40 shows the signature dialog that opens before Approve and Complete when the step requires a signature. The Draw tab is selected and the canvas is empty. Cancel closed the dialog. No stroke was saved, and the document was not approved.",
            "30-sign-and-approve-dialog.png",
        ),
        (
            "4.2.22 Return to the Previous Step",
            "Figure 41. Return to Previous Step Dialog",
            "Figure 41 shows the return dialog. The previous step's reviewer becomes responsible, the content stays read-only, and no correction task is created for the author. A reason is optional. Cancel closed the dialog, and the document was not returned.",
            "31-return-dialog.png",
        ),
        (
            "4.2.23 Reject and Stop",
            "Figure 42. Reject Document Dialog",
            "Figure 42 shows the reject dialog. Rejecting stops the workflow, and a reason is required. No reason was entered. Cancel closed the dialog, and the document was not rejected.",
            "32-reject-dialog.png",
        ),
        (
            "4.2.24 Released Document",
            "Figure 43. Released Memorandum",
            "Figure 43 shows UT-EMP-RELEASED-DEMO after release. The screen states that the released document is finalized and read-only. The current step is Released, there is no active assignee, and this employee account has no release control.",
            "34-released-detail.png",
        ),
        (
            "4.2.25 Document Awaiting Release",
            "Figure 44. Memorandum Awaiting Release",
            "Figure 44 shows UT-HR-AWAITING-RELEASE after approval and before release. The status is Approved, Awaiting release. The current step is Approval complete, and there is no active assignee. The employee account cannot release the document, and release was not confirmed.",
            "35-awaiting-release.png",
        ),
        (
            "4.2.26 Released and Awaiting Release in the Document List",
            "Figure 45. Document List with Released and Awaiting Release",
            "Figure 45 shows the employee document list. A released memorandum and a memorandum awaiting release appear with overdue documents that are still in review. Completed records stay in this list.",
            "33-list-released-awaiting.png",
        ),
        (
            "4.2.27 Shared Approval Workflows",
            "Figure 46. Approval Workflow Catalog",
            "Figure 46 shows the shared approval workflows. Department - Final HR is system-managed and synced from DTR. Memo version 18 has three steps: Department Head, Mayor's Office, and Mayor. Purchase Request version 3 has a first step and a final step. No workflow was created.",
            "36-workflow-catalog-memo.png",
        ),
        (
            "4.2.28 Memorandum Workflow Configuration",
            "Figure 47. Memorandum Workflow Editor",
            "Figure 47 shows Memo workflow version 18. The default deadline is 24 hours, and release after final approval is required. Step 1 is Department Head, with a signature required and Dann Zapitan as the primary assignee. Allowed actions include approve and continue, reject and stop, return to previous step, and forward without approval. Steps 2 and 3 are Mayor's Office and Mayor. The workflow was not published.",
            "37-memo-workflow-editor.png",
        ),
        (
            "4.2.29 Effective Access Preview",
            "Figure 48. Effective Access Preview for One Employee",
            "Figure 48 shows the read-only effective access preview for Dann Zapitan on all document types. View and download depend on the person's relationship to the document. Create draft is blocked by the employee role rule. Save changes was not used.",
            "39-effective-access-preview.png",
        ),
        (
            "4.2.30 Employee Required Actions",
            "Figure 49. Employee Required Actions",
            "Figure 49 shows the required-actions queue for the employee account. Overdue DocuTracker documents assigned for review are listed separately from the administrator queue.",
            "41-employee-required-actions.png",
        ),
    ]

    anchor = next(
        para for para in doc.paragraphs if para.text.strip().startswith("4.3 Testing")
    )
    predecessor = None
    for para in doc.paragraphs:
        if para._p is anchor._p:
            break
        predecessor = para
    if predecessor is None:
        raise RuntimeError("Section 4.3 has no preceding paragraph")

    last = predecessor
    for heading, caption, desc, image in extras:
        h = insert_after(last, heading, bold=True)
        h.alignment = WD_ALIGN_PARAGRAPH.LEFT
        ip = insert_after(h, "")
        set_picture(ip, os.path.join(SHOTS, image))
        c = insert_after(ip, caption, bold=True)
        c.alignment = WD_ALIGN_PARAGRAPH.LEFT
        d = insert_after(c, desc)
        last = d

    texts = [p.text.strip() for p in doc.paragraphs]
    joined = "\n".join(texts)
    if "Archiv" in joined or any(t.startswith("CHAPTER V") or t.startswith("CHAPTER I ") for t in texts):
        raise RuntimeError("Unexpected chapter or archiving text")
    drawings = sum(1 for p in doc.paragraphs if p._element.xpath(".//w:drawing"))
    doc.save(DOC)
    print("DRAWINGS", drawings)
    print("BYTES", os.path.getsize(DOC))


if __name__ == "__main__":
    main()
