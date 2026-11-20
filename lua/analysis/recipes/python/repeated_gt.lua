-- Python / 反復測定: 表で出す版
local F = require("analysis.recipes.fields")
local T = { lang = "python", cat = "反復測定" }
local L = T
local function add(name, fields, body) L[#L + 1] = { name = name, fields = fields, body = body } end
local col, cols = F.col, F.cols

add("[ペア] 対応のある検定(wide: 前の列 × 後の列, 対応t + Wilcoxon → 表)", { cols("pre", "前(1回目)の列 ※後と同じ順で"), cols("post", "後(2回目)の列 ※前と同じ順で") }, [=[
import numpy as np
import pandas as pd
from scipy import stats
stat = "mean"  # "median" で 中央値 [IQR] 表示
def _desc(x):
    if stat == "mean":
        return f"{x.mean():.2f} ± {x.std():.2f}"
    return f"{x.median():.2f} [{x.quantile(0.25):.2f}, {x.quantile(0.75):.2f}]"
_pre, _post = {{pre}}, {{post}}
assert len(_pre) == len(_post)
_rows = []
for a, b in zip(_pre, _post):
    d = {{df}}[[a, b]].dropna()  # 両方そろった人だけ
    x, y = d[a], d[b]
    dif = y - x
    tt = stats.ttest_rel(y, x)
    ci = tt.confidence_interval()
    _rows.append({
        "変数": f"{a} → {b}", "n": len(d), "前": _desc(x), "後": _desc(y),
        "差(後−前) [95%CI]": f"{dif.mean():.2f} [{ci.low:.2f}, {ci.high:.2f}]",
        "効果量 dz": round(dif.mean() / dif.std(), 2),
        "対応t p": tt.pvalue,
        "Wilcoxon p": stats.wilcoxon(y, x).pvalue,
    })
paired_res = pd.DataFrame(_rows)
_fmt_p = lambda p: "<0.001" if p < 0.001 else f"{p:.3f}"
paired_res.style.format({"対応t p": _fmt_p, "Wilcoxon p": _fmt_p}).hide(axis="index")
# gt 風にするなら: from great_tables import GT; GT(paired_res).fmt(_fmt_p, columns=["対応t p", "Wilcoxon p"])  # uv pip install great_tables]=])

add("[ペア] 対応のある検定(long: ID × 時点の列, 2時点, 対応t + Wilcoxon → 表)", { col("id", "ID(人)"), col("time", "時点(2水準: 前/後)"), cols("vars", "比較する変数") }, [=[
import numpy as np
import pandas as pd
from scipy import stats
stat = "mean"  # "median" で 中央値 [IQR] 表示
def _desc(x):
    if stat == "mean":
        return f"{x.mean():.2f} ± {x.std():.2f}"
    return f"{x.median():.2f} [{x.quantile(0.25):.2f}, {x.quantile(0.75):.2f}]"
_t = {{df}}[{{time}}]
tp = list(_t.cat.remove_unused_categories().cat.categories) if isinstance(_t.dtype, pd.CategoricalDtype) else list(pd.unique(_t.dropna()))  # 出てきた順。変えるなら ["pre", "post"]
assert len(tp) == 2
_rows = []
for v in {{vars}}:
    w = {{df}}.pivot_table(index={{id}}, columns={{time}}, values=v, aggfunc="first").dropna(subset=tp)
    x, y = w[tp[0]], w[tp[1]]
    dif = y - x
    tt = stats.ttest_rel(y, x)
    ci = tt.confidence_interval()
    _rows.append({
        "変数": v, "n": len(w), str(tp[0]): _desc(x), str(tp[1]): _desc(y),
        "差 [95%CI]": f"{dif.mean():.2f} [{ci.low:.2f}, {ci.high:.2f}]",
        "効果量 dz": round(dif.mean() / dif.std(), 2),
        "対応t p": tt.pvalue,
        "Wilcoxon p": stats.wilcoxon(y, x).pvalue,
    })
paired_res = pd.DataFrame(_rows)
_fmt_p = lambda p: "<0.001" if p < 0.001 else f"{p:.3f}"
paired_res.style.format({"対応t p": _fmt_p, "Wilcoxon p": _fmt_p}).hide(axis="index")
# gt 風にするなら: from great_tables import GT; GT(paired_res).fmt(_fmt_p, columns=["対応t p", "Wilcoxon p"])  # uv pip install great_tables]=])


return T
