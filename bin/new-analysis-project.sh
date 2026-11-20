#!/usr/bin/env bash
# 解析プロジェクトの雛形を作る(R / Python / Quarto / Neovim の分析設定と同じ構成)
#
#   new-analysis-project.sh <フォルダ> [--venv] [--no-git]
#     --venv    .venv を作って requirements.txt を入れる(uv があれば uv、無ければ python -m venv)
#     --no-git  git init しない
#
# できるもの:
#   data/00_raw 01_interim 02_processed   データ(中身は git 管理しない)
#   scripts/01_fetch 02_preprocess 03_features common(utils.R / utils.py: パス定義)
#   analysis/_metadata.yml + analysis/templates/(pptx / reveal.js / scss など)
#   output/  reports/  _quarto.yml  _quarto-embed.yml  references.bib  <名前>.Rproj  .here
#   requirements.txt  pyproject.toml  README.md  .gitignore
# テーマごとの解析フォルダは nvim で :QStudy 名前(Python は :QStudy! 名前)
set -euo pipefail

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

DIR="" VENV=0 GIT=1
for a in "$@"; do
  case "$a" in
    --venv) VENV=1 ;;
    --no-git) GIT=0 ;;
    -h | --help) usage 0 ;;
    -*) echo "不明なオプション: $a" >&2; usage 1 ;;
    *) DIR="$a" ;;
  esac
done
[ -n "$DIR" ] || usage 1

# テンプレートの場所(この script は nvim-config/bin/ にある)
SELF="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$0")")" && pwd)"
TPL="$SELF/../templates"
[ -d "$TPL" ] || TPL="$HOME/.config/nvim/templates"
[ -d "$TPL" ] || { echo "テンプレートが見つからない: $TPL" >&2; exit 1; }

if [ -e "$DIR" ] && [ -n "$(ls -A "$DIR" 2>/dev/null)" ]; then
  echo "既にファイルがあるフォルダ: $DIR(無いものだけ作る)"
fi
mkdir -p "$DIR"
cd "$DIR"
ROOT="$(pwd)"
NAME="$(basename "$ROOT")"

made=()
# 無いときだけ書く: put <path>  (中身は標準入力)
put() {
  if [ -e "$1" ]; then cat >/dev/null; return; fi
  mkdir -p "$(dirname "$1")"
  cat >"$1"
  made+=("$1")
}

for d in data/00_raw data/01_interim data/02_processed output reports \
  scripts/01_fetch scripts/02_preprocess scripts/03_features scripts/common analysis/templates; do
  mkdir -p "$d"
done
for d in data/00_raw data/01_interim data/02_processed output reports; do
  [ -e "$d/.gitkeep" ] || : >"$d/.gitkeep"
done

put .here </dev/null
put "$NAME.Rproj" <<'EOF'
Version: 1.0

RestoreWorkspace: No
SaveWorkspace: No
AlwaysSaveHistory: No

EnableCodeIndexing: Yes
Encoding: UTF-8

AutoAppendNewline: Yes
StripTrailingWhitespace: Yes
EOF

put .gitignore <<'EOF'
# データは個人情報を含みうるので git に入れない(フォルダ構成だけ残す)
data/**
!data/**/
!data/**/.gitkeep
output/**
!output/.gitkeep

# Quarto / knitr
/.quarto/
**/*_cache/
**/*_files/
**/*.quarto_ipynb
**/section-preview-*.qmd
**/part-preview-*.qmd

# Python
.venv/
__pycache__/
.ipynb_checkpoints/

# R
.Rproj.user/
.Rhistory
.RData
renv/library/

.DS_Store
Thumbs.db
EOF

put _quarto.yml <<'EOF'
project:
  execute-dir: project      # コードのパスはプロジェクト直下基準(here::here / pyprojroot と一致)
  output-dir: output
  # プロジェクト一括 render(quarto render)で main.qmd だけ出す
  # render: ["analysis/**/main.qmd"]
  # ターミナルからの render でも pptx 後処理をする(\qx は不要・要 python-pptx)
  # post-render: analysis/templates/pptx_post.py

# 文献を使うときは有効に(analysis/_metadata.yml に書けば analysis/ 以下だけに効く)
# bibliography: references.bib
# csl: custom_citation.csl

# html の埋め込み(embed-resources)はここに書かない → _quarto-embed.yml(\qr の時だけ)
EOF

put _quarto-embed.yml <<'EOF'
# \qr(html render)の時だけ使うプロファイル: 画像・CSS を1つの html に埋め込む(配布用)
# preview(\qp)はこれを使わない → 埋め込みしないぶん速い
# _quarto.yml / _metadata.yml / qmd に embed-resources(self-contained)を書くとそちらが優先されて preview も遅くなる
format:
  html:
    embed-resources: true
