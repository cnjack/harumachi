# Stretch sleeve guide: saved-source rebuild

`rebuild_sleeve_guide_candidate.py` closes the conversion, guide fit and midpoint
writer entry chain. It takes explicit saved inputs and writes a new directory;
it does not capture Godot, replace formal assets, recover historical rig/gait
inputs, or confer visual acceptance.

```sh
python art/tools/characters/rebuild_sleeve_guide_candidate.py \
  --input <closed-seam-parent.glb> \
  --protected-reference <protected-original.glb> \
  --peaks-manifest <native-four-peaks/joint-poses/manifest.json> \
  --continuous-native <native-transitions/transition-gait.json> \
  --output-dir <new-output-directory> \
  --character mio --weight-smoothing 1000 --phase .5
```

The peaks manifest's capture root must retain its `model-hashes.json`: the writer
checks the closed-seam source SHA. The continuous JSON must retain actual final
bone matrices, model transforms, actual named shape values and same-frame
acknowledgements. The converter rejects acknowledged mismatches; missing
acknowledgements are counted and excluded. NumPy and SciPy are required. The
entry uses only normal repository Python modules; no ignored Python module is
imported. Saved models, pose packets, traces and reports remain external data
inputs/evidence, with their source hashes recorded.

The default recipe uses `monotone-arm`, strength 1, weight smoothing 1000 and no
guide smoothing. It preserves stored skin weights and only changes the existing
four stretch guide fields plus a midpoint control and their corresponding
NORMAL values. The midpoint lies at the closest actual front stretch pose to the
requested phase; its scalar has finite support between .375 and .625. The two
neighboring stretch guide functions crossfade through it. Other old scalar
functions remain unchanged; other actions receive a zero new column. The writer
reports the inserted-key function error rather than assuming preservation.

`--max-world-shift .12` is a direct-peak calculation parameter, **not a bound
imposed by the least-squares mode**. Independently check actual decoded world
movement over captured and interpolated poses. Rest delta magnitude is not the
actual world movement or the distance from skin.

The rebuild emits `rebuild-manifest.json` with input/tool/output hashes and exact
commands. To reproduce an older manifest label byte for byte, pass its explicit
`--source-kind`; the label is provenance text, not a deformation setting.

Before adopting a result, check the correct old/new shape functions, all physical
UV seams, bare skin and skirt preservation, all changed face/edge support,
normals and distances to available actual skin/filler geometry. Source-triangle
area ratios and transported-normal signs are diagnostic and do not themselves
prove naturalness or self-intersection. A model without a hidden torso surface
cannot supply a numerical torso/clothes air gap. Inspect native views and the
whole transition; retain any visible or geometric limits in the report.
