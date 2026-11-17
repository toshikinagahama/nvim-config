-- R / 多変量
local F = require("analysis.recipes.fields")

return {
  lang = "r",
  cat = "多変量",

  {
    name = "因子分析(KMO・Bartlett・平行分析・プロマックス回転)",
    fields = { F.cols("items", "項目"), F.input("n_factors", "因子数", "2") },
    body = [[
d_f <- {{df}} %>% dplyr::select(all_of({{items}})) %>% tidyr::drop_na()
psych::KMO(d_f)                              # MSA 全体 >= 0.6 が目安
psych::cortest.bartlett(cor(d_f), n = nrow(d_f))
psych::fa.parallel(d_f, fm = "ml", fa = "fa")  # 因子数の目安
n_factors <- {{n_factors}}                   # 平行分析の結果を見て変えてよい
fa_res <- psych::fa(d_f, nfactors = n_factors, rotate = "promax", fm = "ml")
print(fa_res$loadings, cutoff = 0.3, sort = TRUE)
fa_res$Phi                                   # 因子間相関
psych::fa.diagram(fa_res)]],
  },

  {
    name = "主成分分析(寄与率・スクリープロット・負荷量)",
    fields = { F.cols("vars", "変数") },
    body = [[
d_p <- {{df}} %>% dplyr::select(all_of({{vars}})) %>% tidyr::drop_na()
pca <- prcomp(d_p, scale. = TRUE)
summary(pca)                                 # 寄与率・累積寄与率
tibble::tibble(PC = seq_along(pca$sdev), 固有値 = pca$sdev^2) %>%
  ggplot(aes(PC, 固有値)) + geom_line() + geom_point() + geom_hline(yintercept = 1, linetype = 2) +
  labs(title = "スクリープロット") + theme_minimal()
round(pca$rotation[, 1:min(3, ncol(d_p))], 3)  # 負荷量
# 主成分得点を元データに付ける: scores <- as.data.frame(pca$x)]],
  },

  {
    name = "クラスター分析(k-means: エルボー+シルエット / 階層: デンドログラム)",
    fields = { F.cols("vars", "変数"), F.input("k", "クラスタ数 k", "3") },
    body = [[
d_k <- {{df}} %>% dplyr::select(all_of({{vars}})) %>% tidyr::drop_na()
x <- scale(d_k)
set.seed(1)
tibble::tibble(k = 2:8) %>%
  dplyr::mutate(
    within_ss = purrr::map_dbl(k, \(k) kmeans(x, k, nstart = 25)$tot.withinss),
    silhouette = purrr::map_dbl(k, \(k) mean(cluster::silhouette(kmeans(x, k, nstart = 25)$cluster, dist(x))[, 3]))
  )
k <- {{k}}                                   # 上の表を見て変えてよい
km <- kmeans(x, k, nstart = 25)
d_k %>% dplyr::mutate(cluster = factor(km$cluster)) %>%
  dplyr::group_by(cluster) %>% dplyr::summarise(n = dplyr::n(), dplyr::across(everything(), mean))
hc <- hclust(dist(x), method = "ward.D2")
plot(hc, labels = FALSE, main = "Ward 法"); rect.hclust(hc, k = k)]],
  },

  {
    name = "判別分析(線形判別 LDA, 判別的中率)",
    fields = { F.col("g", "群"), F.cols("vars", "判別に使う変数") },
    body = [[
d_d <- {{df}} %>% dplyr::select({{g}}, all_of({{vars}})) %>% tidyr::drop_na() %>% dplyr::mutate({{g}} = factor({{g}}))
m <- MASS::lda(reformulate(sprintf("`%s`", {{vars}}), response = {{g_str}}), data = d_d)
m                                            # 判別係数
pred_cv <- MASS::lda(reformulate(sprintf("`%s`", {{vars}}), response = {{g_str}}), data = d_d, CV = TRUE)$class
tab <- table(実際 = d_d${{g}}, 予測 = pred_cv)
tab
cat("交差検証の的中率 =", round(sum(diag(tab)) / sum(tab) * 100, 1), "%\n")]],
  },

  {
    name = "決定木(rpart, 剪定+図)",
    fields = { F.col("y", "目的変数"), F.cols("vars", "説明変数") },
    body = [[
d_t <- {{df}} %>% dplyr::select({{y}}, all_of({{vars}})) %>% tidyr::drop_na()
if (dplyr::n_distinct(d_t${{y}}) <= 10) d_t${{y}} <- factor(d_t${{y}})   # 少数カテゴリなら分類木
set.seed(1)
tree <- rpart::rpart(reformulate(sprintf("`%s`", {{vars}}), response = {{y_str}}), data = d_t,
                     control = rpart::rpart.control(cp = 0.001, minbucket = 20))
rpart::printcp(tree)
best_cp <- tree$cptable[which.min(tree$cptable[, "xerror"]), "CP"]
tree_p <- rpart::prune(tree, cp = best_cp)
rpart.plot::rpart.plot(tree_p, type = 4, extra = 104, roundint = FALSE)]],
  },
}
