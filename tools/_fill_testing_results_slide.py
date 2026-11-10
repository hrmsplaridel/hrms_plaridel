from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.util import Pt, Emu

PPT = r"c:\Users\danza\Downloads\DocuTrack_PPT_Final.pptx"
OUT = r"c:\Users\danza\Downloads\DocuTrack_PPT_Final.pptx"

CONTENT = {
    "Functional Suitability": [
        ("Functional Suitability", True, 20),
        ("Employee mean: 4.40 — Strongly Agree", False, 14),
        ("HR/Admin mean: 4.54 — Strongly Agree", False, 14),
        ("", False, 12),
        (
            "Respondents favorably rated document handling, "
            "workflow routing, review, and access control.",
            False,
            13,
        ),
    ],
    "Usability": [
        ("Usability", True, 20),
        ("Employee mean: 4.07 — Agree", False, 14),
        ("HR/Admin mean: 4.11 — Agree", False, 14),
        ("", False, 12),
        (
            "Ratings were lower than functional suitability; "
            "navigation, instructions, and task guidance need refinement.",
            False,
            13,
        ),
    ],
    "Performance Efficiency": [
        ("Performance Efficiency", True, 20),
        ("Employee mean: 4.43 — Strongly Agree", False, 14),
        ("HR/Admin mean: 4.00 — Agree", False, 14),
        ("", False, 12),
        (
            "Based on perceived loading and responsiveness; "
            "not actual response-time measurements.",
            False,
            13,
        ),
    ],
}


def set_textbox(shape, lines):
    tf = shape.text_frame
    tf.clear()
    tf.word_wrap = True
    first = True
    for text, bold, size in lines:
        p = tf.paragraphs[0] if first else tf.add_paragraph()
        first = False
        run = p.add_run()
        run.text = text
        run.font.name = "Calibri"
        run.font.size = Pt(size)
        run.font.bold = bold
        run.font.color.rgb = RGBColor(0x1A, 0x2A, 0x4A)
        p.space_after = Pt(4 if bold else 2)


def main():
    prs = Presentation(PPT)
    slide = prs.slides[18]  # Testing and Results

    updated = []
    for shape in slide.shapes:
        if not shape.has_text_frame:
            continue
        raw = shape.text_frame.text.strip()
        for title, lines in CONTENT.items():
            if raw.startswith(title):
                # Expand height so the summary fits
                shape.height = max(shape.height, Emu(2200000))
                set_textbox(shape, lines)
                updated.append(title)
                break

    if len(updated) != 3:
        raise SystemExit(f"Expected 3 boxes, updated: {updated}")

    prs.save(OUT)
    print("Updated:", ", ".join(updated))
    print("Saved:", OUT)


if __name__ == "__main__":
    main()
