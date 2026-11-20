-- Python / 同期
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "同期",

  {
    name = "2信号の時間ずれ推定(相互相関)→ ずらして揃える",
    fields = { F.col("a", "基準の信号"), F.col("b", "ずれている信号"), F.input("fs", "サンプリング周波数 [Hz]", "100.0") },
    body = [[
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from scipy import signal
fs = {{fs}}                     # 両信号のサンプリング周波数 [Hz](同じであること)
a = {{df}}[{{a}}].interpolate().to_numpy(); b = {{df}}[{{b}}].interpolate().to_numpy()
az, bz = (a - a.mean()) / a.std(), (b - b.mean()) / b.std()
cc = signal.correlate(bz, az, mode="full") / len(a)
lags = signal.correlation_lags(len(b), len(a), mode="full")
max_lag = int(fs * 5)          # 探索範囲 ±5 秒
m = np.abs(lags) <= max_lag
k = lags[m][np.argmax(cc[m])]
print(f"b は a より {k / fs:+.3f} 秒 遅れ({k:+d} サンプル), 最大相関={cc[m].max():.3f}")
{{df}}[{{b}} + "_aligned"] = pd.Series(b).shift(-k).to_numpy()   # b を a に合わせる
fig, ax = plt.subplots(1, 2, figsize=(12, 3.5))
ax[0].plot(lags[m] / fs, cc[m]); ax[0].axvline(k / fs, c="r", ls="--"); ax[0].set(xlabel="ラグ [s]", ylabel="相互相関")
n = int(fs * 10)
ax[1].plot(az[:n], label="a"); ax[1].plot(((({{df}}[{{b}} + "_aligned"] - b.mean()) / b.std()).to_numpy())[:n], label="b (aligned)")
ax[1].set(xlabel="サンプル(先頭10秒)"); ax[1].legend(); plt.show()]],
  },

  {
    name = "サンプリングの違う2データを時刻で結合(merge_asof / 補間)",
    fields = { F.col("time", "このdfの時刻列"), F.input("df_b", "もう一方のデータフレーム名", "df_b"), F.input("time_b", "その時刻列名", "time") },
    body = [[
import pandas as pd
# {{df}} と df_b(別センサーなど)を時刻で揃える
df_b = {{df_b}}                                 # もう一方のデータフレーム
time_b = {{time_b_str}}                         # df_b の時刻列名
_to_t = lambda s: pd.to_datetime(s, unit="s") if pd.api.types.is_numeric_dtype(s) else pd.to_datetime(s)  # 数値の時刻列は「秒」として扱う
a = {{df}}.assign(_t=_to_t({{df}}[{{time}}])).sort_values("_t")
b = df_b.assign(_t=_to_t(df_b[time_b])).sort_values("_t")
offset = pd.Timedelta(seconds=0)                # 機器間の時計ずれがわかっていれば補正
b["_t"] = b["_t"] + offset
# A) 最も近い時刻の値を付ける(許容 0.5 秒)
merged = pd.merge_asof(a, b.drop(columns=[time_b]), on="_t", direction="nearest",
                       tolerance=pd.Timedelta("500ms"), suffixes=("", "_b"))
# B) 共通の等間隔グリッドに線形補間して揃える(周波数解析・相互相関向け)
grid = pd.date_range(max(a["_t"].min(), b["_t"].min()), min(a["_t"].max(), b["_t"].max()), freq="10ms")
num = lambda d: d.set_index("_t").select_dtypes("number")
both = pd.concat([num(a).add_suffix("_a"), num(b).add_suffix("_b")], axis=1, sort=True)
aligned = both.interpolate(method="time").reindex(grid)
merged.head(), aligned.head()]],
  },

  {
    name = "コヒーレンス(2信号の周波数ごとの結びつき)",
    fields = { F.col("a", "信号1"), F.col("b", "信号2"), F.input("fs", "サンプリング周波数 [Hz]", "100.0") },
    body = [[
import matplotlib.pyplot as plt
from scipy import signal
fs = {{fs}}     # [Hz]
a = {{df}}[{{a}}].interpolate().to_numpy(); b = {{df}}[{{b}}].interpolate().to_numpy()
f, coh = signal.coherence(a, b, fs=fs, nperseg=min(len(a), int(fs * 30)))
print(f"最大コヒーレンス {coh[1:].max():.3f} @ {f[1:][coh[1:].argmax()]:.3f} Hz")
fig, ax = plt.subplots(figsize=(9, 4))
ax.plot(f, coh); ax.set(xlabel="周波数 [Hz]", ylabel="コヒーレンス", ylim=(0, 1), xlim=(0, fs / 2))
plt.show()]],
  },
}
