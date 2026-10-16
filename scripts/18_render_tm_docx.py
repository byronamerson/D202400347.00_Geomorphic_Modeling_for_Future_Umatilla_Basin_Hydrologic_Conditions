"""
Render the Umatilla migration technical memorandum from Markdown into the ESA
memorandum template.

Purpose
    Convert docs/TM_Umatilla_Migration_DRAFT_*.md into a Word document that
    carries ESA's named styles for body text, headings, tables, figures and
    appendix slipsheets.

Inputs
    draft   Markdown technical memorandum. Headings are ATX ('##'), tables are
            GitHub pipe tables, figures are inline images with a bolded caption
            line beneath, and captions are numbered literally in the source.
    plots/  PNG figures referenced by relative path from the draft's directory.
    docs/memorandum.docx   ESA template supplying all named styles.

Outputs
    A .docx in docs/, same base name as the draft.

Key decisions
    - Draft '##' maps to Heading2 and '###' to Heading3, one level below the
      obvious mapping: ESA's Heading1 (16.5 pt) and Heading2 (15.5 pt) are too
      close in size to read as a hierarchy in a memo.
    - Section numbers are kept as literal text; ESA heading styles carry no
      automatic numbering. Appendix slipsheets drop the numbers entirely.
    - Caption numbers are literal, matching the template, which uses no SEQ
      fields. Reordering content in Word will not renumber anything.
"""

import pathlib
import re
from dataclasses import dataclass, field


# ---------------------------------------------------------------- parsing ---

@dataclass
class Block:
    """One parsed element of the draft, tagged by kind.

    kind is one of: heading, para, bullet, table, figure.
    Remaining fields carry whatever that kind needs; unused fields stay empty.
    """
    kind: str
    text: str = ""
    level: int = 0
    rows: list = field(default_factory=list)
    caption: str = ""
    number: str = ""
    path: str = ""
    notes: str = ""


CAPTION = re.compile(r"^\*\*(Table|Figure)\s+([A-Z]?\d+)\.\*\*\s*(.*)$")
IMAGE = re.compile(r"^!\[(.*?)\]\((.*?)\)\s*$")
HEADING = re.compile(r"^(#{1,6})\s+(.*)$")
BULLET = re.compile(r"^(\s*)[-*]\s+(.*)$")
RULE = re.compile(r"^\s*(-{3,}|\*{3,}|_{3,})\s*$")
QUOTE = re.compile(r"^\s*>\s?(.*)$")


def split_row(line):
    """Split one pipe-table line into cell strings, dropping the outer pipes."""
    return [c.strip() for c in line.strip().strip("|").split("|")]


def is_divider(line):
    """True for a pipe-table header divider such as '|---|---|'."""
    return bool(re.match(r"^\s*\|[\s:|-]+\|\s*$", line))


