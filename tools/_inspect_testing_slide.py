from pptx import Presentation

prs = Presentation(r"c:\Users\danza\Downloads\DocuTrack_PPT_Final.pptx")
print("slides", len(prs.slides))
for i, slide in enumerate(prs.slides):
    texts = []
    for shape in slide.shapes:
        if shape.has_text_frame:
            t = shape.text_frame.text.strip()
            if t:
                texts.append(t.replace("\n", " | ")[:100])
    joined = " || ".join(texts)
    if "testing" in joined.lower() or "functional" in joined.lower() or "usability" in joined.lower():
        print(f"\n=== SLIDE {i+1} ===")
        for j, shape in enumerate(slide.shapes):
            if shape.has_text_frame:
                t = shape.text_frame.text.strip()
                if t:
                    print(f"[{j}] {shape.name} L={shape.left} T={shape.top} W={shape.width} H={shape.height}")
                    print(repr(t[:400]))
