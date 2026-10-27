# Aura Forge: setup checklist

An RNG/gacha game for Roblox: grind coins, roll auras, chase the 1 in 10,000,000 Secret.

## 1. File map (where each file goes, and what instance type it is)

| Path in Studio | Instance | Source file |
|---|---|---|
| **Config** | | |
| ReplicatedStorage/Modules/Config | ModuleScript | `src/ReplicatedStorage/Modules/Config.lua` |
| ReplicatedStorage/Modules/RarityTable | ModuleScript | `src/ReplicatedStorage/Modules/RarityTable.lua` |
| **Data** | | |
| ReplicatedStorage/Modules/ProfileTemplate | ModuleScript | `src/ReplicatedStorage/Modules/ProfileTemplate.lua` |
| ServerScriptService/Services/DataService | ModuleScript | `src/ServerScriptService/Services/DataService.lua` |
| ServerScriptService/Packages/ProfileService | ModuleScript | `src/ServerScriptService/Packages/ProfileService.lua` (bundled, see step 2) |
| StarterPlayerScripts/Controllers/DataController | ModuleScript | `src/StarterPlayer/StarterPlayerScripts/Controllers/DataController.lua` |
| **Shared** | | |
| ReplicatedStorage/Modules/Formulas | ModuleScript | `src/ReplicatedStorage/Modules/Formulas.lua` |
| ReplicatedStorage/Modules/Util | ModuleScript | `src/ReplicatedStorage/Modules/Util.lua` |
| ReplicatedStorage/Modules/Signal | ModuleScript | `src/ReplicatedStorage/Modules/Signal.lua` |
| ReplicatedStorage/Modules/Net | ModuleScript | `src/ReplicatedStorage/Modules/Net.lua` |
| **Roll** | | |
| ServerScriptService/Services/RollService | ModuleScript | `src/ServerScriptService/Services/RollService.lua` |
| ServerScriptService/Services/InventoryService | ModuleScript | `src/ServerScriptService/Services/InventoryService.lua` |
| StarterPlayerScripts/Controllers/RollController | ModuleScript | `src/StarterPlayer/StarterPlayerScripts/Controllers/RollController.lua` |
| StarterPlayerScripts/UI/RollReveal | ModuleScript | `src/StarterPlayer/StarterPlayerScripts/UI/RollReveal.lua` |
| **Economy** | | |
| ServerScriptService/Services/EconomyService | ModuleScript | `src/ServerScriptService/Services/EconomyService.lua` |
| StarterPlayerScripts/Controllers/CurrencyController | ModuleScript | `src/StarterPlayer/StarterPlayerScripts/Controllers/CurrencyController.lua` |
| **Monetization** | | |
| ServerScriptService/Services/MonetizationService | ModuleScript | `src/ServerScriptService/Services/MonetizationService.lua` |
| **Quests / Daily / Events / Admin** | | |
| ServerScriptService/Services/QuestService | ModuleScript | `src/ServerScriptService/Services/QuestService.lua` |
| ServerScriptService/Services/DailyRewardService | ModuleScript | `src/ServerScriptService/Services/DailyRewardService.lua` |
| ServerScriptService/Services/EventService | ModuleScript | `src/ServerScriptService/Services/EventService.lua` |
| ServerScriptService/Services/AdminService | ModuleScript | `src/ServerScriptService/Services/AdminService.lua` |
| **UI** | | |
| StarterPlayerScripts/Controllers/UIController | ModuleScript | `.../Controllers/UIController.lua` |
| StarterPlayerScripts/Controllers/AudioController | ModuleScript | `.../Controllers/AudioController.lua` |
| StarterPlayerScripts/UI/UIKit | ModuleScript | `.../UI/UIKit.lua` |
| StarterPlayerScripts/UI/Hud | ModuleScript | `.../UI/Hud.lua` |
| StarterPlayerScripts/UI/Notifications | ModuleScript | `.../UI/Notifications.lua` |
| StarterPlayerScripts/UI/InventoryWindow | ModuleScript | `.../UI/InventoryWindow.lua` |
| StarterPlayerScripts/UI/ShopWindow | ModuleScript | `.../UI/ShopWindow.lua` |
| StarterPlayerScripts/UI/QuestsWindow | ModuleScript | `.../UI/QuestsWindow.lua` |
| StarterPlayerScripts/UI/DailyWindow | ModuleScript | `.../UI/DailyWindow.lua` |
| StarterPlayerScripts/UI/SettingsWindow | ModuleScript | `.../UI/SettingsWindow.lua` |
| **Bootstrappers** | | |
| ServerScriptService/Server | **Script** | `src/ServerScriptService/Server.server.lua` |
| StarterPlayer/StarterPlayerScripts/Client | **LocalScript** | `src/StarterPlayer/StarterPlayerScripts/Client.client.lua` |

`Modules`, `Services`, `Packages`, `Controllers` and `UI` are plain **Folders**.
StarterPlayerScripts means `StarterPlayer/StarterPlayerScripts`.

## 2. Things you must create by hand

1. **ProfileService** is already bundled at `src/ServerScriptService/Packages/ProfileService.lua`
   (unmodified, pinned commit and Apache-2.0 license in `third_party/ProfileService/`). With Rojo
   there's nothing to do. If you copy-paste instead, create a `Packages` Folder in
   ServerScriptService and a ModuleScript named `ProfileService` inside it. The game errors with a
   clear message on startup if it's missing.
