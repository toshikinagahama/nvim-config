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
    name = "散布図+回帰直線",
    fields = { F.col("x", "x"), F.col("y", "y") },
    body = [[
ggplot({{df}}, aes({{x}}, {{y}})) +
  geom_point(alpha = 0.5) +
  geom_smooth(method = "lm") +
  theme_minimal()]],
  },
}
