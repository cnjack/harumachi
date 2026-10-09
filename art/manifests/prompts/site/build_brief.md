Build a single-page "coming soon" website for an indie game, in Simplified Chinese, as static files in the current directory (site/). Plain HTML + CSS + vanilla JS only: no frameworks, no build step, no CDN, no external fonts or scripts, nothing loaded from the network. It must work when opened straight from the file system and when served from any static host.

## The game

- Title: 明年夏祭 (English subtitle: Harumachi: Next Summer)
- One line: 回到晴町的这个夏天，把停了十五年的夏祭办回来。
- Status: 开发中 · 即将上线. Platform: macOS 单机, 中文, 键鼠 (PC 平台待定). No release date yet.
- Story (use this, do not invent plot):
  奶奶走的那个春天，空辞掉城里的工作，搬回山谷里的小镇晴町。十岁那年夏天，他在这里捞金鱼，纸网一下就破了；有个女孩和他约好：明年夏祭，还要一起来。可是那之后，晴町再也没有办过夏祭。
  这个夏天，他在河边的市民农园种菜，给邻居做饭，周六傍晚到庭院的集市摆摊，一点点把大家的旧物和往事拼起来——直到庭院里再一次搭起盆舞台。
- Things you can do (feature cards, keep the copy short and concrete, no marketing clichés):
  1. 种菜：河边的市民农园，15 种作物，浇水、施肥、看它们一天天长大。
  2. 做饭：家里的厨房和莲的面包店，24 个配方，做好的料理送人或者拿去卖。
  3. 摆摊：每个周六傍晚，庭院里开集市。
  4. 过节：七夕、品评会、夏祭、花火大会、灯笼流、月见。
  5. 小游戏：捏饭团、捞金鱼、太鼓、拼地图、拆箱子。
  6. 旧物：十三件晴町的旧东西，每一件后面有一段往事。
- People (with the face images below):
  空 (sora) — 主角，从城里搬回奶奶的房子。
  澪 (mio) — 町内会的联络人，那年夏祭一起捞金鱼的女孩。
  莲 (ren) — 面包店的第三代，菠萝包的配方五十年没变。
  小葵 (aoi) — 来奶奶家过暑假，从没见过晴町的夏祭。
  和子阿姨 (kazuko) — 晴町商店的店主，嗓门大，爱塞东西给你。
- Credits line in the footer: 画面、音乐、配音由 AI 工具辅助制作 · © 2026 明年夏祭 开发组

## Assets (already in site/assets/, use these exact files; each .webp has a .jpg / .png twin, use <picture> with webp first)

- assets/hero.webp (1916x821): key visual, a sunny shopping street in summer, the hero stands lower right looking at the huge zelkova tree; the upper half is open sky. Use it full-bleed behind the title.
- assets/night.webp (2172x724): night festival panorama with the bon-odori tower, lanterns and fireworks. Use it for the story's second half or the "coming soon" footer band.
- assets/cast.webp (1774x887): the five characters standing together on a pale background.
- assets/scene_1..4.webp (1280x720): anime stills (bus through the valley, the tree, the goldfish memory, the veranda) for a gallery/strip.
- assets/face_sora|mio|ren|aoi|kazuko.webp (320x320, transparent): character faces.
- assets/fonts/wenkai-sub.woff2: LXGW WenKai (霞鹜文楷) subset. Use it for ALL text (headings and body), with fallbacks "PingFang SC", "Hiragino Sans GB", serif. Keep the OFL.txt licence file next to it. If you add Chinese characters that are not in the file, list them in site/NEW_CHARS.txt (I will re-subset the font).

## Look and feel (important)

The whole game is drawn in a Makoto Shinkai-inspired ANIME style: clean line art, flat cel shading, luminous summer blue skies with huge cumulus clouds, warm golden sunlight, cool lavender shadows, paper lanterns. The site must feel like the opening of a summer anime film, not like a generic SaaS or crypto landing page, and never photorealistic.

