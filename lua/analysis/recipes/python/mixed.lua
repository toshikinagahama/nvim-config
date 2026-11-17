-- Python / 混合・GEE
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "混合・GEE",

  {
    name = "線形混合モデル(ランダム切片)",
    fields = { F.col("y", "目的変数"), F.cols("fixed", "固定効果"), F.col("id", "クラスタ・ID") },
    body = [[
import statsmodels.formula.api as smf
q = lambda c: f'Q("{c}")'
_d = {{df}}[[{{y}}, {{id}}] + {{fixed}}].dropna()
m = smf.mixedlm(f"{q({{y}})} ~ " + " + ".join(q(c) for c in {{fixed}}), data=_d, groups=_d[{{id}}]).fit(reml=True)
print(m.summary())
_var_id = float(m.cov_re.iloc[0, 0])
print(f"ICC = {_var_id / (_var_id + m.scale):.3f}")
# ランダム傾き: mixedlm(..., re_formula="~time")]],
  },

  {
    name = "GEE(一般化推定方程式, 交換可能相関)",
    fields = { F.col("y", "目的変数"), F.cols("vars", "説明変数"), F.col("id", "クラスタ・ID") },
    body = [[
import pandas as pd
import numpy as np
import statsmodels.api as sm
import statsmodels.formula.api as smf
q = lambda c: f'Q("{c}")'
_d = {{df}}[[{{y}}, {{id}}] + {{vars}}].dropna().sort_values({{id}})
_binary = _d[{{y}}].nunique() == 2
fam = sm.families.Binomial() if _binary else sm.families.Gaussian()
m = smf.gee(f"{q({{y}})} ~ " + " + ".join(q(c) for c in {{vars}}), groups={{id}}, data=_d,
            family=fam, cov_struct=sm.cov_struct.Exchangeable()).fit()
print(m.summary())                    # ロバスト(サンドイッチ)SE
if _binary:
    print(pd.concat([np.exp(m.params), np.exp(m.conf_int())], axis=1).set_axis(["OR", "2.5%", "97.5%"], axis=1).round(3))
# cov_struct: Independence() / Exchangeable() / Autoregressive()]],
  },
}