def parse_blocks(lines):
    """Turn draft lines into an ordered list of Blocks.

    Captions are attached to the element they describe: a table caption
    precedes its table, a figure caption follows its image. A paragraph
    immediately after a table is held as a note candidate rather than a body
    paragraph, because ESA sets table notes inside the table's final row.
    """
    blocks, i, pending_caption = [], 0, None
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if not stripped or RULE.match(line):
            # Horizontal rules divide sections in the source only; the Word
            # heading styles carry that separation visually.
            i += 1
            continue

        if QUOTE.match(line):
            quoted = []
            while i < len(lines) and QUOTE.match(lines[i]):
                quoted.append(QUOTE.match(lines[i]).group(1).strip())
                i += 1
            blocks.append(Block("quote", text=" ".join(quoted).strip()))
            continue

        cap = CAPTION.match(stripped)
        if cap:
            kind, number, title = cap.groups()
            if kind == "Table":
                pending_caption = (number, title)
            else:
                for b in reversed(blocks):
                    if b.kind == "figure" and not b.caption:
                        b.number, b.caption = number, title
                        break
            i += 1
            continue

        img = IMAGE.match(stripped)
        if img:
            blocks.append(Block("figure", path=img.group(2), text=img.group(1)))
            i += 1
            continue

        head = HEADING.match(stripped)
        if head:
            blocks.append(Block("heading", text=head.group(2),
                                level=len(head.group(1))))
            i += 1
            continue

        if stripped.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                if not is_divider(lines[i]):
                    rows.append(split_row(lines[i]))
                i += 1
            number, title = pending_caption or ("", "")
            pending_caption = None
            blocks.append(Block("table", rows=rows, number=number, caption=title))
            continue

        bul = BULLET.match(line)
        if bul:
            indent = len(bul.group(1))
            blocks.append(Block("bullet", text=bul.group(2),
                                level=1 + indent // 2))
            i += 1
            continue

        para, start = [], i
        while i < len(lines) and lines[i].strip() and not re.match(
                r"^\s*(#|\||!\[|>|[-*]\s)", lines[i]):
            para.append(lines[i].strip())
            i += 1
        if para:
            text = " ".join(para)
            follows_table = bool(blocks) and blocks[-1].kind == "table"
            blocks.append(Block("note_candidate" if follows_table else "para",
                                text=text))
        else:
            i = start + 1
    return blocks


# ---------------------------------------------------------------- writing ---

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.text import WD_TAB_ALIGNMENT
from docx.oxml.ns import qn
from docx.shared import Inches, Emu
import struct


TEXT_WIDTH_IN = 6.5          # letter page less 1 in margins each side
MAX_FIGURE_HEIGHT_IN = 7.5   # keeps caption on the same page as its figure

HEADING_FOR_LEVEL = {2: "Heading2", 3: "Heading3", 4: "Heading4"}

APPENDIX_TITLES = {
    "A": ("Appendix A", "Methods Detail"),
    "B": ("Appendix B", "Additional Figures"),
}

INLINE = re.compile(r"(\*\*.+?\*\*|\*.+?\*|`.+?`|~.+?~)")


MATH_NS = "http://schemas.openxmlformats.org/officeDocument/2006/math"
EQUATION = re.compile(r"^[^=]+=.+$")
DRAFT_NOTE = re.compile(r"^(draft status|status|todo|note to self)\b", re.I)
OPERATORS = {"=", "+", "-", "×", "·", "/", "(", ")"}


def is_equation(text):
    """True for a quoted line that reads as a formula rather than prose.

    Requires an equals sign and no sentence punctuation, which separates the
    fitted relationship from ordinary quoted commentary.
    """
    return bool(EQUATION.match(text)) and "." not in text.split("=")[0]


def build_omml(expression):
    """Render a plain-text expression as a centred OMML equation element.

    Word stores equations as Office Math Markup, which python-docx has no API
    for, so the element is built directly. 'base_sub' becomes a true subscript.
    Operators carry spaces around them; adjacent identifiers are separated by a
    thin space, which is how implied multiplication is set.
    """
    from docx.oxml import parse_xml

    def escape(token):
        return (token.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))

    def run(token, literal=False):
        props = "<m:rPr><m:nor/></m:rPr>" if literal else ""
        return f'<m:r>{props}<m:t xml:space="preserve">{escape(token)}</m:t></m:r>'

    def identifier(token):
        """One variable, rendered with a subscript if the source marks one."""
        if "_" not in token:
            return run(token)
        base, sub = token.split("_", 1)
        return (f"<m:sSub><m:e>{run(base)}</m:e>"
                f"<m:sub>{run(sub)}</m:sub></m:sSub>")

    runs, previous_was_identifier = [], False
    for piece in re.split(r"\s*([=+\-×·/()])\s*", expression):
        if piece.strip() in OPERATORS:
            runs.append(run(f" {piece.strip()} ", literal=True))
            previous_was_identifier = False
            continue
        for word in piece.split():
            if previous_was_identifier:
                runs.append(run("\u2009", literal=True))   # thin space
            if word.replace(".", "").isdigit():
                runs.append(run(word, literal=True))
            else:
                runs.append(identifier(word))
            previous_was_identifier = True

    xml = (f'<m:oMathPara xmlns:m="{MATH_NS}">'
           f'<m:oMathParaPr><m:jc m:val="center"/></m:oMathParaPr>'
           f'<m:oMath>{"".join(runs)}</m:oMath></m:oMathPara>')
    return parse_xml(xml)


def add_equation(doc, styles, expression):
    """Append a display equation as a Word equation object."""
    p = add_styled(doc, styles, "12space")
    p._p.append(build_omml(expression))
    return p


def style_index(doc):
    """Map style_id to style object, since python-docx looks styles up by name."""
    return {s.style_id: s for s in doc.styles}


def clear_body(doc):
    """Strip the template's sample content, keeping the memo front matter.

    Retains the 'memorandum' title, the date/to/cc/from/subject control table
    and the trailing section properties; removes the demonstration headings,
    body text, sample tables and figure placeholders.
    """
    body = doc.element.body
    kept_title, kept_table = False, False
    for child in list(body.iterchildren()):
        tag = child.tag.split("}")[1]
        if tag == "sectPr":
            continue
        if tag == "p" and not kept_title:
            kept_title = True
            continue
        if tag == "tbl" and not kept_table:
            kept_table = True
            continue
        body.remove(child)


def add_runs(paragraph, text):
    """Write text into a paragraph, honouring **bold**, *italic* and `code`."""
    for token in INLINE.split(text):
        if not token:
            continue
        if token.startswith("**") and token.endswith("**"):
            paragraph.add_run(token[2:-2]).bold = True
        elif token.startswith("*") and token.endswith("*"):
            paragraph.add_run(token[1:-1]).italic = True
        elif token.startswith("`") and token.endswith("`"):
            paragraph.add_run(token[1:-1])
        elif token.startswith("~") and token.endswith("~"):
            run = paragraph.add_run(token[1:-1])
            run.font.subscript = True
        else:
            paragraph.add_run(token)


def add_styled(doc, styles, style_id, text=""):
    """Append a paragraph in the named ESA style and return it."""
    p = doc.add_paragraph()
    p.style = styles[style_id]
    if text:
        add_runs(p, text)
    return p


def add_label_caption(doc, styles, style_id, label, title):
    """Append a caption as 'Table 1<tab>Title', the template's own convention."""
    p = doc.add_paragraph()
    p.style = styles[style_id]
    p.add_run(label)
    p.add_run("\t")
    add_runs(p, title)
    return p


def png_pixel_size(path):
    """Read width and height from a PNG's IHDR chunk.

    Avoids a Pillow dependency: every figure in this project is a PNG, whose
    dimensions sit at a fixed offset in the header.
    """
    header = pathlib.Path(path).read_bytes()[:24]
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"not a PNG: {path}")
    return struct.unpack(">II", header[16:24])


