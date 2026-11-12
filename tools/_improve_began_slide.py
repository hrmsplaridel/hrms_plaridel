from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.util import Pt

PPT = r"c:\Users\danza\Downloads\DocuTrack_PPT_FinalManTaliNI_improved.pptx"
OUT = r"c:\Users\danza\Downloads\DocuTrack_PPT_FinalManTaliNI_v2.pptx"
NAVY = RGBColor(0x1A, 0x2A, 0x4A)

prs = Presentation(PPT)
slide = prs.slides[1]

for shape in slide.shapes:
    if not shape.has_text_frame:
        continue
    text = shape.text_frame.text.strip()
    if text.startswith("Where it all began"):
        continue
    if "Manual and paper-based" in text or shape.top > 1500000:
        tf = shape.text_frame
        tf.clear()
        tf.word_wrap = True
        lines = [
            ("Manual and paper-based document processing in government offices", True, 20),
            ("", False, 12),
            ("• Lost or misplaced documents", False, 18),
            ("• Slow routing and unclear current assignee", False, 18),
            ("• Limited visibility of document status and history", False, 18),
            ("• Heavy reliance on logbooks and follow-up inquiries", False, 18),
        ]
        first = True
        for text_line, bold, size in lines:
            p = tf.paragraphs[0] if first else tf.add_paragraph()
            first = False
            run = p.add_run()
            run.text = text_line
            run.font.name = "Calibri"
            run.font.size = Pt(size)
            run.font.bold = bold
            run.font.color.rgb = NAVY
            p.alignment = PP_ALIGN.LEFT
            p.space_after = Pt(8)
        print("Updated Where it all began body")
        break

prs.save(OUT)
print("Saved", OUT)
