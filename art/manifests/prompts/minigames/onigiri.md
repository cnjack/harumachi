# Your mini-game: id `onigiri` — 捏饭团 (kitchen, timing game)

Where: the player's new home kitchen. Neighbours drop by the kitchen window and order rice balls. Round length: 75 s (`duration`).

Flow per rice ball (one active order at a time; 2–3 customers wait in a queue with a patience bar):
1. 盛饭 Scoop rice: a fill meter rises while the player holds Space (or holds the left mouse button over the rice cooker); release inside the green sweet spot. Too little / too much lowers quality.
2. 放馅 Filling: choose the filling the customer asked for — 梅干 (umeboshi), 鲑鱼 (salmon), 昆布 (kombu), 金枪鱼蛋黄酱 (tuna mayo). Keys 1–4 or click the ingredient bowls. Wrong filling still makes an onigiri but the customer is disappointed (small score).
3. 捏形 Shaping: three presses in rhythm. A ring shrinks toward a target circle (about 0.8 s per beat); press A/D alternately (or click) as it meets the circle. Timing accuracy → shape quality; show the rice morphing from a lumpy blob to a neat triangle.
4. 包海苔 Nori: a nori strip slides back and forth under the rice ball; press Space when it's centred.
5. The finished onigiri slides to the customer, who reacts (happy / neutral portrait swap, small bounce). Score = base 60 for the right filling (15 for wrong) + up to 40 quality (scoop + shaping + nori) + speed bonus from remaining patience; consecutive perfect onigiri add a combo bonus. A customer whose patience runs out leaves (no score, combo reset).

Customers: use the existing portraits `res://assets/ui/portraits/{mio,ren,haru}_{neutral,happy}.png` (512×512, transparent) shown small in speech-bubble order cards: the bubble shows the filling icon plus its name. You may also generate one extra generic neighbour portrait (a kind middle-aged woman in an apron, same anime style, neutral + happy) for variety.

Art to generate (hand-painted anime, warm kitchen light): elevated front view of a kitchen counter as the play-area background (wooden cutting board in the middle, bamboo mat, a white rice cooker on the left, four small ceramic ingredient bowls, a kitchen window with morning light at the top where customers appear); rice-ball sprites for the stages (loose rice mound, lumpy ball, neat triangle, triangle with nori); the four filling icons; a nori strip; a wooden rice paddle; soft steam wisps; plus `icon.png` AND `onigiri_item.png` (192×192 transparent, a single onigiri with nori — used as the inventory icon of the reward item).

Stars guide: a decent player makes ~6–8 onigiri in 75 s. Choose thresholds accordingly.

sfx names you may use (besides the common ones): `rice_scoop`, `rice_press`, `filling`, `nori`, `serve`, `order_bad`, `customer_leave`.
