import json
import math
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

try:
    import pyarrow.feather as feather
except ImportError:  # pragma: no cover
    feather = None

from gdx2arrow import SV_EPS, SV_NA, SV_NONE, default_classify, write_manifest, write_symbol_table  # noqa: E402


@unittest.skipIf(feather is None, "pyarrow not installed")
class WriterTests(unittest.TestCase):
    def test_special_values_round_trip(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "P.arrow"
            n = write_symbol_table(p, [["a", "b", "c", "d", "e"]],
                                   {"value": [1.5, -0.0, float("inf"), float("nan"), 0.0]})
            self.assertEqual(n, 5)
            t = feather.read_table(str(p))
            self.assertEqual(t.column_names, ["d1", "value", "value__sv"])
            v = t.column("value").to_pylist()
            sv = t.column("value__sv").to_pylist()
            self.assertEqual(sv, [SV_NONE, SV_EPS, SV_NONE, SV_NA, SV_NONE])
            self.assertEqual(math.copysign(1.0, v[1]), -1.0)
            self.assertTrue(math.isinf(v[2]))
            self.assertTrue(math.isnan(v[3]))

    def test_set_and_manifest(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d)
            write_symbol_table(out / "S.arrow", [["r1", "r1"], ["p1", "p2"]], {"element_text": ["", "x"]})
            m = write_manifest(out, "test.gdx", [{"name": "S", "kind": "set", "file": "S.arrow"}], ["r1", "p1", "p2"])
            self.assertEqual(json.loads((out / "manifest.json").read_text())["format_version"], m["format_version"])
            t = feather.read_table(str(out / "S.arrow"))
            self.assertEqual(t.column_names, ["d1", "d2", "element_text"])

    def test_default_classify(self):
        self.assertEqual(default_classify([1.0, -0.0, float("nan")]), [SV_NONE, SV_EPS, SV_NA])


if __name__ == "__main__":
    unittest.main()
