# Your mini-game: id `taiko` — 祭典太鼓 (courtyard stage, rhythm game)

Where: the little wooden stage in the courtyard; neighbours rehearse the festival drumming. Set `"mute_bgm": true` in `mg_info()` so the game music stops while you play.

Data (already in the project, read-only):
- Chart: `res://data/taiko_chart.json` = `{"title", "bpm": 132, "offset": first-note time (s), "duration": song length (s), "notes": [{"t": seconds from the start of the audio file, "k": "don" | "ka"}, ...]}` (104 notes).
- Song: `res://assets/audio/music/taiko.ogg` (51.6 s; fue melody + shime pulse + a soft guide drum on every chart note). Play it with your own `AudioStreamPlayer` on bus `"Music"`, started in `mg_begin()`.
Timing: song time = `player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()`, smoothed so it never runs backwards; if the stream can't load (or the audio driver is Dummy/headless), fall back to an internal clock so the game still works.

Gameplay: notes scroll from right to left along a horizontal lane toward a judgement circle near the left, at a fixed speed (a note is visible ~1.6 s before its hit time). don = red circle, hit with F or J (or left click); ka = blue circle, hit with D or K (or right click).
Judgement: |error| ≤ 0.050 s → 良 (100 pts), ≤ 0.100 s → 可 (50 pts), otherwise / wrong colour / not hit by +0.100 s → 不可 (0, combo reset). A hit with no note within 0.15 s does nothing (no penalty). Combo bonus: +10 per note while combo ≥ 10. Each hit plays `sfx("don")` or `sfx("ka")` (big drum face on the left flashes: centre for don, rim for ka), judgement text pops, combo counter bounces. The round ends 1.5 s after the last note.
Stars: compute from the chart in `mg_info()` as fractions of the maximum possible score (e.g. 45 % / 70 % / 88 %).
mg_auto: hits each note with a random error of ±35 ms, misses ~6 %, and uses the right key; drum flashes accordingly.

Art to generate: the play-area background — an evening festival stage (paper lanterns glowing, soft bokeh, warm orange and indigo sky, wooden stage floor), leaving a calmer band where the note lane sits; the drum face seen from the front (big round taiko skin with rim tacks) for the left side; don and ka note sprites (red and blue rounded notes with a simple cute face or kanji-free design); a hit burst effect; `icon.png`.

sfx names (besides common): `don`, `ka`, `combo`, `full_combo`.
