-- Python / 生存
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "生存",

  {
    name = "Kaplan-Meier 曲線+log-rank 検定+リスク集合表",
    fields = { F.col("time", "観察期間"), F.col("event", "イベント(1=発生, 0=打ち切り)"), F.col("g", "群"), F.input("times", "生存率を出す時点(カンマ区切り, time と同じ単位)", "1, 3, 5") },
    body = [=[
import pandas as pd
import matplotlib.pyplot as plt
from lifelines import KaplanMeierFitter
from lifelines.plotting import add_at_risk_counts
from lifelines.statistics import multivariate_logrank_test
_d = {{df}}[[{{time}}, {{event}}, {{g}}]].dropna()
fig, ax = plt.subplots(figsize=(7, 5))
fitters, rows = [], []
for lv, s in _d.groupby({{g}}):
    kmf = KaplanMeierFitter(label=str(lv)).fit(s[{{time}}], s[{{event}}])
    kmf.plot_survival_function(ax=ax, ci_show=True)
    fitters.append(kmf)
    rows.append({"群": lv, "n": len(s), "イベント": int(s[{{event}}].sum()), "中央生存時間": kmf.median_survival_time_})
res = multivariate_logrank_test(_d[{{time}}], _d[{{g}}], _d[{{event}}])
ax.set(xlabel="期間", ylabel="生存率", title=f"log-rank p = {res.p_value:.4f}")
add_at_risk_counts(*fitters, ax=ax)
plt.tight_layout(); plt.show()
print(pd.concat([f.survival_function_at_times([{{times}}]) for f in fitters], axis=1).round(3))   # 各時点の生存率
pd.DataFrame(rows)]=],
  },

  {
    name = "Cox 比例ハザード回帰(HR+比例ハザード性の確認)",
    fields = { F.col("time", "観察期間"), F.col("event", "イベント(1/0)"), F.cols("vars", "説明変数") },
    body = [=[
import pandas as pd
from lifelines import CoxPHFitter
_d = {{df}}[[{{time}}, {{event}}] + {{vars}}].dropna()
_cat = [c for c in {{vars}} if not pd.api.types.is_numeric_dtype(_d[c])]
_x = pd.get_dummies(_d, columns=_cat, drop_first=True, dtype=float)
cph = CoxPHFitter().fit(_x, duration_col={{time}}, event_col={{event}})
cph.check_assumptions(_x, p_value_threshold=0.05, show_plots=False)   # 比例ハザード性
cph.plot()
cph.summary[["exp(coef)", "exp(coef) lower 95%", "exp(coef) upper 95%", "p"]].round(3)]=],
  },
}
