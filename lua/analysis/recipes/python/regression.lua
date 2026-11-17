-- Python / 回帰
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "回帰",

  {
    name = "ロジスティック回帰(statsmodels, OR表)",
    fields = { F.col("outcome", "アウトカム(0/1)"), F.cols("vars", "説明変数") },
    body = [[
import pandas as pd
import numpy as np
import statsmodels.formula.api as smf
q = lambda c: f'Q("{c}")'   # 日本語・記号の列名対策
formula = f"{q({{outcome}})} ~ " + " + ".join(q(c) for c in {{vars}})
_d = {{df}}[[{{outcome}}] + {{vars}}].dropna()
m = smf.logit(formula, data=_d).fit(disp=0)
or_tab = pd.concat([np.exp(m.params), np.exp(m.conf_int()), m.pvalues], axis=1)
or_tab.columns = ["OR", "2.5%", "97.5%", "p"]
print(f"n={int(m.nobs)}, pseudo R²={m.prsquared:.3f}, AIC={m.aic:.1f}")
or_tab.round(3)]],
  },

  {
    name = "線形回帰+VIF+残差プロット",
    fields = { F.col("outcome", "目的変数"), F.cols("vars", "説明変数") },
    body = [[
import pandas as pd
import matplotlib.pyplot as plt
import statsmodels.api as sm
import statsmodels.formula.api as smf
from statsmodels.stats.outliers_influence import variance_inflation_factor
q = lambda c: f'Q("{c}")'
_d = {{df}}[[{{outcome}}] + {{vars}}].dropna()
m = smf.ols(f"{q({{outcome}})} ~ " + " + ".join(q(c) for c in {{vars}}), data=_d).fit()
print(m.summary().tables[1])
X = m.model.exog
vif = pd.Series([variance_inflation_factor(X, i) for i in range(1, X.shape[1])], index=m.model.exog_names[1:], name="VIF")
print(vif.round(2))
fig, ax = plt.subplots(1, 2, figsize=(10, 4))
ax[0].scatter(m.fittedvalues, m.resid, alpha=0.4); ax[0].axhline(0, color="grey", ls="--")
ax[0].set(xlabel="予測値", ylabel="残差")
sm.qqplot(m.resid, line="s", ax=ax[1])
plt.tight_layout(); plt.show()]],
  },

  {
    name = "ステップワイズ変数選択(AIC, 前進・後退)",
    fields = { F.col("y", "目的変数"), F.cols("vars", "候補の説明変数") },
    body = [[
import statsmodels.formula.api as smf
q = lambda c: f'Q("{c}")'
_d = {{df}}[[{{y}}] + {{vars}}].dropna()
_binary = _d[{{y}}].nunique() == 2      # 2値ならロジスティック

def _fit(terms):
    f = f"{q({{y}})} ~ " + (" + ".join(q(t) for t in terms) or "1")
    return smf.logit(f, data=_d).fit(disp=0) if _binary else smf.ols(f, data=_d).fit()

selected, remaining = [], list({{vars}})
best = _fit(selected).aic
while True:
    cands = [(_fit(selected + [t]).aic, "+", t) for t in remaining]
    cands += [(_fit([s for s in selected if s != t]).aic, "-", t) for t in selected]
    if not cands:
        break
    aic, op, t = min(cands)
    if aic >= best:
        break
    best = aic
    if op == "+":
        selected.append(t); remaining.remove(t)
    else:
        selected.remove(t); remaining.append(t)
    print(f"{op} {t}: AIC={aic:.1f}")
m = _fit(selected)
print(m.summary())
# 注意: ステップワイズの p 値・CI は楽観的。探索目的と明記する]],
  },

  {
    name = "ポアソン / 負の二項回帰(件数, IRR)",
    fields = { F.col("y", "件数(目的変数)"), F.cols("vars", "説明変数"), F.col("exposure", "観察期間・人年(exposure)", { optional = true }) },
    body = [[
import pandas as pd
import numpy as np
import statsmodels.api as sm
import statsmodels.formula.api as smf
q = lambda c: f'Q("{c}")'
_d = {{df}}[[{{y}}{{#exposure}}, {{exposure}}{{/exposure}}] + {{vars}}].dropna()
f = f"{q({{y}})} ~ " + " + ".join(q(c) for c in {{vars}})
m_p = smf.glm(f, data=_d, family=sm.families.Poisson(){{#exposure}}, exposure=_d[{{exposure}}]{{/exposure}}).fit()
print(f"過分散の指標 = {m_p.pearson_chi2 / m_p.df_resid:.2f} (1 を大きく超えるなら負の二項)")
m_nb = smf.negativebinomial(f, data=_d{{#exposure}}, exposure=_d[{{exposure}}]{{/exposure}}).fit(disp=0)
print(f"AIC: Poisson={m_p.aic:.1f}, 負の二項={m_nb.aic:.1f}")
_m = m_nb
irr = pd.concat([np.exp(_m.params), np.exp(_m.conf_int()), _m.pvalues], axis=1).drop(index="alpha", errors="ignore")
irr.columns = ["IRR", "2.5%", "97.5%", "p"]
irr.round(3)]],
  },

  {
    name = "多項ロジスティック回帰(3カテゴリ以上, RRR)",
    fields = { F.col("y", "目的変数(名義)"), F.cols("vars", "説明変数") },
    body = [[
import numpy as np
import statsmodels.formula.api as smf
q = lambda c: f'Q("{c}")'
_d = {{df}}[[{{y}}] + {{vars}}].dropna().copy()
_cat = _d[{{y}}].astype("category")       # 最初の水準が基準。変えるなら reorder_categories
_d["_y"] = _cat.cat.codes
print("基準:", _cat.cat.categories[0], " 比較:", list(_cat.cat.categories[1:]))
m = smf.mnlogit("_y ~ " + " + ".join(q(c) for c in {{vars}}), data=_d).fit(disp=0)
print(m.summary())
rrr = np.exp(m.params)
rrr.columns = list(_cat.cat.categories[1:])
rrr.round(3)]],
  },

  {
    name = "順序ロジスティック回帰(比例オッズ, OR)",
    fields = { F.col("y", "目的変数(順序)"), F.cols("vars", "説明変数") },
    body = [=[
import pandas as pd
import numpy as np
from statsmodels.miscmodels.ordinal_model import OrderedModel
_d = {{df}}[[{{y}}] + {{vars}}].dropna()
_yc = pd.Categorical(_d[{{y}}], ordered=True)     # 順番を指定するなら categories=[...] を渡す
print("水準の順番:", list(_yc.categories))
_X = pd.get_dummies(_d[{{vars}}], drop_first=True, dtype=float)
m = OrderedModel(_yc, _X, distr="logit").fit(method="bfgs", disp=0)
print(m.summary())
_k = _X.shape[1]
or_tab = pd.concat([np.exp(m.params[:_k]), np.exp(m.conf_int().iloc[:_k]), m.pvalues[:_k]], axis=1)
or_tab.columns = ["OR", "2.5%", "97.5%", "p"]
or_tab.round(3)]=],
  },
}