def fit_image_size(path):
    """Scale a figure to the text column, capped so its caption stays with it."""
    w_px, h_px = png_pixel_size(path)
    width = TEXT_WIDTH_IN
    height = width * h_px / w_px
    if height > MAX_FIGURE_HEIGHT_IN:
        width *= MAX_FIGURE_HEIGHT_IN / height
        height = MAX_FIGURE_HEIGHT_IN
    return Inches(width), Inches(height)


def add_figure(doc, styles, block, draft_dir):
    """Append an image in Photo style with its caption beneath, ESA layout."""
    path = (draft_dir / block.path).resolve()
    width, height = fit_image_size(path)
    holder = add_styled(doc, styles, "Photo")
    holder.add_run().add_picture(str(path), width=width, height=height)
    add_label_caption(doc, styles, "Figure",
                      f"Figure {block.number}", block.caption)


def add_table(doc, styles, block, note):
    """Append a caption, the table itself, and any note inside its final row.

    Column headings take Tablecolumnheading, data cells Tabletext, and the note
    occupies a single merged row in TableNotes, which is where ESA sets table
    notes rather than in body text beneath.
    """
    add_label_caption(doc, styles, "TableNoTitle",
                      f"Table {block.number}", block.caption)
    header, data = block.rows[0], block.rows[1:]
    n_cols = len(header)
    table = doc.add_table(rows=0, cols=n_cols)
    table.style = styles["TableGrid"]
    table.autofit = False

    first_col = Inches(0.78)
    rest = Inches((TEXT_WIDTH_IN - 0.78) / (n_cols - 1))
    widths = [first_col] + [rest] * (n_cols - 1)

    def fill(values, style_id):
        row = table.add_row()
        for cell, value, width in zip(row.cells, values, widths):
            cell.width = width
            p = cell.paragraphs[0]
            p.style = styles[style_id]
            add_runs(p, value)
        return row

    fill(header, "Tablecolumnheading")
    repeat_header_row(table.rows[0])
    for values in data:
        fill(values, "Tabletext")

    if note:
        row = table.add_row()
        merged = row.cells[0]
        for cell in row.cells[1:]:
            merged = merged.merge(cell)
        p = merged.paragraphs[0]
        p.style = styles["TableNotes"]
        add_runs(p, note)

    add_styled(doc, styles, "Tableclosingborder")


