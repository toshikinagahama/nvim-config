-- Python / 信頼性
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "信頼性",

  {
    name = "信頼性分析(Cronbach の α・項目削除時の α)",
    fields = { F.cols("items", "尺度の項目") },
    body = [=[
import pandas as pd
import pingouin as pg
_d = {{df}}[{{items}}].dropna()
a, ci = pg.cronbach_alpha(_d)
print(f"α = {a:.3f} (95%CI {ci[0]:.3f}-{ci[1]:.3f}), n = {len(_d)}")
rows = []
for c in {{items}}:
    rest = _d.drop(columns=c)
    rows.append({"項目": c, "平均": _d[c].mean(), "SD": _d[c].std(),
                 "修正済み項目-合計相関": _d[c].corr(rest.sum(axis=1)),
                 "削除時の α": pg.cronbach_alpha(rest)[0]})
pd.DataFrame(rows).set_index("項目").round(3)
# 逆転項目は先に反転: _d["q3"] = (最大 + 最小) - _d["q3"]]=],
  },
}
