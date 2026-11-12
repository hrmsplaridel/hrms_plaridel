from pptx import Presentation
from pptx.util import Emu

prs = Presentation(r"c:\Users\danza\Downloads\DocuTrack_PPT_FinalManTaliNI_improved.pptx")
slide = prs.slides[1]
print("=== SLIDE 2 ===")
for j, shape in enumerate(slide.shapes):
    text = ""
    if shape.has_text_frame:
        text = shape.text_frame.text
    print(
        f"[{j}] {shape.name} L={shape.left} T={shape.top} "
        f"W={shape.width} H={shape.height}"
    )
    if text.strip():
        print(repr(text[:500]))
        print("---")
