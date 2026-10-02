"""Check SMU argument encoding without accessing hardware."""

import importlib.machinery
import types
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "files/usr/local/bin/pbo-curve"
LOADER = importlib.machinery.SourceFileLoader("pbo_curve", str(SCRIPT))
pbo_curve = types.ModuleType(LOADER.name)
LOADER.exec_module(pbo_curve)


class CurveOptimizerTests(unittest.TestCase):
    def test_core_argument_selects_each_core(self):
        for core in range(8):
            with self.subTest(core=core):
                self.assertEqual(pbo_curve.core_arg(core), core << 20)

    def test_negative_offset_is_encoded_for_the_selected_core(self):
        with patch.object(pbo_curve, "smu") as smu_command:
            pbo_curve.set_offset(3, -30)

        smu_command.assert_called_once_with(
            pbo_curve.OP_SET_CORE, (3 << 20) | (-30 & 0xFFFF)
        )

    def test_unsigned_readback_becomes_a_negative_offset(self):
        with patch.object(pbo_curve, "smu", return_value=2**32 - 29):
            self.assertEqual(pbo_curve.get_offset(1), -29)


if __name__ == "__main__":
    unittest.main()