- Palette: summer sky blues (#2f7fd1 to #9fd8f2), cloud white #fffaf0, washi paper cream #f6efe0, lantern red #d8453a, sunset orange #f3a44b, night indigo #1d2350, ink brown #3b2a20 for text. Avoid purple-on-white gradients.
- Texture: a subtle washi paper grain (CSS noise via an inline SVG feTurbulence data URI is fine), soft grain overlay on images.
- Type: generous line height (1.9 for body), vertical Japanese-style accents are welcome (e.g. a vertical 「夏祭」 label with writing-mode: vertical-rl).
- Layout: not a centred template. Asymmetry, big sky, overlapping cut-outs (faces overlapping panels), a strip that feels like film frames.

## Animation (the user asked for animation; make it lovely but calm)

1. Hero: the key visual slowly zooms and drifts (Ken Burns, 25–30 s, alternate). Parallax: on scroll the sky layer moves slower than the title. Drifting clouds: 3–4 soft white CSS/SVG cloud shapes crossing the sky slowly at different speeds. Floating light motes / petals (a light canvas particle layer, ~40 particles, very cheap). The title 明年夏祭 appears character by character with a soft blur-to-sharp reveal, then the subtitle and the "即将上线" badge.
2. Paper lanterns: 3 small CSS-drawn chochin lanterns hanging from a string near the top edge, gently swaying (transform-origin at the top, different phases), glowing softly.
3. Scroll reveals: sections fade/slide up with IntersectionObserver, staggered.
4. Story section: the text reveals line by line as it enters the viewport.
5. Characters: faces float slightly (bob), on hover a face lifts and its one-line intro appears in a speech-bubble-like paper card.
6. Night band: fireworks drawn on a canvas over night.webp (a few bursts every couple of seconds, low particle count), lanterns twinkle.
7. A small "subscribe" form (email input + 订阅上线通知 button). There is no backend: on submit, validate the email, store it in localStorage, show a thank-you message with a tiny confetti of paper petals. Say clearly in small text that this is a placeholder ("邮件订阅即将开放，目前只保存在你的浏览器里").
8. Respect prefers-reduced-motion: turn off the particle canvases, Ken Burns, parallax and fireworks, keep simple fades.
9. Pause canvases when the tab is hidden or the canvas is off-screen. Keep total JS small (< 15 KB unminified is ideal) and 60 fps on a laptop.

## Page structure (one page)

1. Hero (100vh): key visual, drifting clouds, lanterns, title + subtitle + one line, "即将上线" badge, a gentle scroll hint.
2. 故事 (story): the two paragraphs above, with scene_3 (goldfish memory) as a framed still, and a vertical label.
3. 在晴町的一天 (features): the six feature cards (small, paper-card style, each with a tiny hand-drawn-looking CSS/SVG icon; do not use emoji).
4. 晴町的人 (characters): cast image plus the five faces with intros.
5. Film strip: scene_1..4 as film frames, slowly auto-scrolling horizontally (pausable on hover), with captions: 沿着晴川开进山谷 / 庭院中央的老榉树 / 十岁那年的金鱼 / 这个夏天，住下来.
6. Night band: night.webp + fireworks canvas, large text 「今年夏天，庭院里见。」 and the subscribe form.
7. Footer: title, platform line, credits line, a back-to-top link.

## Quality bar

- Responsive: looks right at 1440x900, 1280x720 and on a 390x844 phone (stack everything, hero title still big).
- Accessibility: semantic landmarks, alt text in Chinese for every image, visible focus styles, sufficient contrast for text over images (use a soft gradient scrim), the form has a label.
- <title>明年夏祭 · Harumachi: Next Summer — 即将上线</title>, a meta description in Chinese, Open Graph tags pointing at assets/hero.jpg, a favicon made as an inline SVG (a small red lantern).
- Files: site/index.html, site/style.css, site/main.js. Do not modify anything outside site/. Do not create other pages.
- When done, reply with a short list of the files you created. Do not start a server.
