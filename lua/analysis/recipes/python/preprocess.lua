-- Python / 前処理
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "前処理",

  {
    name = "データ概要(型・欠測・ユニーク数・要約)",
    fields = { F.cols("vars", "見る列") },
    body = [[
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
_d.describe(include="all").T]],
  },

  {
    name = "欠測の処理(欠測率 → 行削除 or 中央値/最頻値で補完)",
    fields = { F.cols("vars", "対象列") },
    body = [[
import pandas as pd
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
    df_imp[c] = df_imp[c].fillna(fill)]],
  },

  {
    name = "外れ値の検出(IQR法・zスコア)→ フラグ列",
    fields = { F.cols("vars", "数値列") },
    body = [=[
import pandas as pd
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
# 置換(winsorize)するなら: {{df}}[_cols] = _x.clip(q1 - 1.5 * iqr, q3 + 1.5 * iqr, axis=1)]=],
  },

  {
    name = "カテゴリ化(四分位 / 任意の区切り)",
    fields = { F.col("x", "連続変数") },
    body = [[
import pandas as pd
_c = {{x}}
{{df}}[f"{_c}_q4"] = pd.qcut({{df}}[_c], 4, labels=["Q1", "Q2", "Q3", "Q4"])
# 任意の区切り(例: BMI 18.5 / 25):
# {{df}}["bmi_cat"] = pd.cut({{df}}["BMI"], [-np.inf, 18.5, 25, np.inf], right=False, labels=["低体重", "普通", "肥満"])
{{df}}.groupby(f"{_c}_q4", observed=True)[_c].agg(["count", "min", "max"])]],
  },

  {
    name = "標準化(zスコア)/ 0-1正規化",
    fields = { F.cols("vars", "数値列") },
    body = [=[
_cols = {{vars}}
for c in _cols:
    {{df}}[f"{c}_z"] = ({{df}}[c] - {{df}}[c].mean()) / {{df}}[c].std()
    {{df}}[f"{c}_mm"] = ({{df}}[c] - {{df}}[c].min()) / ({{df}}[c].max() - {{df}}[c].min())
{{df}}[[f"{c}_z" for c in _cols]].describe().round(2)]=],
  },

  {
    name = "ワイド → ロング(melt)",
    fields = { F.cols("ids", "ID列(残す列)"), F.cols("vals", "縦に並べる列") },
    body = [[
df_long = {{df}}.melt(id_vars={{ids}}, value_vars={{vals}}, var_name="variable", value_name="value")
df_long.head()
# 戻す: df_long.pivot_table(index={{ids}}, columns="variable", values="value").reset_index()]],
  },

  {
    name = "日時の変換+リサンプリング(平均)",
    fields = { F.col("time", "日時列"), F.cols("vals", "値の列") },
    body = [[
import pandas as pd
_t = pd.to_datetime({{df}}[{{time}}])
ts = {{df}}.assign(**{{{time}}: _t}).set_index({{time}}).sort_index()[{{vals}}]
rule = "1min"   # "1s" "1min" "1h" "1D" "1W" など
ts_r = ts.resample(rule).mean()
ts_r = ts_r.interpolate(limit=3)   # 短い欠損だけ線形補間
ts_r.head()]],
  },

  {
    name = "カテゴリ型に変換(順序・ラベル・基準カテゴリ)",
    fields = { F.cols("vars", "カテゴリにする列") },
    body = [[
import pandas as pd
for c in {{vars}}:
    print({{df}}[c].value_counts(dropna=False), "\n")
{{df}}[{{vars}}] = {{df}}[{{vars}}].astype("category")
# 値ラベル+順番を指定(1列ずつ):
# {{df}}["sex"] = pd.Categorical({{df}}["sex"].map({1: "男性", 2: "女性"}), categories=["男性", "女性"])
# 順序つき: pd.Categorical(x, categories=["軽度", "中等度", "重度"], ordered=True)
# 基準カテゴリ(回帰で最初の水準が基準): x.cat.reorder_categories(["基準", ...])]],
  },

  {
    name = "値の再コード化(np.select)",
    fields = { F.col("x", "再コード化する列") },
    body = [[
import pandas as pd
import numpy as np
_c = {{x}}
print({{df}}[_c].value_counts(dropna=False))
{{df}}[f"{_c}_new"] = np.select(
    [
        {{df}}[_c].isin([]),
        {{df}}[_c].isin([]),
    ],
    ["", ""],
    default=None,
)
pd.crosstab({{df}}[_c], {{df}}[f"{_c}_new"], dropna=False)]],
  },

  {
    name = "多重代入法(MICE → 回帰 → Rubin のルールで統合)",
    fields = { F.col("y", "目的変数"), F.cols("vars", "説明変数"), F.cols("aux", "補完だけに使う補助変数", { optional = true }) },
    body = [[
import pandas as pd
import statsmodels.api as sm
from statsmodels.imputation.mice import MICE, MICEData
_cols = list(dict.fromkeys([{{y}}] + {{vars}}{{#aux}} + {{aux}}{{/aux}}))
_d = {{df}}[_cols].apply(pd.to_numeric, errors="coerce")      # MICEData は数値列のみ(カテゴリは事前に数値化)
print((_d.isna().mean() * 100).round(1).rename("欠測%"))
_safe = {c: f"v{i}" for i, c in enumerate(_cols)}            # 日本語列名対策
imp = MICEData(_d.rename(columns=_safe))
_binary = _d[{{y}}].dropna().nunique() == 2
fam = sm.families.Binomial() if _binary else sm.families.Gaussian()
formula = f"{_safe[{{y}}]} ~ " + " + ".join(_safe[c] for c in {{vars}})
res = MICE(formula, sm.GLM, imp, init_kwds={"family": fam}).fit(n_burnin=10, n_imputations=20)
print({v: k for k, v in _safe.items()})
print(res.summary())
# ロジスティックなら OR = np.exp(res.params)]],
  },

  {
    id = "rename",
    name = "列名変更(rename 雛形, 変更先は空)",
    fields = { F.cols("vars", "変更する列 (Tab=選択 C-a=全選択)") },
    body = '{{df}} = {{df}}.rename(columns={\n    "旧": "",\n})', -- プレビュー用
    build = function(_, df, values)
      local q = require("analysis").q
      local lines = { ("%s = %s.rename(columns={"):format(df, df) }
      for _, c in ipairs(values.vars) do
        lines[#lines + 1] = ('    %s: "",'):format(q(c))
      end
      lines[#lines + 1] = "})"
      return lines
    end,
  },
}
