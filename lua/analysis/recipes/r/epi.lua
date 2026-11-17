-- R / 疫学
local F = require("analysis.recipes.fields")

return {
  lang = "r",
  cat = "疫学",

  {
    name = "有病率+95%CI(全体・群別, Wilson法)",
    fields = { F.col("outcome", "該当/非該当の列(例: サルコペニア肥満)"), F.col("by", "群") },
    body = [[
pos <- 1  # 「該当」を表す値。factor/文字なら "あり" 等に変更
wilson <- function(k, n, conf = 0.95) {
  z <- qnorm(1 - (1 - conf) / 2)
  p <- k / n
  ctr <- (p + z^2 / (2 * n)) / (1 + z^2 / n)
  h <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / (1 + z^2 / n)
  c(ctr - h, ctr + h)
}
prev_tab <- dplyr::bind_rows(
  {{df}} %>% dplyr::mutate(.grp = "全体"),
  {{df}} %>% dplyr::mutate(.grp = as.character({{by}}))
) %>%
  dplyr::filter(!is.na({{outcome}}), !is.na(.grp)) %>%
  dplyr::group_by(.grp) %>%
  dplyr::summarise(n = dplyr::n(), k = sum({{outcome}} == pos), .groups = "drop") %>%
  dplyr::arrange(.grp != "全体") %>%
  dplyr::mutate(
    prev = k / n,
    lo = purrr::map2_dbl(k, n, \(k, n) wilson(k, n)[1]),
    hi = purrr::map2_dbl(k, n, \(k, n) wilson(k, n)[2]),
    `有病率 (95%CI)` = sprintf("%.1f%% (%.1f-%.1f)", 100 * prev, 100 * lo, 100 * hi)
  )
prev_tab
# 群間差(カイ二乗検定)
with(dplyr::filter({{df}}, !is.na({{outcome}}), !is.na({{by}})), chisq.test(table({{by}}, {{outcome}} == pos)))

prev_tab %>%
  ggplot(aes(forcats::fct_inorder(.grp), 100 * prev)) +
  geom_pointrange(aes(ymin = 100 * lo, ymax = 100 * hi)) +
  labs(x = NULL, y = "有病率 (%)") +
  theme_minimal()]],
  },

  {
    name = "年齢調整有病率(直接法)",
    fields = { F.col("outcome", "該当/非該当の列"), F.col("age", "年齢"), F.col("by", "比較する群(性別・地域など)") },
    body = [[
pos <- 1                                      # 「該当」を表す値
age_breaks <- c(-Inf, 39, 49, 59, 69, Inf)    # 年齢階級(右端を含む)
d_a <- {{df}} %>%
  dplyr::filter(!is.na({{outcome}}), !is.na({{age}}), !is.na({{by}})) %>%
  dplyr::mutate(age_grp = cut({{age}}, age_breaks), event = {{outcome}} == pos)
# 標準人口: 既定は全対象者の年齢構成。モデル人口を使うなら std を差し替え(age_grp と w の2列, w の合計 = 1)
std <- d_a %>% dplyr::count(age_grp, name = "N") %>% dplyr::mutate(w = N / sum(N))
d_a %>%
  dplyr::group_by({{by}}, age_grp) %>%
  dplyr::summarise(n_i = dplyr::n(), k_i = sum(event), .groups = "drop") %>%
  dplyr::left_join(std, by = "age_grp") %>%
  dplyr::mutate(p_i = k_i / n_i) %>%
  dplyr::group_by({{by}}) %>%
  # 注意: ある群で 0 人の年齢階級があると、その階級分が抜けて過小評価になる
  dplyr::summarise(
    n = sum(n_i),
    crude = sum(k_i) / sum(n_i),
    adj = sum(w * p_i),
    se = sqrt(sum(w^2 * p_i * (1 - p_i) / n_i)),
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    `粗有病率` = sprintf("%.1f%%", 100 * crude),
    `年齢調整有病率 (95%CI)` = sprintf("%.1f%% (%.1f-%.1f)", 100 * adj, 100 * (adj - 1.96 * se), 100 * (adj + 1.96 * se))
  )]],
  },
}
