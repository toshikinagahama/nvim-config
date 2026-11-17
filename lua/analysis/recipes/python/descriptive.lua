-- Python / 記述
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "記述",

  {
    name = "群別の要約統計量",
    fields = { F.cols("vars", "変数"), F.col("by", "群") },
    body = [[
{{df}}.groupby({{by}})[{{vars}}].describe().T]],
  },

  {
    name = "クロス表(割合つき)",
    fields = { F.col("row", "行"), F.col("col", "列") },
    body = [[
pd.crosstab({{df}}[{{row}}], {{df}}[{{col}}], margins=True)
pd.crosstab({{df}}[{{row}}], {{df}}[{{col}}], normalize="index").round(3)]],
  },

  {
    name = "正規性の確認(Shapiro-Wilk + Q-Q プロット, 群別)",
    fields = { F.cols("vars", "変数"), F.col("by", "群", { optional = true, fallback = '"全体"' }) },
    body = [[
import pandas as pd
import matplotlib.pyplot as plt
from scipy import stats
_dn = {{df}}{{^by}}.assign(全体="全体"){{/by}}
_levels = sorted(_dn[{{by}}].dropna().unique())
rows = []
fig, axes = plt.subplots(len(_levels), len({{vars}}), figsize=(3.2 * len({{vars}}), 3 * len(_levels)), squeeze=False)
for i, lv in enumerate(_levels):
    for j, v in enumerate({{vars}}):
        x = _dn.loc[_dn[{{by}}] == lv, v].dropna()
        w, p = stats.shapiro(x)
        rows.append({"群": lv, "変数": v, "n": len(x), "W": w, "p": p, "正規": "○" if p >= 0.05 else "×"})
        stats.probplot(x, plot=axes[i][j])
        axes[i][j].set_title(f"{v} / {lv}", fontsize=9)
plt.tight_layout(); plt.show()
pd.DataFrame(rows).round(4)
# n が大きいと少しのずれでも p<0.05 になる → Q-Q プロットで判断]],
  },

  {
    name = "多重回答の集計(複数の 0/1 列 → 回答数・%)",
    fields = { F.cols("items", "選択肢の列(0/1)"), F.col("by", "群", { optional = true, fallback = '"全体"' }) },
    body = [[
_long = {{df}}{{^by}}.assign(全体="全体"){{/by}}.melt(id_vars={{by}}, value_vars={{items}}, var_name="選択肢", value_name="選択").dropna(subset=["選択"])
mr = (_long.groupby([{{by}}, "選択肢"])
      .agg(回答数=("選択", lambda s: (s == 1).sum()), ケース数=("選択", "size"))
      .reset_index())
mr["ケース%"] = (mr["回答数"] / mr["ケース数"] * 100).round(1)
mr["回答%"] = (mr["回答数"] / mr.groupby({{by}})["回答数"].transform("sum") * 100).round(1)
mr.sort_values([{{by}}, "回答数"], ascending=[True, False])]],
  },

  {
    name = "重み付き集計(平均・SD・割合)",
    fields = { F.col("w", "重み"), F.cols("vars", "数値の変数"), F.col("by", "群") },
    body = [=[
import pandas as pd
from statsmodels.stats.weightstats import DescrStatsW
rows = []
for v in {{vars}}:
    for lv, s in {{df}}[[{{w}}, {{by}}, v]].dropna().groupby({{by}}):
        ds = DescrStatsW(s[v], weights=s[{{w}}])
        lo, hi = ds.tconfint_mean()
        rows.append({"変数": v, "群": lv, "重み付き平均": ds.mean, "SD": ds.std, "95%CI": f"{lo:.2f}-{hi:.2f}", "重み合計": ds.sum_weights})
pd.DataFrame(rows).round(3)
# 名義変数の重み付き割合:
# pd.crosstab({{df}}["行"], {{df}}[{{by}}], values={{df}}[{{w}}], aggfunc="sum", normalize="columns").round(3)]=],
  },
}
