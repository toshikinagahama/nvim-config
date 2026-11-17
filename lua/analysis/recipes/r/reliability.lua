-- R / 信頼性
local F = require("analysis.recipes.fields")

return {
  lang = "r",
  cat = "信頼性",

  {
    name = "信頼性分析(Cronbach の α・項目削除時の α・ω)",
    fields = { F.cols("items", "尺度の項目") },
    body = [[
d_i <- {{df}} %>% dplyr::select(all_of({{items}})) %>% tidyr::drop_na()
a <- psych::alpha(d_i, check.keys = TRUE)    # 逆転項目は自動で反転(警告を確認)
a$total                                      # raw_alpha / std.alpha
a$alpha.drop                                 # 項目を削除したときの α
a$item.stats[, c("r.drop", "mean", "sd")]    # 修正済み項目-合計相関
psych::omega(d_i, nfactors = 1, plot = FALSE)$omega.tot]],
  },
}
