-- Python / 反復測定
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "反復測定",

  {
    name = "対応のある比較(前後: paired t / Wilcoxon)",
    fields = { F.col("before", "前(1回目)"), F.col("after", "後(2回目)") },
    body = [=[
from scipy import stats
d = {{df}}[[{{before}}, {{after}}]].dropna()
diff = d[{{after}}] - d[{{before}}]
print(f"n={len(d)}, 差の平均={diff.mean():.3f} (SD {diff.std():.3f}), 差の中央値={diff.median():.3f}")
print("paired t:", stats.ttest_rel(d[{{after}}], d[{{before}}]))
print("Wilcoxon:", stats.wilcoxon(d[{{after}}], d[{{before}}]))
print("効果量 dz =", round(diff.mean() / diff.std(), 3))]=],
  },

  {
    name = "反復測定分散分析(球面性 + GG 補正 + 多重比較)",
    fields = { F.col("id", "ID"), F.cols("vals", "各時点の列(ワイド)") },
    body = [[
import pandas as pd
import pingouin as pg
_long = ({{df}}[[{{id}}] + {{vals}}].dropna()
         .melt(id_vars={{id}}, value_vars={{vals}}, var_name="time", value_name="value"))
_long["time"] = pd.Categorical(_long["time"], categories={{vals}})
print(_long.groupby("time", observed=True)["value"].agg(["mean", "std"]).round(3))
print(pg.sphericity(_long, dv="value", within="time", subject={{id}}))   # Mauchly
print(pg.rm_anova(_long, dv="value", within="time", subject={{id}}, correction=True, detailed=True))  # p-GG-corr
pg.pairwise_tests(_long, dv="value", within="time", subject={{id}}, padjust="bonf").round(4)
# 群(被験者間要因)も入れるなら: pg.mixed_anova(dv=, within=, between=, subject=)]],
  },

  {
    name = "Friedman 検定 → 多重比較(Wilcoxon, Bonferroni)",
    fields = { F.col("id", "ID"), F.cols("vals", "各時点の列(ワイド)") },
    body = [=[
import pingouin as pg
_long = ({{df}}[[{{id}}] + {{vals}}].dropna()
         .melt(id_vars={{id}}, value_vars={{vals}}, var_name="time", value_name="value"))
print(_long.groupby("time")["value"].describe()[["count", "25%", "50%", "75%"]])
print(pg.friedman(_long, dv="value", within="time", subject={{id}}))   # W = Kendall の W
pg.pairwise_tests(_long, dv="value", within="time", subject={{id}}, parametric=False, padjust="bonf").round(4)]=],
  },

  {
    name = "McNemar / Cochran の Q(対応のある 2値)",
    fields = { F.cols("vals", "各時点の 2値列(2つ→McNemar, 3つ以上→Q)") },
    body = [=[
import pandas as pd
from itertools import combinations
from statsmodels.stats.contingency_tables import cochrans_q, mcnemar
_d = {{df}}[{{vals}}].dropna()
print(_d.mean().round(3).rename("割合"))
if len({{vals}}) == 2:
    tab = pd.crosstab(_d[{{vals}}[0]], _d[{{vals}}[1]])
    print(tab)
    print(mcnemar(tab.values, exact=len(_d) < 25))
else:
    print(cochrans_q(_d.values))
    pairs = list(combinations({{vals}}, 2))
    for a, b in pairs:
        p = mcnemar(pd.crosstab(_d[a], _d[b]).values, exact=len(_d) < 25).pvalue
        print(f"{a} vs {b}: p={p:.4f}, Bonferroni p={min(p * len(pairs), 1):.4f}")]=],
  },
}
