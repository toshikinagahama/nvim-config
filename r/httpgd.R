# Jupyter(IRkernel)上で httpgd を使うための補助。\hh \hu \hc から source する。
# IRkernel はセルごとに専用デバイスを開いて閉じるため、次の2点が必要:
#   - dev.off() しない(専用デバイスと同じ番号で hgd が開き、セル終了時に一緒に閉じられる)
#   - 描画の直前に毎回 hgd デバイスへ切り替える
# ポートは 8765 固定(SSH のポート転送先に合わせる)。ブラウザで http://localhost:8765 を開く。
if ("nvim_hgd" %in% search()) detach("nvim_hgd")
attach(local({
  env <- new.env()

  env$hgd_dev <- function() {
    devs <- dev.list()
    devs <- devs[names(devs) == "unigd"]
    if (length(devs)) devs[[1]] else NULL
  }

  env$hgd_use <- function(...) {
    dev <- env$hgd_dev()
    if (!is.null(dev)) dev.set(dev)
    invisible()
  }

  env$hgd_start <- function() {
    if (!requireNamespace("httpgd", quietly = TRUE)) stop("httpgd未導入")
    if (is.null(env$hgd_dev())) {
      httpgd::hgd(host = "127.0.0.1", port = 8765, token = FALSE, silent = TRUE)
      setHook("before.plot.new", env$hgd_use)
      setHook("before.grid.newpage", env$hgd_use)
      setHook("persp", env$hgd_use)
    }
    cat("httpgd: http://localhost:8765\n")
  }

  env$hgd_show_url <- function() {
    if (is.null(env$hgd_dev())) stop("httpgd未起動")
    cat("httpgd: http://localhost:8765\n")
  }

  env$hgd_stop <- function() {
    for (name in c("before.plot.new", "before.grid.newpage", "persp")) {
      setHook(name, env$hgd_use, "replace")
      setHook(name, NULL, "replace")
    }
    dev <- env$hgd_dev()
    if (!is.null(dev)) dev.off(dev)
    invisible()
  }

  env
}), name = "nvim_hgd", warn.conflicts = FALSE)