EOF

[ -e references.bib ] || { : >references.bib; made+=(references.bib); }

# analysis/: 共通メタデータとテンプレート
[ -e analysis/_metadata.yml ] || { cp "$TPL/analysis/_metadata.yml" analysis/_metadata.yml; made+=(analysis/_metadata.yml); }
for f in "$TPL"/*; do
  n="$(basename "$f")"
  [ -f "$f" ] || continue
  [ "$n" = "_targets.R" ] && continue
  [ -e "analysis/templates/$n" ] || { cp "$f" "analysis/templates/$n"; made+=("analysis/templates/$n"); }
done

put scripts/common/utils.R <<'EOF'
# 解析の共通設定(各 qmd の先頭で source(here::here("scripts/common/utils.R")))
suppressPackageStartupMessages({
  if (!requireNamespace("pacman", quietly = TRUE)) install.packages("pacman")
  pacman::p_load(here, dplyr, tidyr, purrr, stringr, ggplot2, patchwork,
                 gtsummary, gt, flextable, broom, arrow, readxl, janitor, labelled)
})

# パス(here() = プロジェクト直下)
dataDir <- here("data")
rawDataDir <- here("data", "00_raw")
interimDataDir <- here("data", "01_interim")
processedDataDir <- here("data", "02_processed")
outputDir <- here("output")

theme_set(theme_minimal(base_size = 12))
EOF

put scripts/common/utils.py <<'EOF'
# 解析の共通設定(各 qmd / .py の先頭で from scripts.common.utils import *)
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns

# パス(ROOT = プロジェクト直下。.here / pyproject.toml / .git のあるフォルダ)
ROOT = next((p for p in [Path.cwd(), *Path.cwd().parents]
             if any((p / m).exists() for m in (".here", "pyproject.toml", ".git"))), Path.cwd())
DATA_DIR = ROOT / "data"
RAW_DIR = DATA_DIR / "00_raw"
INTERIM_DIR = DATA_DIR / "01_interim"
PROCESSED_DIR = DATA_DIR / "02_processed"
OUTPUT_DIR = ROOT / "output"

sns.set_theme(style="whitegrid", font="BIZ UDPGothic", rc={"axes.unicode_minus": False})
EOF
put scripts/__init__.py </dev/null
put scripts/common/__init__.py </dev/null

put requirements.txt <<'EOF'
pandas
numpy
scipy
statsmodels
matplotlib
seaborn
openpyxl
pyarrow
tabulate
jupyter
pyprojroot
# 必要に応じて: pingouin scikit-learn<1.8 lifelines factor_analyzer plotly great_tables python-pptx
EOF

put pyproject.toml <<EOF
[project]
name = "$(echo "$NAME" | tr -c 'A-Za-z0-9_-' '-' | sed 's/^-*//; s/-*$//; s/^$/analysis/')"
version = "0.1.0"
requires-python = ">=3.11"

[tool.ruff]
extend-exclude = ["*.qmd"]
EOF

put README.md <<EOF
# $NAME

## 構成
- \`data/00_raw\` 元データ(手を加えない) → \`01_interim\` 途中 → \`02_processed\` 解析用
- \`scripts/\` 取得・前処理・特徴量(\`common/utils.R\`, \`common/utils.py\` にパス定義)
- \`analysis/<テーマ>/main.qmd\` 解析(Neovim で \`:QStudy テーマ名\`、Python は \`:QStudy! テーマ名\`)
- \`output/\` render 結果

## セットアップ
- R: \`source("scripts/common/utils.R")\`(pacman が足りないパッケージを入れる)
- Python: \`uv venv && uv pip install -r requirements.txt\`

## よく使うキー(Neovim)
- \`\\qp\` preview / \`\\qpc\` キャッシュ付き / \`\\qr\` render(html は1ファイル化) / \`\\qx\` pptx
- \`\\aw\` 分析レシピ / \`\\if\` データ読込コード / \`\\dv\` \`\\dh\` 表を figviewer(:8766)
EOF

if [ "$VENV" = 1 ] && [ ! -d .venv ]; then
  if command -v uv >/dev/null; then
    uv venv -q .venv && uv pip install -q --python .venv/bin/python -r requirements.txt
  else
    python3 -m venv .venv && .venv/bin/pip install -q -r requirements.txt
  fi
  made+=(.venv)
fi

if [ "$GIT" = 1 ] && [ ! -d .git ] && command -v git >/dev/null; then
  git init -q && made+=(".git")
fi

echo "==> $ROOT"
if [ ${#made[@]} -gt 0 ]; then printf '  作成: %s\n' "${made[@]}"; else echo "  全部既にある"; fi
echo "次: cd \"$ROOT\" && nvim  →  :QStudy テーマ名"
