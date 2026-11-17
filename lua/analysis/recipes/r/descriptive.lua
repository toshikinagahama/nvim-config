-- R / 記述
local F = require("analysis.recipes.fields")

return {
  lang = "r",
  cat = "記述",

  {
    name = "正規性の確認(Shapiro-Wilk + Q-Q プロット, 群別)",
    fields = { F.cols("vars", "変数"), F.col("by", "群", { optional = true, fallback = "全体" }) },
    body = [[
d_n <- {{df}}{{^by}} %>% dplyr::mutate(全体 = "全体"){{/by}}
d_n %>%
  dplyr::group_by({{by}}) %>%
  rstatix::shapiro_test(vars = {{vars}}) %>%
  dplyr::mutate(正規 = dplyr::if_else(p >= 0.05, "○", "×"))
d_n %>%
  dplyr::select({{by}}, all_of({{vars}})) %>%
  tidyr::pivot_longer(-{{by}}, names_to = "変数") %>%
  ggplot(aes(sample = value, color = factor({{by}}))) +
  stat_qq(alpha = 0.6) + stat_qq_line() +
  facet_wrap(~変数, scales = "free") +
  labs(color = {{by_str}}) + theme_minimal()
# n が大きいと少しのずれでも p<0.05 になる → Q-Q プロットで判断]],
  },

  {
    name = "多重回答の集計(複数の 0/1 列 → 回答数・%)",
    fields = { F.cols("items", "選択肢の列(0/1)"), F.col("by", "群", { optional = true, fallback = "全体" }) },
    body = [[
mr <- {{df}}{{^by}} %>% dplyr::mutate(全体 = "全体"){{/by}} %>%
  dplyr::select({{by}}, all_of({{items}})) %>%
  tidyr::pivot_longer(all_of({{items}}), names_to = "選択肢", values_to = "選択") %>%
  dplyr::group_by({{by}}, 選択肢) %>%
  dplyr::summarise(回答数 = sum(選択 == 1, na.rm = TRUE), ケース数 = sum(!is.na(選択)), .groups = "drop_last") %>%
  dplyr::mutate(`ケース%` = round(回答数 / ケース数 * 100, 1),
                `回答%` = round(回答数 / sum(回答数) * 100, 1)) %>%
  dplyr::arrange({{by}}, dplyr::desc(回答数))
mr
mr %>%
  ggplot(aes(reorder(選択肢, `ケース%`), `ケース%`, fill = factor({{by}}))) +
  geom_col(position = "dodge") + coord_flip() +
  labs(x = NULL, fill = {{by_str}}) + theme_minimal()]],
  },

  {
    name = "重み付き集計(平均・割合・クロス表, survey)",
    fields = { F.col("w", "重み"), F.cols("vars", "集計する変数"), F.col("by", "群") },
    body = [[
des <- survey::svydesign(ids = ~1, weights = ~{{w}}, data = {{df}})
survey::svymean(reformulate(sprintf("`%s`", {{vars}})), des, na.rm = TRUE)
survey::svyby(reformulate(sprintf("`%s`", {{vars}})), ~{{by}}, des, survey::svymean, na.rm = TRUE)
# 名義変数のクロス表(重み付き件数)+ Rao-Scott カイ二乗:
# survey::svytable(~ 行 + 列, des); survey::svychisq(~ 行 + 列, des)
# gtsummary で表にするなら: gtsummary::tbl_svysummary(des, by = {{by}}, include = all_of({{vars}}))]],
  },
}
