"""Improve DocuTrack defense PPT: content sync + trim redundant diagrams."""

from __future__ import annotations

from copy import deepcopy
from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE_TYPE
from pptx.enum.text import PP_ALIGN
from pptx.oxml.ns import qn
from pptx.util import Emu, Pt

SRC = Path(r"c:\Users\danza\Downloads\DocuTrack_PPT_FinalManTaliNI_fixed.pptx")
OUT = Path(r"c:\Users\danza\Downloads\DocuTrack_PPT_FinalManTaliNI_improved.pptx")

NAVY = RGBColor(0x1A, 0x2A, 0x4A)


def set_runs(shape, lines: list[tuple[str, bool, int]], align=PP_ALIGN.LEFT) -> None:
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
        p.alignment = align
        p.space_after = Pt(6 if bold else 3)


def find_title_shape(slide):
    for shape in slide.shapes:
        if shape.has_text_frame and shape.text_frame.text.strip():
            # Prefer placeholder/title-like top text
            if shape.top < Emu(1800000):
                return shape
    for shape in slide.shapes:
        if shape.has_text_frame and shape.text_frame.text.strip():
            return shape
    return None


def find_body_shapes(slide):
    bodies = []
    for shape in slide.shapes:
        if not shape.has_text_frame:
            continue
        t = shape.text_frame.text.strip()
        if not t:
            continue
        if shape.top >= Emu(1800000):
            bodies.append(shape)
    return bodies


def delete_slide(prs: Presentation, index: int) -> None:
    sldIdLst = prs.slides._sldIdLst
    sldId = sldIdLst[index]
    rId = sldId.get(qn("r:id"))
    prs.part.drop_rel(rId)
    sldIdLst.remove(sldId)


def rewrite_objectives(slide) -> None:
    # Keep title; replace the six objective cards with three manuscript objectives.
    title = find_title_shape(slide)
    if title:
        set_runs(title, [("System Objectives", True, 32)], align=PP_ALIGN.LEFT)

    # Remove existing body text shapes (old objective cards)
    for shape in list(slide.shapes):
        if shape == title:
            continue
        if shape.has_text_frame and shape.text_frame.text.strip():
            sp = shape._element
            sp.getparent().remove(sp)

    objectives = [
        (
            "1. Design",
            "Design a digital document tracking and routing system with scanning capabilities for recording, monitoring, and movement of documents.",
            900000,
        ),
        (
            "2. Develop",
            "Develop DocuTrack as a centralized platform that supports efficient, transparent, accountable, accessible, and secure document management.",
            2800000,
        ),
        (
            "3. Evaluate",
            "Test and evaluate functionality, usability, and effectiveness through pilot user evaluation.",
            4700000,
        ),
    ]

    left = 1000000
    width = 10000000
    height = 1500000
    for heading, body, top in objectives:
        box = slide.shapes.add_textbox(Emu(left), Emu(top), Emu(width), Emu(height))
        set_runs(
            box,
            [
                (heading, True, 22),
                (body, False, 16),
            ],
        )


def label_slide7(slide) -> None:
    # Add a clear title above the existing picture.
    title = slide.shapes.add_textbox(Emu(734695), Emu(900000), Emu(10497820), Emu(567463))
    set_runs(
        title,
        [("From Manual Process to Digital DocuTrack", True, 28)],
        align=PP_ALIGN.LEFT,
    )


def rewrite_roles(slide) -> None:
    title = find_title_shape(slide)
    if title:
        set_runs(title, [("DocuTrack User Roles and Permissions", True, 28)])

    for shape in list(slide.shapes):
        if shape == title:
            continue
        if shape.has_text_frame and shape.text_frame.text.strip():
            sp = shape._element
            sp.getparent().remove(sp)

    box = slide.shapes.add_textbox(Emu(900000), Emu(1900000), Emu(10200000), Emu(4200000))
    set_runs(
        box,
        [
            ("Uses existing HRMS roles", True, 18),
            ("Administrator — workflows, permissions, escalation, configuration", False, 16),
            ("HR — review and act on HR workflow steps", False, 16),
            ("Supervisor / Department Head — department review actions", False, 16),
            ("Employee — create, submit, track, and sign within authorized scope", False, 16),
            ("Mayor — used for signatory resolution when required", False, 16),
            ("", False, 12),
            (
                "Important: Approve / forward / reject / return also require current-step workflow assignment, not role alone.",
                True,
                15,
            ),
        ],
    )


