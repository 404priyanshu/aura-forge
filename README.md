# Aura Forge

[![luau-lsp](https://github.com/404priyanshu/aura-forge/actions/workflows/luau-lsp.yml/badge.svg)](https://github.com/404priyanshu/aura-forge/actions/workflows/luau-lsp.yml)

An RNG/gacha game for Roblox, written in Luau. Players grind coins, roll for auras across ten rarity tiers (up to a **1 in 10,000,000** Secret), equip their best pulls to boost their luck and coin rate, then roll again.

**grind → roll → pull rare → equip for multipliers → grind faster → roll more**

## Features

- **Server-authoritative rolls.** The client only asks to roll. The server checks the cooldown and cost, rolls with luck it calculates itself, and saves the result.
- **Luck system.** Luck multiplies the odds of the rarer tiers, and Common shrinks to make room. Bonuses stack from equipped auras, the 2x Luck pass, potions, the global Luck Hour and a permanent luck bonus earned from quests and the index.
- **Animated reveals.** The bigger the rarity, the bigger the show: name spin, cinematic build-up, flash, light rays, sparks, camera shake, a 3D particle burst and a rarity sound. Rare pulls are announced to the whole server.
- **Ways to earn coins:** a click-to-earn button, an AFK zone checked on the server, 8 quests (most can be repeated at higher levels), and offline earnings for up to 8 hours.
- **Monetization:** 5 gamepasses (2x Luck, Auto Roll, Fast Roll, +2 Equip Slots, VIP), 5 developer products and a gem shop. A purchase is saved before it's confirmed, so it can't be lost or granted twice.
- **Rewards that bring players back:** a 7-day login streak, playtime rewards, Luck Hour every 2 hours (the same schedule on every server), index completion rewards and a 3-step tutorial for new players.
- **Data:** ProfileService with session locking and auto-save, a versioned save format that upgrades old saves, and a live copy of the player's data on the client.
- **UI built in code** (no Roact). A dark theme scales to fit phones and PCs, with large touch targets. It covers the HUD, Index, Shop, Quests, Rewards and Settings screens, plus toasts, banners and popups.
- **Admin commands** in chat for players listed in Config.

## Project layout

```
src/
  ReplicatedStorage/Modules/       Config, RarityTable, ProfileTemplate, Formulas, Util, Signal, Net
  ServerScriptService/
    Server.server.lua              bootstrapper (Init → Start)
    Services/                      Data, Roll, Inventory, Economy, Monetization,
                                   Quest, DailyReward, Event, Admin
  StarterPlayer/StarterPlayerScripts/
    Client.client.lua              bootstrapper
    Controllers/                   Data, UI, Roll, Currency, Audio
    UI/                            UIKit, Hud, RollReveal, Notifications, *Window
```

Each service and controller is a ModuleScript with `Init()` and `Start()`. They reach each other through a shared table passed to `Init()`, so no module has to require another service directly.

## Quick start

You need [Rojo](https://rojo.space) 7.x. [ProfileService](https://github.com/MadStudioRoblox/ProfileService) is bundled in `src/ServerScriptService/Packages/` (Apache-2.0, see [`third_party/ProfileService`](third_party/ProfileService)).

```bash
rojo serve
```

Connect from the Rojo plugin in Studio, or build a place file:

```bash
rojo build default.project.json -o AuraForge.rbxlx
```

Then publish the place and turn on **Game Settings → Security → Enable Studio Access to API Services**. [SETUP.md](SETUP.md) covers the full checklist: where every file goes, which IDs and audio to replace, and a play-test walkthrough.

## Formatting, type checking & linting

Every push and pull request runs three checks (see [`.github/workflows/luau-lsp.yml`](.github/workflows/luau-lsp.yml)):

- [StyLua](https://github.com/JohnnyMorganz/StyLua) formatting check ([`stylua.toml`](stylua.toml))
- [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) type check against the Roblox API
- [selene](https://github.com/Kampfkarren/selene) lint ([`selene.toml`](selene.toml)); warnings fail the build too

To run them locally:

```bash
rokit install
stylua src            # formats in place (CI runs `stylua --check src`)
./scripts/analyze.sh
selene src
```

## Rebalancing

Every tunable number is in [`Config.lua`](src/ReplicatedStorage/Modules/Config.lua): costs, cooldowns, rewards, quests, gamepass/product IDs, Luck Hour timing and audio. Rarity tiers and auras are in [`RarityTable.lua`](src/ReplicatedStorage/Modules/RarityTable.lua). Both files are commented, so you can rebalance without touching any game logic.

## Admin commands

Admins are the UserIds in `Config.Admins`, the place owner, and everyone during a Studio play-test.

| Command | Effect |
|---|---|
| `/givecoins <n> [player]`, `/givegems`, `/givetokens` | Give currency |
| `/setluck <multiplier> [player]` | Luck multiplier for this session only |
| `/givepotion <minutes> [player]` | Add Luck Potion time |
| `/givepass <PassKey> [player]` | Grant a gamepass |
| `/giveitem <item name>` | Give yourself an aura |
| `/luckhour [minutes]` | Start a Luck Hour on this server |
| `/resettutorial [player]` | Replay the tutorial |

## License

[MIT](LICENSE) © 404priyanshu. The bundled [ProfileService](third_party/ProfileService) keeps its own Apache-2.0 license.
