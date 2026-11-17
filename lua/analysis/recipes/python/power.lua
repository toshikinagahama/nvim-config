-- Python / 検出力
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "検出力",

  {
    name = "サンプルサイズ・検出力(t検定 / 割合 / 相関 / ANOVA / カイ二乗)",
    fields = {  },
    body = [[
import numpy as np
from scipy import stats
from statsmodels.stats.power import FTestAnovaPower, GofChisquarePower, NormalIndPower, TTestIndPower, TTestPower
from statsmodels.stats.proportion import proportion_effectsize
# 求めたいものを None にすると、それを計算する(nobs1 / power / effect_size)
alpha, power = 0.05, 0.8
print("2群の平均 d=0.5   n/群 =", np.ceil(TTestIndPower().solve_power(effect_size=0.5, alpha=alpha, power=power)))
print("対応あり dz=0.5   n    =", np.ceil(TTestPower().solve_power(effect_size=0.5, alpha=alpha, power=power)))
print("割合 30% vs 20%   n/群 =", np.ceil(NormalIndPower().solve_power(proportion_effectsize(0.30, 0.20), alpha=alpha, power=power)))
r = 0.3
print("相関 r=0.3        n    =", np.ceil(((stats.norm.ppf(1 - alpha / 2) + stats.norm.ppf(power)) / np.arctanh(r)) ** 2 + 3))
print("一元配置 3群 f=0.25 総n =", np.ceil(FTestAnovaPower().solve_power(effect_size=0.25, k_groups=3, alpha=alpha, power=power)))
print("カイ二乗 df=1 w=0.3 総n =", np.ceil(GofChisquarePower().solve_power(effect_size=0.3, n_bins=2, alpha=alpha, power=power)))
# 効果量の目安(Cohen): d 0.2/0.5/0.8, r 0.1/0.3/0.5, f 0.1/0.25/0.4, w 0.1/0.3/0.5]],
  },
}
