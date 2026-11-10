"""Fill DocuTrack PPT placeholder diagram slides with manuscript assets."""

from __future__ import annotations

from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.util import Emu, Pt

SRC = Path(r"c:\Users\danza\Downloads\DocuTrack_PPT_Original_Fonts (1).pptx")
OUT = Path(r"c:\Users\danza\Downloads\DocuTrack_PPT_Filled_Diagrams.pptx")
OUT_MAIN = Path(r"c:\Users\danza\Downloads\DocuTrack_PPT_Ready.pptx")
MS = Path(r"c:\Users\danza\hrms_plaridel\docs\docutracker-manuscript")
ERD_NEW = Path(
    r"C:\Users\danza\.cursor\projects\c-Users-danza-hrms-plaridel\assets"
    r"\ERD.drawio-133bd3c1-b60b-4c23-b70f-b4db2d775d2e.png"
)
SHOTS = Path(r"c:\Users\danza\hrms_plaridel\manuscript_screenshots")

SLIDE_IMAGES = {
    8: MS / "06-system-architecture.png",
    9: MS / "05-system-diagram.png",
    10: MS / "07-use-case.png",
    12: MS / "04-flowchart.png",
    13: MS / "08-user-sequence.png",
    14: MS / "02-dfd-level-0.png",
    15: MS / "03-dfd-level-1.png",
    16: ERD_NEW if ERD_NEW.exists() else MS / "01-erd.png",
    17: SHOTS / "11_Document_History_Timeline.png",
}

ROLES_SLIDE = 11

CONTENT_LEFT = 762000
CONTENT_TOP = 1897380
CONTENT_WIDTH = 10470515
CONTENT_HEIGHT = 4921250


def delete_shape(shape) -> None:
    sp = shape._element
    sp.getparent().remove(sp)


def clear_placeholder_texts(slide) -> None:
    for shape in list(slide.shapes):
        if not shape.has_text_frame:
            continue
        text = (shape.text_frame.text or "").strip().lower()
        if "insert verified docutrack diagram" in text:
            delete_shape(shape)


def fit_picture(slide, image_path: Path) -> None:
    """Place image as large as possible inside the content box, centered."""
    pic = slide.shapes.add_picture(str(image_path), Emu(0), Emu(0))
    nat_w, nat_h = pic.width, pic.height
    delete_shape(pic)

    scale = min(CONTENT_WIDTH / nat_w, CONTENT_HEIGHT / nat_h)
    width = int(nat_w * scale)
    height = int(nat_h * scale)
    left = CONTENT_LEFT + (CONTENT_WIDTH - width) // 2
    top = CONTENT_TOP + (CONTENT_HEIGHT - height) // 2
    slide.shapes.add_picture(
        str(image_path),
        Emu(left),
        Emu(top),
        width=Emu(width),
        height=Emu(height),
    )


def fill_roles_slide(slide) -> None:
    clear_placeholder_texts(slide)
    box = slide.shapes.add_textbox(
        Emu(CONTENT_LEFT + 300000),
        Emu(CONTENT_TOP + 200000),
        Emu(CONTENT_WIDTH - 600000),
        Emu(CONTENT_HEIGHT - 400000),
    )
    tf = box.text_frame
    tf.word_wrap = True

    lines = [
        ("DocuTrack uses the existing HRMS roles for access and workflow.", False),
        ("", False),
        ("Administrator", True),
        ("Manages workflows, permissions, escalation, and system configuration.", False),
        ("", False),
        ("HR", True),
        ("Reviews and acts on documents assigned through HR workflow steps.", False),
        ("", False),
        ("Supervisor / Department Head", True),
        ("Reviews department documents and performs assigned workflow actions.", False),
        ("", False),
        ("Employee", True),
        ("Creates, submits, tracks, and signs documents within authorized scope.", False),
        ("", False),
        ("Mayor (signatory resolution)", True),
        ("Used for official signatory resolution where the workflow requires it.", False),
        ("", False),
        (
            "Note: Approve / forward / reject / return also require current-step "
            "workflow assignment, not role alone.",
            False,
        ),
    ]

    first = True
    for text, bold in lines:
        p = tf.paragraphs[0] if first else tf.add_paragraph()
        first = False
        run = p.add_run()
        run.text = text
        run.font.name = "Calibri"
        run.font.size = Pt(18 if bold else 16)
        run.font.bold = bold
        run.font.color.rgb = RGBColor(0x1F, 0x1F, 0x1F)
        p.space_after = Pt(4 if bold else 2)
        p.alignment = PP_ALIGN.LEFT


def main() -> None:
    missing = [(i + 1, str(p)) for i, p in SLIDE_IMAGES.items() if not p.exists()]
    if missing:
        raise SystemExit(f"Missing images: {missing}")

    prs = Presentation(str(SRC))

    for idx, image_path in SLIDE_IMAGES.items():
        slide = prs.slides[idx]
        clear_placeholder_texts(slide)
        fit_picture(slide, image_path)
        print(f"Slide {idx + 1}: inserted {image_path.name}")

    fill_roles_slide(prs.slides[ROLES_SLIDE])
    print(f"Slide {ROLES_SLIDE + 1}: filled roles and permissions text")

    prs.save(str(OUT))
    prs.save(str(OUT_MAIN))
    print(f"Saved: {OUT}")
    print(f"Saved: {OUT_MAIN}")


if __name__ == "__main__":
    main()
