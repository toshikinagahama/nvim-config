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

  -- 表(gt)で出す版
  {
    name = "[ペア] 対応のある検定(wide: 前の列 × 後の列, 対応t + Wilcoxon → gt)",
    fields = {
      { key = "pre", kind = "cols", title = "前(1回目)の列 ※後と同じ順で" },
      { key = "post", kind = "cols", title = "後(2回目)の列 ※前と同じ順で" },
    },
    body = [=[
stat <- "mean"  # "median" で 中央値 [IQR] 表示
fmt_p <- \(p) dplyr::if_else(p < 0.001, "<0.001", sprintf("%.3f", p))
desc <- \(x) if (stat == "mean") sprintf("%.2f ± %.2f", mean(x), sd(x)) else
  sprintf("%.2f [%.2f, %.2f]", median(x), quantile(x, 0.25), quantile(x, 0.75))
stopifnot(length({{pre}}) == length({{post}}))
paired_res <- purrr::map2_dfr({{pre}}, {{post}}, \(a, b) {
  d <- tidyr::drop_na({{df}}[, c(a, b)])  # 両方そろった人だけ
  x <- d[[a]]; y <- d[[b]]; dif <- y - x
  tt <- t.test(y, x, paired = TRUE)
  tibble::tibble(
    変数 = paste(a, "→", b), n = nrow(d),
    前 = desc(x), 後 = desc(y),
    `差(後−前) [95%CI]` = sprintf("%.2f [%.2f, %.2f]", mean(dif), tt$conf.int[1], tt$conf.int[2]),
    `効果量 dz` = mean(dif) / sd(dif),
    `対応t p` = tt$p.value,
    `Wilcoxon p` = wilcox.test(y, x, paired = TRUE, exact = FALSE)$p.value
  )
})
paired_res %>%
  gt::gt() %>%
  gt::fmt_number(`効果量 dz`, decimals = 2) %>%
  gt::fmt(c(`対応t p`, `Wilcoxon p`), fns = fmt_p) %>%
  gt::tab_style(gt::cell_text(weight = "bold"),
                gt::cells_body(columns = `Wilcoxon p`, rows = `Wilcoxon p` < 0.05)) %>%
  gt::tab_footnote(if (stat == "mean") "平均 ± SD" else "中央値 [IQR]")]=],
  },
  {
    name = "[ペア] 対応のある検定(long: ID × 時点の列, 2時点, 対応t + Wilcoxon → gt)",
    fields = {
      { key = "id", kind = "col", title = "ID(人)" },
      { key = "time", kind = "col", title = "時点(2水準: 前/後)" },
      { key = "vars", kind = "cols", title = "比較する変数" },
    },
    body = [=[
stat <- "mean"  # "median" で 中央値 [IQR] 表示
fmt_p <- \(p) dplyr::if_else(p < 0.001, "<0.001", sprintf("%.3f", p))
desc <- \(x) if (stat == "mean") sprintf("%.2f ± %.2f", mean(x), sd(x)) else
  sprintf("%.2f [%.2f, %.2f]", median(x), quantile(x, 0.25), quantile(x, 0.75))
tp <- {{df}}[[{{time_str}}]]
tp <- if (is.factor(tp)) levels(droplevels(tp)) else unique(as.character(na.omit(tp)))  # 出てきた順。変えるなら c("pre", "post")
if (length(tp) > 2) {  # 3時点以上 → 最初と最後を比べる(別の組なら上の行で tp <- c("pre", "mid") のように指定)
  message("3時点以上なので ", tp[1], " vs ", tp[length(tp)], " を比較")
  tp <- tp[c(1, length(tp))]
}
stopifnot(length(tp) == 2)
paired_res <- purrr::map_dfr({{vars}}, \(v) {
  w <- {{df}} %>%
    dplyr::select({{id}}, {{time}}, value = dplyr::all_of(v)) %>%
    tidyr::pivot_wider(names_from = {{time}}, values_from = value) %>%
    tidyr::drop_na(dplyr::all_of(tp))
  x <- w[[tp[1]]]; y <- w[[tp[2]]]; dif <- y - x
  tt <- t.test(y, x, paired = TRUE)
  tibble::tibble(
    変数 = v, n = nrow(w),
    !!tp[1] := desc(x), !!tp[2] := desc(y),
    `差 [95%CI]` = sprintf("%.2f [%.2f, %.2f]", mean(dif), tt$conf.int[1], tt$conf.int[2]),
    `効果量 dz` = mean(dif) / sd(dif),
    `対応t p` = tt$p.value,
    `Wilcoxon p` = wilcox.test(y, x, paired = TRUE, exact = FALSE)$p.value
  )
})
paired_res %>%
  gt::gt() %>%
  gt::fmt_number(`効果量 dz`, decimals = 2) %>%
  gt::fmt(c(`対応t p`, `Wilcoxon p`), fns = fmt_p) %>%
  gt::tab_style(gt::cell_text(weight = "bold"),
                gt::cells_body(columns = `Wilcoxon p`, rows = `Wilcoxon p` < 0.05)) %>%
  gt::tab_footnote(paste0(if (stat == "mean") "平均 ± SD" else "中央値 [IQR]", "、差 = ", tp[2], " − ", tp[1]))]=],
  },
  {
    name = "[ペア] 対応のある2値(McNemar, wide: 前の列 × 後の列 → gt)",
    fields = {
      { key = "pre", kind = "cols", title = "前(1回目)の2値列 ※後と同じ順で" },
      { key = "post", kind = "cols", title = "後(2回目)の2値列 ※前と同じ順で" },
    },
    body = [=[
fmt_p <- \(p) dplyr::if_else(p < 0.001, "<0.001", sprintf("%.3f", p))
stopifnot(length({{pre}}) == length({{post}}))
mcn_res <- purrr::map2_dfr({{pre}}, {{post}}, \(a, b) {
  d <- tidyr::drop_na({{df}}[, c(a, b)])
  lv <- sort(unique(c(as.character(d[[a]]), as.character(d[[b]]))))
  stopifnot(length(lv) == 2)  # 2値のみ(Yes/No, 0/1 など)
  tab <- table(factor(d[[a]], lv), factor(d[[b]], lv))
  tibble::tibble(
    変数 = paste(a, "→", b), 水準 = lv[2], n = nrow(d),
    `前 n (%)` = sprintf("%d (%.1f%%)", tab[2, 1] + tab[2, 2], (tab[2, 1] + tab[2, 2]) / nrow(d) * 100),
    `後 n (%)` = sprintf("%d (%.1f%%)", tab[1, 2] + tab[2, 2], (tab[1, 2] + tab[2, 2]) / nrow(d) * 100),
    `なし→あり` = tab[1, 2], `あり→なし` = tab[2, 1],
    `McNemar p` = mcnemar.test(tab)$p.value
  )
})
mcn_res %>%
  gt::gt() %>%
  gt::fmt(`McNemar p`, fns = fmt_p) %>%
  gt::tab_footnote("あり = 水準の列の値(2値の後ろ側)")]=],
  },
}
