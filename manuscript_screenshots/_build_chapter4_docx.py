"""Insert DocuTracker screenshots into Chapter 4.2 without redesigning the manuscript."""
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
SRC = r"c:\Users\danza\Downloads\MANUSCRIPT-REVISION_SYSIGNITE-Final2.docx"
OUT = os.path.join(
    os.path.dirname(HERE),
    "UNITY_PILLAR_Docutracker_Manuscript_With_Feature_Screenshots.docx",
)
PH = os.path.join(HERE, "_placeholders")
FIG_WIDTH = Inches(4.98)


def pick(*names: str) -> str | None:
    for name in names:
        for base in (HERE, PH, os.path.join(HERE, "chapter4")):
            path = os.path.join(base, name)
            if os.path.isfile(path) and os.path.getsize(path) > 8000:
                return path
    return None


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


def set_picture(paragraph, image_path: str | None) -> bool:
    if not image_path:
        return False
    clear_drawings(paragraph)
    if not paragraph.runs:
        paragraph.add_run()
    run = paragraph.runs[0]
    for extra in paragraph.runs[1:]:
        extra._element.getparent().remove(extra._element)
    # clear leftover text
    run.text = ""
    run.add_picture(fit_png(image_path), width=FIG_WIDTH)
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    return True


def set_desc(paragraph, text: str) -> None:
    if paragraph.runs:
        paragraph.runs[0].text = text
        for r in paragraph.runs[1:]:
            r.text = ""
    else:
        paragraph.add_run(text)


def insert_after(paragraph, text: str = "", *, bold: bool = False) -> Paragraph:
    new_p = copy.deepcopy(paragraph._p)
    for child in list(new_p):
        tag = child.tag
        if tag == qn("w:r") or tag.endswith("}r"):
            new_p.remove(child)
    paragraph._p.addnext(new_p)
    p = Paragraph(new_p, paragraph._parent)
    run = p.add_run(text)
    run.bold = bold
    if paragraph.runs:
        font = paragraph.runs[0].font
        if font.name:
            run.font.name = font.name
        if font.size:
            run.font.size = font.size
    return p


