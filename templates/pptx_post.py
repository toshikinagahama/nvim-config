"""quarto で作った pptx の後処理(reference.pptx とセットで使う)
- 章(#)の名前を、その後の各スライド(##)のタイトル帯の上段に薄いグレーで小さく入れる(revealjs の section-label と同じ)
- 表のキャプション(pandoc は表の下に置く)を表の上へ移す。相互参照付き表は pptx-tables.lua と併用
- マーカー(==文字==、pptx-tables.lua が SmallCaps で目印)→ 黄色ハイライト
- columns の下に書いた文(pptx-tables.lua が左カラム末尾に目印付きで入れる)→ カラムの下に全幅で配置

使い方:
  python pptx_post.py out.pptx [...]
  _quarto.yml に  post-render: analysis/templates/pptx_post.py  (引数なし → QUARTO_PROJECT_OUTPUT_FILES の pptx を処理)
  nvim の \\qx(pptx render)は自動で実行
何度実行しても二重にはならない。要 python-pptx
"""
import copy
import os
import sys

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Emu, Pt

LABEL_PT = 11
LABEL_COLOR = RGBColor(0xA8, 0xAD, 0xB5)


def title_shape(slide):
    for s in slide.placeholders:
        if s.placeholder_format.idx == 0:
            return s
    return None


def add_label(shape, text):
    """タイトルの前に段落を1つ足してラベルを入れる(段落書式は元タイトルを複製)"""
    tf = shape.text_frame
    first = tf.paragraphs[0]._p
    new = copy.deepcopy(first)
    for child in list(new):
        if not child.tag.endswith("}pPr"):
            new.remove(child)
    first.addprevious(new)
    para = tf.paragraphs[0]
    para.space_after = Pt(0)
    r = para.add_run()
    r.text = text
    r.font.size = Pt(LABEL_PT)
    r.font.bold = False
    r.font.color.rgb = LABEL_COLOR


def caption_on_top(slide):
    """表(graphicFrame)の直後にあるキャプション用テキストボックスを表の上へ"""
    shapes = list(slide.shapes)
    moved = 0
    for i, s in enumerate(shapes):
        if not getattr(s, "has_table", False) or i + 1 >= len(shapes):
            continue
        cap = shapes[i + 1]
        if not cap.name.startswith("TextBox") or not cap.has_text_frame or cap.top < s.top + s.height - Emu(10):
            continue  # 既に上にある(再実行)/キャプションでない
        h = cap.height
        cap.top = s.top
        s.top = s.top + h
        for para in cap.text_frame.paragraphs:
            para.alignment = PP_ALIGN.LEFT
        cap.text_frame.vertical_anchor = MSO_ANCHOR.BOTTOM
        moved += 1
    return moved


MARK_COLOR = "F9E27D"
A_NS = "{http://schemas.openxmlformats.org/drawingml/2006/main}"
# rPr の子要素の並び(highlight はこれらより前)
AFTER_HIGHLIGHT = {A_NS + t for t in ("uLnTx", "uLn", "uFillTx", "uFill", "latin", "ea", "cs", "sym",
                                       "hlinkClick", "hlinkMouseOver", "rtl", "extLst")}


def markers(slide):
    """cap="small" の run → ハイライト(PowerPoint 2019+/365、LibreOffice で表示)"""
    n = 0
    for rpr in slide._element.iter(A_NS + "rPr"):
        if rpr.get("cap") != "small":
            continue
        del rpr.attrib["cap"]
        if rpr.find(A_NS + "highlight") is None:
            hl = rpr.makeelement(A_NS + "highlight", {})
            hl.append(hl.makeelement(A_NS + "srgbClr", {"val": MARK_COLOR}))
            idx = next((i for i, c in enumerate(rpr) if c.tag in AFTER_HIGHLIGHT), len(rpr))
            rpr.insert(idx, hl)
        n += 1
    return n


BELOW = "@@COLUMNS_BELOW@@"
GAP = Emu(int(914400 * 0.15))


