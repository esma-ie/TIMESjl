"""Convert a GAMS GDX file into a directory of Arrow IPC files for TIMES.jl.

Layout written to ``out_dir`` (format version 1):

    manifest.json          one entry per symbol (see SYMBOL_FIELDS below)
    uels.arrow             column "uel": the universe of labels
    <symbol>.arrow         one file per symbol with records

Each symbol file has positional domain columns ``d1 .. dN`` (strings, record
order exactly as read from the GDX) followed by its value columns:

    set        element_text (string)
    parameter  value (float64)
    variable   level, marginal, lower, upper, scale (float64)
    equation   level, marginal, lower, upper, scale (float64)

GAMS special values are kept explicit. For every float column ``c`` there is an
int8 column ``c__sv``: 0 ordinary value, 1 EPS, 2 NA, 3 UNDEF. +INF/-INF stay as
IEEE infinities in ``c``; EPS is written as -0.0 and NA/UNDEF as NaN in ``c``.

Only ``write_symbol_table`` and ``write_manifest`` are used in CI (no GAMS);
``convert_gdx`` needs the GAMS Python API (``gams.transfer``), available on any
machine with GAMS via ``pip install gamsapi[transfer]==<GAMS version>``.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

FORMAT_VERSION = 1
VALUE_COLUMNS = {
    "set": ["element_text"],
    "alias": [],
    "parameter": ["value"],
    "variable": ["level", "marginal", "lower", "upper", "scale"],
    "equation": ["level", "marginal", "lower", "upper", "scale"],
}
SV_NONE, SV_EPS, SV_NA, SV_UNDEF = 0, 1, 2, 3


def default_classify(values):
    """Special-value codes without gams.transfer: EPS = -0.0, any NaN = NA."""
    codes = []
    for x in values:
        if x is None or (isinstance(x, float) and math.isnan(x)):
            codes.append(SV_NA)
        elif x == 0.0 and math.copysign(1.0, x) < 0:
            codes.append(SV_EPS)
        else:
            codes.append(SV_NONE)
    return codes


def write_symbol_table(path: Path, domain_values: list[list[str]], value_columns: dict, classify=default_classify):
    """Write one symbol to an Arrow IPC file.

    ``domain_values``: one list of label strings per domain position.
    ``value_columns``: ordered mapping column name -> list of values; floats get
    a ``__sv`` companion column, ``element_text`` stays a string column.
    """
    import pyarrow as pa
    import pyarrow.feather as feather

    arrays, names = [], []
    for i, col in enumerate(domain_values, start=1):
        arrays.append(pa.array([str(v) for v in col], type=pa.string()))
        names.append(f"d{i}")
    for name, vals in value_columns.items():
        if name == "element_text":
            arrays.append(pa.array(["" if v is None else str(v) for v in vals], type=pa.string()))
            names.append(name)
            continue
        vals = [float("nan") if v is None else float(v) for v in vals]
        codes = list(classify(vals))
        fixed = []
        for v, c in zip(vals, codes):
            if c == SV_EPS:
                fixed.append(-0.0)
            elif c in (SV_NA, SV_UNDEF):
                fixed.append(float("nan"))
            else:
                fixed.append(v)
        arrays.append(pa.array(fixed, type=pa.float64()))
        names.append(name)
        arrays.append(pa.array(codes, type=pa.int8()))
        names.append(f"{name}__sv")
    table = pa.Table.from_arrays(arrays, names=names) if arrays else pa.table({})
    feather.write_feather(table, str(path), compression="zstd")
    return table.num_rows


def write_manifest(out_dir: Path, source: str, symbols: list[dict], uels: list[str]):
    import pyarrow as pa
    import pyarrow.feather as feather

    feather.write_feather(pa.table({"uel": pa.array(uels, type=pa.string())}), str(out_dir / "uels.arrow"), compression="zstd")
    manifest = {
        "format": "timesjl-dump",
        "format_version": FORMAT_VERSION,
        "source": source,
        "uels": "uels.arrow",
        "symbols": symbols,
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=1))
    return manifest


def _gt_classify(gt):
    sv = gt.SpecialValues

    def classify(values):
        import numpy as np

        arr = np.asarray(values, dtype=float)
        codes = np.zeros(arr.shape, dtype=np.int8)
        codes[sv.isEps(arr)] = SV_EPS
        codes[sv.isNA(arr)] = SV_NA
        codes[sv.isUndef(arr)] = SV_UNDEF
        return codes.tolist()

    return classify


def gams_system_directory(gams_exe: str | None = None) -> str | None:
    """Directory of the GAMS system to hand to ``gams.transfer``.

    gams.transfer only finds GAMS on its own when the system directory is on
    PATH. Resolve it from the executable the harness was given (or ``gams`` on
    PATH, or the PyPI ``gamspy_base`` package) so conversions work regardless
    of PATH. Returns None when nothing is found, which lets gams.transfer raise
    its own error.
    """
    import shutil

    exe = shutil.which(gams_exe or "gams")
    if exe:
        return str(Path(exe).resolve().parent)
    try:
        import gamspy_base

        return gamspy_base.directory
    except ImportError:
        return None


def convert_gdx(gdx_path: Path, out_dir: Path, only: set | None = None, system_directory: str | None = None) -> dict:
    """Convert every symbol in ``gdx_path`` (needs gams.transfer)."""
    import gams.transfer as gt

    out_dir.mkdir(parents=True, exist_ok=True)
    c = gt.Container(load_from=str(gdx_path), system_directory=system_directory or gams_system_directory())
    classify = _gt_classify(gt)
    symbols = []
    for name in c.listSymbols():
        if only and name not in only:
            continue
        sym = c[name]
        if isinstance(sym, (gt.Alias, gt.UniverseAlias)):
            symbols.append({"name": name, "kind": "alias", "alias_with": getattr(sym.alias_with, "name", "*"),
                            "dimension": sym.dimension, "domain": list(sym.domain_names), "description": "",
                            "records": 0, "file": None})
            continue
        if isinstance(sym, gt.Set):
            kind = "set"
        elif isinstance(sym, gt.Parameter):
            kind = "parameter"
        elif isinstance(sym, gt.Variable):
            kind = "variable"
        elif isinstance(sym, gt.Equation):
            kind = "equation"
        else:
            continue
        entry = {"name": name, "kind": kind, "type": str(getattr(sym, "type", "")),
                 "dimension": sym.dimension, "domain": list(sym.domain_names),
                 "description": sym.description, "records": 0, "file": None}
        df = sym.records
        if df is not None and len(df) > 0:
            dom_cols = list(df.columns[: sym.dimension])
            domain_values = [df[col].astype(str).tolist() for col in dom_cols]
            values = {}
            for vc in VALUE_COLUMNS[kind]:
                if vc in df.columns:
                    values[vc] = df[vc].tolist()
            fname = f"{name}.arrow"
            entry["records"] = write_symbol_table(out_dir / fname, domain_values, values, classify)
            entry["file"] = fname
        symbols.append(entry)
    uels = [str(u) for u in c.getUELs()]
    return write_manifest(out_dir, str(gdx_path), symbols, uels)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("gdx", type=Path)
    p.add_argument("out_dir", type=Path)
    p.add_argument("--symbols", help="comma-separated subset of symbols")
    a = p.parse_args(argv)
    only = set(a.symbols.split(",")) if a.symbols else None
    m = convert_gdx(a.gdx, a.out_dir, only)
    print(f"{a.gdx} -> {a.out_dir}: {len(m['symbols'])} symbols")


if __name__ == "__main__":
    sys.exit(main())
