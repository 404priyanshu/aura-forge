# Aura Forge — asset generation guide

Prompts for generating the game's art, audio and 3D assets with AI tools, what each tool is best at, and where every finished asset plugs into the game.

## 0. Ground rules (read first)

- **Everything you generate must be uploaded to Roblox** (Creator Hub / Studio) to get an asset ID. Roblox moderates every upload. Keep prompts free of real brands, logos, real people and other games' names.
- **Don't reference other games in prompts** (e.g. never write "like Sol's RNG"). Describe the look you want instead. That keeps the art original and moderation-safe.
- **Check commercial rights** for whichever generator you use. Many AI music and image tools only grant commercial use on paid plans, and a Roblox game with Robux purchases is commercial.
- **Roblox limits worth knowing:** textures and images are effectively capped at 1024×1024 in-game, so generate larger and downscale. A single mesh is limited to 20,000 triangles. Audio uploads count against a monthly quota tied to your account verification.
- **One art direction everywhere.** Paste the style block below into every image and 3D prompt so all assets match each other and the UI.

### Shared style block (append to image and 3D prompts)

> stylized cosmic fantasy, glossy and luminous, soft bloom, rich saturated neon accents (violet #7C5CFF, cyan #00C4FF, gold #FFCE4A) on a deep navy-black background, clean readable silhouette, high contrast, polished mobile-game quality

### Rarity colour reference (from `RarityTable.lua`)

| Tier | Colour | Feel |
|---|---|---|
| Common | grey `#BEC4D2` | dusty, simple |
| Uncommon | green `#5ADC78` | natural, leafy |
| Rare | blue `#4696FF` | watery, crisp |
| Epic | purple `#AA5AFF` | electric, prismatic |
| Legendary | gold `#FFBE28` | royal, radiant |
| Mythic | pink-red `#FF468C` | fiery, mythical |
| Exotic | teal `#00E6D2` | alien, bioluminescent |
| Divine | ivory `#FFF5BE` | holy, angelic |
| Celestial | indigo `#788CFF` | starry, cosmic |
| Secret | red `#FF2828` | ominous, glitched, singular |

---

## 1. Marketing: game icon and thumbnails

**Where it goes:** Creator Dashboard → your experience → Places / Associated Items. No code changes.

**Best tools:** Midjourney (best overall look), ChatGPT image generation (best for following instructions precisely), Ideogram (best when you want the title rendered as text). If an image can't spell "AURA FORGE" cleanly, generate it without text and add the title yourself in Figma, Photopea or Canva.

### Game icon (square, 512×512 after downscale)

```
Square game icon. A glowing crystal die mid-roll, floating above an ornate dark-metal forge altar, bursting with a vortex of multicolored aura light (gold, violet, cyan, pink). Dramatic rim lighting, sparks and stardust, shallow depth of field, centered subject filling 80% of the frame, bold silhouette that reads at small size, no text, no border. [style block]
```

Midjourney: add `--ar 1:1`. Generate 8–12 options and test them at 64×64 px. The icon that still reads at that size wins.

### Thumbnails (16:9, 1920×1080)

**Thumbnail 1, the big pull:**
```
Wide 16:9 game thumbnail. A stylized blocky avatar character stands on a glowing altar, arms raised, as a colossal pillar of crimson and gold light erupts behind them. A shockwave ring of energy spreads across the floor, giant floating text space left empty in the upper third for a title. Cinematic low-angle shot, dramatic god rays, particle sparks everywhere, night sky full of stars. [style block]
```

**Thumbnail 2, the rarity ladder:**
```
Wide 16:9 game thumbnail. A row of ten glowing aura orbs ascending left to right like a staircase, each a different color from dull grey to blazing red, the last one cracked and radiating ominous red light with a question mark silhouette inside. Clean dark background with subtle stars, strong contrast, room on the left for a title. [style block]
```

**Thumbnail 3, luck and loot:**
```
Wide 16:9 game thumbnail. An explosion of gold coins, cyan gems, glowing potion bottles and a four-leaf clover charm bursting outward from a glowing slot-machine style crystal reel. Joyful, energetic composition, motion blur on flying coins, bright rim light, empty space at the top for a title. [style block]
```

Tip: thumbnails with **one clear focal point and huge contrast** perform best in Roblox discovery. Test them small on a phone-sized preview.

---

## 2. UI icons (replace the emoji)

**Where it goes:** `Config.Images` in `src/ReplicatedStorage/Modules/Config.lua`. It has one slot per icon, grouped as `Currencies`, `Menu`, `Gamepasses`, `DevProducts`, `Boosts` and `GemShop`. Paste `"rbxassetid://<id>"` into a slot and that icon replaces its emoji in the HUD, menu, shop and boost chips. Empty slots keep showing the emoji.

**Best tools:** Recraft (best for a **consistent icon set**: lock a style and generate the whole list; also exports SVG), ChatGPT image generation (supports transparent backgrounds directly), Midjourney plus a background remover.

**Format:** 512×512 transparent PNG, centered, ~10% padding, no text, readable at 32 px.

### Base icon prompt

```
Single game UI icon of {SUBJECT}, glossy 3D-rendered stylized look, soft top-left key light, subtle inner glow, thick clean silhouette, slight bevel, centered with padding, transparent background, no text, no shadow outside the object. Palette: {COLORS}. Consistent icon set style.
```

### Icon list

| Icon | {SUBJECT} | {COLORS} |
|---|---|---|
| Coins | a small stack of thick gold coins with a star emblem | gold, warm orange |
| Gems | a faceted diamond-cut crystal gem | cyan, light blue, white sparkle |
| Lucky Token | a ticket-shaped token with a four-leaf clover stamp | violet, lilac |
| Menu: Auras | an open satchel spilling glowing orbs | violet, multicolor glow |
| Menu: Shop | a small market stall awning with a coin | gold, violet |
| Menu: Quests | a rolled parchment scroll with a ribbon | parchment beige, green ribbon |
| Menu: Rewards | a wrapped gift box with a glowing bow | pink, gold |
| Menu: Settings | a mechanical gear | silver, cyan |
| Pass: 2x Luck | a glowing four-leaf clover with "×2" energy sparks (no text) | emerald green, gold |
| Pass: Auto Roll | two circular arrows wrapped around a glowing die | cyan, violet |
| Pass: Fast Roll | a lightning bolt striking a die | yellow, electric blue |
| Pass: +2 Slots | a backpack with two extra glowing pockets | violet, gold |
| Pass: VIP | an ornate crown with a gem | gold, ruby |
| Luck Potion | a round potion flask with swirling green clover liquid | emerald, glass |
| Lucky Brew | a steaming teacup with a clover in the steam | jade, porcelain white |
| Coin Charm | a horseshoe magnet attracting coins | red, gold |
| Coin Pouch / Chest / Vault | a small coin pouch / an open treasure chest / a round vault door overflowing with coins | gold, brown leather / gold, wood / steel, gold |

Generate the set in one session with the same seed/style so they match.

---

## 3. Aura visuals

The aura is the thing players chase, so this is where quality matters most.

### 3a. Particle textures (biggest upgrade for the least effort)

**Where it goes:** `Config.Particles` in `Config.lua`:
- `DefaultTexture` is the main aura particle for every rarity, and is also used for the 3D burst on reveal.
- `DefaultSparkleTexture` is an optional twinkle layer on top.

To give one rarity its own look, set `Texture` / `SparkleTexture` on that tier in `RarityTable.lua`. Empty values fall back to the defaults, and then to Roblox's built-in particle.

These black-background textures only work on 3D particles. Don't use them in UI images, where the black would show.

**Best tools:** any image generator. Generate **white/greyscale on pure black**: the game tints particles to each rarity's colour, so one texture serves all tiers. In Roblox, set `ParticleEmitter.LightEmission` to 1 so the black background disappears.

**Format:** 512×512 PNG, the shape centered, soft falloff to pure black at the edges.

```
Particle texture sprite on pure black background: {SHAPE}. Pure white and light grey only, no color, soft glowing falloff fading to black well before the edges, centered, no text, flat orthographic view, high resolution, suitable for a video game particle effect.
```

| Texture | {SHAPE} | Used for |
|---|---|---|
| Soft orb | a soft round glow with a bright core | Common–Rare base glow |
| Sparkle star | a four-pointed sparkle star with thin long rays | Rare+ twinkles |
| Wisp | a curling smoke wisp, elongated vertically | Uncommon/Exotic flowing auras |
| Flame lick | a single stylized flame tongue | Mythic (Phoenix Wing), Legendary |
| Shard | a sharp crystal shard with a glowing edge | Chronoshard, Prism |
| Rune ring | a thin circular ring of glowing arcane runes | Divine/Celestial orbiting rings |
| Shockwave | a thin expanding ring with soft inner fade | reveal bursts |
| Star field | scattered tiny star points of varied size | Celestial, Event Horizon |
| Glitch block | a fragmented pixel-glitch square | Secret tier |

### 3b. 3D aura pieces for the top tiers (Mythic → Secret)

**Where it goes:** build each as a **Model in `ReplicatedStorage/AuraModels/<Name>`** and set `Model = "<Name>"` on the item in `RarityTable.lua`. Particle setups built from Attachments work today. **Solid meshes (wings, halos) need a small code change** so they're welded to the character instead of falling. *Ask Claude to add mesh welding first.*

**Best tools:**
- **Roblox Studio's built-in mesh generation (Cube 3D, via the Assistant).** It's instant, in-engine and already within Roblox limits, but lower fidelity. Great for blocking out shapes.
- **Meshy, Tripo or Rodin (Hyper3D)** give much higher quality. Best results come from **image-to-3D**: generate a concept image first with the prompt below, then feed that image to the 3D tool.
- **Cleanup in Blender:** decimate to under 20,000 triangles (aim for 3–8k for wearables), bake textures to 1024 px, export FBX, then import with Studio's 3D Importer.

Concept-image prompt (then image-to-3D):

```
Game asset concept, isolated on plain neutral grey background, three-quarter view, single object, no character: {OBJECT}. Stylized, clean readable shapes, glowing emissive details, game-ready proportions, no text. [style block]
```

| Aura (tier) | {OBJECT} |
|---|---|
| Solar Crown (Legendary) | a floating halo-crown of golden sun rays, thin ring with spiky radiant points |
| Phoenix Wing (Mythic) | a pair of stylized flaming phoenix wings made of layered feather-shaped flame panels |
| Chronoshard (Mythic) | a cluster of six floating teal crystal clock-hand shards arranged in a circle |
| Void Lotus (Exotic) | a floating dark-violet lotus flower with glowing cyan petal edges, open bloom |
| Aurora Prime (Exotic) | three translucent ribbon bands of aurora light twisted into a ring |
| Seraphim (Divine) | two pairs of elegant ivory-white angel wings with golden trim, stylized |
| Genesis (Divine) | an ornate golden halo with a slowly rotating inner ring of tiny suns |
| Event Horizon (Celestial) | a small black hole sphere with a glowing indigo accretion disk ring |
| Astral Throne (Celestial) | a floating backplate shaped like a cosmic throne silhouette made of constellations |
| The Last Light (Secret) | a cracked white star core leaking red light, surrounded by shattered floating fragments |

For a text-to-3D tool, drop the "concept image" framing and use `3D model of {OBJECT}, stylized game asset, clean topology, emissive glowing parts` plus the style block.

---

## 4. World: lobby, altar and sky

**Where it goes:** placed directly in Studio (Workspace / Lighting). The Rojo project doesn't manage Workspace or Lighting. **Important:** once you've added world assets, save the place in Studio and use `rojo serve` from then on. `rojo build` makes a fresh place file and would discard your map.

### Skybox

**Best tool:** Blockade Labs Skybox AI generates seamless 360° panoramas, which ordinary image generators can't. Export the equirectangular image, convert it into **6 cube faces** with an "equirectangular to cubemap" converter, upload all 6, then set them on a `Sky` object in `Lighting` (SkyboxBk/Dn/Ft/Lf/Rt/Up).

```
Fantasy night sky high above the clouds, deep navy and violet nebula swirls, scattered bright stars and a few distant glowing planets, a faint aurora band in cyan and gold near the horizon, calm sea of soft clouds below, magical and serene, no landmasses close up.
```

Alternative: an "infinite cosmic void" style, with deeper blacks and dense star fields, if you want the aura colours to pop even more.

### Surfaces and materials

**Best tool:** Roblox Studio's built-in **Material Generator** (creates tiling MaterialVariants from a prompt) and **Texture Generator** (textures an existing mesh from a prompt). Both work in-engine and are already the right format.

| Surface | Prompt |
|---|---|
| Plaza floor | `polished dark obsidian tiles with thin glowing violet inlay lines between tiles, subtle reflections` |
| Altar stone | `ancient carved dark stone with gold filigree engravings and faint arcane runes` |
| AFK zone pad | `soft glowing indigo energy grid on dark glass, calm and hypnotic` |
| Crystal rocks | `translucent cyan crystal with internal light refraction and frosted edges` |

### Props (3D)

Same pipeline as the aura pieces (concept image → Meshy/Tripo/Rodin → Blender → import), or Studio's mesh generation for quick versions.

| Prop | Prompt object |
|---|---|
| Roll altar (centerpiece) | `a circular forge altar on a three-step dais, dark stone with gold filigree, a floating glowing crystal die above a basin of liquid light` |
| Luck Hour obelisk | `a tall slim obelisk with a glowing clover emblem and an hourglass carved into its face` |
| Crystal clusters | `a cluster of tall glowing crystals of varying heights growing from dark rock` |
| Floating islands | `a small floating rock island with glowing crystals and drifting dust underneath` |
| Lanterns | `an ornate hanging lantern with a floating flame orb inside, gold frame` |
| AFK zone sign | `a small floating crescent-moon sign with a sleepy star, no text` |
| Leaderboard frame | `an ornate tall gold-trimmed board frame with an empty dark panel, no text` |

Lighting tip: set `Lighting.Technology` to *Future*, add `Atmosphere`, `Bloom` and `ColorCorrection` (cool tint), and use neon parts and `PointLight`s on the altar. Lighting alone transforms the scene.

---

## 5. Audio

**Where it goes:** `Config.Audio` in `src/ReplicatedStorage/Modules/Config.lua`, already wired up. Paste `"rbxassetid://<id>"` into the matching key and it plays.

### Music (`Config.Audio.Music`, a playlist)

**Safest option:** Roblox's licensed music library (Creator Store → Audio, creator *Roblox*). It's free, cleared for every experience, and needs no upload.

**AI option:** Suno or Udio. Check that your plan grants commercial rights. Ask for instrumental and a seamless ending.

```
Lobby: Instrumental, no vocals. Dreamy cosmic synthwave lofi for a fantasy gacha game lobby, 90 BPM, warm analog pads, soft arpeggiated synth, gentle sidechained beat, glittering chime accents, hopeful and slightly mysterious, loop-friendly with no intro build or fade-out, 2 minutes.
```
```
Luck Hour: Instrumental, no vocals. Upbeat euphoric electronic track for a timed luck bonus event, 128 BPM, driving four-on-the-floor kick, bright supersaw chords, sparkling arps, celebratory and urgent, loop-friendly, 2 minutes.
```

Keep music quiet. `Config.Audio.MusicVolume` defaults to 0.3 so reveal SFX stay on top.

### Sound effects (`Config.Audio.Sfx`)

**Best tool:** ElevenLabs Sound Effects (text-to-SFX with a duration setting). Stable Audio also works. Generate 4+ variations of each and pick the best. Trim silence at the start so they play instantly.

| Key | Duration | Prompt |
|---|---|---|
| `Click` | 0.1 s | `soft glassy UI button click, short, clean, satisfying, no reverb` |
| `Tick` | 0.08 s | `tiny crisp mechanical tick of a spinning prize wheel, very short` |
| `Whoosh` | 0.6 s | `magical rising whoosh with shimmering sparkles, building anticipation` |
| `RevealSmall` | 0.5 s | `light pleasant magical chime pop, item reveal, bright and short` |
| `Fanfare` | 1.5 s | `short triumphant orchestral fanfare with brass and sparkling bells, rare item reveal` |
| `RevealBig` | 3 s | `huge cinematic magical impact, deep boom followed by a choir swell and shimmering sparkles, legendary item reveal` |
| `Purchase` | 1 s | `satisfying coins and gem shimmer cascade, successful purchase` |
| `Claim` | 0.8 s | `cheerful reward collect jingle, coins and magical sparkle` |
| `Error` | 0.3 s | `soft low muted buzz, gentle error, not harsh` |

Optional extra, the Secret tier: `ominous glitching digital distortion swelling into a massive reverse-cymbal impact and an eerie choir, 4 seconds`. Wiring a per-tier sound needs a new key; the `Sound` field in `RarityTable` already picks an Sfx key per tier.

---

## 6. Animations

**Where it goes:** the game doesn't play character animations yet. A "summon" pose on roll and a float during big reveals need a small code hook (`Animator:LoadAnimation`). *Ask Claude to add it once you have animation IDs.* Animations must be uploaded by the account or group that owns the experience, or they won't play.

**Best tools:**
- **Roblox Studio Animation Capture.** Record the motion from your webcam or a video, then clean it up in the Animation Editor. Quickest way to an R15 animation.
- **Moon Animator 2** (Studio plugin) for hand-keyed polish.
- AI text-to-motion tools that export FBX can work, but **retargeting to Roblox's R15 rig** takes extra effort in Blender. Only worth it for complex motion.

What to make:

| Animation | Motion to capture or describe |
|---|---|
| Roll summon | `raise right hand overhead with fingers spread, slight lean back, hold, then a quick downward fist pump; 1.2 s` |
| Big-pull float | `rise slightly onto tiptoes, arms spread outward palms up, head tilted up in awe; loopable 2 s` |
| Victory | `two-arm triumphant fist raise with a small jump; 1.5 s` |
| AFK idle | `sitting cross-legged meditation with gentle breathing sway; loopable 4 s` |

---

## 7. Suggested order (best upgrade per hour)

1. **SFX** in `Config.Audio.Sfx` (already wired up, instant payoff).
2. **Licensed lobby music** from Roblox's library.
3. **Particle textures** in `Config.Particles` (already wired up).
4. **Lighting plus a skybox** (no code).
5. **Roll altar and lobby props.**
6. **Game icon and thumbnails** (before publishing publicly).
7. **UI icons** in `Config.Images` (already wired up).
8. **3D Mythic+ aura pieces** (needs mesh welding) and **animations**.
