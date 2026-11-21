-- R / Word(論文用の表・docx)
local F = require("analysis.recipes.fields")

-- 表を論文書式の flextable にする関数(各レシピの先頭に入れる。何度定義しても同じ)
local ft_paper = [=[
# 論文書式の表: 三線(上・見出し下・下)、フォント統一、見出し太字、本文幅に収める
ft_paper <- function(x, caption = NULL, note = NULL, font = "Times New Roman",
                     font_ja = "游明朝", size = 10, width = 6.5) {
  ft <- if (inherits(x, "flextable")) x
        else if (inherits(x, "gtsummary")) gtsummary::as_flex_table(x)
        else if (inherits(x, "gt_tbl")) flextable::flextable(as.data.frame(x[["_data"]]))
        else flextable::flextable(as.data.frame(x))
  thick <- officer::fp_border(width = 1.5)
  thin <- officer::fp_border(width = 0.75)
  ft <- ft |>
    flextable::font(fontname = font, eastasia.family = font_ja, part = "all") |>
    flextable::fontsize(size = size, part = "all") |>
    flextable::border_remove() |>
    flextable::hline_top(part = "header", border = thick) |>
    flextable::hline_bottom(part = "header", border = thin) |>
    flextable::hline_bottom(part = "body", border = thick) |>
    flextable::bold(part = "header") |>
    flextable::align(j = -1, align = "center", part = "header") |>
    flextable::padding(padding.top = 1, padding.bottom = 1, part = "all") |>
    flextable::autofit() |>
    flextable::fit_to_width(max_width = width)   # A4縦の本文幅 ≈ 6.5インチ(横向きなら 9)
  if (!is.null(caption) && nzchar(caption)) ft <- flextable::set_caption(ft, caption)
  if (!is.null(note) && nzchar(note)) {
    ft <- ft |>
      flextable::add_footer_lines(note) |>
      flextable::font(fontname = font, eastasia.family = font_ja, part = "footer") |>
      flextable::fontsize(size = size - 1, part = "footer")
  }
  ft
}
]=]

