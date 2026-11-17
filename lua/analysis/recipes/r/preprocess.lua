-- R / 前処理
local F = require("analysis.recipes.fields")

return {
  lang = "r",
  cat = "前処理",

  {
    name = "データ概要(型・欠測・ユニーク数・要約)",
    fields = { F.cols("vars", "見る列") },
    body = [[
d_ov <- {{df}} %>% dplyr::select(all_of({{vars}}))
tibble::tibble(
  変数 = names(d_ov),
  型 = purrr::map_chr(d_ov, \(x) class(x)[1]),
  n = purrr::map_int(d_ov, \(x) sum(!is.na(x))),
  欠測 = purrr::map_int(d_ov, \(x) sum(is.na(x))),
  `欠測%` = round(purrr::map_dbl(d_ov, \(x) mean(is.na(x)) * 100), 1),
  ユニーク = purrr::map_int(d_ov, dplyr::n_distinct),
  例 = purrr::map_chr(d_ov, \(x) paste(head(unique(na.omit(x)), 3), collapse = ", "))
)
summary(d_ov)]],
  },

  {
    name = "欠測の処理(欠測率 → 行削除 or 中央値/最頻値で補完)",
    fields = { F.cols("vars", "対象列") },
    body = [[
{{df}} %>%
  dplyr::summarise(dplyr::across(all_of({{vars}}), \(x) round(mean(is.na(x)) * 100, 1))) %>%
  tidyr::pivot_longer(everything(), names_to = "変数", values_to = "欠測%") %>%
  dplyr::arrange(dplyr::desc(`欠測%`))
# A) 欠測のある行を落とす
d_cc <- {{df}} %>% tidyr::drop_na(all_of({{vars}}))
cat("完全ケース:", nrow(d_cc), "/", nrow({{df}}), "\n")
# B) 補完(数値=中央値, それ以外=最頻値)+ 補完フラグ列
mode_val <- \(x) names(sort(table(x), decreasing = TRUE))[1]
d_imp <- {{df}} %>%
  dplyr::mutate(dplyr::across(all_of({{vars}}), is.na, .names = "{.col}_imputed")) %>%
  dplyr::mutate(dplyr::across(all_of({{vars}}), \(x) {
    if (is.numeric(x)) dplyr::coalesce(x, median(x, na.rm = TRUE))
    else { v <- mode_val(x); x[is.na(x)] <- v; x }
  }))]],
  },

  {
    name = "外れ値の検出(IQR法・zスコア)→ フラグ列",
    fields = { F.cols("vars", "数値列") },
    body = [[
out_tab <- {{df}} %>%
  dplyr::select(all_of({{vars}})) %>%
  tidyr::pivot_longer(everything(), names_to = "変数") %>%
  dplyr::group_by(変数) %>%
  dplyr::summarise(
    下限 = quantile(value, .25, na.rm = TRUE) - 1.5 * IQR(value, na.rm = TRUE),
    上限 = quantile(value, .75, na.rm = TRUE) + 1.5 * IQR(value, na.rm = TRUE),
    IQR法 = sum(value < 下限 | value > 上限, na.rm = TRUE),
    `|z|>3` = sum(abs(as.numeric(scale(value))) > 3, na.rm = TRUE)
  )
out_tab
iqr_out <- \(x) { q <- quantile(x, c(.25, .75), na.rm = TRUE); h <- 1.5 * diff(q); x < q[1] - h | x > q[2] + h }
{{df}} <- {{df}} %>%
  dplyr::mutate(outlier_any = dplyr::if_any(all_of({{vars}}), \(x) dplyr::coalesce(iqr_out(x), FALSE)))
# 除外するなら: {{df}} <- {{df}} %>% dplyr::filter(!outlier_any)]],
  },

  {
    name = "カテゴリ化(四分位 / 任意の区切り)",
    fields = { F.col("x", "連続変数") },
    body = [=[
new_col <- paste0({{x_str}}, "_q4")
{{df}} <- {{df}} %>%
  dplyr::mutate(!!new_col := factor(dplyr::ntile({{x}}, 4), labels = c("Q1", "Q2", "Q3", "Q4")))
# 任意の区切り(例: BMI 18.5 / 25):
# {{df}} <- {{df}} %>% dplyr::mutate(bmi_cat = cut(BMI, c(-Inf, 18.5, 25, Inf), right = FALSE, labels = c("低体重", "普通", "肥満")))
{{df}} %>% dplyr::group_by(.data[[new_col]]) %>% dplyr::summarise(n = dplyr::n(), min = min({{x}}), max = max({{x}}))]=],
  },

  {
    name = "標準化(zスコア)/ 0-1正規化",
    fields = { F.cols("vars", "数値列") },
    body = [[
{{df}} <- {{df}} %>%
  dplyr::mutate(dplyr::across(all_of({{vars}}),
    list(z = \(x) as.numeric(scale(x)), mm = \(x) (x - min(x, na.rm = TRUE)) / diff(range(x, na.rm = TRUE))),
    .names = "{.col}_{.fn}"))
{{df}} %>% dplyr::select(dplyr::ends_with("_z")) %>% summary()]],
  },

  {
    name = "factor 化(水準の順番・ラベルを指定)",
    fields = { F.cols("vars", "factor にする列") },
    body = [=[
purrr::walk({{vars}}, \(v) { cat(v, ":\n"); print(table({{df}}[[v]], useNA = "ifany")) })
{{df}} <- {{df}} %>%
  dplyr::mutate(dplyr::across(all_of({{vars}}), as.factor))
# 水準の順番・ラベルを指定(1列ずつ):
# {{df}} <- {{df}} %>% dplyr::mutate(sex = factor(sex, levels = c(1, 2), labels = c("男性", "女性")))
# 基準カテゴリの変更: forcats::fct_relevel(x, "基準")
# 少ない水準をまとめる: forcats::fct_lump_min(x, min = 10, other_level = "その他")]=],
  },

  {
    name = "値の再コード化(recode / case_when)",
    fields = { F.col("x", "再コード化する列") },
    body = [=[
new_col <- paste0({{x_str}}, "_new")
{{df}} %>% dplyr::count({{x}})
{{df}} <- {{df}} %>%
  dplyr::mutate(!!new_col := dplyr::case_when(
    {{x}} %in% c() ~ "",
    {{x}} %in% c() ~ "",
    .default = NA
  ))
{{df}} %>% dplyr::count({{x}}, .data[[new_col]])]=],
  },

  {
    name = "ワイド → ロング(pivot_longer)",
    fields = { F.cols("ids", "ID列(残す列)"), F.cols("vals", "縦に並べる列") },
    body = [[
d_long <- {{df}} %>%
  dplyr::select(all_of(c({{ids}}, {{vals}}))) %>%
  tidyr::pivot_longer(all_of({{vals}}), names_to = "time", values_to = "value") %>%
  dplyr::mutate(time = factor(time, levels = {{vals}}))
d_long]],
  },

  {
    name = "多重代入法(mice → 回帰 → Rubin のルールで統合)",
    fields = { F.col("y", "目的変数"), F.cols("vars", "説明変数"), F.cols("aux", "補完だけに使う補助変数", { optional = true }) },
    body = [[
d_mi <- {{df}} %>% dplyr::select({{y}}, all_of(unique(c({{vars}}{{#aux}}, {{aux}}{{/aux}}))))
mice::md.pattern(d_mi, rotate.names = TRUE)
naniar::mcar_test(d_mi)                      # Little の MCAR 検定(SPSS の欠損値分析)
imp <- mice::mice(d_mi, m = 20, seed = 1, printFlag = FALSE)
plot(imp)                                    # 収束の確認
fam <- if (dplyr::n_distinct(na.omit(d_mi${{y}})) == 2) binomial else gaussian
fit <- with(imp, glm(reformulate(sprintf("`%s`", {{vars}}), response = {{y_str}}), family = fam))
summary(mice::pool(fit), conf.int = TRUE, exponentiate = identical(fam, binomial))]],
  },

  {
    id = "rename",
    name = "列名変更(rename 雛形, 変更先は空)",
    fields = { F.cols("vars", "変更する列 (Tab=選択 C-a=全選択)") },
    -- 新しい名前 = "旧名"。そのままでも動く(同じ名前)ので、左辺だけ書き換える
    body = '{{df}} <- {{df}} %>%\n  dplyr::rename(\n    旧 = "旧",\n  )', -- プレビュー用
    build = function(_, df, values)
      local A = require("analysis")
      local lines = { ("%s <- %s %%>%%"):format(df, df), "  dplyr::rename(" }
      for _, c in ipairs(values.vars) do
        lines[#lines + 1] = ("    %s = %s,"):format(A.format_cols("r", { c }), A.q(c))
      end
      lines[#lines + 1] = "  )"
      return lines
    end,
  },
}
