-- Python / 周波数
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "周波数",

  {
    name = "FFT 振幅スペクトル",
    fields = { F.col("y", "信号"), F.input("fs", "サンプリング周波数 [Hz]", "100.0") },
    body = [[
import numpy as np
import matplotlib.pyplot as plt
fs = {{fs}}                         # サンプリング周波数 [Hz]
x = {{df}}[{{y}}].interpolate().to_numpy()
x = x - x.mean()                   # 直流成分を除く
win = np.hanning(len(x))
X = np.fft.rfft(x * win)
f = np.fft.rfftfreq(len(x), d=1 / fs)
amp = 2 * np.abs(X) / win.sum()
peak = f[1:][np.argmax(amp[1:])]
print(f"ピーク周波数 = {peak:.3f} Hz(周期 {1 / peak:.3f} s)")
fig, ax = plt.subplots(figsize=(9, 4))
ax.plot(f, amp); ax.set(xlabel="周波数 [Hz]", ylabel="振幅", xlim=(0, fs / 2))
plt.show()]],
  },

  {
    name = "Welch パワースペクトル密度+バンドパワー",
    fields = { F.col("y", "信号"), F.input("fs", "サンプリング周波数 [Hz]", "100.0") },
    body = [[
import numpy as np
import matplotlib.pyplot as plt
from scipy import signal
from scipy.integrate import trapezoid
fs = {{fs}}                                           # [Hz]
bands = {"LF": (0.04, 0.15), "HF": (0.15, 0.40)}     # 例: 心拍変動。用途に合わせて変更
x = {{df}}[{{y}}].interpolate().to_numpy()
f, pxx = signal.welch(x - x.mean(), fs=fs, nperseg=min(len(x), int(fs * 60)))   # 窓 60 秒
power = {k: trapezoid(pxx[(f >= lo) & (f < hi)], f[(f >= lo) & (f < hi)]) for k, (lo, hi) in bands.items()}
print("バンドパワー:", {k: round(v, 5) for k, v in power.items()})
print("LF/HF =", round(power["LF"] / power["HF"], 3))
fig, ax = plt.subplots(figsize=(9, 4))
ax.semilogy(f, pxx)
for k, (lo, hi) in bands.items():
    ax.axvspan(lo, hi, alpha=0.15, label=k)
ax.set(xlabel="周波数 [Hz]", ylabel="PSD"); ax.legend()
plt.show()]],
  },

  {
    name = "スペクトログラム(時間 × 周波数)",
    fields = { F.col("y", "信号"), F.input("fs", "サンプリング周波数 [Hz]", "100.0") },
    body = [[
import numpy as np
import matplotlib.pyplot as plt
from scipy import signal
fs = {{fs}}                     # [Hz]
x = {{df}}[{{y}}].interpolate().to_numpy()
f, t, S = signal.spectrogram(x - x.mean(), fs=fs, nperseg=int(fs * 2), noverlap=int(fs * 1.5))
fig, ax = plt.subplots(figsize=(11, 4))
pcm = ax.pcolormesh(t, f, 10 * np.log10(S + 1e-12), shading="gouraud", cmap="magma")
ax.set(xlabel="時間 [s]", ylabel="周波数 [Hz]", ylim=(0, fs / 2))
fig.colorbar(pcm, label="dB")
plt.show()]],
  },

  {
    name = "バターワースフィルタ(ローパス/ハイパス/バンドパス, 位相ずれなし)",
    fields = { F.col("y", "信号"), F.input("fs", "サンプリング周波数 [Hz]", "100.0") },
    body = [[
import matplotlib.pyplot as plt
from scipy import signal
fs = {{fs}}           # [Hz]
cut = (0.5, 10.0)    # バンドパス [Hz]。ローパスは 10.0 + btype="lowpass"、ハイパスは 0.5 + btype="highpass"
sos = signal.butter(4, cut, btype="bandpass", fs=fs, output="sos")
x = {{df}}[{{y}}].interpolate().to_numpy()
{{df}}[{{y}} + "_filt"] = signal.sosfiltfilt(sos, x)    # 前後2回かけて位相ずれ 0
n = int(fs * 10)
fig, ax = plt.subplots(figsize=(11, 4))
ax.plot(x[:n], lw=0.7, alpha=0.6, label="raw"); ax.plot({{df}}[{{y}} + "_filt"].to_numpy()[:n], label="filtered")
ax.set(xlabel="サンプル(先頭10秒)"); ax.legend()
plt.show()]],
  },

  {
    name = "ピーク検出(心拍・歩行周期など)",
    fields = { F.col("y", "信号"), F.input("fs", "サンプリング周波数 [Hz]", "100.0") },
    body = [[
import numpy as np
import matplotlib.pyplot as plt
from scipy import signal
fs = {{fs}}                      # [Hz]
x = {{df}}[{{y}}].interpolate().to_numpy()
peaks, prop = signal.find_peaks(x, distance=int(fs * 0.3), prominence=np.std(x))   # 最短間隔 0.3 秒。拾いすぎ/取りこぼしは prominence を調整
ibi = np.diff(peaks) / fs       # ピーク間隔 [s]
print(f"ピーク数={len(peaks)}, 間隔 平均={ibi.mean():.3f}s (SD {ibi.std():.3f}), レート={60 / ibi.mean():.1f}/分")
fig, ax = plt.subplots(figsize=(11, 4))
t = np.arange(len(x)) / fs
ax.plot(t, x, lw=0.7); ax.plot(t[peaks], x[peaks], "rx")
ax.set(xlabel="時間 [s]", xlim=(0, min(t[-1], 20)))
plt.show()]],
  },
}
