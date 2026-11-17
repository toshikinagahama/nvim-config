-- R / 生存
local F = require("analysis.recipes.fields")

return {
  lang = "r",
  cat = "生存",

  {
    name = "Kaplan-Meier 曲線+log-rank 検定+リスク集合表",
    fields = { F.col("time", "観察期間"), F.col("event", "イベント(1=発生, 0=打ち切り)"), F.col("g", "群"), F.input("times", "生存率を出す時点(カンマ区切り, time と同じ単位)", "1, 3, 5") },
    body = [[
library(survival)
fit <- survfit(Surv({{time}}, {{event}}) ~ {{g}}, data = {{df}})
fit                                          # 群ごとの n・イベント数・中央生存時間
survdiff(Surv({{time}}, {{event}}) ~ {{g}}, data = {{df}})   # log-rank
summary(fit, times = c({{times}}))           # 各時点の生存率(単位は time と同じ)
survminer::ggsurvplot(fit, data = {{df}}, pval = TRUE, conf.int = TRUE, risk.table = TRUE,
                      xlab = "期間", ylab = "生存率", legend.title = {{g_str}}, ggtheme = theme_minimal())]],
  },

  {
    name = "Cox 比例ハザード回帰(HR+比例ハザード性の確認)",
    fields = { F.col("time", "観察期間"), F.col("event", "イベント(1/0)"), F.cols("vars", "説明変数") },
    body = [[
library(survival)
d_s <- {{df}} %>% dplyr::select({{time}}, {{event}}, all_of({{vars}})) %>% tidyr::drop_na()
m <- coxph(reformulate(sprintf("`%s`", {{vars}}), response = sprintf("Surv(`%s`, `%s`)", {{time_str}}, {{event_str}})), data = d_s)
tbl_regression(m, exponentiate = TRUE)       # HR(95%CI)
zph <- cox.zph(m)
zph                                          # p<0.05 の変数は比例ハザード性の仮定違反
survminer::ggcoxzph(zph)
survminer::ggforest(m, data = d_s)]],
  },
}
