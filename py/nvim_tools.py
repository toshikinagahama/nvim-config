# Neovim(lua/analysis)から呼ぶ Python カーネル側ヘルパ。結果は JSON を一時ファイルに書いて返す。
# カーネルのグローバルには _nv だけを置く。
def _nv_setup():
    import io
    import json
    import os
    import sys
    import types

    from IPython import get_ipython

    ns = get_ipython().user_ns
    hidden = {"In", "Out", "exit", "quit", "get_ipython", "open", "view", "figviewer_view", "figviewer_clear"}

    def out(obj, path):
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, default=str)
        os.replace(tmp, path)

    def run(path, fn):
        try:
            res = fn()
        except Exception as e:  # noqa: BLE001
            res = {"error": f"{type(e).__name__}: {e}"}
        out(res, path)

    def is_df(x):
        pd = sys.modules.get("pandas")
        return pd is not None and isinstance(x, pd.DataFrame)

    def shape(x):
        s = getattr(x, "shape", None)
        if isinstance(s, tuple):
            return "×".join(map(str, s))
        try:
            return str(len(x))
        except TypeError:
            return ""

    def get(name, df=None):
        if name in ns:
            return ns[name]
        d = ns.get(df) if df else None
        if is_df(d) and name in d.columns:
            return d[name]
        raise NameError(f"'{name}' が見つからない(変数でも {df or 'df'} の列でもない)")

    def user_vars():
        for name, x in list(ns.items()):
            if name.startswith("_") or name in hidden:
                continue
            if isinstance(x, (types.ModuleType, types.FunctionType, type, types.BuiltinFunctionType)):
                continue
            yield name, x

    def preview(x):
        if is_df(x):
            buf = io.StringIO()
            x.info(buf=buf, verbose=True, show_counts=True)
            return buf.getvalue()
        return repr(x)[:3000]

    def objects(path):
        run(path, lambda: [
            {"name": n, "class": type(x).__name__, "shape": shape(x), "size": "",
             "df": is_df(x), "preview": preview(x)}
            for n, x in user_vars()
        ])

    def column_info(d, col):
        v = d[col]
        import pandas as pd

        if pd.api.types.is_numeric_dtype(v):
            prev = v.describe().to_string()
        else:
            prev = v.value_counts(dropna=False).head(15).to_string()
        return {"name": str(col), "type": str(v.dtype), "na": int(v.isna().sum()),
                "unique": int(v.nunique(dropna=False)), "preview": prev}

    def dfs(path):
        run(path, lambda: [
            {"name": n, "shape": shape(x), "columns": [column_info(x, c) for c in x.columns]}
            for n, x in user_vars() if is_df(x)
        ])

    def peek(name, kind, df, path):
        def fn():
            x = get(name, df)
            import pandas as pd

            s = x if isinstance(x, (pd.Series, pd.DataFrame)) else pd.Series(x)
            if kind == "summary":
                head = f"{name}  [{s.dtype if hasattr(s, 'dtype') else type(x).__name__}, n={len(s)}, NA={int(s.isna().sum().sum())}]"
                return {"text": head + "\n" + s.describe(include="all").to_string()}
            if kind == "table":
                return {"text": s.value_counts(dropna=False).to_string()}
            import matplotlib.pyplot as plt

            plt.figure()
            if pd.api.types.is_numeric_dtype(s):
                s.dropna().plot.hist(bins=30, title=name)
            else:
                s.value_counts(dropna=False).plot.bar(title=name)
            return {"text": "図 → figviewer http://localhost:8766"}

        run(path, fn)

    def as_df(x):
        import pandas as pd

        if hasattr(x, "data") and type(x).__name__ == "Styler":
            x = x.data
        if isinstance(x, pd.Series):
            x = x.to_frame()
        if not isinstance(x, pd.DataFrame):
            x = pd.DataFrame(x)
        return x

    def tsv(name, path):
        def fn():
            import pandas as pd

            d = as_df(get(name))
            keep_index = not isinstance(d.index, pd.RangeIndex)
            return {"text": d.to_csv(sep="\t", index=keep_index).rstrip("\n"), "shape": shape(d)}

        run(path, fn)

    def view(name, path):
        def fn():
            v = ns.get("figviewer_view")
            if v is None:
                raise RuntimeError("figviewer が無効(nvim から起動したカーネルで FIGVIEWER=1 のとき有効)")
            v(as_df(get(name)), name=name)
            return {"text": f"{name} → http://localhost:8766"}

        run(path, fn)

    def view_html(name, path):
        def fn():
            import json, os, random, time
            from pathlib import Path

            x = get(name)
            if hasattr(x, "as_raw_html"):  # great_tables.GT
                body = x.as_raw_html()
            elif hasattr(x, "to_html"):  # pandas Styler / DataFrame
                body = x.to_html() if hasattr(x, "export") else as_df(x).head(500).to_html()
            elif hasattr(x, "_repr_html_"):
                body = x._repr_html_()
            else:
                raise RuntimeError(f"{name} ({type(x).__name__}) は HTML 表示できない")
            root = Path.home() / ".cache" / "figviewer"
            root.mkdir(parents=True, exist_ok=True)
            entry_id = time.strftime("%Y%m%d-%H%M%S") + "-" + "".join(random.choice("0123456789abcdef") for _ in range(6))
            html = f"{entry_id}.html"
            (root / html).write_text("<!doctype html><meta charset='utf-8'><body style='font-family:sans-serif;padding:12px'>" + body, encoding="utf-8")
            ep = root / "entries.json"
            try:
                entries = json.loads(ep.read_text(encoding="utf-8"))
            except Exception:
                entries = []
            entries.append({"id": entry_id, "kind": "html", "title": f"{name} (py)", "html": html, "files": [html],
                            "run": entry_id, "exec": None, "time": time.strftime("%H:%M:%S"), "cell": f"view_html({name})"})
            tmp = ep.with_suffix(".json.py.tmp")
            tmp.write_text(json.dumps(entries, ensure_ascii=False), encoding="utf-8")
            os.replace(tmp, ep)
            return {"text": f"{name} (HTML) → http://localhost:8766"}

        run(path, fn)

    def levels(df, col, path):
        def fn():
            import pandas as pd

            v = ns[df][col]
            if isinstance(v.dtype, pd.CategoricalDtype):
                lv = [str(x) for x in v.cat.categories]
                numeric = False
            else:
                numeric = bool(pd.api.types.is_numeric_dtype(v))
                uniq = v.dropna().unique().tolist()
                lv = sorted(uniq) if numeric else sorted(map(str, uniq))
                if numeric:
                    lv = [int(x) if float(x).is_integer() else x for x in lv]
            return {"values": lv[:200], "n": len(lv), "numeric": numeric}

        run(path, fn)

    def fmt_cell(v):
        import math

        if v is None or (isinstance(v, float) and math.isnan(v)):
            return ""
        if isinstance(v, float):
            if v != 0 and abs(v) < 0.001:
                return f"{v:.2e}"
            return f"{v:.3f}".rstrip("0").rstrip(".") if abs(v) < 1e6 else f"{v:,.0f}"
        s = str(v)
        return "" if s in ("nan", "NaT", "<NA>") else s

    def docx(name, file, path):
        def fn():
            import pandas as pd

            try:
                from docx import Document
            except ImportError as e:
                raise RuntimeError("python-docx が必要: uv pip install python-docx") from e
            x = get(name)
            if hasattr(x, "summary2"):  # statsmodels の結果 → 係数表
                x = x.summary2().tables[1]
            d = as_df(x)
            if not isinstance(d.index, pd.RangeIndex):
                d = d.reset_index().rename(columns={"index": ""})
            os.makedirs(os.path.dirname(file) or ".", exist_ok=True)
            doc = Document()
            t = doc.add_table(rows=1, cols=len(d.columns))
            t.style = "Table Grid"
            for cell, c in zip(t.rows[0].cells, d.columns):
                cell.text = str(c)
                for r in cell.paragraphs[0].runs:
                    r.bold = True
            for row in d.itertuples(index=False):
                for cell, v in zip(t.add_row().cells, row):
                    cell.text = fmt_cell(v)
            doc.save(file)
            return {"text": file}

        run(path, fn)

    return types.SimpleNamespace(out=out, objects=objects, dfs=dfs, peek=peek, tsv=tsv, view=view, view_html=view_html,
                                 levels=levels, docx=docx)


_nv = _nv_setup()
del _nv_setup
