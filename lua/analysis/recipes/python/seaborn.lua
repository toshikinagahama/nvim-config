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
