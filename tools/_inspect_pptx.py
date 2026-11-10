from pptx import Presentation

pptx_path = r"c:\Users\danza\Downloads\DocuTrack_PPT_Original_Fonts (1).pptx"
prs = Presentation(pptx_path)
print("slide size", prs.slide_width, prs.slide_height)
for i in range(8, 18):
    slide = prs.slides[i]
    print(f"\n=== SLIDE {i+1} ===")
    for j, shape in enumerate(slide.shapes):
        text = ""
        if shape.has_text_frame:
            text = shape.text_frame.text.replace("\n", " | ")[:140]
        print(
            f"  [{j}] {shape.name} type={shape.shape_type} "
            f"L={shape.left} T={shape.top} W={shape.width} H={shape.height} "
            f"text={text!r}"
        )
