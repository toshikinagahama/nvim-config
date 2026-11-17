-- R / 群比較
local F = require("analysis.recipes.fields")

return {
  lang = "r",
  cat = "群比較",

  {
    name = "群比較表(gtsummary, 中央値[IQR]+p値)",
    fields = { F.cols("vars", "比較する変数"), F.col("by", "群(by)") },
    body = [[
{{df}} %>%
  dplyr::select(all_of({{vars}}), {{by}}) %>%
  tbl_summary(
    by = {{by}},
    type = list(where(is.numeric) ~ "continuous", all_dichotomous() ~ "categorical"),
    statistic = all_continuous() ~ "{median} ({p25}, {p75})",
    missing = "no"
  ) %>%
  add_n() %>%
  add_p()]],
  },

  {
    name = "層別の群比較表(tbl_strata)",
    fields = { F.cols("vars", "比較する変数"), F.col("by", "群(by)"), F.col("strata", "層(strata)") },
    body = [[
{{df}} %>%
  dplyr::select(all_of({{vars}}), {{by}}, {{strata}}) %>%
  tbl_strata(
    strata = {{strata}},
    .tbl_fun = ~ .x %>%
      tbl_summary(by = {{by}}, type = list(where(is.numeric) ~ "continuous", all_dichotomous() ~ "categorical"),
                  statistic = all_continuous() ~ "{median} ({p25}, {p75})", missing = "no") %>%
      add_p()
  )]],
  },

  {
    name = "3群以上の比較(Kruskal-Wallis → Dunn, Bonferroni)",
    fields = { F.cols("vars", "比較する変数(数値)"), F.col("by", "群") },
    body = [[
kw_long <- {{df}} %>%
  dplyr::select(all_of({{vars}}), {{by}}) %>%
  dplyr::filter(!is.na({{by}})) %>%
  dplyr::mutate(.g = factor({{by}})) %>%
  tidyr::pivot_longer(all_of({{vars}}), names_to = "variable") %>%
  dplyr::group_by(variable)
kw_long %>% rstatix::kruskal_test(value ~ .g)
kw_long %>% rstatix::kruskal_effsize(value ~ .g)
kw_long %>% rstatix::dunn_test(value ~ .g, p.adjust.method = "bonferroni")]],
  },

  {
    name = "一元配置分散分析(ANOVA)+ Tukey / Games-Howell",
    fields = { F.col("y", "目的変数"), F.col("g", "群") },
    body = [[
d_a <- {{df}} %>% dplyr::select({{y}}, {{g}}) %>% tidyr::drop_na() %>% dplyr::mutate({{g}} = factor({{g}}))
d_a %>% dplyr::group_by({{g}}) %>% rstatix::get_summary_stats({{y}}, type = "mean_sd")
car::leveneTest({{y}} ~ {{g}}, data = d_a)        # 等分散性(p<0.05 なら Welch + Games-Howell)
d_a %>% rstatix::anova_test({{y}} ~ {{g}}, effect.size = "pes")
d_a %>% rstatix::welch_anova_test({{y}} ~ {{g}})
d_a %>% rstatix::tukey_hsd({{y}} ~ {{g}})
d_a %>% rstatix::games_howell_test({{y}} ~ {{g}})]],
  },

  {
    name = "二元配置分散分析(主効果+交互作用, Type III)",
    fields = { F.col("y", "目的変数"), F.col("a", "要因A"), F.col("b", "要因B") },
    body = [[
d_a <- {{df}} %>% dplyr::select({{y}}, {{a}}, {{b}}) %>% tidyr::drop_na() %>%
  dplyr::mutate({{a}} = factor({{a}}), {{b}} = factor({{b}}))
m <- lm({{y}} ~ {{a}} * {{b}}, data = d_a, contrasts = list({{a}} = contr.sum, {{b}} = contr.sum))
car::Anova(m, type = 3)                            # SPSS の既定(Type III 平方和)と一致
emmeans::emmeans(m, ~ {{a}} | {{b}}) %>% pairs(adjust = "bonferroni")   # 単純主効果
emmeans::emmip(m, {{b}} ~ {{a}}, CIs = TRUE) + theme_minimal()            # 交互作用プロット]],
  },

  {
    name = "共分散分析(ANCOVA, 調整済み平均)",
    fields = { F.col("y", "目的変数"), F.col("g", "群"), F.cols("cov", "共変量") },
    body = [[
d_a <- {{df}} %>% dplyr::select({{y}}, {{g}}, all_of({{cov}})) %>% tidyr::drop_na() %>% dplyr::mutate({{g}} = factor({{g}}))
f <- reformulate(c(sprintf("`%s`", {{cov}}), {{g_str}}), response = {{y_str}})
m <- lm(f, data = d_a, contrasts = list({{g}} = contr.sum))
car::Anova(m, type = 3)
emmeans::emmeans(m, ~ {{g}})                                   # 共変量で調整した平均
emmeans::emmeans(m, pairwise ~ {{g}}, adjust = "bonferroni")$contrasts
# 回帰の平行性(群 × 共変量 の交互作用が無いこと)の確認:
car::Anova(lm(reformulate(c(sprintf("`%s` * `%s`", {{g_str}}, {{cov}})), response = {{y_str}}), data = d_a), type = 3)]],
  },
}
