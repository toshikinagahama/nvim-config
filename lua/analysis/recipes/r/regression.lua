-- R / 回帰
local F = require("analysis.recipes.fields")

return {
  lang = "r",
  cat = "回帰",

  {
    name = "ロジスティック回帰: 1変数ずつ(調整なし vs 調整あり, 連続は1SDあたりOR・2値はそのまま)",
    fields = { F.col("outcome", "アウトカム(2値)"), F.cols("vars", "説明変数"), F.cols("adjust", "調整変数") },
    body = [[
# 連続変数(数値で3値以上)だけ z 化 → 1SDあたり OR。0/1・カテゴリはそのまま(1 vs 0 / 参照カテゴリ比の OR)
is_cont <- \(x) is.numeric(x) && dplyr::n_distinct(x, na.rm = TRUE) > 2
d_z <- {{df}} %>% dplyr::mutate(dplyr::across(all_of({{vars}}) & where(is_cont), \(x) structure(as.numeric(scale(x)), label = attr(x, "label"))))  # 変数ラベルは残す
z_vars <- names(dplyr::select(d_z, all_of({{vars}}) & where(is_cont)))
message("1SDあたり: ", paste(z_vars, collapse = ", "))
adj_terms <- paste0("`", {{adjust}}, "`", collapse = " + ")
t_crude <- d_z %>%
  dplyr::select({{outcome}}, all_of({{vars}})) %>%
  tbl_uvregression(method = glm, y = {{outcome}}, method.args = list(family = binomial), exponentiate = TRUE)
t_adj <- d_z %>%
  dplyr::select({{outcome}}, all_of(c({{vars}}, {{adjust}}))) %>%
  tbl_uvregression(method = glm, y = {{outcome}}, include = all_of({{vars}}),
                   formula = paste("{y} ~ {x} +", adj_terms),
                   method.args = list(family = binomial), exponentiate = TRUE)
sd_label <- \(t) modify_table_body(t, \(b) dplyr::mutate(b, label = ifelse(
  variable %in% z_vars & row_type == "label", paste0(label, "(1SDあたり)"), label)))
tbl_merge(list(sd_label(t_crude), sd_label(t_adj)), tab_spanner = c("**調整なし**", "**調整あり**"))]],
  },

  {
    name = "1変数ずつ回帰 tbl_uvregression: ロジスティック(OR, 調整変数を複数選択)",
    fields = {
      F.col("outcome", "アウトカム(2値)"),
      F.cols("vars", "1つずつ回す説明変数"),
      F.cols("adjust", "調整変数(複数可・Tab で選択)", { optional = true }),
      F.yesno("crude", "調整なしの結果も横に並べる?", true),
    },
    body = [=[
uv <- function(d, adjust = character()) {
  tbl_uvregression(d, method = glm, method.args = list(family = binomial), exponentiate = TRUE, y = {{outcome}}, include = all_of({{vars}}),
                   formula = paste(c("{y} ~ {x}", if (length(adjust)) paste0("`", adjust, "`")), collapse = " + "))
}
d_uv <- {{df}} %>% dplyr::select({{outcome}}, all_of(c({{vars}}{{#adjust}}, {{adjust}}{{/adjust}})))
{{#adjust}}t_adj <- uv(d_uv, {{adjust}})  # 表には各説明変数の行だけ出る(調整変数の行は出ない)
{{#crude}}t_crude <- uv(d_uv)
tbl_merge(list(t_crude, t_adj), tab_spanner = c("**調整なし**", "**調整あり**"))
{{/crude}}{{^crude}}t_adj
{{/crude}}{{/adjust}}{{^adjust}}uv(d_uv)
{{/adjust}}]=],
  },

  {
    name = "1変数ずつ回帰 tbl_uvregression: 線形(β, 調整変数を複数選択)",
    fields = {
      F.col("outcome", "アウトカム(連続)"),
      F.cols("vars", "1つずつ回す説明変数"),
      F.cols("adjust", "調整変数(複数可・Tab で選択)", { optional = true }),
      F.yesno("crude", "調整なしの結果も横に並べる?", true),
    },
    body = [=[
uv <- function(d, adjust = character()) {
  tbl_uvregression(d, method = lm, y = {{outcome}}, include = all_of({{vars}}),
                   formula = paste(c("{y} ~ {x}", if (length(adjust)) paste0("`", adjust, "`")), collapse = " + "))
}
d_uv <- {{df}} %>% dplyr::select({{outcome}}, all_of(c({{vars}}{{#adjust}}, {{adjust}}{{/adjust}})))
{{#adjust}}t_adj <- uv(d_uv, {{adjust}})  # 表には各説明変数の行だけ出る(調整変数の行は出ない)
{{#crude}}t_crude <- uv(d_uv)
tbl_merge(list(t_crude, t_adj), tab_spanner = c("**調整なし**", "**調整あり**"))
{{/crude}}{{^crude}}t_adj
{{/crude}}{{/adjust}}{{^adjust}}uv(d_uv)
{{/adjust}}]=],
  },

  {
    name = "多変量ロジスティック回帰+VIF+ROC/AUC",
    fields = { F.col("outcome", "アウトカム(2値)"), F.cols("vars", "説明変数"), F.cols("adjust", "調整変数(ベースモデル)") },
    body = [[
d_m <- {{df}} %>% dplyr::select({{outcome}}, all_of(c({{vars}}, {{adjust}}))) %>% tidyr::drop_na()
m0 <- glm(reformulate(paste0("`", {{adjust}}, "`"), response = {{outcome_str}}), family = binomial, data = d_m)
m_all <- glm(reformulate(".", response = {{outcome_str}}), family = binomial, data = d_m)
tbl_regression(m_all, exponentiate = TRUE)
car::vif(m_all)
anova(m0, m_all, test = "LRT")  # ベースモデルへの上乗せ

roc_all <- pROC::roc(m_all$y, fitted(m_all), quiet = TRUE)
ci <- pROC::ci.auc(roc_all)
pROC::ggroc(roc_all, legacy.axes = TRUE) +
  geom_abline(linetype = 2, color = "grey60") +
  annotate("text", x = 0.5, y = 0.15, hjust = 0,
           label = sprintf("AUC = %.2f\n(95%%CI %.2f-%.2f)", ci[2], ci[1], ci[3])) +
  labs(x = "1 - 特異度", y = "感度") + coord_equal() + theme_minimal()]],
  },

  {
    name = "交互作用(ロジスティック): 交互作用p + 層別OR",
    fields = { F.col("outcome", "アウトカム(2値)"), F.col("exposure", "曝露(主な説明変数)"), F.col("modifier", "効果修飾因子(性別など)"), F.cols("adjust", "調整変数") },
    body = [[
adj <- setdiff({{adjust}}, c({{exposure_str}}, {{modifier_str}}))  # 曝露・修飾因子と重なる調整変数は外す
d_i <- {{df}} %>%
  dplyr::select({{outcome}}, {{exposure}}, {{modifier}}, all_of(adj)) %>%
  tidyr::drop_na()
bt <- \(x) paste0("`", x, "`")
terms0 <- bt(c({{exposure_str}}, {{modifier_str}}, adj))
m0 <- glm(reformulate(terms0, response = {{outcome_str}}), family = binomial, data = d_i)
m1 <- glm(reformulate(c(terms0, paste0(terms0[1], ":", terms0[2])), response = {{outcome_str}}),
          family = binomial, data = d_i)
anova(m0, m1, test = "LRT")  # 交互作用の p 値

# 効果修飾因子の層ごとの OR
d_i %>%
  dplyr::group_by({{modifier}}) %>%
  dplyr::group_modify(\(d, key) {
    m <- glm(reformulate(bt(c({{exposure_str}}, adj)), response = {{outcome_str}}), family = binomial, data = d)
    broom::tidy(m, exponentiate = TRUE, conf.int = TRUE) %>%
      dplyr::filter(startsWith(term, {{exposure_str}}) | startsWith(term, bt({{exposure_str}}))) %>%
      dplyr::mutate(n = nrow(d))
  }) %>%
  dplyr::mutate(`OR (95%CI)` = sprintf("%.2f (%.2f-%.2f)", estimate, conf.low, conf.high))]],
  },

  {
    name = "線形回帰+VIF+残差プロット",
    fields = { F.col("y", "目的変数"), F.cols("vars", "説明変数") },
    body = [[
d_m <- {{df}} %>% dplyr::select({{y}}, all_of({{vars}})) %>% tidyr::drop_na()
m <- lm(reformulate(sprintf("`%s`", {{vars}}), response = {{y_str}}), data = d_m)
tbl_regression(m) %>% add_glance_source_note(include = c(r.squared, adj.r.squared, nobs))
lm.beta::lm.beta(m) %>% summary()      # 標準化係数 β(SPSS の「標準化係数」)
car::vif(m)
par(mfrow = c(2, 2)); plot(m); par(mfrow = c(1, 1))]],
  },

  {
    name = "ステップワイズ変数選択(AIC, 前進・後退)",
    fields = { F.col("y", "目的変数"), F.cols("vars", "候補の説明変数") },
    body = [[
d_m <- {{df}} %>% dplyr::select({{y}}, all_of({{vars}})) %>% tidyr::drop_na()
fam <- if (dplyr::n_distinct(d_m${{y}}) == 2) binomial else gaussian   # 2値ならロジスティック
m_full <- glm(reformulate(sprintf("`%s`", {{vars}}), response = {{y_str}}), family = fam, data = d_m)
m_null <- glm(reformulate("1", response = {{y_str}}), family = fam, data = d_m)
m_step <- MASS::stepAIC(m_null, scope = list(lower = m_null, upper = m_full), direction = "both", trace = 1)
summary(m_step)
tbl_regression(m_step, exponentiate = identical(fam, binomial))
# 注意: ステップワイズの p 値・CI は楽観的。探索目的と明記する]],
  },

  {
    name = "ポアソン / 負の二項回帰(件数, IRR)",
    fields = { F.col("y", "件数(目的変数)"), F.cols("vars", "説明変数"), F.col("offset", "観察期間・人年(offset)", { optional = true }) },
    body = [[
d_m <- {{df}} %>% dplyr::select({{y}}, all_of({{vars}}){{#offset}}, {{offset}}{{/offset}}) %>% tidyr::drop_na()
f <- reformulate(c(sprintf("`%s`", {{vars}}){{#offset}}, sprintf("offset(log(`%s`))", {{offset_str}}){{/offset}}), response = {{y_str}})
m_p <- glm(f, family = poisson, data = d_m)
disp <- sum(residuals(m_p, type = "pearson")^2) / m_p$df.residual
cat("過分散の指標 =", round(disp, 2), "(1 を大きく超えるなら負の二項)\n")
m_nb <- MASS::glm.nb(f, data = d_m)
AIC(m_p, m_nb)
tbl_regression(m_nb, exponentiate = TRUE)   # IRR(発生率比)]],
  },

  {
    name = "多項ロジスティック回帰(3カテゴリ以上, RRR)",
    fields = { F.col("y", "目的変数(名義)"), F.cols("vars", "説明変数") },
    body = [[
d_m <- {{df}} %>% dplyr::select({{y}}, all_of({{vars}})) %>% tidyr::drop_na() %>% dplyr::mutate({{y}} = factor({{y}}))
# 基準カテゴリを変えるなら: d_m${{y}} <- relevel(d_m${{y}}, ref = "基準")
m <- nnet::multinom(reformulate(sprintf("`%s`", {{vars}}), response = {{y_str}}), data = d_m, trace = FALSE)
tbl_regression(m, exponentiate = TRUE)
car::Anova(m)                               # 変数ごとの尤度比検定]],
  },

  {
    name = "順序ロジスティック回帰(比例オッズ, OR)",
    fields = { F.col("y", "目的変数(順序)"), F.cols("vars", "説明変数") },
    body = [[
d_m <- {{df}} %>% dplyr::select({{y}}, all_of({{vars}})) %>% tidyr::drop_na() %>%
  dplyr::mutate({{y}} = factor({{y}}, ordered = TRUE))   # 水準の順番を確認: levels(d_m${{y}})
m <- MASS::polr(reformulate(sprintf("`%s`", {{vars}}), response = {{y_str}}), data = d_m, Hess = TRUE)
tbl_regression(m, exponentiate = TRUE)
brant::brant(m)                             # 比例オッズ性の検定(p<0.05 の変数は仮定違反)]],
  },
}
