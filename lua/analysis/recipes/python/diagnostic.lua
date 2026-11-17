-- Python / 診断・一致
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "診断・一致",

  {
    name = "ROC/AUC+Youdenカットオフ(sklearn)",
    fields = { F.col("outcome", "アウトカム(0/1)"), F.col("marker", "指標") },
    body = [=[
import numpy as np
import matplotlib.pyplot as plt
from sklearn.metrics import roc_auc_score, roc_curve
d = {{df}}[[{{outcome}}, {{marker}}]].dropna()
y, s = d[{{outcome}}].astype(int), d[{{marker}}]
auc = roc_auc_score(y, s)
if auc < 0.5:   # 低いほど陽性の指標
    s, auc = -s, 1 - auc
fpr, tpr, thr = roc_curve(y, s)
# AUC の 95%CI(ブートストラップ)
rng = np.random.default_rng(0)
boots = [roc_auc_score(y.iloc[i], s.iloc[i]) for i in (rng.integers(0, len(y), len(y)) for _ in range(1000)) if y.iloc[i].nunique() == 2]
lo, hi = np.percentile(boots, [2.5, 97.5])
k = np.argmax(tpr - fpr)
cut = abs(thr[k])
print(f"AUC={auc:.3f} (95%CI {lo:.3f}-{hi:.3f}), cutoff={cut:.3f}, 感度={tpr[k]:.3f}, 特異度={1 - fpr[k]:.3f}")
fig, ax = plt.subplots(figsize=(5, 5))
ax.plot(fpr, tpr); ax.plot([0, 1], [0, 1], ls="--", c="grey"); ax.scatter(fpr[k], tpr[k], c="firebrick", zorder=3)
ax.set(xlabel="1 - 特異度", ylabel="感度", title=f"AUC = {auc:.2f}")
plt.show()]=],
  },

  {
    name = "一致度(ICC(2,1)+Bland-Altman)",
    fields = { F.col("x", "測定1"), F.col("y", "測定2") },
    body = [=[
import numpy as np
import matplotlib.pyplot as plt
from scipy import stats
d = {{df}}[[{{x}}, {{y}}]].dropna()
Y = d.to_numpy(); n, k = Y.shape
gm = Y.mean()
msr = k * ((Y.mean(axis=1) - gm) ** 2).sum() / (n - 1)
msc = n * ((Y.mean(axis=0) - gm) ** 2).sum() / (k - 1)
mse = ((Y - Y.mean(axis=1, keepdims=True) - Y.mean(axis=0) + gm) ** 2).sum() / ((n - 1) * (k - 1))
icc = (msr - mse) / (msr + (k - 1) * mse + k * (msc - mse) / n)
m, diff = Y.mean(axis=1), Y[:, 0] - Y[:, 1]
bias, sd = diff.mean(), diff.std(ddof=1)
loa = (bias - 1.96 * sd, bias + 1.96 * sd)
r, p = stats.pearsonr(m, diff)
print(f"ICC(2,1)={icc:.3f}, bias={bias:.3f}, LoA={loa[0]:.3f}〜{loa[1]:.3f}, 比例誤差 r={r:.3f} (p={p:.4f})")
fig, ax = plt.subplots(figsize=(6, 4.5))
ax.scatter(m, diff, alpha=0.4)
ax.axhline(bias, c="k"); [ax.axhline(v, c="k", ls="--") for v in loa]
ax.set(xlabel="2測定の平均", ylabel="差 (" + {{x}} + " − " + {{y}} + ")")
plt.show()]=],
  },
}
