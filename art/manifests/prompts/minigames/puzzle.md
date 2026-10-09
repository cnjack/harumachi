# Your mini-game: id `puzzle` — 晴町地图拼图 (bedroom desk, sliding-tile puzzle)

Where: the bedroom desk. The player restores a hand-painted map of 晴町 that got scrambled during the move.

Rules: a 4×4 sliding puzzle (15 tiles + one gap) of the map illustration. Time limit 240 s (`duration`).
- Shuffle by applying random legal moves from the solved state (so it is always solvable), about 70–90 moves, never undoing the previous move, and re-shuffle if fewer than 12 tiles end up misplaced.
- Controls: click a tile in the same row/column as the gap to slide it (and the tiles between) toward the gap; or arrow keys / WASD slide the tile next to the gap in that direction. Tiles slide with a quick tween (~0.12 s); input during a slide is queued, not dropped.
- "H" toggles small tile numbers (hint); a small reference thumbnail of the finished map sits beside the board. A move counter is shown with `set_status`.
- Solved: the seams fade out, the full map glows briefly, then the round ends. Score = max(0, 1500 − 6 × moves − 2 × seconds) if solved; on time-out, score = 25 × tiles in the right place.
- mg_auto: a believable solver. Easiest honest approach: remember the shuffle sequence and replay its inverse with human-like pauses (0.25–0.6 s, occasional longer "thinking" stops); it must finish well inside the time limit.

Art to generate: the map illustration (square, 1024×1024): a charming hand-painted illustrated bird's-eye map of a small Japanese town — a stone-paved shopping street running left to right along the top with little shops (bakery, flower shop, zakka shop, post office, a small apartment), a bus stop at the far left end, a shared courtyard below the street with a market stall with a green awning, raised vegetable beds, a big flowering tree in the middle, swings and a small wooden stage, a narrow residential lane on the right with a few houses; soft watercolour-anime style, warm sunny colours, no text or labels. Also the play-area background: a top-down view of a wooden study desk (pencils, a mug, a plant, a desk lamp's warm pool of light) where the board sits; a wooden frame for the board; `icon.png`.

sfx names (besides common): `slide`, `slide_blocked`, `hint`, `solved`.
