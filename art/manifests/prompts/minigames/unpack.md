# Your mini-game: id `unpack` — 拆箱整理 (living room, placement puzzle)

Where: the living room of the player's new home, full of moving boxes. Inspired by the game "Unpacking": calm, tactile, satisfying. Untimed, but a clock runs and finishing faster gives a bonus; cap the round at 150 s (`duration` = 150; when time is up, score what was placed).

Play area: a front view of one living-room wall with furniture drawn as a grid of slots:
- a tall bookshelf (e.g. 3 columns × 4 rows of cells),
- a kitchen-side open shelf / dish rack area (e.g. 4 × 2),
- a low sideboard top and a window sill (decor areas, e.g. 6 × 1 and 3 × 1),
- the moving boxes on the floor at the bottom-left (3 boxes, opened one after another).
Cells are about 90–110 px. Each item has a footprint (1×1, 2×1, 1×2) and a category: 书 book, 餐具 tableware, 摆件 decor, 植物 plant, 杂物 misc.
Allowed zones: books → bookshelf; tableware → kitchen shelf; decor/plants → sideboard, window sill or the bookshelf top row; misc → bookshelf bottom row or sideboard. When the player drags an item over a slot, highlight green (fits and allowed), orange (fits but "not quite the right place" — allowed, fewer points) or red (doesn't fit / overlapping), with a short Chinese reason label ("书放在书架上更好找", "放不下").

Flow: click a box to open it (lid-flap animation); items come out one at a time into a "hand" tray; drag the current item with the mouse and drop it on the grid (right click or R rotates 2×1 items). Keyboard alternative: arrows move a slot cursor, Space picks/places, R rotates. Already-placed items can be picked up again. When the last item of the last box is placed, the round ends; empty boxes fold flat.
About 22–26 items total, ≥ 16 distinct item sprites: books (stack, single upright pair, big art book 2×1), mugs, teapot, rice bowls, plates stack, glass jar, small cactus, pothos in pot, photo frame, alarm clock, desk lamp, daruma, maneki-neko figurine, snow globe, vase with flowers, record player 2×1, stuffed rabbit, wind-up radio, candle, tissue box.
Scoring: allowed zone +30 per item, "right place" bonus +10 more; +5 for each same-category neighbour touching it (books next to books); finish bonus max(0, 300 − 2 × seconds). The self test must prove the layout can always hold every item in its best zone (e.g. run a greedy packer over the item list).

Art to generate: the living-room wall background with the empty shelves, sideboard and window (warm plaster wall, honey wood, afternoon light shafts, front view, empty shelves so items can be placed on top); an item sprite sheet (sliced into individual transparent PNGs, drawn in the same front view); a cardboard moving box closed / open / flattened; `icon.png`.

sfx names (besides common): `pickup`, `place`, `place_good`, `bump`, `box_open`, `box_fold`, `rotate`.
