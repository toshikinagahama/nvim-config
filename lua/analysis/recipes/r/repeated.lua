-- R / 反復測定
local F = require("analysis.recipes.fields")

return {
  lang = "r",
  cat = "反復測定",

  {
    name = "反復測定分散分析(球面性 + GG 補正 + 多重比較)",
    fields = { F.col("id", "ID"), F.cols("vals", "各時点の列(ワイド)") },
    body = [[
d_long <- {{df}} %>%
  dplyr::select({{id}}, all_of({{vals}})) %>%
  tidyr::drop_na() %>%
  tidyr::pivot_longer(all_of({{vals}}), names_to = "time", values_to = "value") %>%
  dplyr::mutate(time = factor(time, levels = {{vals}}), {{id}} = factor({{id}}))
d_long %>% dplyr::group_by(time) %>% rstatix::get_summary_stats(value, type = "mean_sd")
res <- rstatix::anova_test(d_long, dv = value, wid = {{id}}, within = time, effect.size = "pes")
res                                    # Mauchly の球面性検定・GG/HF 補正つき
rstatix::get_anova_table(res, correction = "GG")
d_long %>% rstatix::pairwise_t_test(value ~ time, paired = TRUE, p.adjust.method = "bonferroni")
# 群(被験者間要因)も入れるなら: anova_test(..., between = group)]],
  },

  {
    name = "Friedman 検定 → 多重比較(Wilcoxon, Bonferroni)",
    fields = { F.col("id", "ID"), F.cols("vals", "各時点の列(ワイド)") },
    body = [[
d_long <- {{df}} %>%
  dplyr::select({{id}}, all_of({{vals}})) %>%
  tidyr::drop_na() %>%
  tidyr::pivot_longer(all_of({{vals}}), names_to = "time", values_to = "value") %>%
  dplyr::mutate(time = factor(time, levels = {{vals}}), {{id}} = factor({{id}}))
d_long %>% dplyr::group_by(time) %>% rstatix::get_summary_stats(value, type = "median_iqr")
d_long %>% rstatix::friedman_test(value ~ time | {{id}})
d_long %>% rstatix::friedman_effsize(value ~ time | {{id}})    # Kendall の W
d_long %>% rstatix::wilcox_test(value ~ time, paired = TRUE, p.adjust.method = "bonferroni")]],
  },

  {
    name = "McNemar / Cochran の Q(対応のある 2値)",
    fields = { F.col("id", "ID"), F.cols("vals", "各時点の 2値列(2つ→McNemar, 3つ以上→Q)") },
    body = [=[
d_b <- {{df}} %>% dplyr::select({{id}}, all_of({{vals}})) %>% tidyr::drop_na()
if (length({{vals}}) == 2) {
  tab <- table(d_b[[{{vals}}[1]]], d_b[[{{vals}}[2]]], dnn = {{vals}})
  print(tab)
  print(mcnemar.test(tab))                 # n が小さいなら exact2x2::mcnemar.exact(tab)
} else {
  d_long <- d_b %>%
    tidyr::pivot_longer(all_of({{vals}}), names_to = "time", values_to = "value") %>%
    dplyr::mutate(time = factor(time, levels = {{vals}}), {{id}} = factor({{id}}))
  print(d_long %>% dplyr::group_by(time) %>% dplyr::summarise(割合 = mean(value == 1)))
  print(d_long %>% rstatix::cochran_qtest(value ~ time | {{id}}))
  print(d_long %>% rstatix::pairwise_mcnemar_test(value ~ time | {{id}}, p.adjust.method = "bonferroni"))
}]=],
  },

  {
    name = "対応のある比較(前後: paired t / Wilcoxon)",
    fields = { F.col("before", "前(1回目)"), F.col("after", "後(2回目)") },
    body = [[
d_p <- {{df}} %>% dplyr::select({{before}}, {{after}}) %>% tidyr::drop_na()
diff <- d_p${{after}} - d_p${{before}}
cat(sprintf("n=%d, 差の平均=%.3f (SD %.3f), 差の中央値=%.3f\n", nrow(d_p), mean(diff), sd(diff), median(diff)))
t.test(d_p${{after}}, d_p${{before}}, paired = TRUE)
wilcox.test(d_p${{after}}, d_p${{before}}, paired = TRUE, exact = FALSE)
cat("効果量 dz =", round(mean(diff) / sd(diff), 3), "\n")]],
  },
}
