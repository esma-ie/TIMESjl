# Crafted cases: added data files

Each folder holds the files a crafted case in [`../crafted.toml`](../crafted.toml)
adds to an open suite model, to reach TIMES code paths no suite model's data
reaches. A crafted case inherits the licence of the model it extends; the files
here are TIMES.jl's own (GPL-3.0-or-later, like the repository) and contain no
data from any other model.

| Folder | Extends | What it adds | Made for |
| --- | --- | --- | --- |
| `demo12_red17b/` | TIMES_Demo demo12 (`etsap-TIMES/TIMES_Demo` @ `962db86`, CC BY 4.0) | `demo12_red17b.run`: `demo12.run` unchanged but for a three-line header and the include of `red17b.dd`. `red17b.dd`: `VDA_EMCB` OIL→INDCO2 (0.1 in both regions) and four `FLO_BND` records on `REFEOIL00`'s OIL input (LO, UP below and above the existing `ACT_BND`, FX) | M1.3 change 17b, 5 Nov 2026: under REDUCE, an emission whose source flow is the activity flow (`cal_red.red` L37-38) and flow bounds on that flow (`bnd_flo.mod` L37-39); with REDUCE off, `bnd_flo.mod` L25-27. Fixtures `demo12_red17b`, `demo12_red17b_off` |

Make a crafted reference with the harness's `--suite` option, for example:

```
python reference/python/make_reference.py --suite reference/crafted.toml --out ../timesjl-reference --solvers CPLEX,HIGHS --root times_source=../TIMES_model --root times_demo=../TIMES_Demo --model TIMES_Demo-demo12_red17b
```

then the fixtures with `scripts/make_m11_fixture.jl`.
