-- Python の分析レシピ(recipes.lua から読み込む)。{{df}} = データフレーム名
--   kind = "col" → "a"、"cols" → ["a", "b"]。{{key_str}} も "a"(1列目)
--   各レシピは import を含むので単体で動く。サンプリング周波数 fs などは本文先頭の値を書き換える
local L = {}
local function add(name, fields, body) L[#L + 1] = { name = name, lang = "python", fields = fields, body = body } end
local col = function(key, title) return { key = key, kind = "col", title = title } end
local cols = function(key, title) return { key = key, kind = "cols", title = title } end

-- 前処理 -------------------------------------------------------------------
add("[前処理] データ概要(型・欠測・ユニーク数・要約)", { cols("vars", "見る列") }, [=[
import pandas as pd
_d = {{df}}[{{vars}}]
overview = pd.DataFrame({
    "dtype": _d.dtypes.astype(str),
    "n": _d.notna().sum(),
    "欠測": _d.isna().sum(),
    "欠測%": (_d.isna().mean() * 100).round(1),
    "ユニーク": _d.nunique(),
    "例": _d.apply(lambda s: ", ".join(map(str, s.dropna().unique()[:3]))),
})
overview
_d.describe(include="all").T]=])

add("[前処理] 欠測の処理(欠測率 → 行削除 or 中央値/最頻値で補完)", { cols("vars", "対象列") }, [=[
_cols = {{vars}}
print({{df}}[_cols].isna().mean().mul(100).round(1).sort_values(ascending=False))
# A) 欠測のある行を落とす
df_cc = {{df}}.dropna(subset=_cols)
print(f"完全ケース: {len(df_cc)} / {len({{df}})}")
# B) 補完(数値=中央値, それ以外=最頻値)+ 補完フラグ列
df_imp = {{df}}.copy()
for c in _cols:
    df_imp[f"{c}_imputed"] = df_imp[c].isna()
    fill = df_imp[c].median() if pd.api.types.is_numeric_dtype(df_imp[c]) else df_imp[c].mode().iloc[0]
    df_imp[c] = df_imp[c].fillna(fill)]=])

add("[前処理] 外れ値の検出(IQR法・zスコア)→ フラグ列", { cols("vars", "数値列") }, [=[
import numpy as np
_cols = {{vars}}
_x = {{df}}[_cols]
q1, q3 = _x.quantile(0.25), _x.quantile(0.75)
iqr = q3 - q1
out_iqr = (_x < q1 - 1.5 * iqr) | (_x > q3 + 1.5 * iqr)
out_z = ((_x - _x.mean()) / _x.std()).abs() > 3
summary = pd.DataFrame({"IQR法": out_iqr.sum(), "|z|>3": out_z.sum(), "下限(IQR)": q1 - 1.5 * iqr, "上限(IQR)": q3 + 1.5 * iqr})
summary
{{df}}["outlier_any"] = out_iqr.any(axis=1)
# 除外するなら: {{df}} = {{df}}[~{{df}}["outlier_any"]]
# 置換(winsorize)するなら: {{df}}[_cols] = _x.clip(q1 - 1.5 * iqr, q3 + 1.5 * iqr, axis=1)]=])

add("[前処理] カテゴリ化(四分位 / 任意の区切り)", { col("x", "連続変数") }, [=[
_c = {{x}}
{{df}}[f"{_c}_q4"] = pd.qcut({{df}}[_c], 4, labels=["Q1", "Q2", "Q3", "Q4"])
# 任意の区切り(例: BMI 18.5 / 25):
# {{df}}["bmi_cat"] = pd.cut({{df}}["BMI"], [-np.inf, 18.5, 25, np.inf], right=False, labels=["低体重", "普通", "肥満"])
{{df}}.groupby(f"{_c}_q4", observed=True)[_c].agg(["count", "min", "max"])]=])

add("[前処理] 標準化(zスコア)/ 0-1正規化", { cols("vars", "数値列") }, [=[
_cols = {{vars}}
for c in _cols:
    {{df}}[f"{c}_z"] = ({{df}}[c] - {{df}}[c].mean()) / {{df}}[c].std()
    {{df}}[f"{c}_mm"] = ({{df}}[c] - {{df}}[c].min()) / ({{df}}[c].max() - {{df}}[c].min())
{{df}}[[f"{c}_z" for c in _cols]].describe().round(2)]=])

add("[前処理] ワイド → ロング(melt)", { cols("ids", "ID列(残す列)"), cols("vals", "縦に並べる列") }, [=[
df_long = {{df}}.melt(id_vars={{ids}}, value_vars={{vals}}, var_name="variable", value_name="value")
df_long.head()
# 戻す: df_long.pivot_table(index={{ids}}, columns="variable", values="value").reset_index()]=])

add("[前処理] 日時の変換+リサンプリング(平均)", { col("time", "日時列"), cols("vals", "値の列") }, [=[
_t = pd.to_datetime({{df}}[{{time}}])
ts = {{df}}.assign(**{{{time}}: _t}).set_index({{time}}).sort_index()[{{vals}}]
rule = "1min"   # "1s" "1min" "1h" "1D" "1W" など
ts_r = ts.resample(rule).mean()
ts_r = ts_r.interpolate(limit=3)   # 短い欠損だけ線形補間
ts_r.head()]=])

-- 統計 ---------------------------------------------------------------------
add("[統計] 群比較表(平均±SD / 中央値[IQR] + 検定)", { cols("vars", "比較する変数"), col("by", "群") }, [=[
from scipy import stats
rows = []
_g = {{df}}[{{by}}]
levels = sorted(_g.dropna().unique())
for v in {{vars}}:
    groups = [{{df}}.loc[_g == lv, v].dropna() for lv in levels]
    row = {"変数": v}
    for lv, x in zip(levels, groups):
        row[f"{lv} 平均±SD"] = f"{x.mean():.2f} ± {x.std():.2f}"
        row[f"{lv} 中央値[IQR]"] = f"{x.median():.2f} [{x.quantile(.25):.2f}, {x.quantile(.75):.2f}]"
    if len(levels) == 2:
        row["t検定 p"] = stats.ttest_ind(*groups, equal_var=False).pvalue        # Welch
        row["Mann-Whitney p"] = stats.mannwhitneyu(*groups).pvalue
    else:
        row["ANOVA p"] = stats.f_oneway(*groups).pvalue
        row["Kruskal p"] = stats.kruskal(*groups).pvalue
    rows.append(row)
pd.DataFrame(rows).set_index("変数").round(4)]=])

add("[統計] クロス表+カイ二乗/Fisher+Cramér's V", { col("row", "行"), col("col", "列") }, [=[
import numpy as np
from scipy import stats
tab = pd.crosstab({{df}}[{{row}}], {{df}}[{{col}}])
print(pd.crosstab({{df}}[{{row}}], {{df}}[{{col}}], normalize="index").mul(100).round(1).astype(str) + "%")
chi2, p, dof, expected = stats.chi2_contingency(tab)
v = np.sqrt(chi2 / (tab.values.sum() * (min(tab.shape) - 1)))
print(f"χ²={chi2:.2f}, df={dof}, p={p:.4f}, Cramér's V={v:.3f}, 期待度数<5 のセル: {(expected < 5).sum()}")
if tab.shape == (2, 2):
    print("Fisher p =", stats.fisher_exact(tab).pvalue)
tab]=])

add("[統計] 相関(Pearson/Spearman, 係数+p値の一覧)", { cols("vars", "変数") }, [=[
import itertools
from scipy import stats
rows = []
for a, b in itertools.combinations({{vars}}, 2):
    d = {{df}}[[a, b]].dropna()
    r, p = stats.pearsonr(d[a], d[b])
    rho, ps = stats.spearmanr(d[a], d[b])
    rows.append({"x": a, "y": b, "n": len(d), "Pearson r": r, "p": p, "Spearman ρ": rho, "p(ρ)": ps})
pd.DataFrame(rows).sort_values("Spearman ρ", key=abs, ascending=False).round(4)]=])

add("[統計] ロジスティック回帰(statsmodels, OR表)", { col("outcome", "アウトカム(0/1)"), cols("vars", "説明変数") }, [=[
import numpy as np
import statsmodels.formula.api as smf
q = lambda c: f'Q("{c}")'   # 日本語・記号の列名対策
formula = f"{q({{outcome}})} ~ " + " + ".join(q(c) for c in {{vars}})
_d = {{df}}[[{{outcome}}] + {{vars}}].dropna()
m = smf.logit(formula, data=_d).fit(disp=0)
or_tab = pd.concat([np.exp(m.params), np.exp(m.conf_int()), m.pvalues], axis=1)
or_tab.columns = ["OR", "2.5%", "97.5%", "p"]
print(f"n={int(m.nobs)}, pseudo R²={m.prsquared:.3f}, AIC={m.aic:.1f}")
or_tab.round(3)]=])

add("[統計] 線形回帰+VIF+残差プロット", { col("outcome", "目的変数"), cols("vars", "説明変数") }, [=[
import matplotlib.pyplot as plt
import statsmodels.api as sm
import statsmodels.formula.api as smf
from statsmodels.stats.outliers_influence import variance_inflation_factor
q = lambda c: f'Q("{c}")'
_d = {{df}}[[{{outcome}}] + {{vars}}].dropna()
m = smf.ols(f"{q({{outcome}})} ~ " + " + ".join(q(c) for c in {{vars}}), data=_d).fit()
print(m.summary().tables[1])
X = m.model.exog
vif = pd.Series([variance_inflation_factor(X, i) for i in range(1, X.shape[1])], index=m.model.exog_names[1:], name="VIF")
print(vif.round(2))
fig, ax = plt.subplots(1, 2, figsize=(10, 4))
ax[0].scatter(m.fittedvalues, m.resid, alpha=0.4); ax[0].axhline(0, color="grey", ls="--")
ax[0].set(xlabel="予測値", ylabel="残差")
sm.qqplot(m.resid, line="s", ax=ax[1])
plt.tight_layout(); plt.show()]=])

add("[統計] 対応のある比較(前後: paired t / Wilcoxon)", { col("before", "前(1回目)"), col("after", "後(2回目)") }, [=[
from scipy import stats
d = {{df}}[[{{before}}, {{after}}]].dropna()
diff = d[{{after}}] - d[{{before}}]
print(f"n={len(d)}, 差の平均={diff.mean():.3f} (SD {diff.std():.3f}), 差の中央値={diff.median():.3f}")
print("paired t:", stats.ttest_rel(d[{{after}}], d[{{before}}]))
print("Wilcoxon:", stats.wilcoxon(d[{{after}}], d[{{before}}]))
print("効果量 dz =", round(diff.mean() / diff.std(), 3))]=])

add("[統計] 3群以上の多重比較(Mann-Whitney 全ペア, Holm補正)", { col("y", "数値変数"), col("by", "群") }, [=[
import itertools
from scipy import stats
from statsmodels.stats.multitest import multipletests
_g = {{df}}[{{by}}]
levels = sorted(_g.dropna().unique())
print("Kruskal:", stats.kruskal(*[{{df}}.loc[_g == lv, {{y}}].dropna() for lv in levels]))
rows = []
for a, b in itertools.combinations(levels, 2):
    xa, xb = {{df}}.loc[_g == a, {{y}}].dropna(), {{df}}.loc[_g == b, {{y}}].dropna()
    rows.append({"群1": a, "群2": b, "n1": len(xa), "n2": len(xb), "p": stats.mannwhitneyu(xa, xb).pvalue})
res = pd.DataFrame(rows)
res["p_holm"] = multipletests(res["p"], method="holm")[1]
res.round(4)]=])

add("[統計] ROC/AUC+Youdenカットオフ(sklearn)", { col("outcome", "アウトカム(0/1)"), col("marker", "指標") }, [=[
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
plt.show()]=])

add("[統計] 一致度(ICC(2,1)+Bland-Altman)", { col("x", "測定1"), col("y", "測定2") }, [=[
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
plt.show()]=])

-- 時系列・周波数 -----------------------------------------------------------
add("[時系列] プロット+移動平均", { col("time", "時刻列"), col("y", "値") }, [=[
import matplotlib.pyplot as plt
ts = {{df}}.assign(_t=pd.to_datetime({{df}}[{{time}}])).set_index("_t")[{{y}}].sort_index()
fig, ax = plt.subplots(figsize=(11, 4))
ax.plot(ts.index, ts, lw=0.6, alpha=0.6, label="raw")
ax.plot(ts.index, ts.rolling("5min").mean(), lw=1.5, label="移動平均 5min")   # 行数なら rolling(50, center=True)
ax.set(ylabel={{y}}); ax.legend()
plt.show()]=])

add("[周波数] FFT 振幅スペクトル", { col("y", "信号") }, [=[
import numpy as np
import matplotlib.pyplot as plt
fs = 100.0                         # サンプリング周波数 [Hz] ← 要変更
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
plt.show()]=])

add("[周波数] Welch パワースペクトル密度+バンドパワー", { col("y", "信号") }, [=[
import numpy as np
import matplotlib.pyplot as plt
from scipy import signal
from scipy.integrate import trapezoid
fs = 100.0                                           # [Hz] ← 要変更
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
plt.show()]=])

add("[周波数] スペクトログラム(時間 × 周波数)", { col("y", "信号") }, [=[
import numpy as np
import matplotlib.pyplot as plt
from scipy import signal
fs = 100.0                     # [Hz] ← 要変更
x = {{df}}[{{y}}].interpolate().to_numpy()
f, t, S = signal.spectrogram(x - x.mean(), fs=fs, nperseg=int(fs * 2), noverlap=int(fs * 1.5))
fig, ax = plt.subplots(figsize=(11, 4))
pcm = ax.pcolormesh(t, f, 10 * np.log10(S + 1e-12), shading="gouraud", cmap="magma")
ax.set(xlabel="時間 [s]", ylabel="周波数 [Hz]", ylim=(0, fs / 2))
fig.colorbar(pcm, label="dB")
plt.show()]=])

add("[周波数] バターワースフィルタ(ローパス/ハイパス/バンドパス, 位相ずれなし)", { col("y", "信号") }, [=[
import matplotlib.pyplot as plt
from scipy import signal
fs = 100.0           # [Hz] ← 要変更
cut = (0.5, 10.0)    # バンドパス [Hz]。ローパスは 10.0 + btype="lowpass"、ハイパスは 0.5 + btype="highpass"
sos = signal.butter(4, cut, btype="bandpass", fs=fs, output="sos")
x = {{df}}[{{y}}].interpolate().to_numpy()
{{df}}[{{y}} + "_filt"] = signal.sosfiltfilt(sos, x)    # 前後2回かけて位相ずれ 0
n = int(fs * 10)
fig, ax = plt.subplots(figsize=(11, 4))
ax.plot(x[:n], lw=0.7, alpha=0.6, label="raw"); ax.plot({{df}}[{{y}} + "_filt"].to_numpy()[:n], label="filtered")
ax.set(xlabel="サンプル(先頭10秒)"); ax.legend()
plt.show()]=])

add("[周波数] ピーク検出(心拍・歩行周期など)", { col("y", "信号") }, [=[
import numpy as np
import matplotlib.pyplot as plt
from scipy import signal
fs = 100.0                      # [Hz] ← 要変更
x = {{df}}[{{y}}].interpolate().to_numpy()
peaks, prop = signal.find_peaks(x, distance=int(fs * 0.3), prominence=np.std(x))   # 最短間隔 0.3 秒。拾いすぎ/取りこぼしは prominence を調整
ibi = np.diff(peaks) / fs       # ピーク間隔 [s]
print(f"ピーク数={len(peaks)}, 間隔 平均={ibi.mean():.3f}s (SD {ibi.std():.3f}), レート={60 / ibi.mean():.1f}/分")
fig, ax = plt.subplots(figsize=(11, 4))
t = np.arange(len(x)) / fs
ax.plot(t, x, lw=0.7); ax.plot(t[peaks], x[peaks], "rx")
ax.set(xlabel="時間 [s]", xlim=(0, min(t[-1], 20)))
plt.show()]=])

add("[時系列] 自己相関(ACF/PACF)", { col("y", "値") }, [=[
import matplotlib.pyplot as plt
from statsmodels.graphics.tsaplots import plot_acf, plot_pacf
x = {{df}}[{{y}}].interpolate().dropna()
fig, ax = plt.subplots(1, 2, figsize=(11, 3.5))
plot_acf(x, lags=60, ax=ax[0]); plot_pacf(x, lags=60, ax=ax[1], method="ywm")
plt.tight_layout(); plt.show()]=])

add("[時系列] 季節・トレンド分解(STL)", { col("time", "時刻列"), col("y", "値") }, [=[
import matplotlib.pyplot as plt
from statsmodels.tsa.seasonal import STL
ts = {{df}}.assign(_t=pd.to_datetime({{df}}[{{time}}])).set_index("_t")[{{y}}].sort_index()
ts = ts.resample("1D").mean().interpolate()   # 日単位にそろえる(粒度は要調整)
res = STL(ts, period=7, robust=True).fit()      # period: 周期(日次データで週周期なら 7)
res.plot(); plt.show()]=])

-- 2系列の同期 --------------------------------------------------------------
add("[同期] 2信号の時間ずれ推定(相互相関)→ ずらして揃える", { col("a", "基準の信号"), col("b", "ずれている信号") }, [=[
import numpy as np
import matplotlib.pyplot as plt
from scipy import signal
fs = 100.0                     # 両信号のサンプリング周波数 [Hz](同じであること)← 要変更
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
ax[1].set(xlabel="サンプル(先頭10秒)"); ax[1].legend(); plt.show()]=])

add("[同期] サンプリングの違う2データを時刻で結合(merge_asof / 補間)", { col("time", "このdfの時刻列") }, [=[
# {{df}} と df_b(別センサーなど)を時刻で揃える。df_b / "time_b" は書き換える
df_b = df_b                                     # ← もう一方のデータフレーム
time_b = "time_b"                               # ← df_b の時刻列名
a = {{df}}.assign(_t=pd.to_datetime({{df}}[{{time}}])).sort_values("_t")
b = df_b.assign(_t=pd.to_datetime(df_b[time_b])).sort_values("_t")
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
merged.head(), aligned.head()]=])

add("[同期] コヒーレンス(2信号の周波数ごとの結びつき)", { col("a", "信号1"), col("b", "信号2") }, [=[
import matplotlib.pyplot as plt
from scipy import signal
fs = 100.0     # [Hz] ← 要変更
a = {{df}}[{{a}}].interpolate().to_numpy(); b = {{df}}[{{b}}].interpolate().to_numpy()
f, coh = signal.coherence(a, b, fs=fs, nperseg=min(len(a), int(fs * 30)))
print(f"最大コヒーレンス {coh[1:].max():.3f} @ {f[1:][coh[1:].argmax()]:.3f} Hz")
fig, ax = plt.subplots(figsize=(9, 4))
ax.plot(f, coh); ax.set(xlabel="周波数 [Hz]", ylabel="コヒーレンス", ylim=(0, 1), xlim=(0, fs / 2))
plt.show()]=])

-- seaborn ------------------------------------------------------------------
add("[seaborn] 群別の箱ひげ+点(変数ごとに並べる)", { cols("vars", "変数"), col("by", "群") }, [=[
import matplotlib.pyplot as plt
import seaborn as sns
d = {{df}}.melt(id_vars={{by}}, value_vars={{vars}})
g = sns.catplot(data=d, x={{by}}, y="value", col="variable", kind="box", sharey=False,
                col_wrap=4, height=3, showfliers=False, color="lightgrey")
g.map_dataframe(sns.stripplot, x={{by}}, y="value", alpha=0.4, size=2, color="k")
g.set_titles("{col_name}"); plt.show()]=])

add("[seaborn] バイオリン(群 × 色分け)", { col("y", "数値"), col("by", "群(x軸)"), col("hue", "色分け") }, [=[
import matplotlib.pyplot as plt
import seaborn as sns
fig, ax = plt.subplots(figsize=(8, 4.5))
sns.violinplot(data={{df}}, x={{by}}, y={{y}}, hue={{hue}}, split=True, inner="quart", ax=ax)
plt.show()]=])

add("[seaborn] 分布の重ね描き(ヒストグラム+KDE, 群別)", { cols("vars", "変数"), col("hue", "群") }, [=[
import matplotlib.pyplot as plt
import seaborn as sns
d = {{df}}.melt(id_vars={{hue}}, value_vars={{vars}})
g = sns.displot(data=d, x="value", hue={{hue}}, col="variable", col_wrap=3, kde=True,
                stat="density", common_norm=False, facet_kws={"sharex": False, "sharey": False}, height=3)
plt.show()]=])

add("[seaborn] 散布図+回帰直線(群別, lmplot)", { col("x", "x"), col("y", "y"), col("hue", "群") }, [=[
import matplotlib.pyplot as plt
import seaborn as sns
g = sns.lmplot(data={{df}}, x={{x}}, y={{y}}, hue={{hue}}, height=4.5, aspect=1.3, scatter_kws={"alpha": 0.4, "s": 12})
plt.show()]=])

add("[seaborn] ペアプロット(散布図行列)", { cols("vars", "変数"), col("hue", "色分け") }, [=[
import matplotlib.pyplot as plt
import seaborn as sns
sns.pairplot({{df}}[{{vars}} + [{{hue}}]], hue={{hue}}, corner=True, plot_kws={"alpha": 0.4, "s": 10})
plt.show()]=])

add("[seaborn] 相関ヒートマップ(下三角, 値入り)", { cols("vars", "変数") }, [=[
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
corr = {{df}}[{{vars}}].corr(method="spearman")
mask = np.triu(np.ones_like(corr, dtype=bool))
fig, ax = plt.subplots(figsize=(0.6 * len(corr) + 3, 0.5 * len(corr) + 2.5))
sns.heatmap(corr, mask=mask, annot=True, fmt=".2f", cmap="RdBu_r", vmin=-1, vmax=1, square=True, ax=ax)
plt.show()]=])

-- plotly -------------------------------------------------------------------
add("[plotly] 散布図(ホバーでID表示, 色分け, トレンド線)", { col("x", "x"), col("y", "y"), col("color", "色分け"), cols("hover", "ホバー表示する列") }, [=[
import plotly.express as px
fig = px.scatter({{df}}, x={{x}}, y={{y}}, color={{color}}, hover_data={{hover}},
                 trendline="ols", opacity=0.6, template="simple_white")
fig.show()]=])

add("[plotly] 時系列(複数系列, 範囲スライダー付き)", { col("time", "時刻列"), cols("vals", "表示する列") }, [=[
import plotly.express as px
d = {{df}}.assign(_t=pd.to_datetime({{df}}[{{time}}])).sort_values("_t")
fig = px.line(d, x="_t", y={{vals}}, template="simple_white")
fig.update_xaxes(rangeslider_visible=True, title=None)
fig.show()]=])

add("[plotly] 箱ひげ(全点表示, 群別)", { col("y", "数値"), col("by", "群") }, [=[
import plotly.express as px
fig = px.box({{df}}, x={{by}}, y={{y}}, points="all", color={{by}}, template="simple_white")
fig.show()]=])

add("[plotly] 散布図行列", { cols("vars", "変数"), col("color", "色分け") }, [=[
import plotly.express as px
fig = px.scatter_matrix({{df}}, dimensions={{vars}}, color={{color}}, opacity=0.5, template="simple_white")
fig.update_traces(diagonal_visible=False, marker_size=3)
fig.show()]=])

add("[plotly] ヒストグラム(群別の重ね描き)", { col("x", "変数"), col("color", "群") }, [=[
import plotly.express as px
fig = px.histogram({{df}}, x={{x}}, color={{color}}, barmode="overlay", opacity=0.6,
                   histnorm="probability density", marginal="box", template="simple_white")
fig.show()]=])

-- pd を使うレシピには import pandas を補う
for _, r in ipairs(L) do
  if r.body:find("pd%.") and not r.body:find("import pandas") then r.body = "import pandas as pd\n" .. r.body end
end

return L
