-- Python / 相関
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "相関",

  {
    name = "Spearman 相関行列ヒートマップ",
    fields = { F.cols("vars", "変数") },
    body = [[
import matplotlib.pyplot as plt
corr = {{df}}[{{vars}}].corr(method="spearman")
fig, ax = plt.subplots(figsize=(7, 6))
im = ax.imshow(corr.abs(), vmin=0, vmax=1, cmap="Reds")
ax.set_xticks(range(len(corr)), corr.columns, rotation=45, ha="right")
ax.set_yticks(range(len(corr)), corr.index)
for i in range(len(corr)):
    for j in range(len(corr)):
        ax.text(j, i, f"{corr.iat[i, j]:.2f}", ha="center", va="center", fontsize=8)
fig.colorbar(im, label="|ρ|")
plt.show()]],
  },

  {
    name = "相関(Pearson/Spearman, 係数+p値の一覧)",
    fields = { F.cols("vars", "変数") },
    body = [=[
import pandas as pd
import itertools
from scipy import stats
rows = []
for a, b in itertools.combinations({{vars}}, 2):
    d = {{df}}[[a, b]].dropna()
    r, p = stats.pearsonr(d[a], d[b])
    rho, ps = stats.spearmanr(d[a], d[b])
    rows.append({"x": a, "y": b, "n": len(d), "Pearson r": r, "p": p, "Spearman ρ": rho, "p(ρ)": ps})
pd.DataFrame(rows).sort_values("Spearman ρ", key=abs, ascending=False).round(4)]=],
  },
}