return {
  lang = "r",
  cat = "Word",

  {
    name = "[Word] gtsummary の雑誌テーマ(JAMA / Lancet / NEJM, 以降の表に効く)",
    fields = {
      F.input("journal", "雑誌(jama / lancet / nejm / qjecon)", "jama"),
      F.yesno("compact", "行間を詰める(compact)", true),
      F.yesno("ja", "見出しを日本語にする(language = ja)", false),
    },
    body = [[
# 以降に作る tbl_summary / tbl_regression の書式(p値・CIの書き方、桁数など)が雑誌の規定になる
gtsummary::reset_gtsummary_theme()
gtsummary::theme_gtsummary_journal("{{journal}}")
{{#compact}}gtsummary::theme_gtsummary_compact()
{{/compact}}{{#ja}}gtsummary::theme_gtsummary_language("ja", big.mark = ",")
{{/ja}}# 元に戻す: gtsummary::reset_gtsummary_theme()]],
  },

  {
    name = "[Word] 表を論文書式に(三線・フォント・表題・脚注, flextable)",
    fields = {
      F.input("tbl", "表オブジェクト(gtsummary / gt / data.frame)", "t1"),
      F.input("caption", "表題", "Table 1. Characteristics of the participants"),
      F.input("note", "脚注(空欄で無し)", "", { optional = true }),
      F.input("font", "欧文フォント", "Times New Roman"),
      F.input("size", "文字サイズ(pt)", "10"),
      F.yesno("save", "docx にも保存する", false),
      F.input("file", "保存先(save の時)", "output/table1.docx"),
    },
    body = ft_paper .. [[
ft_{{tbl}} <- ft_paper({{tbl}}, caption = "{{caption}}", note = "{{note}}",
                     font = "{{font}}", size = {{size}})
ft_{{tbl}}   # Quarto の docx 出力ではこの書式のまま Word の表になる
{{#save}}dir.create(here::here(dirname("{{file}}")), recursive = TRUE, showWarnings = FALSE)
flextable::save_as_docx(ft_{{tbl}}, path = here::here("{{file}}"))
{{/save}}# 和文フォントは ft_paper(font_ja = "游ゴシック") で変更。横向きページに置くなら width = 9]],
  },

  {
    name = "[Word] 複数の表・図を1つの docx に(Table / Figure 番号付き, 横向き可)",
    fields = {
      F.input("tbls", "表オブジェクト(カンマ区切り)", "t1, t2"),
      F.input("figs", "図オブジェクト ggplot(カンマ区切り, 空欄で無し)", "", { optional = true }),
      F.yesno("landscape", "横向きページ", false),
      F.input("file", "保存先", "output/tables_figures.docx"),
    },
    body = ft_paper .. [=[
split_names <- \(s) Filter(nzchar, trimws(strsplit(s, ",")[[1]]))
tbls <- mget(split_names("{{tbls}}"))
figs <- mget(split_names("{{figs}}"))
# 表題: 名前ごとに書き換える(無い分はオブジェクト名)
captions <- c(t1 = "Characteristics of the participants")
fig_captions <- c()
page_w <- {{#landscape}}9{{/landscape}}{{^landscape}}6.5{{/landscape}}

doc <- officer::read_docx()
for (i in seq_along(tbls)) {
  nm <- names(tbls)[i]
  doc <- doc |>
    officer::body_add_par(sprintf("Table %d. %s", i, dplyr::coalesce(captions[nm], nm)), style = "table title") |>
    flextable::body_add_flextable(ft_paper(tbls[[i]], width = page_w)) |>
    officer::body_add_break()
}
for (i in seq_along(figs)) {
  nm <- names(figs)[i]
  doc <- doc |>
    officer::body_add_gg(figs[[i]], width = page_w, height = page_w * 0.6, res = 300) |>
    officer::body_add_par(sprintf("Figure %d. %s", i, dplyr::coalesce(fig_captions[nm], nm)), style = "graphic title") |>
    officer::body_add_break()
}
{{#landscape}}doc <- officer::body_end_section_landscape(doc)
{{/landscape}}out <- here::here("{{file}}")
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
print(doc, target = out)
message("保存: ", out)]=],
  },

  {
    name = "[Word] Quarto の Word 書式テンプレート(reference.docx)を作る",
    fields = {
      F.input("file", "保存先", "analysis/templates/reference.docx"),
      F.input("font", "本文の欧文フォント", "Times New Roman"),
      F.input("font_ja", "本文の和文フォント", "游明朝"),
      F.input("size", "本文の文字サイズ(pt)", "10.5"),
    },
    body = [[
# Pandoc 既定の reference.docx を書き出し、本文・見出しのフォントを変える
ref <- here::here("{{file}}")
dir.create(dirname(ref), recursive = TRUE, showWarnings = FALSE)
quarto_bin <- Sys.which("quarto")
if (!nzchar(quarto_bin)) {  # R から PATH が見えない時(Mac の GUI 起動など)
  cand <- c("/usr/local/bin/quarto", "/opt/homebrew/bin/quarto", "/Applications/quarto/bin/quarto")
  quarto_bin <- cand[file.exists(cand)][1]
}
system2(quarto_bin, c("pandoc", "-o", shQuote(ref), "--print-default-data-file", "reference.docx"))
doc <- officer::read_docx(ref)
fp <- officer::fp_text_lite(font.family = "{{font}}", eastasia.family = "{{font_ja}}", font.size = {{size}})
for (st in c("Normal", "Body Text", "First Paragraph", "Compact")) {
  if (st %in% officer::styles_info(doc)$style_name) {
    doc <- officer::docx_set_paragraph_style(doc, style_id = gsub(" ", "", st), style_name = st, base_on = "Normal", fp_t = fp)
  }
}
print(doc, target = ref)
message("作成: ", ref, "\n細かい調整は Word で開いて「スタイル」を編集 → 上書き保存")
# qmd / _metadata.yml に:
# format:
#   docx:
#     reference-doc: templates/reference.docx
#     fig-dpi: 300]],
  },
}
