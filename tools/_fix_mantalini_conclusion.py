from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.util import Pt

PPT = r"c:\Users\danza\Downloads\DocuTrack_PPT_FinalManTaliNI.pptx"
OUT = r"c:\Users\danza\Downloads\DocuTrack_PPT_FinalManTaliNI_fixed.pptx"

prs = Presentation(PPT)
slide = prs.slides[19]

for shape in slide.shapes:
    if not shape.has_text_frame:
        continue
    text = shape.text_frame.text
    if "Six pilot respondents" not in text and "pooled mean" not in text.lower():
        continue

    lines = [
        (
            "DocuTrack supports centralized document registration, routing, and status tracking.",
            False,
            18,
        ),
        (
            "Three unique respondents completed both Employee and HR/Admin forms "
            "(six questionnaires). Overall pooled mean: 4.29 (Strongly Agree).",
            False,
            18,
        ),
        (
            "Improve workflow feedback, verify permissions, and conduct broader testing.",
            False,
            18,
        ),
    ]

    tf = shape.text_frame
    tf.clear()
    tf.word_wrap = True
    first = True
    for text_line, bold, size in lines:
        p = tf.paragraphs[0] if first else tf.add_paragraph()
        first = False
        run = p.add_run()
        run.text = text_line
        run.font.name = "Calibri"
        run.font.size = Pt(size)
        run.font.bold = bold
        run.font.color.rgb = RGBColor(0x1A, 0x2A, 0x4A)
        p.space_after = Pt(12)

    print("Updated conclusion text")
    break
else:
    raise SystemExit("Conclusion text box not found")

prs.save(OUT)
print("Saved", OUT)