def text_width_pt(text, size=16):
    return sum(size if ord(ch) > 0x2E7F else size * 0.55 for ch in text)


def _place_below(slide, slide_w, tail, top, bottom, make_shape):
    """tail(段落 XML)を全幅の枠に入れて bottom 揃えで置き、上の図・枠を縮める"""
    t = title_shape(slide)
    x0 = t.left if t is not None else Emu(548640)  # 全幅枠の左端 = タイトルと同じ余白
    width = slide_w - 2 * x0
    line_w = width / 12700 - 20
    texts = ["".join(x.text or "" for x in e.iter(A_NS + "t")) for e in tail]
    lines = sum(max(1, -(-int(text_width_pt(s)) // int(line_w))) for s in texts)
    h = Emu(int(lines * Pt(16 * 1.3 + 4) + Pt(12)))
    new_top = bottom - h
    ns = make_shape()
    txb = ns._element.find(".//{*}txBody")
    for e in txb.findall(A_NS + "p"):
        txb.remove(e)
    for e in tail:
        txb.append(copy.deepcopy(e))
    ns.left, ns.top, ns.width, ns.height = x0, new_top, width, h
    ns.name = "ColumnsBelow"
    ns.text_frame.vertical_anchor = MSO_ANCHOR.TOP
    ns.text_frame.word_wrap = True
    limit = new_top - GAP
    for o in slide.shapes:
        if o.name == "ColumnsBelow" or o.top is None or o.top >= limit:
            continue
        if o.is_placeholder and o.placeholder_format.idx in (0, 10, 11, 12):
            continue
        if o.top + o.height <= limit:
            continue
        if o.shape_type == 13:  # 図: 縦横比を保って縮小、横中央そのまま
            s = min(1.0, (limit - top) / o.height)
            cx = o.left + o.width // 2
            o.height, o.width = int(o.height * s), int(o.width * s)
            o.left, o.top = cx - o.width // 2, top
        else:  # 継承位置のプレースホルダは4値とも明示しないと左上に飛ぶ
            l, tp, w = o.left, o.top, o.width
            o.left, o.top, o.width, o.height = l, tp, w, max(Emu(0), limit - tp)
    return ns


def columns_below(slide, slide_w):
    """目印段落以降をカラムの下(全幅)の新しい枠へ移し、カラム側を縮める"""
    for shp in list(slide.shapes):
        if not shp.has_text_frame:
            continue
        paras = shp.text_frame.paragraphs
        k = next((i for i, para in enumerate(paras) if para.text.strip() == BELOW), None)
        if k is None:
            continue
        left, top, height, w0 = shp.left, shp.top, shp.height, shp.width
        shp.left, shp.top, shp.width, shp.height = left, top, w0, height  # 継承位置を明示
        tail = [para._p for para in paras[k + 1:]]

        def make():
            new = copy.deepcopy(shp._element)  # 本文プレースホルダを複製(書式を引き継ぐ)
            shp._element.addnext(new)
            from pptx.shapes.autoshape import Shape
            return Shape(new, shp._parent)

        _place_below(slide, slide_w, tail, top, top + height, make)
        body = paras[0]._p.getparent()
        for para in paras[k:]:
            body.remove(para._p)
        if body.find(A_NS + "p") is None:
            body.append(body.makeelement(A_NS + "p", {}))
        return 1
    # 両カラムとも図/表 → ノートに退避された分をスライドへ
    if not slide.has_notes_slide:
        return 0
    ntf = slide.notes_slide.notes_text_frame
    if ntf is None:
        return 0
    paras = ntf.paragraphs
    k = next((i for i, para in enumerate(paras) if para.text.strip() == BELOW), None)
    if k is None:
        return 0
    tail = [copy.deepcopy(para._p) for para in paras[k + 1:]]
    for e in tail:  # ノートの書式は捨てて本文の見た目(16pt・#333・BIZ UDPGothic)に
        for r in e.iter(A_NS + "rPr"):
            r.set("sz", "1600")
        ppr = e.find(A_NS + "pPr")
        bullet = ppr is not None and (ppr.find(A_NS + "buChar") is not None or ppr.find(A_NS + "buAutoNum") is not None)
        if ppr is not None:
            e.remove(ppr)
        if bullet:  # 箇条書きは「•」付きで
            np_ = e.makeelement(A_NS + "pPr", {"marL": "285750", "indent": "-285750"})
            np_.append(np_.makeelement(A_NS + "buFont", {"typeface": "Arial"}))
            np_.append(np_.makeelement(A_NS + "buChar", {"char": "•"}))
            e.insert(0, np_)
    pics = [o for o in slide.shapes if o.shape_type == 13 or getattr(o, "has_table", False)]
    top = min((o.top for o in pics), default=Emu(914400 * 1.3))
    t = title_shape(slide)
    foot = next((o for o in slide.placeholders if o.placeholder_format.idx == 11), None)
    bottom = (foot.top - GAP) if foot is not None else prs_h(slide) - Emu(914400 * 0.6)

    def make():
        tb = slide.shapes.add_textbox(0, 0, 100, 100)
        return tb

    ns = _place_below(slide, slide_w, tail, top, bottom, make)
    for para in ns.text_frame.paragraphs:
        for r in para.runs:
            r.font.size = Pt(16)
            r.font.color.rgb = RGBColor(0x33, 0x33, 0x33)
            r.font.name = "BIZ UDPGothic"
    body = paras[0]._p.getparent()
    for para in paras[k:]:
        body.remove(para._p)
    if body.find(A_NS + "p") is None:  # txBody は段落 0 個だと PowerPoint が開けない
        body.append(body.makeelement(A_NS + "p", {}))
    return 1


def fix_ids(slide):
    """複製した図形の id 重複を解消(PowerPoint の修復ダイアログ対策)"""
    P = "{http://schemas.openxmlformats.org/presentationml/2006/main}"
    seen, nxt = set(), 1
    nodes = list(slide._element.iter(P + "cNvPr"))
    nxt = max((int(e.get("id", "0")) for e in nodes if e.get("id", "").isdigit()), default=0) + 1
    for e in nodes:
        i = e.get("id")
        if i in seen:
            e.set("id", str(nxt))
            nxt += 1
        seen.add(e.get("id"))


def prs_h(slide):
    return slide.part.package.presentation_part.presentation.slide_height


def process(path):
    prs = Presentation(path)
    label, n, nc, nm, nb = None, 0, 0, 0, 0
    for slide in prs.slides:
        nc += caption_on_top(slide)
        nb += columns_below(slide, prs.slide_width)
        nm += markers(slide)  # columns 下へ移した分も含めるため後
        fix_ids(slide)
        lay = slide.slide_layout.name
        t = title_shape(slide)
        if lay == "Title Slide":
            label = None
            continue
        if lay == "Section Header":
            label = t.text_frame.text.strip() if t is not None else None
            continue
        if not label or t is None or not t.text_frame.text.strip():
            continue
        tf = t.text_frame
        # 二重適用防止: 先頭段落がラベル書式(LABEL_PT)なら置き換え
        p0 = tf.paragraphs[0]
        if len(tf.paragraphs) > 1 and p0.runs and p0.runs[0].font.size == Pt(LABEL_PT):
            p0.runs[0].text = label
            continue
        add_label(t, label)
        n += 1
    prs.save(path)
    print(f"pptx_post: {path}: 章ラベル {n} 枚 / 表キャプション {nc} 個 / マーカー {nm} 箇所 / columns下 {nb}")


def main():
    files = sys.argv[1:]
    if not files:
        files = [f for f in os.environ.get("QUARTO_PROJECT_OUTPUT_FILES", "").splitlines() if f.endswith(".pptx")]
    for f in files:
        if os.path.exists(f):
            process(f)


if __name__ == "__main__":
    main()
