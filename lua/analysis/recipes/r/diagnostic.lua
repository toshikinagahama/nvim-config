-- R / 診断・一致
local F = require("analysis.recipes.fields")

return {
  lang = "r",
  cat = "診断・一致",

  {
    name = "カットオフ探索(ROC + Youden, 感度・特異度)",
    fields = { F.col("outcome", "アウトカム(2値)"), F.col("marker", "指標(連続)") },
    body = [=[
roc_c <- pROC::roc({{df}}[[{{outcome_str}}]], {{df}}[[{{marker_str}}]], quiet = TRUE)
ci_c <- pROC::ci.auc(roc_c)
best <- pROC::coords(roc_c, "best", best.method = "youden", transpose = FALSE,
                     ret = c("threshold", "sensitivity", "specificity", "ppv", "npv", "youden"))
best
sprintf("AUC = %.2f (95%%CI %.2f-%.2f), 方向: %s", ci_c[2], ci_c[1], ci_c[3], roc_c$direction)

pROC::ggroc(roc_c, legacy.axes = TRUE) +
  geom_abline(linetype = 2, color = "grey60") +
  geom_point(data = best, aes(1 - specificity, sensitivity), color = "firebrick", size = 2) +
  annotate("text", x = 1 - best$specificity[1] + 0.03, y = best$sensitivity[1] - 0.05, hjust = 0,
           label = sprintf("cutoff = %.2f\n感度 %.2f / 特異度 %.2f", best$threshold[1], best$sensitivity[1], best$specificity[1])) +
  labs(x = "1 - 特異度", y = "感度") + coord_equal() + theme_minimal()]=],
  },

  {
    name = "2つの測定の一致度(ICC + Bland-Altman)",
    fields = { F.col("x", "測定1(例: BIA)"), F.col("y", "測定2(例: DXA)") },
    body = [[
d_ag <- {{df}} %>% dplyr::select({{x}}, {{y}}) %>% tidyr::drop_na()
# ICC(2,1) 絶対一致。要 install.packages("irr")
irr::icc(d_ag, model = "twoway", type = "agreement", unit = "single")

ba <- d_ag %>% dplyr::transmute(m = ({{x}} + {{y}}) / 2, d = {{x}} - {{y}})
bias <- mean(ba$d)
loa <- bias + c(-1.96, 1.96) * sd(ba$d)
cor.test(ba$m, ba$d)  # 有意なら比例誤差(大きいほど差が開く)
ggplot(ba, aes(m, d)) +
  geom_point(alpha = 0.4) +
  geom_hline(yintercept = bias) +
  geom_hline(yintercept = loa, linetype = 2) +
  geom_smooth(method = "lm", se = FALSE, color = "grey50", linewidth = 0.5) +
  labs(x = "2測定の平均", y = sprintf("差 (%s − %s)", {{x_str}}, {{y_str}}),
       subtitle = sprintf("bias = %.2f, LoA = %.2f 〜 %.2f", bias, loa[1], loa[2])) +
  theme_minimal()]],
  },
}
