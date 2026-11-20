-- R / 図
local F = require("analysis.recipes.fields")

return {
  lang = "r",
  cat = "図",

  {
    name = "分布(ヒストグラム, 変数ごとに facet)",
    fields = { F.cols("vars", "変数") },
    body = [[
{{df}} %>%
  dplyr::select(all_of({{vars}})) %>%
  tidyr::pivot_longer(everything()) %>%
  ggplot(aes(value)) +
  geom_histogram(bins = 30, fill = "grey60", color = "white") +
  facet_wrap(~name, scales = "free") +
  theme_minimal()]],
  },

  {
    name = "群別の箱ひげ図(変数ごとに facet)",
    fields = { F.cols("vars", "変数"), F.col("by", "群") },
    body = [[
{{df}} %>%
  dplyr::select(all_of({{vars}}), {{by}}) %>%
  tidyr::pivot_longer(-{{by}}) %>%
  ggplot(aes(factor({{by}}), value)) +
  geom_boxplot(outlier.shape = NA) +
  geom_jitter(width = 0.15, alpha = 0.3, size = 0.8) +
  facet_wrap(~name, scales = "free_y") +
  labs(x = NULL) +
  theme_minimal()]],
  },

  {
    name = "散布図+回帰直線(詳細: 色分け / 式・R² / 95%CI / y=x)",
    fields = {
      F.col("x", "x"),
      F.col("y", "y"),
      F.col("by", "色分け(性別など)", { optional = true }),
      F.yesno("eq", "回帰式+R² を入れる?", true),
      F.yesno("ci", "95%CI の帯を入れる?", true),
      F.yesno("idl", "y = x の線を入れる?(入れると縦横比 1:1)", false),
    },
    body = [=[
d <- {{df}}{{#by}} %>% dplyr::mutate(.grp = factor({{by}})){{/by}}
fit <- lm({{y}} ~ {{x}}, data = d)
pos <- if (isTRUE(coef(fit)[2] >= 0)) "left" else "right"  # 式の位置: 右上がり→左上 / 右下がり→右上
{{#idl}}lims <- range(c(d[[{{x_str}}]], d[[{{y_str}}]]), na.rm = TRUE)
{{/idl}}ggplot(d, aes({{x}}, {{y}}{{#by}}, color = .grp, fill = .grp{{/by}})) +
  geom_point(alpha = 0.6, size = 1.5) +
  geom_smooth(method = "lm", formula = y ~ x, se = {{#ci}}TRUE{{/ci}}{{^ci}}FALSE{{/ci}}, level = 0.95) +
{{#eq}}  ggpmisc::stat_poly_eq(ggpmisc::use_label(c("eq", "R2")), formula = y ~ x,
                         label.x = pos, label.y = "top", size = 3.5) +  # 群ごとに縦に並ぶ
{{/eq}}{{#idl}}  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey50") +
  coord_equal(xlim = lims, ylim = lims) +  # y = x と縦横比 1:1
{{/idl}}{{#by}}  labs(color = {{by_str}}, fill = {{by_str}}) +
{{/by}}  theme_minimal()]=],
  },

  {
    name = "散布図+回帰直線",
    fields = { F.col("x", "x"), F.col("y", "y") },
    body = [[
ggplot({{df}}, aes({{x}}, {{y}})) +
  geom_point(alpha = 0.5) +
  geom_smooth(method = "lm") +
  theme_minimal()]],
  },
}
