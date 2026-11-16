-- 10. 分析レシピ: レシピを選ぶ → 列ピッカーで変数を選ぶ → 完成コードを挿入
-- {{df}} はデータフレーム名、それ以外の {{key}} は fields の key。
--   kind = "cols": 複数列 → c("a", "b") / ["a", "b"]、"col": 1列 → `a` / "a"
local A = require("analysis")
local M = {}

M.list = {
  -- R --------------------------------------------------------------------
  {
    name = "群比較表(gtsummary, 中央値[IQR]+p値)",
    lang = "r",
    fields = {
      { key = "vars", kind = "cols", title = "比較する変数" },
      { key = "by", kind = "col", title = "群(by)" },
    },
    body = [=[
{{df}} %>%
  dplyr::select(all_of({{vars}}), {{by}}) %>%
  tbl_summary(
    by = {{by}},
    type = list(where(is.numeric) ~ "continuous", all_dichotomous() ~ "categorical"),
    statistic = all_continuous() ~ "{median} ({p25}, {p75})",
    missing = "no"
  ) %>%
  add_n() %>%
  add_p()]=],
  },
  {
    name = "層別の群比較表(tbl_strata)",
    lang = "r",
    fields = {
      { key = "vars", kind = "cols", title = "比較する変数" },
      { key = "by", kind = "col", title = "群(by)" },
      { key = "strata", kind = "col", title = "層(strata)" },
    },
    body = [=[
{{df}} %>%
  dplyr::select(all_of({{vars}}), {{by}}, {{strata}}) %>%
  tbl_strata(
    strata = {{strata}},
    .tbl_fun = ~ .x %>%
      tbl_summary(by = {{by}}, type = list(where(is.numeric) ~ "continuous", all_dichotomous() ~ "categorical"),
                  statistic = all_continuous() ~ "{median} ({p25}, {p75})", missing = "no") %>%
      add_p()
  )]=],
  },
  {
    name = "Spearman 相関(変数群 × 変数群)",
    lang = "r",
    fields = { { key = "x", kind = "cols", title = "変数群1" }, { key = "y", kind = "cols", title = "変数群2" } },
    body = [=[
cor_res <- {{df}} %>%
  rstatix::cor_test(vars = {{x}}, vars2 = {{y}}, method = "spearman") %>%
  dplyr::arrange(dplyr::desc(abs(cor)))
cor_res]=],
  },
  {
    name = "偏相関(調整変数あり, Spearman)+ヒートマップ",
    lang = "r",
    fields = {
      { key = "x", kind = "cols", title = "変数群1" },
      { key = "y", kind = "cols", title = "変数群2" },
      { key = "z", kind = "cols", title = "調整する変数(年齢など)" },
    },
    body = [=[
pcor_res <- tidyr::expand_grid(x = {{x}}, y = {{y}}) %>%
  dplyr::filter(x != y) %>%
  purrr::pmap_dfr(\(x, y) {
    d <- tidyr::drop_na({{df}}[, c(x, y, {{z}})])
    r <- ppcor::pcor.test(d[[x]], d[[y]], d[, {{z}}], method = "spearman")
    tibble::tibble(x, y, rho = r$estimate, p = r$p.value, n = nrow(d))
  }) %>%
  dplyr::arrange(dplyr::desc(abs(rho)))

pcor_res %>%
  dplyr::mutate(val = dplyr::if_else(p < 0.05, abs(rho), NA_real_)) %>%
  ggplot(aes(x, y, fill = val)) +
  geom_tile(color = "white") +
  geom_text(aes(label = dplyr::if_else(is.na(val), "-", sprintf("%.2f", val)))) +
  scale_fill_gradient(low = "white", high = "firebrick", limits = c(0, 1), na.value = "grey95", name = "|ρ|") +
  labs(x = NULL, y = NULL) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))]=],
  },
  {
    name = "ロジスティック回帰: 1変数ずつ(調整なし vs 調整あり, 1SDあたりOR)",
    lang = "r",
    fields = {
      { key = "outcome", kind = "col", title = "アウトカム(2値)" },
      { key = "vars", kind = "cols", title = "説明変数" },
      { key = "adjust", kind = "cols", title = "調整変数" },
    },
    body = [=[
d_z <- {{df}} %>% dplyr::mutate(dplyr::across(all_of({{vars}}), \(x) as.numeric(scale(x))))
adj_terms <- paste0("`", {{adjust}}, "`", collapse = " + ")
t_crude <- d_z %>%
  dplyr::select({{outcome}}, all_of({{vars}})) %>%
  tbl_uvregression(method = glm, y = {{outcome}}, method.args = list(family = binomial), exponentiate = TRUE)
t_adj <- d_z %>%
  dplyr::select({{outcome}}, all_of(c({{vars}}, {{adjust}}))) %>%
  tbl_uvregression(method = glm, y = {{outcome}}, include = all_of({{vars}}),
                   formula = paste("{y} ~ {x} +", adj_terms),
                   method.args = list(family = binomial), exponentiate = TRUE)
tbl_merge(list(t_crude, t_adj), tab_spanner = c("**調整なし**", "**調整あり**"))]=],
  },
  {
    name = "多変量ロジスティック回帰+VIF+ROC/AUC",
    lang = "r",
    fields = {
      { key = "outcome", kind = "col", title = "アウトカム(2値)" },
      { key = "vars", kind = "cols", title = "説明変数" },
      { key = "adjust", kind = "cols", title = "調整変数(ベースモデル)" },
    },
    body = [=[
d_m <- {{df}} %>% dplyr::select({{outcome}}, all_of(c({{vars}}, {{adjust}}))) %>% tidyr::drop_na()
m0 <- glm(reformulate(paste0("`", {{adjust}}, "`"), response = {{outcome_str}}), family = binomial, data = d_m)
m_all <- glm(reformulate(".", response = {{outcome_str}}), family = binomial, data = d_m)
tbl_regression(m_all, exponentiate = TRUE)
car::vif(m_all)
anova(m0, m_all, test = "LRT")  # ベースモデルへの上乗せ

roc_all <- pROC::roc(m_all$y, fitted(m_all), quiet = TRUE)
ci <- pROC::ci.auc(roc_all)
pROC::ggroc(roc_all, legacy.axes = TRUE) +
  geom_abline(linetype = 2, color = "grey60") +
  annotate("text", x = 0.5, y = 0.15, hjust = 0,
           label = sprintf("AUC = %.2f\n(95%%CI %.2f-%.2f)", ci[2], ci[1], ci[3])) +
  labs(x = "1 - 特異度", y = "感度") + coord_equal() + theme_minimal()]=],
  },
  {
    name = "分布(ヒストグラム, 変数ごとに facet)",
    lang = "r",
    fields = { { key = "vars", kind = "cols", title = "変数" } },
    body = [=[
{{df}} %>%
  dplyr::select(all_of({{vars}})) %>%
  tidyr::pivot_longer(everything()) %>%
  ggplot(aes(value)) +
  geom_histogram(bins = 30, fill = "grey60", color = "white") +
  facet_wrap(~name, scales = "free") +
  theme_minimal()]=],
  },
  {
    name = "群別の箱ひげ図(変数ごとに facet)",
    lang = "r",
    fields = { { key = "vars", kind = "cols", title = "変数" }, { key = "by", kind = "col", title = "群" } },
    body = [=[
{{df}} %>%
  dplyr::select(all_of({{vars}}), {{by}}) %>%
  tidyr::pivot_longer(-{{by}}) %>%
  ggplot(aes(factor({{by}}), value)) +
  geom_boxplot(outlier.shape = NA) +
  geom_jitter(width = 0.15, alpha = 0.3, size = 0.8) +
  facet_wrap(~name, scales = "free_y") +
  labs(x = NULL) +
  theme_minimal()]=],
  },
  {
    name = "散布図+回帰直線",
    lang = "r",
    fields = { { key = "x", kind = "col", title = "x" }, { key = "y", kind = "col", title = "y" } },
    body = [=[
ggplot({{df}}, aes({{x}}, {{y}})) +
  geom_point(alpha = 0.5) +
  geom_smooth(method = "lm") +
  theme_minimal()]=],
  },
  {
    name = "有病率+95%CI(全体・群別, Wilson法)",
    lang = "r",
    fields = {
      { key = "outcome", kind = "col", title = "該当/非該当の列(例: サルコペニア肥満)" },
      { key = "by", kind = "col", title = "群" },
    },
    body = [=[
pos <- 1  # 「該当」を表す値。factor/文字なら "あり" 等に変更
wilson <- function(k, n, conf = 0.95) {
  z <- qnorm(1 - (1 - conf) / 2)
  p <- k / n
  ctr <- (p + z^2 / (2 * n)) / (1 + z^2 / n)
  h <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / (1 + z^2 / n)
  c(ctr - h, ctr + h)
}
prev_tab <- dplyr::bind_rows(
  {{df}} %>% dplyr::mutate(.grp = "全体"),
  {{df}} %>% dplyr::mutate(.grp = as.character({{by}}))
) %>%
  dplyr::filter(!is.na({{outcome}}), !is.na(.grp)) %>%
  dplyr::group_by(.grp) %>%
  dplyr::summarise(n = dplyr::n(), k = sum({{outcome}} == pos), .groups = "drop") %>%
  dplyr::arrange(.grp != "全体") %>%
  dplyr::mutate(
    prev = k / n,
    lo = purrr::map2_dbl(k, n, \(k, n) wilson(k, n)[1]),
    hi = purrr::map2_dbl(k, n, \(k, n) wilson(k, n)[2]),
    `有病率 (95%CI)` = sprintf("%.1f%% (%.1f-%.1f)", 100 * prev, 100 * lo, 100 * hi)
  )
prev_tab
# 群間差(カイ二乗検定)
with(dplyr::filter({{df}}, !is.na({{outcome}}), !is.na({{by}})), chisq.test(table({{by}}, {{outcome}} == pos)))

prev_tab %>%
  ggplot(aes(forcats::fct_inorder(.grp), 100 * prev)) +
  geom_pointrange(aes(ymin = 100 * lo, ymax = 100 * hi)) +
  labs(x = NULL, y = "有病率 (%)") +
  theme_minimal()]=],
  },
  {
    name = "年齢調整有病率(直接法)",
    lang = "r",
    fields = {
      { key = "outcome", kind = "col", title = "該当/非該当の列" },
      { key = "age", kind = "col", title = "年齢" },
      { key = "by", kind = "col", title = "比較する群(性別・地域など)" },
    },
    body = [=[
pos <- 1                                      # 「該当」を表す値
age_breaks <- c(-Inf, 39, 49, 59, 69, Inf)    # 年齢階級(右端を含む)
d_a <- {{df}} %>%
  dplyr::filter(!is.na({{outcome}}), !is.na({{age}}), !is.na({{by}})) %>%
  dplyr::mutate(age_grp = cut({{age}}, age_breaks), event = {{outcome}} == pos)
# 標準人口: 既定は全対象者の年齢構成。モデル人口を使うなら std を差し替え(age_grp と w の2列, w の合計 = 1)
std <- d_a %>% dplyr::count(age_grp, name = "N") %>% dplyr::mutate(w = N / sum(N))
d_a %>%
  dplyr::group_by({{by}}, age_grp) %>%
  dplyr::summarise(n_i = dplyr::n(), k_i = sum(event), .groups = "drop") %>%
  dplyr::left_join(std, by = "age_grp") %>%
  dplyr::mutate(p_i = k_i / n_i) %>%
  dplyr::group_by({{by}}) %>%
  # 注意: ある群で 0 人の年齢階級があると、その階級分が抜けて過小評価になる
  dplyr::summarise(
    n = sum(n_i),
    crude = sum(k_i) / sum(n_i),
    adj = sum(w * p_i),
    se = sqrt(sum(w^2 * p_i * (1 - p_i) / n_i)),
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    `粗有病率` = sprintf("%.1f%%", 100 * crude),
    `年齢調整有病率 (95%CI)` = sprintf("%.1f%% (%.1f-%.1f)", 100 * adj, 100 * (adj - 1.96 * se), 100 * (adj + 1.96 * se))
  )]=],
  },
  {
    name = "3群以上の比較(Kruskal-Wallis → Dunn, Bonferroni)",
    lang = "r",
    fields = {
      { key = "vars", kind = "cols", title = "比較する変数(数値)" },
      { key = "by", kind = "col", title = "群" },
    },
    body = [=[
kw_long <- {{df}} %>%
  dplyr::select(all_of({{vars}}), {{by}}) %>%
  dplyr::filter(!is.na({{by}})) %>%
  dplyr::mutate(.g = factor({{by}})) %>%
  tidyr::pivot_longer(all_of({{vars}}), names_to = "variable") %>%
  dplyr::group_by(variable)
kw_long %>% rstatix::kruskal_test(value ~ .g)
kw_long %>% rstatix::kruskal_effsize(value ~ .g)
kw_long %>% rstatix::dunn_test(value ~ .g, p.adjust.method = "bonferroni")]=],
  },
  {
    name = "交互作用(ロジスティック): 交互作用p + 層別OR",
    lang = "r",
    fields = {
      { key = "outcome", kind = "col", title = "アウトカム(2値)" },
      { key = "exposure", kind = "col", title = "曝露(主な説明変数)" },
      { key = "modifier", kind = "col", title = "効果修飾因子(性別など)" },
      { key = "adjust", kind = "cols", title = "調整変数" },
    },
    body = [=[
d_i <- {{df}} %>%
  dplyr::select({{outcome}}, {{exposure}}, {{modifier}}, all_of({{adjust}})) %>%
  tidyr::drop_na()
bt <- \(x) paste0("`", x, "`")
terms0 <- bt(c({{exposure_str}}, {{modifier_str}}, {{adjust}}))
m0 <- glm(reformulate(terms0, response = {{outcome_str}}), family = binomial, data = d_i)
m1 <- glm(reformulate(c(terms0, paste0(terms0[1], ":", terms0[2])), response = {{outcome_str}}),
          family = binomial, data = d_i)
anova(m0, m1, test = "LRT")  # 交互作用の p 値

# 効果修飾因子の層ごとの OR
d_i %>%
  dplyr::group_by({{modifier}}) %>%
  dplyr::group_modify(\(d, key) {
    m <- glm(reformulate(bt(c({{exposure_str}}, {{adjust}})), response = {{outcome_str}}), family = binomial, data = d)
    broom::tidy(m, exponentiate = TRUE, conf.int = TRUE) %>%
      dplyr::filter(startsWith(term, {{exposure_str}}) | startsWith(term, bt({{exposure_str}}))) %>%
      dplyr::mutate(n = nrow(d))
  }) %>%
  dplyr::mutate(`OR (95%CI)` = sprintf("%.2f (%.2f-%.2f)", estimate, conf.low, conf.high))]=],
  },
  {
    name = "カットオフ探索(ROC + Youden, 感度・特異度)",
    lang = "r",
    fields = {
      { key = "outcome", kind = "col", title = "アウトカム(2値)" },
      { key = "marker", kind = "col", title = "指標(連続)" },
    },
    body = [=[
roc_c <- pROC::roc({{df}}[[{{outcome_str}}]], {{df}}[[{{marker_str}}]], quiet = TRUE)
ci_c <- pROC::ci.auc(roc_c)
best <- pROC::coords(roc_c, "best", best.method = "youden", transpose = FALSE,
                     ret = c("threshold", "sensitivity", "specificity", "ppv", "npv", "youden"))
best
sprintf("AUC = %.2f (95%%CI %.2f-%.2f), 方向: %s", ci_c[2], ci_c[1], ci_c[3], roc_c$direction)

pROC::ggroc(roc_c, legacy.axes = TRUE) +
  geom_abline(linetype = 2, color = "grey60") +
  geom_point(data = best, aes(1 - specificity, sensitivity), color = "firebrick", size = 2) +
  annotate("text", x = 1 - best$specificity[1] + 0.03, y = best$sensitivity[1] - 0.05, hjust = 0,
           label = sprintf("cutoff = %.2f\n感度 %.2f / 特異度 %.2f", best$threshold[1], best$sensitivity[1], best$specificity[1])) +
  labs(x = "1 - 特異度", y = "感度") + coord_equal() + theme_minimal()]=],
  },
  {
    name = "2つの測定の一致度(ICC + Bland-Altman)",
    lang = "r",
    fields = {
      { key = "x", kind = "col", title = "測定1(例: BIA)" },
      { key = "y", kind = "col", title = "測定2(例: DXA)" },
    },
    body = [=[
d_ag <- {{df}} %>% dplyr::select({{x}}, {{y}}) %>% tidyr::drop_na()
# ICC(2,1) 絶対一致。要 install.packages("irr")
irr::icc(d_ag, model = "twoway", type = "agreement", unit = "single")

ba <- d_ag %>% dplyr::transmute(m = ({{x}} + {{y}}) / 2, d = {{x}} - {{y}})
bias <- mean(ba$d)
loa <- bias + c(-1.96, 1.96) * sd(ba$d)
cor.test(ba$m, ba$d)  # 有意なら比例誤差(大きいほど差が開く)
ggplot(ba, aes(m, d)) +
  geom_point(alpha = 0.4) +
  geom_hline(yintercept = bias) +
  geom_hline(yintercept = loa, linetype = 2) +
  geom_smooth(method = "lm", se = FALSE, color = "grey50", linewidth = 0.5) +
  labs(x = "2測定の平均", y = sprintf("差 (%s − %s)", {{x_str}}, {{y_str}}),
       subtitle = sprintf("bias = %.2f, LoA = %.2f 〜 %.2f", bias, loa[1], loa[2])) +
  theme_minimal()]=],
  },
  {
    name = "群別の要約統計量",
    lang = "python",
    fields = { { key = "vars", kind = "cols", title = "変数" }, { key = "by", kind = "col", title = "群" } },
    body = [=[
{{df}}.groupby({{by}})[{{vars}}].describe().T]=],
  },
  {
    name = "クロス表(割合つき)",
    lang = "python",
    fields = { { key = "row", kind = "col", title = "行" }, { key = "col", kind = "col", title = "列" } },
    body = [=[
pd.crosstab({{df}}[{{row}}], {{df}}[{{col}}], margins=True)
pd.crosstab({{df}}[{{row}}], {{df}}[{{col}}], normalize="index").round(3)]=],
  },
  {
    name = "Spearman 相関行列ヒートマップ",
    lang = "python",
    fields = { { key = "vars", kind = "cols", title = "変数" } },
    body = [=[
import matplotlib.pyplot as plt
corr = {{df}}[{{vars}}].corr(method="spearman")
fig, ax = plt.subplots(figsize=(7, 6))
im = ax.imshow(corr.abs(), vmin=0, vmax=1, cmap="Reds")
ax.set_xticks(range(len(corr)), corr.columns, rotation=45, ha="right")
ax.set_yticks(range(len(corr)), corr.index)
for i in range(len(corr)):
    for j in range(len(corr)):
        ax.text(j, i, f"{corr.iat[i, j]:.2f}", ha="center", va="center", fontsize=8)
fig.colorbar(im, label="|ρ|")
plt.show()]=],
  },
  {
    name = "列名変更(rename 雛形, 変更先は空)",
    lang = "python",
    fields = { { key = "vars", kind = "cols", title = "変更する列 (Tab=選択 C-a=全選択)" } },
    body = '{{df}} = {{df}}.rename(columns={\n    "旧": "",\n})', -- プレビュー用
    build = function(_, df, values)
      local lines = { ("%s = %s.rename(columns={"):format(df, df) }
      for _, c in ipairs(values.vars) do
        lines[#lines + 1] = ('    %s: "",'):format(A.q(c))
      end
      lines[#lines + 1] = "})"
      return lines
    end,
  },
}

vim.list_extend(M.list, require("analysis.recipes_py"))

local function fill(recipe, lang, df, values)
  if recipe.build then
    return recipe.build(lang, df, values)
  end
  local body = recipe.body:gsub("{{df}}", df)
  for key, cols in pairs(values) do
    local field
    for _, f in ipairs(recipe.fields) do
      if f.key == key then
        field = f
      end
    end
    local text = A.format_cols(lang, cols, field.kind == "cols")
    body = body:gsub("{{" .. key .. "}}", function()
      return text
    end)
    body = body:gsub("{{" .. key .. "_str}}", function()
      return A.q(cols[1])
    end)
  end
  return vim.split(body, "\n", { plain = true })
end

local function start(recipe, where, lang)
  A.pick_df(lang, function(df)
    A.last_df[lang] = df.name
    local values, i = {}, 0
    local function next_field()
      i = i + 1
      local f = recipe.fields[i]
      if not f then
        return A.insert_code(where, lang, fill(recipe, lang, df.name, values))
      end
      A.pick_columns(lang, df, function(cols)
        values[f.key] = f.kind == "col" and { cols[1] } or cols
        next_field()
      end, { title = ("%d/%d %s"):format(i, #recipe.fields, f.title), single = f.kind == "col" })
    end
    next_field()
  end)
end

function M.pick()
  local where = A.capture_pos()
  local lang = A.lang()
  local items = {}
  for _, r in ipairs(M.list) do
    if r.lang == lang then
      items[#items + 1] = { text = r.name, label = r.name, recipe = r, preview = { text = r.body, ft = lang } }
    end
  end
  A.picker({
    title = "分析レシピ (" .. lang .. ")",
    items = items,
    on_pick = function(sel)
      start(sel[1].recipe, where, lang)
    end,
  })
end

-- 一覧を飛ばして名前指定で実行
function M.run(name)
  for _, r in ipairs(M.list) do
    if r.name == name then
      return start(r, A.capture_pos(), r.lang)
    end
  end
  vim.notify("レシピなし: " .. name, vim.log.levels.WARN)
end

return M
