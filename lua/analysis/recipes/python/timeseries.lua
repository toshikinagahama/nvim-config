-- Python / 時系列
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "時系列",

  {
    name = "プロット+移動平均",
    fields = { F.col("time", "時刻列"), F.col("y", "値") },
    body = [[
import pandas as pd
import matplotlib.pyplot as plt
ts = {{df}}.assign(_t=pd.to_datetime({{df}}[{{time}}])).set_index("_t")[{{y}}].sort_index()
fig, ax = plt.subplots(figsize=(11, 4))
ax.plot(ts.index, ts, lw=0.6, alpha=0.6, label="raw")
ax.plot(ts.index, ts.rolling("5min").mean(), lw=1.5, label="移動平均 5min")   # 行数なら rolling(50, center=True)
ax.set(ylabel={{y}}); ax.legend()
plt.show()]],
  },

  {
    name = "自己相関(ACF/PACF)",
    fields = { F.col("y", "値") },
    body = [[
import matplotlib.pyplot as plt
from statsmodels.graphics.tsaplots import plot_acf, plot_pacf
x = {{df}}[{{y}}].interpolate().dropna()
fig, ax = plt.subplots(1, 2, figsize=(11, 3.5))
plot_acf(x, lags=60, ax=ax[0]); plot_pacf(x, lags=60, ax=ax[1], method="ywm")
plt.tight_layout(); plt.show()]],
  },

  {
    name = "季節・トレンド分解(STL)",
    fields = { F.col("time", "時刻列"), F.col("y", "値") },
    body = [[
import pandas as pd
import matplotlib.pyplot as plt
from statsmodels.tsa.seasonal import STL
ts = {{df}}.assign(_t=pd.to_datetime({{df}}[{{time}}])).set_index("_t")[{{y}}].sort_index()
ts = ts.resample("1D").mean().interpolate()   # 日単位にそろえる(粒度は要調整)
res = STL(ts, period=7, robust=True).fit()      # period: 周期(日次データで週周期なら 7)
res.plot(); plt.show()]],
  },
}
