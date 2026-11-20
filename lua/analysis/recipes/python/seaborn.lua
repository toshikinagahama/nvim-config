-- Python / seaborn
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "seaborn",

  {
    name = "群別の箱ひげ+点(変数ごとに並べる)",
    fields = { F.cols("vars", "変数"), F.col("by", "群") },
    body = [[
import matplotlib.pyplot as plt
import seaborn as sns
d = {{df}}.melt(id_vars={{by}}, value_vars={{vars}})
g = sns.catplot(data=d, x={{by}}, y="value", col="variable", kind="box", sharey=False,
                col_wrap=4, height=3, showfliers=False, color="lightgrey")
g.map_dataframe(sns.stripplot, x={{by}}, y="value", alpha=0.4, size=2, color="k")
g.set_titles("{col_name}"); plt.show()]],
  },

  {
    name = "バイオリン(群 × 色分け)",
    fields = { F.col("y", "数値"), F.col("by", "群(x軸)"), F.col("hue", "色分け") },
    body = [[
import matplotlib.pyplot as plt
import seaborn as sns
fig, ax = plt.subplots(figsize=(8, 4.5))
sns.violinplot(data={{df}}, x={{by}}, y={{y}}, hue={{hue}}, split=True, inner="quart", ax=ax)
plt.show()]],
  },

  {
    name = "分布の重ね描き(ヒストグラム+KDE, 群別)",
    fields = { F.cols("vars", "変数"), F.col("hue", "群") },
    body = [[
import matplotlib.pyplot as plt
import seaborn as sns
d = {{df}}.melt(id_vars={{hue}}, value_vars={{vars}})
g = sns.displot(data=d, x="value", hue={{hue}}, col="variable", col_wrap=3, kde=True,
                stat="density", common_norm=False, facet_kws={"sharex": False, "sharey": False}, height=3)
plt.show()]],
  },

  {
    name = "散布図+回帰直線(詳細: 色分け / 式・R² / 95%CI / y=x)",
    fields = {
      F.col("x", "x"),
      F.col("y", "y"),
      F.col("by", "色分け(性別など)", { optional = true }),
      F.yesno("eq", "回帰式+R² を入れる?", true),
      F.yesno("ci", "95%CI の帯を入れる?", true),
      F.yesno("idl", "y = x の線を入れる?(入れると縦横比 1:1)", false),
    },
    body = [=[
import matplotlib.pyplot as plt
import seaborn as sns
from scipy import stats

d = {{df}}.dropna(subset=[{{x}}, {{y}}])
groups = {{#by}}list(d.groupby({{by}}, observed=True)){{/by}}{{^by}}[(None, d)]{{/by}}
ha, xpos = ("left", 0.03) if stats.linregress(d[{{x}}], d[{{y}}]).slope >= 0 else ("right", 0.97)  # 右上がり→左上 / 右下がり→右上
fig, ax = plt.subplots(figsize=(6, 5))
for i, (g, dg) in enumerate(groups):
    color = f"C{i}"
    sns.regplot(data=dg, x={{x}}, y={{y}}, ax=ax, color=color, ci={{#ci}}95{{/ci}}{{^ci}}None{{/ci}},
                scatter_kws={"alpha": 0.6, "s": 14}, label=None if g is None else str(g))
{{#eq}}    r = stats.linregress(dg[{{x}}], dg[{{y}}])
    head = "" if g is None else f"{g}: "
    sign = "+" if r.intercept >= 0 else "−"
    ax.text(xpos, 0.97 - i * 0.07, f"{head}y = {r.slope:.3g}x {sign} {abs(r.intercept):.3g},  R² = {r.rvalue**2:.3f}",
            transform=ax.transAxes, ha=ha, va="top", color=color, fontsize=9)  # 群ごとに縦に並ぶ
{{/eq}}{{#idl}}lims = [min(d[{{x}}].min(), d[{{y}}].min()), max(d[{{x}}].max(), d[{{y}}].max())]
ax.axline((lims[0], lims[0]), slope=1, ls="--", color="grey", lw=1)
ax.set_xlim(lims); ax.set_ylim(lims); ax.set_aspect("equal")  # y = x と縦横比 1:1
{{/idl}}{{#by}}ax.legend(title={{by_str}})
{{/by}}sns.despine(); plt.tight_layout(); plt.show()]=],
  },

  {
    name = "散布図+回帰直線(群別, lmplot)",
    fields = { F.col("x", "x"), F.col("y", "y"), F.col("hue", "群") },
    body = [[
import matplotlib.pyplot as plt
import seaborn as sns
g = sns.lmplot(data={{df}}, x={{x}}, y={{y}}, hue={{hue}}, height=4.5, aspect=1.3, scatter_kws={"alpha": 0.4, "s": 12})
plt.show()]],
  },

  {
    name = "ペアプロット(散布図行列)",
    fields = { F.cols("vars", "変数"), F.col("hue", "色分け") },
    body = [=[
import matplotlib.pyplot as plt
import seaborn as sns
sns.pairplot({{df}}[{{vars}} + [{{hue}}]], hue={{hue}}, corner=True, plot_kws={"alpha": 0.4, "s": 10})
plt.show()]=],
  },

  {
    name = "相関ヒートマップ(下三角, 値入り)",
    fields = { F.cols("vars", "変数") },
    body = [[
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
corr = {{df}}[{{vars}}].corr(method="spearman")
mask = np.triu(np.ones_like(corr, dtype=bool))
fig, ax = plt.subplots(figsize=(0.6 * len(corr) + 3, 0.5 * len(corr) + 2.5))
sns.heatmap(corr, mask=mask, annot=True, fmt=".2f", cmap="RdBu_r", vmin=-1, vmax=1, square=True, ax=ax)
plt.show()]],
  },
}
