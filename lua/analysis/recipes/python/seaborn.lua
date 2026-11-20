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
    name = "群別の箱ひげ図+有意差アスタリスク(2群・3群以上, 多重比較 Holm)",
    fields = {
      F.col("y", "数値(縦軸)"),
      F.col("by", "群(横軸)"),
      F.yesno("np", "ノンパラ(Mann-Whitney / Kruskal-Wallis)? いいえ→ Welch t検定 / ANOVA", true),
      F.yesno("overall", "全体の検定(3群以上の差)を上に書く?", true),
      F.yesno("sig_only", "有意なペアだけ線を引く?(いいえ→ ns も表示)", true),
    },
    body = [=[
import itertools
import matplotlib.pyplot as plt
import seaborn as sns
from scipy import stats
from statsmodels.stats.multitest import multipletests

d = {{df}}.dropna(subset=[{{y}}, {{by}}])
order = list(d[{{by}}].cat.categories) if isinstance(d[{{by}}].dtype, pd.CategoricalDtype) else sorted(d[{{by}}].unique())
vals = {g: d.loc[d[{{by}}] == g, {{y}}].to_numpy() for g in order}
order = [g for g in order if len(vals[g])]
# ペアごとの検定(Holm 補正)→ アスタリスク: * <0.05, ** <0.01, *** <0.001, **** <0.0001
pairs = list(itertools.combinations(order, 2))
p_raw = [stats.{{#np}}mannwhitneyu(vals[a], vals[b]){{/np}}{{^np}}ttest_ind(vals[a], vals[b], equal_var=False){{/np}}.pvalue for a, b in pairs]
p_adj = multipletests(p_raw, method="holm")[1]
star = lambda p: "****" if p < 1e-4 else "***" if p < 1e-3 else "**" if p < 0.01 else "*" if p < 0.05 else "ns"
pw = pd.DataFrame({"group1": [a for a, _ in pairs], "group2": [b for _, b in pairs],
                   "p": p_raw, "p.adj": p_adj, "p.adj.signif": [star(p) for p in p_adj]})
print(pw.to_string(index=False))  # p 値の一覧(論文の表・本文用)

fig, ax = plt.subplots(figsize=(5, 4.5))
sns.boxplot(data=d, x={{by}}, y={{y}}, order=order, showfliers=False, color="0.92", width=0.6, ax=ax)
sns.stripplot(data=d, x={{by}}, y={{y}}, order=order, color="k", alpha=0.4, size=3, jitter=0.15, ax=ax)
show = pw{{#sig_only}}[pw["p.adj"] < 0.05]{{/sig_only}}.assign(span=lambda t: [abs(order.index(a) - order.index(b)) for a, b in zip(t.group1, t.group2)]).sort_values("span")
top, step = d[{{y}}].max(), (d[{{y}}].max() - d[{{y}}].min()) * 0.08
for k, r in enumerate(show.itertuples()):
    x1, x2, h = order.index(r.group1), order.index(r.group2), top + step * (k + 1)
    ax.plot([x1, x1, x2, x2], [h - step * 0.25, h, h, h - step * 0.25], color="k", lw=1)
    ax.text((x1 + x2) / 2, h, r[5], ha="center", va="bottom", fontsize=10)  # r[5] = p.adj.signif
ax.set_ylim(top=top + step * (len(show) + 1.5))
{{#overall}}{{#np}}h_, p_ = stats.kruskal(*[vals[g] for g in order]); ax.set_title(f"Kruskal-Wallis H = {h_:.2f}, p = {p_:.3g}", loc="left", fontsize=10)
{{/np}}{{^np}}f_, p_ = stats.f_oneway(*[vals[g] for g in order]); ax.set_title(f"ANOVA F = {f_:.2f}, p = {p_:.3g}", loc="left", fontsize=10)
{{/np}}{{/overall}}fig.text(0.99, 0.01, "* p<0.05, ** p<0.01, *** p<0.001, **** p<0.0001 ({{#np}}Mann-Whitney{{/np}}{{^np}}Welch t{{/np}}, Holm-adjusted)",
         ha="right", fontsize=8)
sns.despine(); plt.tight_layout(rect=(0, 0.03, 1, 1)); plt.show()]=],
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
