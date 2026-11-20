"""quarto で作った pptx の後処理(reference.pptx とセットで使う)
- 章(#)の名前を、その後の各スライド(##)のタイトル帯の上段に薄いグレーで小さく入れる(revealjs の section-label と同じ)
- 表のキャプション(pandoc は表の下に置く)を表の上へ移す。相互参照付き表は pptx-tables.lua と併用
- マーカー(==文字==、pptx-tables.lua が SmallCaps で目印)→ 黄色ハイライト
- columns の下に書いた文(pptx-tables.lua が左カラム末尾に目印付きで入れる)→ カラムの下に全幅で配置
- 表: 列幅を文字量に合わせ、はみ出すなら行で分割して次スライドへ(同じタイトル)
- タイトル無しで分かれたスライド(1チャンク2図・カラムから送った図表)→ 前と同じタイトル

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


def no_autofit(shape):
    """タイトルの自動縮小(PowerPoint が章ラベル+長いタイトルで文字を縮める)を切る"""
    bp = shape.text_frame._txBody.find(A_NS + "bodyPr")
    for tag in ("normAutofit", "spAutoFit", "noAutofit"):
        for e in bp.findall(A_NS + tag):
            bp.remove(e)
    bp.append(bp.makeelement(A_NS + "noAutofit", {}))


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
BELOW_BORDER = RGBColor(0xD3, 0x2F, 0x2F)  # columns の下の文の枠線色。枠なしにするなら None


def _has_text(p_el):
    return bool("".join(t.text or "" for t in p_el.iter(A_NS + "t")).strip())


def _drop_marker(paras, k):
    """目印段落以降を消すだけ(下に置く文が無いとき)。txBody は段落 0 個だと PowerPoint が開けない"""
    body = paras[0]._p.getparent()
    for para in paras[k:]:
        body.remove(para._p)
    if body.find(A_NS + "p") is None:
        body.append(body.makeelement(A_NS + "p", {}))


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
    if BELOW_BORDER:  # 赤枠で囲む
        ns.line.color.rgb = BELOW_BORDER
        ns.line.width = Pt(1.5)
        tf = ns.text_frame
        tf.margin_left = tf.margin_right = Pt(8)
        tf.margin_top = tf.margin_bottom = Pt(4)
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
        if not any(_has_text(e) for e in tail):  # 下に置く文が無い(表等は pandoc が落とす) → 空枠を作らない
            _drop_marker(paras, k)
            return 0

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
    if not any(_has_text(e) for e in tail):
        _drop_marker(paras, k)
        return 0
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


TBL_SIZES = (12,)  # 表の文字サイズ候補(pt)。縮めて1枚に収めたいなら (12, 11, 10)。入らなければ行で分割して次スライドへ
TBL_SLACK = 1.2  # 表の下はみ出し許容(1.0=フッター上で厳密に分割、1.2=見積り高さの2割増しまでは同じスライド)
CELL_MAR_LR, CELL_MAR_TB = 4, 2  # セル余白(pt)。既定(左右7.2/上下3.6)より詰める
LINE_H = 1.25  # 行の高さ ≒ 文字サイズ × これ


def _cell_lines(cell):
    """セルの各行の文字列(<a:br> と段落で区切る)"""
    out = []
    for para in cell.text_frame.paragraphs:
        line = ""
        for el in para._p:
            if el.tag == A_NS + "br":
                out.append(line)
                line = ""
            elif el.tag in (A_NS + "r", A_NS + "fld"):
                line += "".join(t.text or "" for t in el.iter(A_NS + "t"))
        out.append(line)
    return out


def _nlines(text, size, avail):
    """折り返し後の行数(英数字は空白で、和文と長い語は文字で折り返す)"""
    n, cur = 1, 0.0
    for tok in text.replace(" ", " \0").split("\0"):
        tw = text_width_pt(tok, size) * 1.05
        if cur + tw <= avail or cur == 0 and tw <= avail:
            cur += tw
            continue
        if tw <= avail:
            n, cur = n + 1, tw
            continue
        for ch in tok:  # 1語が列幅より長い → 文字で割る
            cw = text_width_pt(ch, size) * 1.05
            if cur + cw > avail and cur > 0:
                n, cur = n + 1, 0.0
            cur += cw
    return n


def _table_layout(texts, total, size, full_rows=()):
    """文字サイズ size のときの列幅(EMU)と各行の高さ(pt)。texts[行][列] = 行文字列のリスト
    full_rows: 全列結合した行(脚注)。列幅計算に入れず、高さは全幅で数える"""
    ncol = len(texts[0])
    pad = 2 * CELL_MAR_LR + 3
    need = [0.0] * ncol  # 折り返さない幅
    mn = [0.0] * ncol  # 最低幅 = 一番長い語(これ未満だと語の途中で折れる)
    for i, row in enumerate(texts):
        if i in full_rows:
            continue
        for j, lines in enumerate(row):
            for x in lines:
                need[j] = max(need[j], text_width_pt(x, size) * 1.05 + pad)
                for tok in x.split(" "):
                    mn[j] = max(mn[j], text_width_pt(tok, size) * 1.05 + pad)
    tot = total / 12700
    mn[0] = max(mn[0], min(need[0], tot * 0.25))  # 項目名列は最低 1/4
    if ncol == 1:
        w = [tot]
    elif sum(need) <= tot:  # 全部1行で収まる → 余りを比例配分
        w = [x * tot / sum(need) for x in need]
    elif sum(need[1:]) + mn[0] <= tot:  # 2列目以降(数値)は折り返さず、1列目(項目名)が残りで折り返す
        w = [tot - sum(need[1:])] + need[1:]
    elif sum(mn) <= tot:  # 語の途中では折らない範囲で、長い列から縮める
        k = (tot - sum(mn)) / sum(nd - m for nd, m in zip(need, mn))
        w = [m + (nd - m) * k for nd, m in zip(need, mn)]
    else:
        w = [m * tot / sum(mn) for m in mn]
    heights = []
    for i, row in enumerate(texts):
        nl = 1
        if i in full_rows:
            heights.append(sum(_nlines(x, size, tot - pad) for x in row[0]) * size * LINE_H + 2 * CELL_MAR_TB + 1)
            continue
        for j, lines in enumerate(row):
            avail = max(1.0, w[j] - pad)
            nl = max(nl, sum(_nlines(x, size, avail) for x in lines))
        heights.append(nl * size * LINE_H + 2 * CELL_MAR_TB + 1)
    return [int(x * 12700) for x in w], heights


def _bottom_limit(slide, frame):
    """表が使える下端(EMU): columns の下の文 / フッター / スライド下端"""
    lim = None
    for o in slide.shapes:
        if o.name == "ColumnsBelow" and o.top > frame.top:
            lim = o.top - GAP
    if lim is None:
        foot = next((o for o in slide.placeholders if o.placeholder_format.idx in (10, 11, 12)), None)
        lim = (foot.top - GAP) if foot is not None else prs_h(slide) - Emu(914400 * 0.6)
    return lim


def _apply_table_style(tbl, size):
    for tc in tbl._tbl.iter(A_NS + "tc"):
        for tag in ("rPr", "endParaRPr"):
            for r in tc.iter(A_NS + tag):
                r.set("sz", str(size * 100))
        tcpr = tc.find(A_NS + "tcPr")
        if tcpr is None:
            tcpr = tc.makeelement(A_NS + "tcPr", {})
            tc.append(tcpr)
        for k, v in (("marL", CELL_MAR_LR), ("marR", CELL_MAR_LR), ("marT", CELL_MAR_TB), ("marB", CELL_MAR_TB)):
            tcpr.set(k, str(int(v * 12700)))


def _continuation_slide(prs, slide, frame, rows, after, nh=1):
    """slide と同じレイアウトで同じタイトル + 表(ヘッダ行 + rows)のスライドを after の直後に作る"""
    new = prs.slides.add_slide(slide.slide_layout)
    tree = new.shapes._spTree
    for shp in list(new.shapes):
        tree.remove(shp._element)
    for shp in slide.shapes:
        if shp.is_placeholder and shp.placeholder_format.idx in (0, 10, 11, 12):
            tree.append(copy.deepcopy(shp._element))
    t = title_shape(new)
    if t is not None:
        _set_title_cont(t)
    f = copy.deepcopy(frame._element)
    tbl = f.find(".//" + A_NS + "tbl")
    trs = tbl.findall(A_NS + "tr")
    for tr in trs[nh:]:
        tbl.remove(tr)
    for tr in rows:
        tbl.append(copy.deepcopy(tr))
    tree.append(f)
    lst = prs.slides._sldIdLst
    ids = list(lst)
    lst.remove(ids[-1])
    after.addnext(ids[-1])
    fix_ids(new)
    return ids[-1]


CONT = ""  # 分割・続きスライドのタイトルに付ける語(例 "（続き）")。空なら元と同じタイトル


def _set_title_cont(t, base=None):
    """タイトルを「base（続き）」に(base 省略時は今のタイトル)。二重には付けない"""
    if not CONT:  # タイトルはそのまま(複製元と同じ書式)
        return
    paras = t.text_frame.paragraphs
    text = base if base is not None else paras[-1].text
    text = text.removesuffix(CONT) + CONT
    p = paras[-1]
    for r in p.runs[1:]:
        p._p.remove(r._r)
    if p.runs:
        p.runs[0].text = text
    else:
        p.add_run().text = text


def _tc_text(tc):
    return "".join(t.text or "" for t in tc.iter(A_NS + "t")).strip()


def _merge_spanners(tbl):
    """gtsummary の tbl_strata / tbl_merge の見出し(1行目: 「60~69」等が各グループ先頭列だけに入り残りは空)
    → グループ分の列をセル結合して中央寄せ。戻り値: ヘッダの行数(1 or 2)"""
    trs = tbl._tbl.findall(A_NS + "tr")
    if len(trs) < 3:
        return 1
    r0 = trs[0].findall(A_NS + "tc")
    r1 = trs[1].findall(A_NS + "tc")
    if len(r0) != len(r1) or len(r0) < 3:
        return 1
    if any(tc.get("gridSpan") for tc in r0[1:]):  # 結合済み(再実行)
        return 2
    t0 = [_tc_text(tc) for tc in r0]
    t1 = [_tc_text(tc) for tc in r1]
    # 1行目に空セルがあり、2行目は(1列目以外)全部埋まっている → 1行目はグループ見出し
    if not any(t0[1:]) or all(t0[1:]) or not all(t1[1:]):
        return 1
    j = 1
    while j < len(r0):
        k = j + 1
        while k < len(r0) and not t0[k]:
            k += 1
        if t0[j] and k - j > 1:
            r0[j].set("gridSpan", str(k - j))
            for tc in r0[j + 1:k]:
                tc.set("hMerge", "1")
            for p in r0[j].iter(A_NS + "p"):
                ppr = p.find(A_NS + "pPr")
                if ppr is None:
                    ppr = p.makeelement(A_NS + "pPr", {})
                    p.insert(0, ppr)
                ppr.set("algn", "ctr")
        j = k
    return 2


def _merge_footnotes(tbl, nh):
    """末尾の脚注行(gtsummary の「¹ Median (Q1, Q3)」等、1列目だけ文字)→ 全列結合。戻り値: 行番号の集合"""
    trs = tbl._tbl.findall(A_NS + "tr")
    out = set()
    for i in range(len(trs) - 1, nh, -1):
        tcs = trs[i].findall(A_NS + "tc")
        if len(tcs) < 2:
            break
        if tcs[0].get("gridSpan") == str(len(tcs)):
            out.add(i)
            continue
        if not _tc_text(tcs[0]) or any(_tc_text(tc) for tc in tcs[1:]):
            break
        tcs[0].set("gridSpan", str(len(tcs)))
        for tc in tcs[1:]:
            tc.set("hMerge", "1")
        out.add(i)
    return out


def _widen_beside_text(slide, shp):
    """pandoc は「短い文(### 見出し等) + 表」を左右2分割にする → 文を上・表を全幅の下に置き直す"""
    t = title_shape(slide)
    x0 = t.left if t is not None else Emu(548640)
    full = slide.part.package.presentation_part.presentation.slide_width - 2 * x0
    if shp.width >= full * 0.7:
        return False
    texts = [o for o in slide.placeholders
             if o.placeholder_format.idx not in (0, 10, 11, 12) and o.has_text_frame and o.text_frame.text.strip()]
    if len(texts) != 1:
        return False
    o = texts[0]
    if o.left + o.width > shp.left + Emu(10) or len(o.text_frame.text.strip()) > 40:
        return False
    nlines = len([p for p in o.text_frame.paragraphs if p.text.strip()])
    h = Emu(int(Pt(16 * 1.4) * nlines + Pt(10)))
    top = min(o.top, shp.top)
    o.left, o.top, o.width, o.height = x0, top, full, h
    cols = list(shp.table._tbl.tblGrid.iterchildren(A_NS + "gridCol"))
    total = sum(int(c.get("w")) for c in cols)
    for c in cols:
        c.set("w", str(int(int(c.get("w")) * full / total)))
    shp.left, shp.top, shp.width = x0, top + h + GAP, full
    return True


def fit_tables(prs, slide):
    """表を整える(pandoc の表は列幅均等・文字12pt固定で、長いと下にはみ出す)
    - 列幅: 数値列は折り返さない幅、1列目(項目名)が残りで折り返す(全部1行で入れば比例配分)
    - 文字サイズ: TBL_SIZES から下端に収まる最大を選ぶ(既定 12pt 固定。セル余白は詰める)
    - 入らない → 行で分割し同じタイトルの次スライドへ(ヘッダ行を繰り返す)
    戻り値: (整えた表の数, 増やしたスライド数)"""
    n = added = 0
    for shp in list(slide.shapes):
        if not getattr(shp, "has_table", False):
            continue
        tbl = shp.table
        _widen_beside_text(slide, shp)
        nh = _merge_spanners(tbl)
        cols = list(tbl._tbl.tblGrid.iterchildren(A_NS + "gridCol"))
        total = sum(int(c.get("w")) for c in cols)
        trs = list(tbl._tbl.findall(A_NS + "tr"))
        texts = [[_cell_lines(c) for c in row.cells][: len(cols)] for row in tbl.rows]
        if nh == 2:  # 結合したグループ見出しは列幅計算に入れない
            texts[0] = [texts[0][0]] + [[""]] * (len(cols) - 1)
        foot = _merge_footnotes(tbl, nh)
        below = any(o.name == "ColumnsBelow" and o.top > shp.top for o in slide.shapes)
        avail = (_bottom_limit(slide, shp) - shp.top) / 12700 * (1.0 if below else TBL_SLACK)  # 下の文とは重ねない
        for size in TBL_SIZES:
            w, hs = _table_layout(texts, total, size, foot)
            if sum(hs) <= avail:
                break
        _apply_table_style(tbl, size)
        w[0] += total - sum(w)
        for c, x in zip(cols, w):
            c.set("w", str(x))
        n += 1
        if sum(hs) <= avail or len(trs) < nh + 2:
            continue
        # 分割: ヘッダ(nh 行) + 入るだけの行 を1枚ずつ
        head_h, chunks, cur, h = sum(hs[:nh]), [], [], 0.0
        for tr, rh in zip(trs[nh:], hs[nh:]):
            if cur and head_h + h + rh > avail:
                chunks.append(cur)
                cur, h = [], 0.0
            cur.append(tr)
            h += rh
        chunks.append(cur)
        if len(chunks) < 2:
            continue
        for tr in trs[nh:]:
            if not any(tr is x for x in chunks[0]):
                tbl._tbl.remove(tr)
        after = next(x for x in prs.slides._sldIdLst if prs.part.related_part(x.rId) is slide.part)
        for rows in chunks[1:]:
            after = _continuation_slide(prs, slide, shp, rows, after, nh)
            added += 1
    return n, added


def titles_for_split(prs):
    """タイトルの無いスライドにタイトルを付ける
    - pandoc が自動で分けたスライド(1チャンク2図など)→ 前と同じタイトル
    - 章(#)の直後の本文(「# はじめに」の下に直接書いた文)→ 章の名前"""
    prev, sec, n = None, None, 0
    for slide in prs.slides:
        lay = slide.slide_layout.name
        t = title_shape(slide)
        if lay in ("Title Slide", "Section Header"):
            prev = None
            sec = t if lay == "Section Header" and t is not None and t.text_frame.text.strip() else None
            continue
        if t is not None and t.text_frame.text.strip():
            prev = t
            continue
        src = prev if prev is not None else sec
        if src is None:
            continue
        e = copy.deepcopy(src._element)
        sppr = e.find("{http://schemas.openxmlformats.org/presentationml/2006/main}spPr")
        if sppr is not None:  # 位置はこのスライドのレイアウトに従う
            for c in list(sppr):
                sppr.remove(c)
        if t is None:
            slide.shapes._spTree.insert(2, e)
        else:
            t._element.getparent().replace(t._element, e)
        t = title_shape(slide)
        if src is prev:
            _set_title_cont(t)
        fix_ids(slide)
        n += 1
    return n


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
    label, n, nc, nm, nb, nt, ns = None, 0, 0, 0, 0, 0, 0
    for slide in list(prs.slides):
        nc += caption_on_top(slide)
        nb += columns_below(slide, prs.slide_width)
        a, b = fit_tables(prs, slide)  # columns の下の文を置いた後(表の下端が決まる)
        nt += a
        ns += b
        nm += markers(slide)  # columns 下へ移した分も含めるため後
        fix_ids(slide)
    ncont = titles_for_split(prs)
    for slide in prs.slides:
        lay = slide.slide_layout.name
        t = title_shape(slide)
        if t is not None:
            no_autofit(t)
        if lay == "Title Slide":
            label = None
            continue
        if lay == "Section Header":
            label = t.text_frame.text.strip() if t is not None else None
            continue
        if not label or t is None or not t.text_frame.text.strip() or t.text_frame.text.strip() == label:
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
    print(f"pptx_post: {path}: 章ラベル {n} 枚 / 表キャプション {nc} 個 / マーカー {nm} 箇所 / columns下 {nb}"
          f" / 表 {nt} 個(分割で +{ns} 枚) / 続きタイトル {ncont} 枚")


def main():
    files = sys.argv[1:]
    if not files:
        files = [f for f in os.environ.get("QUARTO_PROJECT_OUTPUT_FILES", "").splitlines() if f.endswith(".pptx")]
    for f in files:
        if os.path.exists(f):
            process(f)


if __name__ == "__main__":
    main()