2. **RemoteEvents:** nothing to do. `Net.Setup()` creates every remote inside
   `ReplicatedStorage/Remotes` when the server starts.
3. **AFK zone (optional):** a glowing zone is generated at `Config.AFK.ZonePosition`. To place it
   yourself, add an anchored Part named `AFKZone` to Workspace. The game uses its size and position.
4. **Custom aura effects (optional):** create `ReplicatedStorage/AuraModels/<Name>` (an Attachment or
   Folder holding ParticleEmitters/Beams) and set `Model = "<Name>"` on the item in RarityTable.
   Items with no model get an aura generated from their colour.

## 3. Install

**Option A: Rojo (recommended).** Run `rojo serve` in this folder and connect from the Rojo Studio
plugin, or build a place file directly:

```bash
rojo build default.project.json -o AuraForge.rbxlx
```

**Option B: copy and paste.** Create each instance from the table above with the exact name and type,
then paste the file contents in.

## 4. IDs to replace (all in `Config`)

| Where | What |
|---|---|
| `Config.Gamepasses.*.Id` | 2x Luck, Auto Roll, Fast Roll, +2 Equip Slots, VIP |
| `Config.DevProducts.*.Id` | Luck Potion, Coin Pouch / Chest / Vault, Lucky Tokens x5 |
| `Config.Audio.Music` | One or more music asset IDs (`"rbxassetid://123"`) |
| `Config.Audio.Sfx` | Whoosh, RevealSmall, Fanfare, Purchase, Claim, Error (Click/Tick/RevealBig default to sounds built into the Roblox client) |
| `Config.Images.*` | Optional icon images (currencies, menu, passes, products, boosts, gem shop). Empty = emoji |
| `Config.Particles` / `RarityTable` `Texture`, `SparkleTexture` | Optional aura particle textures. Empty = Roblox's default particle |
| `Config.Admins.UserIds` | Your admins' UserIds |

An ID of `0` is safe. The shop shows "Not set up" and nothing prompts.

**Image IDs:** upload images in Studio (**View → Asset Manager → Bulk Import**), then right-click each one → **Copy ID**. The ID of a website "Decal" upload usually won't work as an image ID.

**Creating the products:** open Creator Dashboard → your experience → Monetization → Passes and Developer
Products. Create each one, copy its ID into Config, and set the price there (the shop reads prices live).

**Audio:** in Studio, open Toolbox → Audio, or the Creator Store, and filter by Creator = *Roblox*. Those
tracks and SFX are licensed for use in every experience. Since Roblox's 2022 audio privacy change, most
old "public ID" lists no longer play. I left those slots blank rather than guess IDs that might be dead.

## 5. Enable DataStores and publish

1. **File → Publish to Roblox** (DataStores need a published place).
2. **Home → Game Settings → Security → Enable Studio Access to API Services** = ON, then Save.
3. Leave `Config.Data.UseMockInStudio = false` to test real saving in Studio, or set it to `true` for
   throwaway sessions that never touch your real data.
4. Developer product purchases in Studio are free test prompts. ProcessReceipt runs normally, so you can
   test the full grant and confirmation-popup flow.

## 6. Test checklist (Studio → Play)

Everyone is an admin in Studio (`Config.Admins.AllowInStudio`). Useful chat commands:

```
/givecoins 100000        /givegems 500          /givetokens 10
/setluck 100000          /giveitem The Last Light
/givepass AutoRoll       /givepass FastRoll     /givepass VIP
/luckhour 2              /givepotion 10         /resettutorial
```

- The first join shows the 3-page tutorial, then the tutorial reward.
- ROLL (or R / gamepad X): spin, reveal, and the coin cost drops. Check `/setluck 100000` for big cinematic reveals.
- A Mythic or rarer pull puts a banner on every player's screen.
- EARN button: floating +X. Stand in the AFK zone: the chip appears after 5 seconds and coins tick in.
- Quests, Rewards (daily + playtime), Index claim (`/giveitem` every item in a tier) and Settings (rejoin to confirm they persist).
- Leave for 2+ minutes and rejoin to see the "Welcome back" offline earnings popup.

## 7. How it fits together

- **Server authority:** clients only send requests. RollService checks cooldown + cost and rolls with
  the luck computed by EconomyService. Clicks are rate-limited with a token bucket. The AFK zone checks the
  character's position on the server every second. Every remote argument is type- and range-checked.
- **Data:** ProfileService (session-locked, auto-saved). `ProfileTemplate.Migrate` upgrades old saves
  with versioned migrations before `Reconcile`. Changes reach the client through batched `DataPatch`
  events, and the client mirror is `DataController`.
- **Receipts:** the reward and the PurchaseId are saved in the same profile write, and the receipt is
  acknowledged only once ProfileService confirms that write. A global `ReceiptLedger` DataStore records
  every confirmed PurchaseId too, so retried receipts are never granted twice.
- **Odds:** at 1x luck every rarity is exactly "1 in Chance". Common takes the leftover (≈1 in 1.5),
  and luck multiplies the rarer tiers and squeezes Common. Tune it with `LuckExponent` in RarityTable.
- **Timers:** potion time only runs down while the player is online. Daily rewards use UTC calendar
  days. Playtime rewards reset each session. Luck Hour is aligned to the UTC clock so every server runs it
  together.
