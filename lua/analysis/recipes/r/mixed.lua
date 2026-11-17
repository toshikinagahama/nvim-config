-- R / 混合・GEE
local F = require("analysis.recipes.fields")

return {
  lang = "r",
  cat = "混合・GEE",

  {
    name = "線形混合モデル(ランダム切片, lmerTest)",
    fields = { F.col("y", "目的変数"), F.cols("fixed", "固定効果"), F.col("id", "クラスタ・ID") },
    body = [[
d_m <- {{df}} %>% dplyr::select({{y}}, all_of({{fixed}}), {{id}}) %>% tidyr::drop_na()
f <- reformulate(c(sprintf("`%s`", {{fixed}}), sprintf("(1 | `%s`)", {{id_str}})), response = {{y_str}})
m <- lmerTest::lmer(f, data = d_m, REML = TRUE)
summary(m)                                  # Satterthwaite の自由度で p 値
anova(m, type = 3)
performance::icc(m)                         # 級内相関
performance::r2(m)                          # 周辺 R² / 条件付き R²
# ランダム傾き: (1 + time | id)。2値なら lme4::glmer(..., family = binomial)]],
  },

  {
    name = "GEE(一般化推定方程式, 交換可能相関)",
    fields = { F.col("y", "目的変数"), F.cols("vars", "説明変数"), F.col("id", "クラスタ・ID") },
    body = [[
d_m <- {{df}} %>% dplyr::select({{y}}, all_of({{vars}}), {{id}}) %>% tidyr::drop_na() %>% dplyr::arrange({{id}})
fam <- if (dplyr::n_distinct(d_m${{y}}) == 2) binomial else gaussian
m <- geepack::geeglm(reformulate(sprintf("`%s`", {{vars}}), response = {{y_str}}),
                     id = {{id}}, data = d_m, family = fam, corstr = "exchangeable")
summary(m)                                  # ロバスト(サンドイッチ)SE
broom::tidy(m, conf.int = TRUE, exponentiate = identical(fam, binomial))
# corstr: "independence" / "exchangeable" / "ar1"(時系列) / "unstructured"]],
  },
}
