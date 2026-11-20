-- Python / 群比較
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "群比較",

  {
    name = "群比較表(平均±SD / 中央値[IQR] + 検定)",
    fields = { F.cols("vars", "比較する変数"), F.col("by", "群") },
    body = [[
import pandas as pd
from scipy import stats
rows = []
_g = {{df}}[{{by}}]
levels = sorted(_g.dropna().unique())
for v in {{vars}}:
    groups = [{{df}}.loc[_g == lv, v].dropna() for lv in levels]
    row = {"変数": v}
    for lv, x in zip(levels, groups):
        row[f"{lv} 平均±SD"] = f"{x.mean():.2f} ± {x.std():.2f}"
        row[f"{lv} 中央値[IQR]"] = f"{x.median():.2f} [{x.quantile(.25):.2f}, {x.quantile(.75):.2f}]"
    if len(levels) == 2:
        row["t検定 p"] = stats.ttest_ind(*groups, equal_var=False).pvalue        # Welch
        row["Mann-Whitney p"] = stats.mannwhitneyu(*groups).pvalue
    else:
        row["ANOVA p"] = stats.f_oneway(*groups).pvalue
        row["Kruskal p"] = stats.kruskal(*groups).pvalue
    rows.append(row)
pd.DataFrame(rows).set_index("変数").round(4)]],
  },

  {
    name = "クロス表+カイ二乗/Fisher+Cramér's V",
    fields = { F.col("row", "行"), F.col("col", "列") },
    body = [[
import pandas as pd
import numpy as np
from scipy import stats
tab = pd.crosstab({{df}}[{{row}}], {{df}}[{{col}}])
print(pd.crosstab({{df}}[{{row}}], {{df}}[{{col}}], normalize="index").mul(100).round(1).astype(str) + "%")
chi2, p, dof, expected = stats.chi2_contingency(tab)
v = np.sqrt(chi2 / (tab.values.sum() * (min(tab.shape) - 1)))
print(f"χ²={chi2:.2f}, df={dof}, p={p:.4f}, Cramér's V={v:.3f}, 期待度数<5 のセル: {(expected < 5).sum()}")
if tab.shape == (2, 2):
    print("Fisher p =", stats.fisher_exact(tab).pvalue)
tab]],
  },

  {
    name = "3群以上の多重比較(Mann-Whitney 全ペア, Holm補正)",
    fields = { F.col("y", "数値変数"), F.col("by", "群") },
    body = [[
import pandas as pd
import itertools
from scipy import stats
from statsmodels.stats.multitest import multipletests
_g = {{df}}[{{by}}]
levels = sorted(_g.dropna().unique())
print("Kruskal:", stats.kruskal(*[{{df}}.loc[_g == lv, {{y}}].dropna() for lv in levels]))
rows = []
for a, b in itertools.combinations(levels, 2):
    xa, xb = {{df}}.loc[_g == a, {{y}}].dropna(), {{df}}.loc[_g == b, {{y}}].dropna()
    rows.append({"群1": a, "群2": b, "n1": len(xa), "n2": len(xb), "p": stats.mannwhitneyu(xa, xb).pvalue})
res = pd.DataFrame(rows)
res["p_holm"] = multipletests(res["p"], method="holm")[1]
res.round(4)]],
  },

  {
    name = "一元配置分散分析(ANOVA)+ Tukey / Games-Howell",
    fields = { F.col("y", "目的変数"), F.col("g", "群") },
    body = [=[
import pingouin as pg
_d = {{df}}[[{{y}}, {{g}}]].dropna()
print(_d.groupby({{g}})[{{y}}].agg(["count", "mean", "std"]).round(3))
print(pg.homoscedasticity(_d, dv={{y}}, group={{g}}))        # Levene(p<0.05 なら Welch + Games-Howell)
print(pg.anova(_d, dv={{y}}, between={{g}}, detailed=True))   # np2 = 偏 η²
print(pg.welch_anova(_d, dv={{y}}, between={{g}}))
print(pg.pairwise_tukey(_d, dv={{y}}, between={{g}}).round(4))
pg.pairwise_gameshowell(_d, dv={{y}}, between={{g}}).round(4)]=],
  },

  {
    name = "二元配置分散分析(主効果+交互作用, Type III)",
    fields = { F.col("y", "目的変数"), F.col("a", "要因A"), F.col("b", "要因B") },
    body = [=[
import matplotlib.pyplot as plt
import seaborn as sns
import statsmodels.api as sm
import statsmodels.formula.api as smf
q = lambda c: f'Q("{c}")'
_d = {{df}}[[{{y}}, {{a}}, {{b}}]].dropna()
m = smf.ols(f'{q({{y}})} ~ C({q({{a}})}, Sum) * C({q({{b}})}, Sum)', data=_d).fit()
print(sm.stats.anova_lm(m, typ=3).round(4))                 # SPSS の既定(Type III)
sns.pointplot(data=_d, x={{a}}, y={{y}}, hue={{b}}, dodge=0.2, errorbar=("ci", 95), capsize=0.1)
plt.title("交互作用プロット"); plt.show()
# 単純主効果: for lv, s in _d.groupby({{b}}): print(lv, pg.anova(s, dv={{y}}, between={{a}}))]=],
  },

  {
    name = "共分散分析(ANCOVA, 調整済み平均)",
    fields = { F.col("y", "目的変数"), F.col("g", "群"), F.cols("cov", "共変量") },
    body = [=[
import pandas as pd
import statsmodels.api as sm
import statsmodels.formula.api as smf
q = lambda c: f'Q("{c}")'
_d = {{df}}[[{{y}}, {{g}}] + {{cov}}].dropna()
_cov = " + ".join(q(c) for c in {{cov}})
m = smf.ols(f'{q({{y}})} ~ C({q({{g}})}, Sum) + {_cov}', data=_d).fit()
print(sm.stats.anova_lm(m, typ=3).round(4))
# 共変量を平均に固定した調整済み平均
grid = pd.DataFrame({ {{g}}: sorted(_d[{{g}}].unique()) })
for c in {{cov}}:
    grid[c] = _d[c].mean() if pd.api.types.is_numeric_dtype(_d[c]) else _d[c].mode()[0]  # カテゴリは最頻値
adj = m.get_prediction(grid).summary_frame()[["mean", "mean_ci_lower", "mean_ci_upper"]]
adj.index = grid[{{g}}]
print(adj.round(3))
# 回帰の平行性(群 × 共変量 の交互作用が無いこと):
_inter = " + ".join(f'C({q({{g}})}, Sum):{q(c)}' for c in {{cov}})
sm.stats.anova_lm(smf.ols(f'{q({{y}})} ~ C({q({{g}})}, Sum) + {_cov} + {_inter}', data=_d).fit(), typ=3).round(4)]=],
  },
}
