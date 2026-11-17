-- R / 検出力
local F = require("analysis.recipes.fields")

return {
  lang = "r",
  cat = "検出力",

  {
    name = "サンプルサイズ・検出力(t検定 / 割合 / 相関 / ANOVA / カイ二乗)",
    fields = {  },
    body = [[
# 求めたいもの(n か power)を NULL にする。d・h・r・f・w は効果量
pwr::pwr.t.test(d = 0.5, sig.level = 0.05, power = 0.8, type = "two.sample")       # 2群の平均
pwr::pwr.t.test(d = 0.5, sig.level = 0.05, power = 0.8, type = "paired")           # 対応あり
pwr::pwr.2p.test(h = pwr::ES.h(0.30, 0.20), sig.level = 0.05, power = 0.8)          # 2群の割合 30% vs 20%
pwr::pwr.r.test(r = 0.3, sig.level = 0.05, power = 0.8)                             # 相関
pwr::pwr.anova.test(k = 3, f = 0.25, sig.level = 0.05, power = 0.8)                 # 一元配置(k群)
pwr::pwr.chisq.test(w = 0.3, df = 1, sig.level = 0.05, power = 0.8)                 # カイ二乗
# 効果量の目安(Cohen): d 0.2/0.5/0.8, r 0.1/0.3/0.5, f 0.1/0.25/0.4, w 0.1/0.3/0.5
# 生存(log-rank): powerSurvEpi::ssizeCT.default(...)]],
  },
}
