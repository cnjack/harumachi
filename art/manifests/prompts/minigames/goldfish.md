# Your mini-game: id `goldfish` — 捞金鱼 (courtyard goldfish pool, dexterity game)

Where: the shared courtyard, a festival-style goldfish scooping tank (kingyo-sukui). Round: 60 s (`duration`), 3 paper scoops (poi).

View: straight top-down onto a shallow rectangular tank that fills most of the play area (light-blue interior, wooden rim), with a small water bowl on the side where caught fish go.
Fish (12–14 at once, respawn gently to keep the count): small red 小红 (10 pts, common, fast), black 黑出目金 (20 pts, slower, bigger), calico 三色 (30 pts, quick turns), and a rare golden 黄金 (60 pts, 0–1 at a time). Swimming: smooth wander (steering behaviours / noise), soft separation, tail wiggle via rotation oscillation or a 2–3 frame flap, slight depth feel (fish near the surface brighter and bigger).
Poi: follows the mouse (with slight lag). Hold the left button = poi goes into the water (ripple rings, the paper darkens as it gets wet); release = lift it out. Keyboard: arrows/WASD move, hold Space to dip.
- A fish is caught when it is inside the paper circle at the moment of lifting and the paper is still intact. Several fish at once is possible but heavier.
- Paper durability (100): drains while submerged (base rate), faster when moving fast in the water, and on lifting by the weight of the fish on it (bigger fish = more). At 0 the paper tears (torn-poi sprite, fish drop back), a new poi appears after a short beat. The round ends when all 3 poi are torn or time is up.
- Fish near a dipping poi get startled and dart away briefly; approaching slowly from behind a fish works best — that is the skill.
- Caught fish arc into the bowl (tween) with `pop_text("+30")`.

Art to generate: the tank background (top-down, blue-painted interior with light caustics, wooden rim, a few floating green leaves); fish sprites seen from above (red, black demekin, calico, golden; transparent; ideally 2 tail frames each); the poi (intact, wet, torn); the side bowl with water; soft light-caustics overlay (or do it with a shader); `icon.png`.

sfx names (besides common): `water_in`, `water_out`, `catch`, `tear`, `escape`, `splash`, `new_poi`.
