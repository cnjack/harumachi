"""Focused metadata-format controls; no Blender/Godot/numerical dependencies."""
import json
import struct
import unittest
from normalize_scalar_bounds import normalize_bytes, parse


def fixture(accessors):
    encoded = json.dumps({"asset": {"version": "2.0"}, "accessors": accessors,
                          "nodes": [{"name": "unchanged"}]}).encode()
    encoded += b" " * ((-len(encoded)) % 4)
    tail = struct.pack("<II", 8, 0x004E4942) + b"\x01\x02\x03\x04\x05\x06\x07\x08"
    return struct.pack("<IIIII", 0x46546C67, 2, 20 + len(encoded) + len(tail),
                       len(encoded), 0x4E4F534A) + encoded + tail


class ScalarBoundsControls(unittest.TestCase):
    def test_numeric_scalar_wraps_only_bounds_and_preserves_bin_other_json(self):
        source = fixture([{"type": "SCALAR", "min": 0.0, "max": 1.0, "count": 3},
                          {"type": "VEC3", "min": [1, 2, 3], "max": [4, 5, 6]}])
        output, report = normalize_bytes(source)
        old, old_bin = parse(source)
        new, new_bin = parse(output)
        self.assertEqual(new["accessors"][0]["min"], [0.0])
        self.assertEqual(new["accessors"][0]["max"], [1.0])
        self.assertEqual(report["changes_count"], 2)
        self.assertEqual(old_bin, new_bin)
        self.assertEqual(old["nodes"], new["nodes"])
        self.assertEqual(old["accessors"][1], new["accessors"][1])

    def test_legal_arrays_are_whole_file_byte_exact_no_op(self):
        source = fixture([{"type": "SCALAR", "min": [0.0], "max": [1.0]}])
        output, report = normalize_bytes(source)
        self.assertEqual(output, source)
        self.assertEqual(report["changes_count"], 0)

    def test_non_scalar_numeric_metadata_is_not_silently_reinterpreted(self):
        source = fixture([{"type": "VEC3", "min": 0.0, "max": 1.0}])
        output, report = normalize_bytes(source)
        self.assertEqual(source, output)
        self.assertEqual(report["changes_count"], 0)

    def test_bool_is_rejected_instead_of_becoming_numeric_bound(self):
        with self.assertRaisesRegex(ValueError, "nonnumeric"):
            normalize_bytes(fixture([{"type": "SCALAR", "min": False}]))


if __name__ == "__main__":
    unittest.main()
