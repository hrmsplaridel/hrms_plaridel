from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.util import Emu, Pt

SRC = r"c:\Users\danza\Downloads\DocuTrack_PPT_FinalManTaliNI_v2.pptx"
OUT = r"c:\Users\danza\Downloads\DocuTrack_PPT_FinalManTaliNI_v3.pptx"
NAVY = RGBColor(0x1A, 0x2A, 0x4A)


def write_box(shape, lines):
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
        run.font.color.rgb = NAVY
        p.alignment = PP_ALIGN.LEFT
        p.space_after = Pt(4 if bold else 2)


prs = Presentation(SRC)
slide = prs.slides[14]  # Conclusion and Recommendations

# Clear old body text boxes (keep title)
title_shape = None
for shape in list(slide.shapes):
    if not shape.has_text_frame:
        continue
    text = shape.text_frame.text.strip()
    if text.startswith("Conclusion and Recommendations"):
        title_shape = shape
        write_box(title_shape, [("Conclusion and Recommendations", True, 28)])
        continue
    if text:
        sp = shape._element
        sp.getparent().remove(sp)

# Two-column layout: Conclusions | Recommendations
left = slide.shapes.add_textbox(Emu(800000), Emu(1850000), Emu(5000000), Emu(4200000))
write_box(
    left,
    [
        ("Conclusions", True, 20),
        (
            "DocuTrack provides centralized registration, routing, review, and status tracking under UNITY PILLAR.",
            False,
            14,
        ),
        (
            "Pilot feedback was positive overall (pooled mean 4.29, Strongly Agree).",
            False,
            14,
        ),
        (
            "Functional suitability and performance rated higher; usability needs more refinement.",
            False,
            14,
        ),
        (
            "Results reflect user perception only—not proven reductions in processing time or paper use.",
            False,
            14,
        ),
    ],
)

right = slide.shapes.add_textbox(Emu(6200000), Emu(1850000), Emu(5200000), Emu(4200000))
write_box(
    right,
    [
        ("Recommendations", True, 20),
        (
            "Improve navigation, labels, status explanations, and confirmation messages.",
            False,
            14,
        ),
        (
            "Re-validate workflow rules, permissions, attachments, escalation, and audit trails.",
            False,
            14,
        ),
        (
            "Conduct a larger office pilot and collect completion-time comparisons where possible.",
            False,
            14,
        ),
        (
            "Enhance search, overdue tracking, audit-trail filtering, and authorized reporting.",
            False,
            14,
        ),
    ],
)

prs.save(OUT)
print("Saved", OUT)
