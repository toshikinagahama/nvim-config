-- R / 読込・保存
return {
  lang = "r",
  cat = "読込・保存",

  {
    name = "[読込] ファイルを選ぶ → 読込コード(文字コード・区切り・シート自動判定)",
    fields = {},
    body = "データファイルを選ぶと、形式に合った読込コードを挿入(\\if と同じ)",
    action = function() require("analysis.extra").read_file() end,
  },
  {
    name = "[読込] よく使う形式の雛形(csv / Excel / parquet / rds / SPSS)",
    fields = {},
    no_df = true,
    body = [=[
# 使う行だけ残す(パスはプロジェクト直下基準)
df <- readr::read_csv(here::here("data/raw/data.csv"), na = c("", "NA", "-", "#N/A"))
# 文字化け(Shift-JIS)なら read_csv(..., locale = readr::locale(encoding = "CP932"))
df <- readxl::read_excel(here::here("data/raw/data.xlsx"), sheet = 1)  # skip = 行数, range = "A1:F100"
df <- arrow::read_parquet(here::here("data/data.parquet"))
df <- readRDS(here::here("data/data.rds"))
df <- haven::read_sav(here::here("data/raw/data.sav")) %>% haven::as_factor()  # 値ラベル → factor
dplyr::glimpse(df)]=],
  },
  {
    name = "[読込] フォルダ内の CSV をまとめて読込(ファイル名列つきで縦結合)",
    fields = {},
    no_df = true,
    body = [=[
files <- list.files(here::here("data/raw"), pattern = "\\.csv$", full.names = TRUE)
df <- purrr::map(files, \(f) readr::read_csv(f, show_col_types = FALSE)) %>%
  purrr::set_names(basename(files)) %>%
  dplyr::bind_rows(.id = "file")
dplyr::count(df, file)]=],
  },
  {
    name = "[保存] データフレームを保存(parquet / rds / csv / Excel)",
    fields = {},
    body = [=[
out_dir <- here::here("data/processed")  # utils.R の processedDataDir を使うならそれに
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
# 使う行だけ残す
arrow::write_parquet({{df}}, file.path(out_dir, "{{df}}.parquet"))  # 型・factor 保持、Python と共有可
saveRDS({{df}}, file.path(out_dir, "{{df}}.rds"))  # R 専用・何でも保存できる
readr::write_excel_csv({{df}}, file.path(out_dir, "{{df}}.csv"), na = "")  # BOM 付き → Excel で文字化けしない
writexl::write_xlsx(list({{df}} = {{df}}), file.path(out_dir, "{{df}}.xlsx"))  # 複数シート: list(名前 = df, ...)]=],
  },
}
