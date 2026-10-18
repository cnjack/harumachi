# Character contact filter

Optional macOS arm64 acceleration for fixed Godot `4.8.dev7.official.c971f93e7`, single precision. Uses the public C API and the engine's original bound `TriangleMesh.intersect_ray`; it does not own garment constraints, coefficients or weights. Windows/Web/Intel use GD. The descriptor restricts `include_tags` to `macos.arm64`. Missing package may log a loader error but GD must remain functional.

`source-lock.json` records all compile inputs, official source URLs, generated public header and formal API dump SHA. `api-layout.json` is an exact excerpt of that pinned dump (the complete dump is reproducible with pinned engine `--headless --dump-extension-api` in a separate project). `filter_abi.h` is derived from those single-precision/64-bit builtin sizes and Vector3 offsets. Public API is used for packed-array access; container layout is never guessed. The included official header retains the upstream license notice.

From this folder:

```sh
python3 build.py --verify-only
python3 build.py --out /tmp/libnative_triangle_filter.arm64.dylib
```

Build uses installed clang and explicit no-fast-math/no-FMA flags. No Godot executable or dependency download is called by build.py. A rebuilt library gets its own receipt and must repeat fieldwise/native checks; this does not promise identical binary bytes across SDK/debug-path/signing changes. Only the accepted library is installed under `game/addons/character_contact_filter/bin/`, with an explicit Git LFS rule. Do not overwrite the accepted library in a rebuild command.

The accepted library is `c521f8dd10adfeb5ebd84e4698cffa3a3a9f77dcfd8761e8d17fa5cf9f4b4822`, recorded in `source-lock.json`. In addition to the unchanged triangle-ray filter, `build_layer_geometry` moves the ordered bounds/grid loop into C11. Only Kazuko enables that method by default; other characters keep their prior path. Missing method, missing native backend, or `--native-geometry=off` retains the original GD bounds/grid calculation.

The implementation preserves Vector3 float32 writebacks, scalar double arithmetic order, panel/face/cell order, grid margins and the original constraints. The new header is a pinned compile input. Same-callback native auditing compared 152 full solves and 528 bounds/grid, ordered-tree and full-filter payloads byte for byte, including actual one-to-four iteration solves. Eleven complete final poses matched the old library; 1mm bounds and .001 amount negative controls were rejected. A separate actual-old-library check exercised the method-absence fallback without a forced flag (82 pairs, four poses).

The later running-arm style change keeps the `c521` library and its source unchanged. Its current combination passed 2579 exclusive functional checks; see [running-arm verification](../../docs/game-design/RUNNING_ARMS_20261018.md).

The preceding character-feedback combination at `7eeb7fc` passed 2502 functional checks with the pinned engine, including the original 5mm cloth and 8ms solve gates. That run observed Kazuko solve p95 6.124ms and Mio 6.694ms; these are local measurements, not a performance promise for other platforms. Full raw logs retain Dummy-renderer, fault-injection and environment errors; strict error-free log qualification is false. Evidence is under `evidence/rig_fix_20261018_followup/`. Desktop ZIP/Web were not updated, and the earlier temporary exported-app loading/signature check applies to the old `f6c60416…` library only.
