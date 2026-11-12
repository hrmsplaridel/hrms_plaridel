from pptx import Presentation
from pptx.enum.shapes import MSO_SHAPE_TYPE

prs = Presentation(r"c:\Users\danza\Downloads\DocuTrack_PPT_FinalManTaliNI.pptx")

for idx in [6, 18, 19]:
    slide = prs.slides[idx]
    print(f"\n=== SLIDE {idx+1} ===")
    for j, shape in enumerate(slide.shapes):
        kind = shape.shape_type
        text = ""
        if shape.has_text_frame:
            text = shape.text_frame.text.replace("\n", " | ")[:300]
        print(
            f"[{j}] {shape.name} type={kind} "
            f"L={shape.left} T={shape.top} W={shape.width} H={shape.height}"
        )
        if text:
            print("   ", text)
        if kind == MSO_SHAPE_TYPE.PICTURE:
            print("    PICTURE")
