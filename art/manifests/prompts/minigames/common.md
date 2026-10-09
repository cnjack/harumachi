# Task: implement ONE mini-game for the Godot 4.7.2 game 晴町日常

晴町日常 is a cozy, Makoto-Shinkai-style Japanese small-town life game. All player-facing text is Simplified Chinese.
You work in a private copy of the project: the Godot project is `game/` inside the current working directory. Other people implement the other mini-games in parallel in their own copies; the integrator will copy ONLY your files back.

## Files you own (create only these)
- `game/scripts/minigames/mg___ID__.gd` — the mini-game. First line: `extends MiniGame`. No `class_name`.
- `game/assets/minigames/__ID__/` — every asset you generate (PNG). Must include `icon.png` (256×256, transparent background, a cute illustrated icon of this mini-game for menus).
- `game/assets/minigames/__ID__/CREDITS.md` — one line per generated image: file name, "codex image_gen", and the prompt you used.
Do NOT modify any other file (base class, UI, autoloads, data, scenes). If the base class is missing something, work around it inside your subclass and mention it in your final reply.

## Read first
- `game/scripts/minigames/minigame.gd` — the base class and its contract (read it fully).
- `game/scripts/ui/ui_theme.gd` — palette (INK, INK_SOFT, PAPER, EDGE, ACCENT, GOOD, BAD), `UITheme.box()`, `UITheme.label()`. The font (LXGW WenKai) is inherited from the theme automatically.
- `game/scripts/autoload/audio.gd` — sounds are played through the base helper `sfx(name)` → `Audio.sfx("mg_" + name)`.
- `game/scripts/minigames/mg_sandbox.gd` — standalone runner.

## How to run
```
GODOT=/Users/jack/workpath/godot/tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot
$GODOT --headless --path game --import                         # after adding/changing art
$GODOT --headless --path game res://scenes/mg_sandbox.tscn -- --mg=__ID__ --selftest    # must end with "ALL PASS", exit 0
$GODOT --path game res://scenes/mg_sandbox.tscn -- --mg=__ID__ --auto --shots=/tmp/mg___ID___shots   # windowed demo run, PNG every 1.5 s
```
Use `timeout` on every Godot command (e.g. `timeout 150`). The windowed run shows the intro card, the countdown, a full round played by your `mg_auto`, and the result card; it quits by itself. Open several of the screenshots and judge them like an art director: fix overlapping text, unreadable elements, empty areas, ugly placeholder shapes, wrong scale. Iterate until it looks polished. If a windowed run is impossible in your sandbox, say so and rely on the headless checks, but still try.

## Art direction
- Hand-painted anime look, luminous Shinkai-like palette: warm sunlight, soft cool-lavender shadows, clean shapes, cozy and gentle. Never photorealistic, never flat vector clip-art.
- The base already draws the UI chrome (warm paper frame, header with title / score / timer, intro and result cards). You fill the 1560×760 play area (`stage`). Give it a proper illustrated background — never leave the plain paper colour showing as the play area.
- Generate illustrations with your built-in image generation tool (image_gen). For sprites ask for a transparent background; if an image comes back opaque, key the background out with Python (`<venv>/python` has Pillow, numpy, scipy). Sprite sheets: slice into separate PNGs and trim. Downscale to the size actually used (backgrounds ≤ 1600 px wide, sprites ≤ 512 px). Keep the game's art under ~8 MB total.
- Procedural drawing in Godot (`_draw`, `StyleBoxFlat`, `Line2D`, polygons, simple `canvas_item` shaders, tweens) is welcome for meters, ripples, particles, highlights — combined with the illustrations so the result feels crafted.
- Juice: small tweens on hits, pop_text() for feedback ("完美！", "+30"), a gentle screen-shake or squash where it fits. Keep it calm and cozy, not frantic.

## Code rules
- Godot 4.7 GDScript, tabs, static typing where practical. Everything visual is a child of `stage` (1560×760, top-left origin).
- Input: handle keyboard and mouse in `mg_input(event)`. Mouse position: `stage_mouse()`. Read game keys from `event.physical_keycode` (InputMap actions other than "interact" (E/Space) are not guaranteed). Escape is reserved by the base (leave).
- Sounds: call `sfx("<name>")` with ONLY the names listed in your spec plus the common ones: `count`, `go`, `good`, `perfect`, `miss`, `result`. The files don't exist yet (the audio team synthesises them from your name list); missing files are silently ignored. Don't create audio files.
- `mg_auto(delta)`: demo AI for the autoplay video. It must play visibly and convincingly (move the cursor/scoop smoothly, react with human-like delays), reach about a 2-star result, and finish the round within the time limit (untimed games: ≤ 75 s).
- `mg_simulate(skill, seed)`: pure logic, no nodes or timers, deterministic, < 50 ms. Model the real rules (not just `skill * max`). Required: skill 1.0 → 3 stars, skill 0.0 → 0 stars, average score non-decreasing with skill.
- `mg_self_test()`: at least 8 meaningful checks of your rules (scoring, judgement windows, win/lose, edge cases, solvability, the simulate thresholds). Headless-safe (it runs after `_ready`, with `stage` built).
- A round must always end (time limit or completion). No blocking loops. 60 FPS; don't allocate big things every frame.
- Star thresholds (`mg_info().stars`): an average first-time player should get 1–2 stars; 3 stars needs skill.
- Text: short, friendly Chinese. Rules on the intro card: 2–4 lines. Controls line: e.g. "鼠标拖动 · 空格 放下 · Esc 离开".

## When done
Run the self test one final time (must be ALL PASS) and reply with: files created, how the game plays, star thresholds, the exact sfx names used, controls, known limitations, and any base-class change you'd suggest.
