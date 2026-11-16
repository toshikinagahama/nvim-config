# targets パイプライン(プロジェクト直下に置く)。重い処理をここに書き、qmd では結果を読むだけにする。
#   実行: nvim で \tm(= targets::tar_make())  変更確認: \to(tar_outdated)
#   qmd 側: targets::tar_load(fit_all) / targets::tar_read(fit_all)
#   変更した関数・データに依存するターゲットだけが再計算される(knitr の cache より確実)
library(targets)

tar_option_set(packages = c("dplyr", "tidyr", "arrow"))

# 自作関数(scripts/utils.R 等)を読み込む
# tar_source("scripts/utils.R")

list(
  # ファイルを追跡: 中身が変わったら下流を再計算
  tar_target(data_file, "data/data.parquet", format = "file"),
  tar_target(df, arrow::read_parquet(data_file)),

  # 例: 重いモデル
  tar_target(fit_all, glm(y ~ ., family = binomial, data = df))
)
