-- Python / plotly
local F = require("analysis.recipes.fields")

return {
  lang = "python",
  cat = "plotly",

  {
    name = "散布図(ホバーでID表示, 色分け, トレンド線)",
    fields = { F.col("x", "x"), F.col("y", "y"), F.col("color", "色分け"), F.cols("hover", "ホバー表示する列") },
    body = [[
import plotly.express as px
fig = px.scatter({{df}}, x={{x}}, y={{y}}, color={{color}}, hover_data={{hover}},
                 trendline="ols", opacity=0.6, template="simple_white")
fig.show()]],
  },

  {
    name = "時系列(複数系列, 範囲スライダー付き)",
    fields = { F.col("time", "時刻列"), F.cols("vals", "表示する列") },
    body = [[
import pandas as pd
import plotly.express as px
d = {{df}}.assign(_t=pd.to_datetime({{df}}[{{time}}])).sort_values("_t")
fig = px.line(d, x="_t", y={{vals}}, template="simple_white")
fig.update_xaxes(rangeslider_visible=True, title=None)
fig.show()]],
  },

  {
    name = "箱ひげ(全点表示, 群別)",
    fields = { F.col("y", "数値"), F.col("by", "群") },
    body = [[
import plotly.express as px
fig = px.box({{df}}, x={{by}}, y={{y}}, points="all", color={{by}}, template="simple_white")
fig.show()]],
  },

  {
    name = "散布図行列",
    fields = { F.cols("vars", "変数"), F.col("color", "色分け") },
    body = [[
import plotly.express as px
fig = px.scatter_matrix({{df}}, dimensions={{vars}}, color={{color}}, opacity=0.5, template="simple_white")
fig.update_traces(diagonal_visible=False, marker_size=3)
fig.show()]],
  },

  {
    name = "ヒストグラム(群別の重ね描き)",
    fields = { F.col("x", "変数"), F.col("color", "群") },
    body = [[
import plotly.express as px
fig = px.histogram({{df}}, x={{x}}, color={{color}}, barmode="overlay", opacity=0.6,
                   histnorm="probability density", marginal="box", template="simple_white")
fig.show()]],
  },
}