def rewrite_testing(slide) -> None:
    title = find_title_shape(slide)
    if title:
        set_runs(title, [("Testing and Results", True, 28)])

    # Replace the three column boxes by matching existing text starts
    mapping = {
        "Functional Suitability": [
            ("Functional Suitability", True, 18),
            ("Employee: 4.40 — Strongly Agree", False, 14),
            ("HR/Admin: 4.54 — Strongly Agree", False, 14),
            ("Favorable ratings for document actions and workflow controls", False, 13),
        ],
        "Usability": [
            ("Usability", True, 18),
            ("Employee: 4.07 — Agree", False, 14),
            ("HR/Admin: 4.11 — Agree", False, 14),
            ("Needs better navigation and task guidance", False, 13),
        ],
        "Performance Efficiency": [
            ("Performance Efficiency", True, 18),
            ("Employee: 4.43 — Strongly Agree", False, 14),
            ("HR/Admin: 4.00 — Agree", False, 14),
            ("Perceived responsiveness only (not timed benchmarks)", False, 13),
        ],
    }

    updated = set()
    for shape in slide.shapes:
        if not shape.has_text_frame:
            continue
        raw = shape.text_frame.text.strip()
        for key, lines in mapping.items():
            if raw.startswith(key):
                set_runs(shape, lines)
                updated.add(key)

    # Add footer note about sample
    note = slide.shapes.add_textbox(Emu(900000), Emu(5200000), Emu(10200000), Emu(900000))
    set_runs(
        note,
        [
            (
                "Pilot sample: 3 unique respondents completed both Employee and HR/Admin forms (6 questionnaires). "
                "7 missing photo-visible ratings were excluded. Overall pooled mean: 4.29 (Strongly Agree).",
                False,
                13,
            )
        ],
    )
    print("Testing columns updated:", sorted(updated))


def rewrite_conclusion(slide) -> None:
    title = find_title_shape(slide)
    if title:
        set_runs(title, [("Conclusion and Recommendations", True, 28)])

    for shape in slide.shapes:
        if not shape.has_text_frame:
            continue
        if shape == title:
            continue
        if not shape.text_frame.text.strip():
            continue
        set_runs(
            shape,
            [
                (
                    "DocuTrack supports centralized document registration, routing, review, and status tracking within UNITY PILLAR.",
                    False,
                    17,
                ),
                (
                    "Pilot feedback was positive overall (pooled mean 4.29, Strongly Agree), with usability as the main area to improve.",
                    False,
                    17,
                ),
                (
                    "Next steps: improve workflow guidance and feedback, verify permission edge cases, and run a larger office pilot.",
                    False,
                    17,
                ),
            ],
        )
        break


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"Missing source: {SRC}")

    prs = Presentation(str(SRC))

    # Content rewrites on current indices before deletion
    rewrite_objectives(prs.slides[4])  # System Objectives
    label_slide7(prs.slides[6])
    rewrite_roles(prs.slides[11])
    rewrite_testing(prs.slides[18])
    rewrite_conclusion(prs.slides[19])

    # Rename ERD companion slide title if present
    slide18 = prs.slides[17]
    t = find_title_shape(slide18)
    if t and "Document and Workflow Records" in t.text_frame.text:
        set_runs(t, [("DocuTrack Document History and Records", True, 28)])

    # Delete redundant diagram slides (highest index first)
    # Current:
    # 9 arch, 10 workflow arch, 11 use case, 12 roles, 13 routing, 14 review/release,
    # 15 context, 16 dfd, 17 erd, 18 history
    # Keep: 9 arch, 11 use case, 12 roles, 13 routing, 17 erd
    # Remove: 10, 14, 15, 16, 18
    for idx in sorted([9, 13, 14, 15, 17], reverse=True):
        title = ""
        ts = find_title_shape(prs.slides[idx])
        if ts:
            title = ts.text_frame.text.strip()
        delete_slide(prs, idx)
        print(f"Removed slide index {idx}: {title}")

    prs.save(str(OUT))
    print("Saved", OUT)
    print("Remaining slides:", len(prs.slides))


if __name__ == "__main__":
    main()
