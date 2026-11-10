"""Build a Chapter IV-only manuscript and drop the archiving section."""
from __future__ import annotations

import os
import re
import shutil

from docx import Document

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "UNITY_PILLAR_Docutracker_Manuscript_Chapter4_Live_Screenshots.docx")
OUT = os.path.join(ROOT, "UNITY_PILLAR_Docutracker_Chapter4_Screens_Only.docx")


def paragraph_text(element) -> str:
    if not element.tag.endswith("p"):
        return ""
    return "".join(element.itertext()).strip()


def renumber(text: str) -> str:
    def section(match: re.Match[str]) -> str:
        number = int(match.group(1))
        if number >= 15:
            return f"4.2.{number - 1}"
        return match.group(0)

    def figure(match: re.Match[str]) -> str:
        number = int(match.group(1))
        if number >= 34:
            return f"Figure {number - 1}"
        return match.group(0)

    text = re.sub(r"4\.2\.(\d+)", section, text)
    return re.sub(r"Figure (\d+)", figure, text)


def main() -> None:
    shutil.copy2(SRC, OUT)
    doc = Document(OUT)
    body = doc.element.body

    start = None
    end = None
    for child in list(body):
        text = paragraph_text(child)
        if start is None and text.startswith("CHAPTER IV"):
            start = child
        elif start is not None and text.startswith("CHAPTER V"):
            end = child
            break
    if start is None or end is None:
        raise RuntimeError("Chapter IV boundaries were not found")

    mode = "before"
    dropping_archive = False
    remove = []
    for child in list(body):
        if child.tag.endswith("sectPr"):
            continue
        text = paragraph_text(child)
        if mode == "before":
            if child is start:
                mode = "inside"
            else:
                remove.append(child)
                continue
        if mode == "inside" and child is end:
            mode = "after"
        if mode == "after":
            remove.append(child)
            continue
        if text.startswith("4.2.14 Document Archiving"):
            dropping_archive = True
        if dropping_archive:
            remove.append(child)
            if text.startswith("Figure 33 shows"):
                dropping_archive = False

    for child in remove:
        body.remove(child)

    for paragraph in doc.paragraphs:
        for run in paragraph.runs:
            updated = renumber(run.text)
            if updated != run.text:
                run.text = updated

    doc.save(OUT)

    headings = []
    figures = []
    for paragraph in doc.paragraphs:
        text = paragraph.text.strip()
        if text.startswith("CHAPTER ") or text.startswith("4.2.") or text.startswith("4.3"):
            headings.append(text[:90])
        if text.startswith("Figure "):
            figures.append(text[:90])
    print("OUT", OUT)
    print("BYTES", os.path.getsize(OUT))
    print("PARAS", len(doc.paragraphs))
    print("TABLES", len(doc.tables))
    print("HEADINGS")
    for line in headings:
        print(line)
    print("FIGURES")
    for line in figures:
        print(line)
    archive_left = any("archiv" in p.text.lower() for p in doc.paragraphs)
    print("ARCHIVE_LEFT", archive_left)


if __name__ == "__main__":
    main()
