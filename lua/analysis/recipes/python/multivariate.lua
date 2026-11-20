-- Python / 多変量
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "多変量",

  {
    name = "因子分析(KMO・Bartlett・平行分析・プロマックス回転)",
    fields = { F.cols("items", "項目"), F.input("n_factors", "因子数", "2") },
    body = [[
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from factor_analyzer import FactorAnalyzer  # scikit-learn 1.8 以降だと fit で落ちる → uv pip install "scikit-learn<1.8"
from factor_analyzer.factor_analyzer import calculate_bartlett_sphericity, calculate_kmo
_d = {{df}}[{{items}}].dropna()
chi2, p = calculate_bartlett_sphericity(_d)
_, kmo = calculate_kmo(_d)
print(f"KMO = {kmo:.3f} (>= 0.6 が目安), Bartlett χ² = {chi2:.1f}, p = {p:.4g}")
# 平行分析: 乱数データの固有値(95%点)より大きい因子数が目安
ev = np.linalg.eigvalsh(_d.corr())[::-1]
rng = np.random.default_rng(1)
rand = np.percentile([np.linalg.eigvalsh(np.corrcoef(rng.standard_normal(_d.shape), rowvar=False))[::-1] for _ in range(100)], 95, axis=0)
plt.plot(range(1, len(ev) + 1), ev, "o-", label="実データ"); plt.plot(range(1, len(ev) + 1), rand, "--", label="乱数(95%)")
plt.xlabel("因子"); plt.ylabel("固有値"); plt.legend(); plt.show()
print("平行分析の因子数:", int((ev > rand).sum()))
n_factors = {{n_factors}}                      # 平行分析の結果を見て変えてよい
fa = FactorAnalyzer(n_factors=n_factors, rotation="promax", method="ml").fit(_d)
loadings = pd.DataFrame(fa.loadings_, index={{items}}, columns=[f"F{i + 1}" for i in range(n_factors)])
print(pd.DataFrame(fa.get_communalities(), index={{items}}, columns=["共通性"]).round(3))
loadings.where(loadings.abs() >= 0.3).round(2)]],
  },

  {
    name = "主成分分析(寄与率・スクリープロット・負荷量)",
    fields = { F.cols("vars", "変数") },
    body = [[
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler
_d = {{df}}[{{vars}}].dropna()
pca = PCA().fit(StandardScaler().fit_transform(_d))
ratio = pd.DataFrame({"固有値": pca.explained_variance_, "寄与率": pca.explained_variance_ratio_,
                      "累積寄与率": pca.explained_variance_ratio_.cumsum()}, index=[f"PC{i + 1}" for i in range(len(_d.columns))])
print(ratio.round(3))
plt.plot(range(1, len(ratio) + 1), ratio["固有値"], "o-"); plt.axhline(1, ls="--", color="grey")
plt.title("スクリープロット"); plt.xlabel("主成分"); plt.show()
loadings = pd.DataFrame(pca.components_.T * np.sqrt(pca.explained_variance_), index={{vars}}, columns=ratio.index)
loadings.iloc[:, :3].round(3)
# 主成分得点: scores = pca.transform(StandardScaler().fit_transform(_d))]],
  },

  {
    name = "クラスター分析(k-means: エルボー+シルエット / 階層: デンドログラム)",
    fields = { F.cols("vars", "変数"), F.input("k", "クラスタ数 k", "3") },
    body = [[
import pandas as pd
import matplotlib.pyplot as plt
from scipy.cluster.hierarchy import dendrogram, fcluster, linkage
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score
from sklearn.preprocessing import StandardScaler
_d = {{df}}[{{vars}}].dropna()
X = StandardScaler().fit_transform(_d)
rows = []
for k in range(2, 9):
    km = KMeans(k, n_init=25, random_state=1).fit(X)
    rows.append({"k": k, "within_ss": km.inertia_, "silhouette": silhouette_score(X, km.labels_)})
print(pd.DataFrame(rows).round(3))
k = {{k}}                                      # 上の表を見て変えてよい
_d = _d.assign(cluster=KMeans(k, n_init=25, random_state=1).fit_predict(X))
print(_d.groupby("cluster").mean().round(2).assign(n=_d["cluster"].value_counts().sort_index()))
Z = linkage(X, method="ward")
dendrogram(Z, no_labels=True, color_threshold=(Z[-k, 2] + Z[-(k - 1), 2]) / 2); plt.title("Ward 法"); plt.show()
# 階層クラスタの所属: fcluster(Z, k, criterion="maxclust")]],
  },

  {
    name = "判別分析(線形判別 LDA, 判別的中率)",
    fields = { F.col("g", "群"), F.cols("vars", "判別に使う変数") },
    body = [[
import pandas as pd
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
from sklearn.model_selection import LeaveOneOut, cross_val_predict
_d = {{df}}[[{{g}}] + {{vars}}].dropna()
X, y = _d[{{vars}}], _d[{{g}}]
lda = LinearDiscriminantAnalysis().fit(X, y)
print(pd.DataFrame(lda.scalings_, index={{vars}}, columns=[f"LD{i + 1}" for i in range(lda.scalings_.shape[1])]).round(3))
pred = cross_val_predict(LinearDiscriminantAnalysis(), X, y, cv=LeaveOneOut())   # SPSS の「1つ抜き」分類
tab = pd.crosstab(y, pred, rownames=["実際"], colnames=["予測"])
print(f"交差検証の的中率 = {(pred == y).mean() * 100:.1f}%")
tab]],
  },

  {
    name = "決定木(コスト複雑度で剪定+図)",
    fields = { F.col("y", "目的変数"), F.cols("vars", "説明変数") },
    body = [[
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from sklearn.model_selection import cross_val_score
from sklearn.tree import DecisionTreeClassifier, DecisionTreeRegressor, plot_tree
_d = {{df}}[[{{y}}] + {{vars}}].dropna()
X = pd.get_dummies(_d[{{vars}}], drop_first=True, dtype=float)
y = _d[{{y}}]
Tree = DecisionTreeClassifier if y.nunique() <= 10 else DecisionTreeRegressor   # 少数カテゴリなら分類木
path = Tree(min_samples_leaf=20, random_state=1).cost_complexity_pruning_path(X, y)
alphas = np.unique(np.quantile(path.ccp_alphas, np.linspace(0, 1, 30)))
scores = [cross_val_score(Tree(min_samples_leaf=20, ccp_alpha=a, random_state=1), X, y, cv=5).mean() for a in alphas]
best = alphas[int(np.argmax(scores))]
tree = Tree(min_samples_leaf=20, ccp_alpha=best, random_state=1).fit(X, y)
print(f"ccp_alpha = {best:.4g}, CV スコア = {max(scores):.3f}, 葉の数 = {tree.get_n_leaves()}")
plt.figure(figsize=(14, 7))
plot_tree(tree, feature_names=X.columns, class_names=[str(c) for c in getattr(tree, "classes_", [])] or None,
          filled=True, proportion=True, fontsize=8)
plt.show()]],
  },
}
