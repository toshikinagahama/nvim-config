-- R / 相関
local F = require("analysis.recipes.fields")

return {
  lang = "r",
  cat = "相関",

  {
    name = "Spearman 相関(変数群 × 変数群)",
    fields = { F.cols("x", "変数群1"), F.cols("y", "変数群2") },
    body = [[
cor_res <- {{df}} %>%
  rstatix::cor_test(vars = {{x}}, vars2 = {{y}}, method = "spearman") %>%
  dplyr::arrange(dplyr::desc(abs(cor)))
cor_res]],
  },

  {
    name = "偏相関(調整変数あり, Spearman)+ヒートマップ",
    fields = { F.cols("x", "変数群1"), F.cols("y", "変数群2"), F.cols("z", "調整する変数(年齢など)") },
    body = [=[
pcor_res <- tidyr::expand_grid(x = {{x}}, y = {{y}}) %>%
  dplyr::filter(x != y) %>%
  purrr::pmap_dfr(\(x, y) {
    d <- tidyr::drop_na({{df}}[, c(x, y, {{z}})])
    r <- ppcor::pcor.test(d[[x]], d[[y]], d[, {{z}}], method = "spearman")
    tibble::tibble(x, y, rho = r$estimate, p = r$p.value, n = nrow(d))
  }) %>%
  dplyr::arrange(dplyr::desc(abs(rho)))

pcor_res %>%
  dplyr::mutate(val = dplyr::if_else(p < 0.05, abs(rho), NA_real_)) %>%
  ggplot(aes(x, y, fill = val)) +
  geom_tile(color = "white") +
  geom_text(aes(label = dplyr::if_else(is.na(val), "-", sprintf("%.2f", val)))) +
  scale_fill_gradient(low = "white", high = "firebrick", limits = c(0, 1), na.value = "grey95", name = "|ρ|") +
  labs(x = NULL, y = NULL) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))]=],
  },
}