def repeat_header_row(row):
    """Mark a table row to repeat as a header across page breaks."""
    trPr = row._tr.get_or_add_trPr()
    trPr.append(row._tr.makeelement(qn("w:tblHeader"), {}))


def blank_header_footer(section):
    """Strip header and footer from a section so a divider page stands alone.

    Without this a slipsheet inherits the preceding section's running header,
    which on Appendix B would read 'Appendix A'.
    """
    section.different_first_page_header_footer = True
    for part in (section.header, section.first_page_header,
                 section.footer, section.first_page_footer):
        part.is_linked_to_previous = False
        for paragraph in part.paragraphs:
            for run in list(paragraph.runs):
                run._r.getparent().remove(run._r)


def start_appendix(doc, styles, letter):
    """Open a new section, lay out the appendix slipsheet, and open another.

    Mirrors docs/Appendix.docx: a divider page carrying only the appendix
    number and title with no header or footer, then a fresh section whose
    running header names the appendix.
    """
    label, title = APPENDIX_TITLES[letter]
    slipsheet = doc.add_section(WD_SECTION.NEW_PAGE)
    blank_header_footer(slipsheet)
    add_styled(doc, styles, "AppendixNumber", label)
    add_styled(doc, styles, "AppendixTitle", title)

    section = doc.add_section(WD_SECTION.NEW_PAGE)
    section.different_first_page_header_footer = True
    header = section.header
    header.is_linked_to_previous = False
    p = header.paragraphs[0]
    p.style = styles["Header"]
    p.text = f"{label}. {title}"
    return section


# ------------------------------------------------------------ orchestration --

def render(draft_path, template_path, output_path):
    """Build the Word memorandum from the Markdown draft.

    I/O happens here only; every helper above works on in-memory objects.
    The draft's level-1 title is skipped deliberately — it belongs in the
    memo's 'subject' control, which is filled by hand in Word.
    """
    draft_path, template_path = pathlib.Path(draft_path), pathlib.Path(template_path)
    blocks = parse_blocks(draft_path.read_text(encoding="utf-8").splitlines())

    doc = Document(str(template_path))
    styles = style_index(doc)
    clear_body(doc)

    pending_note, appendix_open = None, False
    for index, block in enumerate(blocks):
        if block.kind == "heading":
            if block.level == 1:
                continue
            letter = appendix_letter(block.text)
            if letter:
                start_appendix(doc, styles, letter)
                appendix_open = True
                continue
            add_styled(doc, styles, HEADING_FOR_LEVEL.get(block.level, "Heading3"),
                       block.text)
        elif block.kind == "para":
            add_styled(doc, styles, "12space", block.text)
        elif block.kind == "quote":
            if DRAFT_NOTE.match(block.text):
                continue          # working note; not part of the deliverable
            if is_equation(block.text):
                add_equation(doc, styles, block.text)
            else:
                add_styled(doc, styles, "12space", block.text)
        elif block.kind == "bullet":
            add_styled(doc, styles, f"ListBullet{block.level if block.level > 1 else ''}",
                       block.text)
        elif block.kind == "figure":
            add_figure(doc, styles, block, draft_path.parent)
        elif block.kind == "table":
            note = next((b.text for b in blocks[index + 1:index + 2]
                         if b.kind == "note_candidate"), None)
            add_table(doc, styles, block, note)
        elif block.kind == "note_candidate":
            continue

    doc.save(str(output_path))
    return output_path


def appendix_letter(heading_text):
    """Return 'A' or 'B' if a heading opens an appendix, else None.

    Section numbers are stripped: the draft numbers appendices 8 and 9 in
    sequence with the body, but they stand outside that sequence on the
    slipsheet.
    """
    match = re.search(r"Appendix\s+([AB])\b", heading_text)
    return match.group(1) if match else None
