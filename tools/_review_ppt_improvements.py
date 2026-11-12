from pptx import Presentation
from pptx.enum.shapes import MSO_SHAPE_TYPE

prs = Presentation(r"c:\Users\danza\Downloads\DocuTrack_PPT_FinalManTaliNI_fixed.pptx")
print(f"slides={len(prs.slides)} size={prs.slide_width}x{prs.slide_height}")

for i, slide in enumerate(prs.slides):
    texts = []
    pics = 0
    boxes = 0
    for shape in slide.shapes:
        if shape.shape_type == MSO_SHAPE_TYPE.PICTURE:
            pics += 1
        if shape.has_text_frame:
            t = " ".join(shape.text_frame.text.split())
            if t:
                texts.append(t)
                boxes += 1
    title = texts[0][:80] if texts else "(no title)"
    print(f"\nSLIDE {i+1}: {title}")
    print(f"  pics={pics} textboxes_with_text={boxes}")
    for t in texts[1:4]:
        print(f"  - {t[:160]}")
    if any("insert verified" in t.lower() for t in texts):
        print("  !! PLACEHOLDER TEXT")
    if any("six pilot" in t.lower() for t in texts):
        print("  !! OLD SIX-RESPONDENT WORDING")
    if pics == 0 and i + 1 in range(9, 19) and i + 1 != 12:
        print("  !! DIAGRAM SLIDE WITHOUT PICTURE?")
