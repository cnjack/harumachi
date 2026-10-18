# Character contact filter

Optional macOS arm64 acceleration for fixed Godot `4.8.dev7.official.c971f93e7`, single precision. Uses the public C API and the engine's original bound `TriangleMesh.intersect_ray`; it does not own garment constraints, coefficients or weights. Windows/Web/Intel use GD. The descriptor restricts `include_tags` to `macos.arm64`. Missing package may log a loader error but GD must remain functional.

`source-lock.json` records all compile inputs, official source URLs, generated public header and formal API dump SHA. `api-layout.json` is an exact excerpt of that pinned dump (the complete dump is reproducible with pinned engine `--headless --dump-extension-api` in a separate project). `filter_abi.h` is derived from those single-precision/64-bit builtin sizes and Vector3 offsets. Public API is used for packed-array access; container layout is never guessed. The included official header retains the upstream license notice.

From this folder:

```sh
python3 build.py --verify-only
python3 build.py --out /tmp/libnative_triangle_filter.arm64.dylib
```

Build uses installed clang and explicit no-fast-math/no-FMA flags. No Godot executable or dependency download is called by build.py. A rebuilt library gets its own receipt and must repeat fieldwise/native checks; this does not promise identical binary bytes across SDK/debug-path/signing changes. Only the accepted library is installed under `game/addons/character_contact_filter/bin/`, with an explicit Git LFS rule. Do not overwrite the accepted library in a rebuild command.

The current COW candidate copies the accepted original `f6c60416…` library unchanged. It remains a candidate until integration/fallback/guard/performance/export verification completes; source preparation is not production promotion.
