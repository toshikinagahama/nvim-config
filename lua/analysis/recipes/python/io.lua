-- Python / 読込・保存
local T = { lang = "python", cat = "読込・保存" }
local L = T
local function add(name, fields, body) L[#L + 1] = { name = name, fields = fields, body = body } end

local ROOT = [=[
from pathlib import Path
ROOT = next((p for p in [Path.cwd(), *Path.cwd().parents]
             if any((p / m).exists() for m in (".here", ".git", "DESCRIPTION", "pyproject.toml")) or any(p.glob("*.Rproj"))),
            Path.cwd())  # here::here() と同じルート]=]

L[#L + 1] = {
  name = "[読込] ファイルを選ぶ → 読込コード(文字コード・区切り・シート自動判定)",
  lang = "python",
  fields = {},
  body = "データファイルを選ぶと、形式に合った読込コードを挿入(\\if と同じ)",
  action = function() require("analysis.extra").read_file() end,
}

L[#L + 1] = { name = "[読込] よく使う形式の雛形(csv / Excel / parquet / pickle / rds)", lang = "python", fields = {}, no_df = true, body = [=[
import pandas as pd
]=] .. ROOT .. [=[

# 使う行だけ残す(パスはプロジェクト直下基準)
df = pd.read_csv(ROOT / "data/raw/data.csv", na_values=["-", "#N/A"])  # 文字化け(Shift-JIS)なら encoding="cp932"
df = pd.read_excel(ROOT / "data/raw/data.xlsx", sheet_name=0)  # skiprows=行数, usecols="A:F"
df = pd.read_parquet(ROOT / "data/data.parquet")
df = pd.read_pickle(ROOT / "data/data.pkl")
# import pyreadr; df = pyreadr.read_r(ROOT / "data/data.rds")[None]  # R の rds
df.info()]=] }

L[#L + 1] = { name = "[読込] フォルダ内の CSV をまとめて読込(ファイル名列つきで縦結合)", lang = "python", fields = {}, no_df = true, body = [=[
import pandas as pd
]=] .. ROOT .. [=[

files = sorted((ROOT / "data/raw").glob("*.csv"))
df = pd.concat([pd.read_csv(f).assign(file=f.name) for f in files], ignore_index=True)
df["file"].value_counts()]=] }

add("[保存] データフレームを保存(parquet / pickle / csv / Excel)", {}, [=[
]=] .. ROOT .. [=[

out_dir = ROOT / "data/processed"
out_dir.mkdir(parents=True, exist_ok=True)
# 使う行だけ残す
{{df}}.to_parquet(out_dir / "{{df}}.parquet", index=False)  # 型保持・R と共有可(arrow::read_parquet)。要 pyarrow
{{df}}.to_pickle(out_dir / "{{df}}.pkl")  # Python 専用・何でも保存できる
{{df}}.to_csv(out_dir / "{{df}}.csv", index=False, encoding="utf-8-sig")  # BOM 付き → Excel で文字化けしない
with pd.ExcelWriter(out_dir / "{{df}}.xlsx") as w:  # 複数シートは to_excel を並べる。要 openpyxl
    {{df}}.to_excel(w, sheet_name="{{df}}", index=False)]=])

return T
