# Neovim(lua/analysis)から呼ぶ R カーネル側ヘルパ。結果は JSON/テキストを一時ファイルに書いて返す。
# 検索パスに "nvim_tools" として attach し、中身は .nv だけ(base 関数を隠さない・グローバル環境を汚さない)。
if ("nvim_tools" %in% search()) detach("nvim_tools")
attach(local({
  nv <- new.env()
  `%||%` <- function(a, b) if (is.null(a)) b else a

  # 一時ファイル経由で返す(書き終わってから rename → nvim 側が途中を読まない)
  nv$out <- function(x, path) {
    tmp <- paste0(path, ".tmp")
    jsonlite::write_json(x, tmp, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
    file.rename(tmp, path)
    invisible()
  }
  nv$run <- function(path, expr) {
    res <- tryCatch(expr, error = function(e) list(error = conditionMessage(e)))
    nv$out(res, path)
  }
  nv$text <- function(x) paste(utils::capture.output(x), collapse = "\n")

  nv$is_tbl <- function(x) is.data.frame(x) || inherits(x, c("gtsummary", "gt_tbl", "matrix", "table"))
  nv$shape <- function(x) {
    if (!is.null(dim(x))) paste(dim(x), collapse = "×") else as.character(length(x))
  }

  # 名前 → オブジェクト。無ければデータフレーム df の列として探す
  nv$get <- function(name, df = NULL) {
    if (exists(name, envir = globalenv())) return(get(name, envir = globalenv()))
    if (!is.null(df) && exists(df, envir = globalenv())) {
      d <- get(df, envir = globalenv())
      if (is.data.frame(d) && name %in% names(d)) return(d[[name]])
    }
    stop(sprintf("'%s' が見つからない(オブジェクトでも %s の列でもない)", name, df %||% "df"))
  }

  # \vv 変数一覧
  nv$objects <- function(path) nv$run(path, {
    nms <- ls(globalenv())
    lapply(nms, function(n) {
      x <- get(n, envir = globalenv())
      prev <- tryCatch(
        utils::capture.output(utils::str(x, max.level = 1, list.len = 30, give.attr = FALSE, vec.len = 3)),
        error = function(e) conditionMessage(e))
      list(name = n, class = class(x)[1], shape = nv$shape(x),
           size = format(utils::object.size(x), units = "auto"),
           df = is.data.frame(x), preview = paste(utils::head(prev, 60), collapse = "\n"))
    })
  })

  # \cn 列ピッカー用: データフレーム一覧と列情報
  nv$dfs <- function(path) nv$run(path, {
    nms <- Filter(function(n) is.data.frame(get(n, envir = globalenv())), ls(globalenv()))
    lapply(nms, function(n) {
      d <- get(n, envir = globalenv())
      list(name = n, shape = nv$shape(d), columns = lapply(names(d), function(col) {
        v <- d[[col]]
        list(name = col, type = class(v)[1], na = sum(is.na(v)),
             unique = length(unique(v)),
             preview = nv$text(if (is.numeric(v)) summary(v) else utils::head(sort(table(v, useNA = "ifany"), decreasing = TRUE), 15)))
      }))
    })
  })

  # \ps \pt \ph カーソル下の変数を確認
  nv$peek <- function(name, kind, df, path) nv$run(path, {
    x <- nv$get(name, df)
    if (kind == "summary") {
      head <- sprintf("%s  [%s, n=%d, NA=%d]", name, class(x)[1], NROW(x), sum(is.na(x)))
      list(text = paste(head, nv$text(summary(x)), sep = "\n"))
    } else if (kind == "table") {
      list(text = nv$text(table(x, useNA = "ifany")))
    } else {
      if (exists("hgd_start", mode = "function")) hgd_start()
      if (is.numeric(x)) graphics::hist(x, main = name, xlab = name, col = "grey80", border = "white")
      else graphics::barplot(table(x, useNA = "ifany"), main = name)
      list(text = "図 → httpgd http://localhost:8765")
    }
  })

  # 表っぽいものを data.frame に
  nv$as_df <- function(x) {
    if (inherits(x, "gtsummary")) {
      d <- gtsummary::as_tibble(x, col_labels = TRUE)
      names(d) <- trimws(gsub("\\s+", " ", gsub("\\*\\*|__", "", names(d))))
      return(as.data.frame(d, check.names = FALSE))
    }
    if (inherits(x, "gt_tbl")) return(as.data.frame(x[["_data"]], check.names = FALSE))
    if (inherits(x, "table")) return(as.data.frame(x))
    as.data.frame(x, check.names = FALSE)
  }

  # \yt Excel貼り付け用 TSV
  nv$tsv <- function(name, path) nv$run(path, {
    d <- nv$as_df(nv$get(name))
    rn <- rownames(d)
    keep_rn <- !is.null(rn) && !identical(rn, as.character(seq_len(nrow(d))))
    con <- textConnection("lines", "w", local = TRUE)
    utils::write.table(d, con, sep = "\t", quote = FALSE, na = "", row.names = keep_rn, col.names = if (keep_rn) NA else TRUE)
    close(con)
    list(text = paste(lines, collapse = "\n"), shape = nv$shape(d))
  })

  # \dv figviewer(http://localhost:8766)に表を送る。Python 版 view(df) と同じ形式
  nv$view <- function(name, path, max_rows = 2000) nv$run(path, {
    d <- nv$as_df(nv$get(name))
    root <- file.path(Sys.getenv("HOME"), ".cache", "figviewer")
    dir.create(root, recursive = TRUE, showWarnings = FALSE)
    id <- paste0(format(Sys.time(), "%Y%m%d-%H%M%S"), "-", paste(sample(c(0:9, letters[1:6]), 6, TRUE), collapse = ""))
    part <- utils::head(d, max_rows)
    if (!identical(rownames(part), as.character(seq_len(nrow(part))))) part <- cbind(rowname = rownames(part), part)
    part[] <- lapply(part, function(v) if (is.factor(v) || inherits(v, c("Date", "POSIXt"))) as.character(v) else v)
    payload <- list(columns = names(part), dtypes = vapply(part, function(v) class(v)[1], ""),
                    numeric = vapply(part, is.numeric, TRUE), data = unname(part), total = nrow(d))
    data_file <- paste0(id, ".json")
    jsonlite::write_json(payload, file.path(root, data_file), dataframe = "values", na = "null",
                         auto_unbox = TRUE, digits = NA)
    entries_path <- file.path(root, "entries.json")
    entries <- tryCatch(jsonlite::read_json(entries_path), error = function(e) list())
    entries[[length(entries) + 1]] <- list(id = id, kind = "table", title = sprintf("%s %s (R)", name, nv$shape(d)),
                                          data = data_file, files = list(data_file), run = id, exec = NULL,
                                          time = format(Sys.time(), "%H:%M:%S"), cell = sprintf("view(%s)", name))
    tmp <- paste0(entries_path, ".r.tmp")
    jsonlite::write_json(entries, tmp, auto_unbox = TRUE, null = "null", digits = NA)
    file.rename(tmp, entries_path)
    list(text = sprintf("%s → http://localhost:8766", name))
  })

  # \dh 表をHTMLの見た目のまま figviewer へ(gt / gtsummary / flextable / htmlwidget / data.frame)
  nv$view_html <- function(name, path) nv$run(path, {
    x <- nv$get(name)
    root <- file.path(Sys.getenv("HOME"), ".cache", "figviewer")
    dir.create(root, recursive = TRUE, showWarnings = FALSE)
    id <- paste0(format(Sys.time(), "%Y%m%d-%H%M%S"), "-", paste(sample(c(0:9, letters[1:6]), 6, TRUE), collapse = ""))
    html <- paste0(id, ".html")
    out <- file.path(root, html)
    if (inherits(x, "gtsummary")) x <- gtsummary::as_gt(x)
    if (inherits(x, "gt_tbl")) {
      gt::gtsave(x, out)
    } else if (inherits(x, "flextable")) {
      flextable::save_as_html(x, path = out)
    } else if (inherits(x, "htmlwidget")) {
      htmlwidgets::saveWidget(x, out, selfcontained = TRUE)
    } else if (nv$is_tbl(x)) {
      gt::gtsave(gt::gt(utils::head(nv$as_df(x), 500)), out)
    } else {
      stop(sprintf("%s (%s) は HTML 表示できない", name, class(x)[1]))
    }
    entries_path <- file.path(root, "entries.json")
    entries <- if (file.exists(entries_path)) tryCatch(jsonlite::read_json(entries_path), error = function(e) list()) else list()
    entries[[length(entries) + 1]] <- list(id = id, kind = "html", title = sprintf("%s (R)", name),
                                          html = html, files = list(html), run = id, exec = NULL,
                                          time = format(Sys.time(), "%H:%M:%S"), cell = sprintf("view_html(%s)", name))
    tmp <- paste0(entries_path, ".r.tmp")
    jsonlite::write_json(entries, tmp, auto_unbox = TRUE, null = "null", digits = NA)
    file.rename(tmp, entries_path)
    list(text = sprintf("%s (HTML) → http://localhost:8766", name))
  })

  # \it 型変換: 列の水準(factor なら levels、それ以外はソートしたユニーク値)
  nv$levels <- function(df, col, path) nv$run(path, {
    v <- get(df, envir = globalenv())[[col]]
    if (is.null(v)) stop(sprintf("%s に列 %s が無い", df, col))
    lv <- if (is.factor(v)) levels(v) else sort(unique(stats::na.omit(v)))
    list(values = I(utils::head(as.character(lv), 200)), n = length(lv), numeric = is.numeric(v))
  })

  # \yw 表 → Word(data.frame / gtsummary / flextable / gt / lm・glm 等のモデル)
  nv$docx <- function(name, file, path) nv$run(path, {
    x <- nv$get(name)
    dir.create(dirname(file), recursive = TRUE, showWarnings = FALSE)
    # gtsummary は flextable 経由、flextable が古い/無ければ gt 経由
    if (inherits(x, "gtsummary") && !isTRUE(tryCatch({
      flextable::save_as_docx(gtsummary::as_flex_table(x), path = file); TRUE
    }, error = function(e) FALSE))) x <- gtsummary::as_gt(x)
    if (inherits(x, "gtsummary")) {
      # 保存済み
    } else if (inherits(x, "gt_tbl")) {
      gt::gtsave(x, file)
    } else {
      if (!requireNamespace("flextable", quietly = TRUE)) stop("flextable が必要: install.packages(\"flextable\")")
      if (!is.data.frame(x) && !inherits(x, c("gtsummary", "flextable", "matrix", "table")) &&
          requireNamespace("broom", quietly = TRUE)) {
        x <- broom::tidy(x, conf.int = TRUE)  # モデル → 係数表
      }
      ft <- if (inherits(x, "flextable")) x
            else if (inherits(x, "gtsummary")) gtsummary::as_flex_table(x)
            else {
              d <- nv$as_df(x)
              d[] <- lapply(d, function(v) if (is.double(v)) signif(v, 4) else v)
              flextable::autofit(flextable::theme_booktabs(flextable::flextable(d)))
            }
      flextable::save_as_docx(ft, path = file)
    }
    list(text = file)
  })

  # \tm \to targets(store/script はプロジェクト直下)
  nv$tar <- function(what, root, path) nv$run(path, {
    script <- file.path(root, "_targets.R")
    store <- file.path(root, "_targets")
    if (!file.exists(script)) stop("_targets.R が無い(:AnalysisTargetsInit で作成)")
    txt <- if (what == "make") {
      msgs <- NULL
      outs <- utils::capture.output(msgs <- utils::capture.output(
        targets::tar_make(script = script, store = store), type = "message"))
      lines <- c(outs, msgs)
      lines <- gsub("\033\\[[0-9;]*m", "", lines)  # 色コード除去
      paste(lines[!grepl("^→", lines)], collapse = "\n")
    } else {
      out <- targets::tar_outdated(script = script, store = store)
      if (length(out)) paste(c("更新が必要:", out), collapse = "\n  ") else "全て最新"
    }
    list(text = txt)
  })

  e <- new.env()
  e$.nv <- nv
  e
}), name = "nvim_tools", warn.conflicts = FALSE)