def main() -> None:
    shutil.copy2(SRC, OUT)
    doc = Document(OUT)

    admin_n = 0
    employee_n = 0
    skipped: list[str] = []

    # Existing slots: (img_para, caption_para, desc_para, paths, optional_desc, role)
    # role: admin | employee | shared
    slots = [
        (
            428,
            429,
            431,
            ["01_Login_Page.png", "image22.jpeg"],
            None,
            "shared",
        ),
        (
            433,
            434,
            436,
            ["02_Admin_Dashboard.png", "image23.png", "20_Reports_or_Summary.png"],
            None,
            "admin",
        ),
        (
            443,
            444,
            446,
            [
                "employee_05_create_draft.png",
                "admin_04_create_draft.png",
                "04_Document_Registration.png",
                "image24.png",
            ],
            "Figure 23 shows the Create Draft document-type picker used when starting a Memo or Purchase Request in DocuTracker.",
            "shared",
        ),
        (
            448,
            449,
            451,
            [
                "employee_08_notifications.png",
                "employee_10_my_signatures.png",
                "admin_05_document_detail.png",
                "05_Document_Upload_Attachment.png",
                "07_Document_Details.png",
                "image25.png",
            ],
            None,
            "shared",
        ),
        (
            453,
            454,
            456,
            ["08_Document_Routing.png", "admin_06_workflow_progress.png", "image26.png"],
            None,
            "admin",
        ),
        (
            458,
            459,
            461,
            [
                "employee_08_notifications.png",
                "employee_10_my_signatures.png",
                "admin_05_document_detail.png",
                "10_Document_Status_Tracking.png",
                "07_Document_Details.png",
                "image27.png",
            ],
            None,
            "shared",
        ),
        (
            463,
            464,
            466,
            [
                "employee_08_notifications.png",
                "admin_06_workflow_progress.png",
                "10_Document_Status_Tracking.png",
                "image28.png",
            ],
            None,
            "shared",
        ),
        (
            468,
            469,
            471,
            ["admin_08_notifications.png", "19_Notifications.png"],
            None,
            "shared",
        ),
        (
            473,
            474,
            476,
            ["17_User_Management.png", "admin_11_system_access.png", "image29.png"],
            None,
            "admin",
        ),
        (
            478,
            479,
            481,
            [
                "employee_02_documents.png",
                "employee_07_workflow.png",
                "admin_02_documents.png",
                "06_Document_List.png",
                "12_Search_and_Filter.png",
                "image30.png",
            ],
            None,
            "shared",
        ),
        (
            483,
            484,
            486,
            [
                "admin_07_activity_trail.png",
                "11_Document_History_Timeline.png",
                "image31.png",
            ],
            None,
            "shared",
        ),
        (
            488,
            489,
            491,
            [
                "employee_03_required_actions.png",
                "employee_02_documents.png",
                "admin_03_required_actions.png",
                "13_Incoming_Documents.png",
                "02_Admin_Dashboard.png",
                "image32.png",
            ],
            "Figure 32 shows overdue DocuTracker items highlighted for follow-up in Required actions and on the document overview.",
            "shared",
        ),
        (
            496,
            497,
            499,
            ["admin_01_dashboard.png", "02_Admin_Dashboard.png", "20_Reports_or_Summary.png", "image33.png"],
            "Figure 34 shows the DocuTracker monitoring summary with document volume, overdue and escalated counts, and recent activity. Separate printable report generators beyond this dashboard summary are not claimed here.",
            "admin",
        ),
    ]

    for img_i, cap_i, desc_i, names, new_desc, role in slots:
        path = pick(*names)
        ok = set_picture(doc.paragraphs[img_i], path)
        if ok:
            if role == "admin":
                admin_n += 1
            elif role == "employee":
                employee_n += 1
            else:
                # shared counts toward both sides for the report request
                admin_n += 1
                employee_n += 1
            if new_desc:
                set_desc(doc.paragraphs[desc_i], new_desc)
        else:
            skipped.append(doc.paragraphs[cap_i].text)

    # Figure 22 DocuTrack Employee Dashboard — authenticated employee DocuTracker home
    emp_path = pick("employee_02_documents.png", "employee_01_home.png")
    prev22 = doc.paragraphs[438]
    has_img22 = any(r._element.xpath(".//a:blip") for r in prev22.runs)
    if emp_path:
        target = prev22 if (prev22.text.strip() == "" or has_img22) else insert_after(doc.paragraphs[437], "")
        if set_picture(target, emp_path):
            employee_n += 1
            if len(doc.paragraphs) > 441:
                set_desc(
                    doc.paragraphs[441],
                    "Figure 22 shows the employee DocuTracker home with Required actions, document list filters, My Signatures, and Create Draft for the signed-in employee account.",
                )
    else:
        skipped.append(
            "Figure 22 DocuTrack Employee Dashboard (authenticated employee session not available)"
        )

    # Figure 33 — completed/released records (no archive module in product)
    fig33_heading = doc.paragraphs[492]  # 4.2.14
    if fig33_heading.runs:
        fig33_heading.runs[0].text = "4.2.14 Completed and Released Document Records"
        for r in fig33_heading.runs[1:]:
            r.text = ""
    path33 = pick(
        "employee_08_notifications.png",
        "employee_10_my_signatures.png",
        "admin_05_document_detail.png",
        "07_Document_Details.png",
        "10_Document_Status_Tracking.png",
    )
    if path33:
        # Original template: heading, caption, desc — insert image after heading
        img33 = insert_after(fig33_heading, "")
        if set_picture(img33, path33):
            admin_n += 1
            employee_n += 1
        # After insert: 493 image, 494 caption, 495 desc
        if len(doc.paragraphs) > 494:
            set_desc(doc.paragraphs[494], "Figure 33. Completed and Released Document Record")
            if doc.paragraphs[494].runs:
                doc.paragraphs[494].runs[0].bold = True
        if len(doc.paragraphs) > 495:
            set_desc(
                doc.paragraphs[495],
                "Figure 33 shows a completed and released DocuTracker document record that remains "
                "available after workflow processing. DocuTrack does not implement a separate "
                "archive or retention module; completed records stay in the document list and detail views.",
            )
    else:
        skipped.append("Figure 33 Completed and Released Document Record")

    # Extra consolidated figures before 4.3
    insert_at = next(
        i
        for i, p in enumerate(doc.paragraphs)
        if p.text.strip().startswith("4.3 Testing")
    )
    last = doc.paragraphs[insert_at - 1]

    extras = [
        (
            "4.2.16 Required Actions Queue",
            "Figure 35. DocuTrack Required Actions Interface",
            "Figure 35 shows the Required actions queue with overdue review items for the signed-in employee, including search and module filters.",
            pick(
                "employee_03_required_actions.png",
                "employee_02_documents.png",
                "admin_03_required_actions.png",
                "13_Incoming_Documents.png",
            ),
            "shared",
        ),
        (
            "4.2.17 Document Detail and Release Status",
            "Figure 36. Document Detail and Release Status Interface",
            "Figure 36 shows employee document detail with approved/awaiting-release status, workflow steps, and related metadata.",
            pick(
                "employee_08_notifications.png",
                "employee_10_my_signatures.png",
                "admin_05_document_detail.png",
                "07_Document_Details.png",
            ),
            "shared",
        ),
        (
            "4.2.18 Memo Assignment and Signatories",
            "Figure 37. Memo Assignment and Signatories Interface",
            "Figure 37 shows memo assignment and signatory information used during document preparation and approval.",
            pick("09_Document_Assignment.png", "employee_05_create_draft.png"),
            "shared",
        ),
    ]

    for heading, caption, desc, img, role in extras:
        if not img:
            skipped.append(caption)
            continue
        h = insert_after(last, heading, bold=True)
        ip = insert_after(h, "")
        set_picture(ip, img)
        c = insert_after(ip, caption)
        if c.runs:
            c.runs[0].bold = True
        d = insert_after(c, desc)
        last = d
        if role == "admin":
            admin_n += 1
        elif role == "employee":
            employee_n += 1
        else:
            admin_n += 1
            employee_n += 1

    # Features requested but not separately inserted (consolidated or missing)
    skipped.extend(
        [
            "Workflow Editor deep screen (consolidated into Figure 25 / workflow list)",
            "System Access / permission editor (Create Account used for Figure 29; dedicated System Access screen not captured this pass)",
            "Governance Audit Log (admin_12 available but not mapped as a numbered figure this pass)",
            "Escalation Rules screen (overdue monitoring covered in Figure 32; dedicated rules editor not captured)",
            "Official Signatories admin screen (admin_14 available but not mapped as a numbered figure this pass)",
            "Returned Document Summary card (not captured without returning a live document)",
            "My Signatures dedicated panel (entry button visible on employee DocuTracker; panel not separately opened)",
            "Memo Document Builder full page (Create Draft type picker shown in Figure 23; builder page not separately captured)",
            "Employee Review / Sign / Return action panel (detail captured on awaiting-release docs; live review action not exercised)",
            "Employee notifications drawer (bell badge visible; dedicated notification panel not captured this pass)",
        ]
    )

    doc.save(OUT)
    print("OUT", OUT)
    print("ADMIN_INSERTED", admin_n)
    print("EMPLOYEE_INSERTED", employee_n)
    print("SKIPPED_COUNT", len(skipped))
    for s in skipped:
        print("SKIP:", s)


if __name__ == "__main__":
    main()
