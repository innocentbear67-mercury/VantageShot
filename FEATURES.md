# VantageShot — feature map (player POV → files)

Every gameplay feature from the PLAYER's point of view, mapped to the files that
implement it (paths relative to repo root). Built from reading the source plus
audit/findings.md (Phases 1–2 hunt data); known-dead or mis-packaged pieces are
flagged inline. This file is the shared vocabulary for humans and agents —
when a feature's owner is uncertain it says `owns: X (verify)`.

## Movement

- **Always-sprint ground movement** — you never walk: acceleration, snappy turns, overspeed bleed. `src/shared/Vantage/Movement/MovementConfig.luau`, `src/client/VantageMovementClient/{init.client,InputController, MovementController}.luau`, server anti-cheat: `src/server/VantageServer/{MovementServer.server, MovementValidator}.luau`.
- **Crouch (hold C / Ctrl)** — lower, slower, tighter spread. `MovementConfig` (Crouch*), `InputController`, `MovementController`, pose via `src/client/VantageMovementClient/AnimationController.luau`.
- **Jump with buffer + coyote time** — presses near a ledge still count; no auto-bunnyhop. `MovementConfig` (Jump*), `MovementController`.
- **Air control + momentum drag** — steer mid-air; excess speed bleeds. `MovementConfig` (Air*), `MovementController`.
- **Slide** — fast entry boost, friction ramp, early end, cooldown, FOV kick + camera tilt. `MovementConfig` (Slide*), `MovementController`, `src/client/VantageMovementClient/CameraEffects.luau`.
- **Camera feel** — strafe/slide roll, landing dip, tiny head-bob, FOV bonuses. `CameraEffects`.
- **Locomotion animation** — replaces Roblox's default Animate (blocked by `StarterPlayer/StarterCharacterScripts/Animate.client.luau`, intentionally empty). `AnimationController`, `src/shared/Vantage/Movement/{MovementAnimations, GaitFeed}.luau`, placeholder joints `src/client/VantageMovementClient/PoseController.luau`.
- **Server movement validation** — the server samples positions, forgives latency, snaps cheaters. `MovementValidator`, `MovementServer`; exemptions: `src/server/VantageServer/JumpPadServer.server.luau`, `Workspace/Map_LiveFire/Systems/MapServer.server.luau`.

## Weapons & shooting

- **13 weapons** (knife + 12 guns; each its own config merged over the template). `src/shared/Vantage/Weapons/WeaponConfig.luau` (loader), `src/shared/Vantage/Weapons/Configs/*.luau`, `src/shared/Vantage/Weapons/ConfigBase.luau`.
- **Loadout & switching** — 7 slots, keys 1-7 / Q / wheel, presets of 3 guns. `src/shared/Vantage/Weapons/{LoadoutPresets, WeaponUnlocks}.luau`, client `src/client/VantageWeaponClient/Loadout.luau`, server `src/server/VantageServer/{WeaponServer/WeaponService, LoadoutService.server}.luau`.
- **First-person viewmodel** — your arms, the gun, sway/bob/kick springs. `src/client/VantageWeaponClient/{Viewmodel, ViewmodelArms, ViewmodelAnimator}.luau`, `src/shared/Vantage/Weapons/{WeaponClips, ArmRig}.luau`.
- **Fire prediction** — muzzle FX, tracer, impact and ammo appear instantly; the server re-decides. `src/client/VantageWeaponClient/{WeaponController, WeaponEffects, HitPredict}.luau`, `src/server/VantageServer/WeaponServer/{WeaponService, HitValidation}.luau`.
- **Recoil** — deterministic learnable pattern (no randomness). `src/client/VantageWeaponClient/Recoil.luau`, per-gun `Recoil.Pattern` in the Configs.
- **Spread & shotgun pellets** — bloom on move/air, seeded pellet patterns rebuilt identically client+server. `src/shared/Vantage/Weapons/WeaponMath.luau` (`ApplySpread`, `PelletDirs`).
- **Energy weapons** (Arc, Helix) — heat bar, overheat lock, R to vent. `Configs/{Arc, Helix}.luau`, `WeaponController`, `src/client/VantageWeaponClient/EnergyFX.luau`.
- **Projectile guns** (Havoc lobbed rounds, Arc bolts) — server-simulated flight, splash. `Configs/{Havoc, Arc}.luau`, `WeaponService`.
- **Reload choreography** — stylized reloads using the real magazine meshes. `src/shared/Vantage/Weapons/ReloadChoreo/init.luau` (+ clips; note audit D8: a second clip system `WeaponClips` runs in parallel — consolidate: verify), `WeaponService` (validation), auto-reload `WeaponConfig.AutoReloadOnEmpty`.
- **Knife** — quick slash / heavy stab, backstab kills, inspect. `Configs/Knife.luau`, `src/client/VantageWeaponClient/{KnifeController, KnifeViewmodel}.luau`.
- **ADS / scopes** — FOV zoom, red-dot + sniper overlays. `src/client/VantageWeaponClient/HudOptics.luau`, per-gun `ADS` blocks, sensitivity `src/client/VantageWeaponClient/Settings.luau`.
- **Aim assist** — friction + magnetism on visible enemies only. `src/client/VantageWeaponClient/AimAssist.luau`.
- **Weapon input** — every binding via ContextActionService, rebindable, gamepad-ready. `src/client/VantageWeaponClient/WeaponInput.luau`, `src/shared/Vantage/SettingsConfig.luau`.
- **What other players see** — third-person gun poses solved per client. `src/client/VantageWeaponClient/ThirdPersonRig.luau`, `WeaponClips`.
- **Dropped weapons** — a dead player's gun lies where they fell, pickup within lifetime. `WeaponConfig.Server` (DropLifetime/DeathAnchorMaxDrop), `WeaponService`.
- **Weapon audio** — layered fire crack/body/mechanism, reload + equip identity pitching. per-gun `Sounds` blocks, playback `src/client/VantageWeaponClient/WeaponEffects.luau`.

## Damage, elimination, shields

- **Damage** — falloff over distance, headshot/limb multipliers; client never sends values. `src/server/VantageServer/WeaponServer/DamageService.luau`, `src/shared/Vantage/Weapons/WeaponMath.luau` (`Damage`).
- **Lag-compensated hit validation** — server rewinds hitboxes, scales them forgivingly. `src/server/VantageServer/WeaponServer/HitValidation.luau`, `WeaponConfig.Server`.
- **Energy shield** — absorbs first, recharges after quiet time; break/shimmer FX. `src/server/VantageServer/WeaponServer/ShieldService.luau`, `src/shared/Vantage/Shield/{ShieldConfig, ShieldHexData}.luau`, `src/client/VantageWeaponClient/{ShieldFX, EnergyFX}.luau`.
- **Elimination decision** — only the lethal hit's owner is credited; assists tracked. `src/server/VantageServer/WeaponServer/EliminationService.luau`, `src/shared/Vantage/Elimination/EliminationConfig.luau`.
- **Death presentation** — controlled poses, no ragdoll; Crimson Core Overload replaced by the effect catalog. `src/client/VantageWeaponClient/{DeathPresenter, CoreOverloadFX}.luau`, `src/shared/Vantage/Elimination/CoreOverloadConfig.luau`.
- **19 elimination effects** — every kill plays the default ("Collapse"); rarity tiers stretch timing. `src/shared/Vantage/Elimination/EffectCatalog.luau`, `src/client/VantageWeaponClient/ElimFX/{init, Effects}.luau` (older kit: `EliminationFX/{init, Insignia}.luau`).
- **Instant death replay** — rebuilt from what your own client saw. `src/client/VantageWeaponClient/DeathReplay.luau`.
- **Kill feed** — the server decides every line. `src/client/VantageKillFeed.client.luau`, `src/shared/Vantage/Elimination/KillFeedConfig.luau`.
- **Kill reward line** — "+REQ +ORD" pops by the crosshair. `src/client/VantageReqFeed.client.luau`, `src/shared/Vantage/Requisition/RequisitionConfig.luau`.
- **Supply Surge** — random "SUPER BONUS!!" cache drop on a kill. `src/client/VantageSupplySurge.client.luau`, `EliminationService` (rollSurge).
- **Announcer callouts** — streaks / multikills, one voice at a time. `src/client/VantageWeaponClient/Announcer.luau`, `EliminationConfig`.
- **Spawn shields** — one-way force-field walls at team spawns. `src/server/VantageServer/SpawnShieldServer.server.luau`.
- **Friend/foe outlines** — occluded-only team highlights. `src/client/VantageWeaponClient/TeamOutlines.luau`.

## Abilities & grenades & ultimates

- **Grapple (E)** — hook, cable pull, steer, release fling, low-gravity hang. `src/shared/Vantage/Abilities/AbilityConfig.luau`, `src/server/VantageServer/AbilityServer.server.luau`, `src/client/VantageAbilityClient/{init.client, GrappleFX}.luau`.
- **Equipment traits** — hook personalities (Harpoon spear-drag, Mag-Anchor perch, Kraken free re-cast, Lotus pendulum, Starfall blink) and pack traits (Hex Wall, Overshield, Glide, Squad Pulse, Event Horizon phase). `src/shared/Vantage/Equipment/EquipmentCatalog.luau`, `src/server/VantageServer/{EquipmentPerkServer.server, AbilityServer.server}.luau`, `src/server/VantageServer/WeaponServer/ShieldService.luau`, `src/client/VantagePerkClient.client.luau`.
- **Frag grenade (LMB+RMB)** — arcing throw, fuse, lethal blast, cover-aware. `src/shared/Vantage/Grenade/{GrenadeConfig, GrenadeFeed}.luau`, `src/server/VantageServer/GrenadeServer.server.luau`, `src/client/VantageWeaponClient/GrenadeClient.luau`.
- **ULT — Orbital Lance** — streaks bank charges; aimed strike with telegraph. `src/shared/Vantage/Ult/UltConfig.luau`, `src/server/VantageServer/UltServer.server.luau`, `src/client/VantageUltClient.client.luau`.
- **Status effects** — freeze etc. with immunity windows, replicated as attributes. `src/server/VantageServer/StatusService.luau`.

## Signatures (10 Norse powers bought with Ichor)

- **Casting** — Shift / L1 sends only your look vector; the server validates, builds geometry, broadcasts; lock-on brackets match on both sides. `src/server/VantageServer/SignatureServer.server.luau`, `src/client/VantageWeaponClient/SignatureClient.luau`, `src/shared/Vantage/Signatures/{SignatureConfig, SignatureLock, SignatureFeed}.luau`.
- **The ten FX** — Mjölnir hammer, Fenrir wolf charge, Gungnir pierce, Midgard serpent breach, Valkyrie dive, Ragnarök fissure, Helheim freeze cone, Sleipnir trample, Bifrost teleport, Yggdrasil cover. `src/shared/Vantage/Signatures/FX/<Id>.luau` (10 files), toolkit `SignatureVFX.luau`, teleport map `BifrostMap.luau`, creature gait `CreatureGait.luau`.
- **Ichor economy** — balance, ownership, equipping, daily shop, Ichor crate (never duplicates). `src/server/VantageServer/SignatureService.server.luau`, `src/shared/Vantage/Signatures/SignatureCatalog.luau`, `src/shared/Vantage/Ichor/IchorConfig.luau`.
- **Unlock reveal moment** — charge → flash → card. `src/client/VantageWeaponClient/Lobby/SignatureReveal.luau`.
- **Ichor Farm** — lobby well/cauldron that banks Ichor over time. `src/client/VantageWeaponClient/Lobby/{FarmHS, FarmStage}.luau`, `IchorConfig.Well`.
- **Signature Lab** — dev preview panel in the lobby. `src/client/VantageSignatureLab.client.luau` (dev tool, self-gated).

## Vehicles & aircraft

- **Combined-arms vehicles** — spawn markers, multi-crew seats, turret + MG/cannon, hull damage, destruction, respawn. `src/server/VantageServer/{VehicleServer.server, VehicleService}.luau`, `src/shared/Vantage/Vehicles/{VehicleConfig, VehicleMath, VehicleSim}.luau`.
- **Vehicle client** — turret/wheel animation, shells + tracers, hit confirmations both directions, seated HUD. `src/client/VantageVehicleClient/{init.client, VehicleVisuals, VehicleFX, VehicleHitFX, VehicleHud}.luau`.
- **Dropship flyby** — periodic pass you can grapple mid-air, hang beneath, drop from. `src/server/VantageServer/{AircraftServer.server, AircraftService}.luau`, `src/shared/Vantage/Aircraft/{AircraftConfig, AircraftPath}.luau`, `src/client/VantageAircraftClient/{init.client, AircraftRuntime, HangRig}.luau`.
- **Boost ramps** — vehicle ramps with scrolling chevrons. `src/client/RampChevronScroller.client.luau`.

## Lobby, matchmaking, match flow

- **Walking lobby** — you spawn INTO the HyperLobby hall and walk to queue pads; no old-style main menu. `src/server/VantageServer/LobbyService.server.luau`, `src/client/VantageWeaponClient/Lobby/{init, LobbyKit, Pages, Gloss, HS}.luau`, `src/client/{LobbyFX, LobbyLighting, LobbyPresence}.client.luau`.
- **Queue / DEPLOY pads + mode select** — step on a pad (or lobby HUD) to queue a mode. `LobbyPresence`, `src/client/VantageWeaponClient/Lobby/ModesHS.luau`, `src/server/VantageServer/MatchService.server.luau`.
- **Matchmaking & teams** — queue fills a full lobby-sized match, teams assigned, characters spawn once. `MatchService`, `src/server/VantageServer/TeamSpawnServer.server.luau`, `src/shared/Vantage/MatchConfig.luau`.
- **Match phases** — Deploy → Operative Intro → Prep → Countdown → Live → Results, with in-phase HUD countdowns. `MatchService`, `src/shared/Vantage/MatchConfig.luau`, `src/client/VantageWeaponClient/MatchHud.luau`.
- **Operative intro** — lined-up soldiers, Mixamo pose clips, name cards between dropship and prep. `src/server/VantageServer/IntroService.luau`, `src/client/VantageWeaponClient/OperativeIntro.luau` (+ `OperativeIntro/Clips/*.luau`).
- **Map rotation / vote** — exactly one map folder in Workspace at a time. `src/server/VantageServer/MapService.luau`, `MatchConfig.Maps`.
- **Match events lane** — one announcement at a time under the score box. `src/client/VantageMatchEvents.client.luau`.
- **Match results + MVP** — colour wash, VICTORY band, reward cards, full board. `src/client/VantageMatchResults.client.luau`, `src/server/VantageServer/{MatchLedger, MatchStatsServer.server}.luau`. (older `src/client/ScoreboardVictory.client.luau` is DISABLED — kept as fallback.)
- **Lobby boards & leaderboards** — Staging Deck screens, plaza top-10 boards, ranked podium. `src/server/VantageServer/{LobbyBoards, LobbyStats}.server.luau`.
- **Menu avatar** — your own avatar in the menu showcase, built server-side. `src/server/VantageServer/MenuAvatarServer.server.luau`.
- **Ranked & profile** — RP ladder Wood→Mythic, protection/streak, profile modal. `src/server/VantageServer/ProfileService.server.luau`, `src/shared/Vantage/Ranked/RankedConfig.luau`, `src/client/VantageWeaponClient/Lobby/ProfileHS.luau`.
- **VIP chat tag** — gold [VIP] prefix for the pass holder. `src/client/VipChatTag.client.luau`, `src/server/VantageServer/ShopService.server.luau`.
- **Loading** — ReplicatedFirst preload + profile sync + branded hand-off. `ReplicatedFirst/VantageLoader.client.luau`.

## Progression, mastery, requisition, season pass, shop, crates & skins

- **REQ (main currency)** — earned per kill/headshot/assist, spent on skin crates; increment-safe saves. `src/server/VantageServer/Requisition.luau`, `src/shared/Vantage/Requisition/RequisitionConfig.luau`.
- **ORD (second currency)** — buys Arsenal Crates that unlock guns (never a duplicate). `src/server/VantageServer/Ordnance.luau`, `src/shared/Vantage/Ordnance/OrdnanceConfig.luau`, pool `CrateConfig.WeaponPool` + `WeaponUnlocks.CrateWeapons`.
- **Account XP / levels, Daily Directives, weekly Operation** — `src/server/VantageServer/{Progression, ProgressionConfig}.luau` (server-only config per audit D1).
- **Weapon mastery** — per-weapon levels 1-50, variants at 10/25, prestige at 50 with permanent boosts; full-screen prestige cinematic. `src/server/VantageServer/Mastery.luau`, `src/shared/Vantage/Mastery/{MasteryConfig, Variants}.luau`, `src/client/VantageWeaponClient/Lobby/{MasteryHS, PrestigeFX}.luau`.
- **Season pass** — free/premium tracks, tier skips. `src/server/VantageServer/SeasonPassService.server.luau`, `src/shared/Vantage/SeasonPass/PassConfig.luau`, `src/client/VantageWeaponClient/Lobby/SeasonPassHS2.luau`.
- **Robux shop** — premium crates, deals, gamepasses (VIP), REQ packs. `src/server/VantageServer/ShopService.server.luau`, `src/shared/Vantage/Shop/ShopConfig.luau`, `src/client/VantageWeaponClient/Lobby/ShopHS.luau`.
- **Skin crates** (Field / Strike / Prestige / Apex) — Rare+ pool of every gun, pity timers, x5 discount, reel → reveal. `src/server/VantageServer/CrateService.server.luau`, `src/shared/Vantage/Crates/CrateConfig.luau`, `src/client/VantageWeaponClient/Lobby/{CratesScreen, CasesHS, UnboxHS, CrateUX, CoinBurst}.luau` (audit D3: `CrateOpening.luau` built but UnboxHS is the live path — verify).
- **Equipment crates** (shield packs / hooks as shards). `CrateConfig.EquipmentCrates`, `src/shared/Vantage/Equipment/EquipmentCatalog.luau`, shard unlock `CrateService`.
- **Skins** — finishes, patterns, premium ladder, per-skin firing FX + idle auras, inspect animations; ownership saved per player. `src/shared/Vantage/Weapons/{Skins, SkinKits, SkinFX, SkinInspects, VFXKit}.luau`, selection `src/server/VantageServer/LoadoutService.server.luau`, inventory UI `src/client/VantageWeaponClient/Lobby/InventoryHS.luau`, skin photos `Lobby/CardArt.luau`, 3D stage `Lobby/Showcase.luau`.
- **Armory** (B / R3) — weapon inventory + skin customization in match. `src/client/VantageWeaponClient/Armory/init.luau` (`ArmourBay.luau` is an inert stub — armour retired).
- **Loadout presets** — 8 presets of 3 guns; locked guns skipped, starter fallback. `src/shared/Vantage/Weapons/LoadoutPresets.luau`, `src/server/VantageServer/LoadoutService.server.luau`, `src/client/VantageWeaponClient/Lobby/LoadoutHS.luau`.
- **Equipment slots** (Pack / Hook) — equip + owned sets, stat cards, worn model dressing. `EquipmentCatalog`, `src/shared/Vantage/Equipment/{EquipmentBuild, EquipmentModels, EquipmentStatsUI}.luau`.

## Tutorial

- **First-time training** — 6 stages (movement → grapple → weapons → shields → armoury → loadout), server-checked, gated loadout/equipment while in it, completion in the profile. `src/server/VantageServer/TutorialService.server.luau`, `src/shared/Vantage/Tutorial/TutorialConfig.luau`, `src/client/VantageTutorial.client.luau`; gates in `LoadoutPresets.ActiveList` + `EquipmentCatalog.Equipped`.

## HUD & visor & scoreboard & kill feed & results

- **Minimal HUD policy** — crosshair + ammo + hit markers only by default (user decision 2026-11-14). `src/client/VantageMinimalHud.client.luau`, drawn by `src/client/VantageWeaponClient/Hud.luau`.
- **Combat HUD (HS Match v5)** — health/shield, ammo, score box, timer, kill line, ult/ability tiles, heat/reload states. `Hud.luau`, `HudOptics.luau`, `MatchHud.luau`.
- **Exosuit visor (H)** — helmet close/open, holographic panels, energy veins, feed bus. `src/client/VantageVisorClient.client.luau`, `src/shared/Vantage/UI/{VisorKit, VisorHolo, VisorHexGrid, VisorBus, VisorFeed}.luau`. Radar cluster is parked and NOT updating (audit #12) — `owns: VisorClient (verify before reviving)`.
- **Scoreboard (hold Tab)** — match intelligence with per-match stats. `src/client/ScoreboardClient.client.luau`, `src/shared/Vantage/{ScoreboardConfig, ScoreboardTheme}.luau`, `MatchStatsServer`.
- **Kill feed** — see Damage section (`VantageKillFeed`, `KillFeedConfig`).
- **Match results** — see Match flow (`VantageMatchResults`, `MatchLedger`).
- **Settings menu (P)** — schema-driven, server-sanitised, saved per player. `src/client/VantageWeaponClient/{SettingsMenu, Settings}.luau`, `src/shared/Vantage/SettingsConfig.luau`, `src/server/VantageServer/SettingsService.server.luau`.

## Audio (announcer, music, Vantage Control voice)

- **Announcer** — kill streak / multikill voice lines. `Announcer.luau`, `EliminationConfig`.
- **VANTAGE CONTROL radio + VEYRA comms bar** — per-player tactical callouts (#4 "Target eliminated" only to the credited killer). `src/server/VantageControl/init.server.luau`, `src/client/VantageControlClient.client.luau`, `src/shared/Vantage/VantageControlConfig.luau`.
- **Menu music** — loops from lobby hand-off until deployment. `src/client/VantageMenuMusic.client.luau`.
- **Battle music** — fades in when your match goes Live. `src/client/VantageBattleMusic.client.luau`.
- **Ambience bed** — training-facility room tone after the loader. `src/client/VantageAmbience.client.luau`.
- **Gait-synced footsteps** — one step per footfall, same clock as the camera bob. `src/client/VantageFootsteps.client.luau`, `GaitFeed`.
- **Cartoon character sounds muted** — no boing/wind/grunt. `src/client/VantageCharSoundMute.client.luau`.

## Map interactions (lifts, jump pads, ambient)

- **Gravity lifts** — launch you between levels. `Workspace/Map_LiveFire/Systems/MapClient.server.luau` (⚠ audit A1: mis-packaged as a server script — currently DEAD in the live place; needs RunContext fix), exemptions `MapServer.server.luau`.
- **Jump pads** — stand on, get thrown in an arc at the pad's target; chevron FX; validator grace. `src/client/{JumpPadClient, JumpPadFX}.client.luau`, `src/server/VantageServer/JumpPadServer.server.luau`.
- **Ambient prop motion** — ECLIPSE set-piece animation. `Workspace/Map_LiveFire/Systems/AmbientClient.server.luau` (⚠ audit A1: same mis-packaging — frozen in the live place); lobby props `src/client/LobbyFX.client.luau`.
- **Per-map lighting** — presets applied per map / lobby-only lighting. `src/shared/Vantage/MapLighting.luau`, `src/client/LobbyLighting.client.luau`.
- **Kill volumes** — out-of-bounds death. `MapServer.server.luau`.

## Bots

- **Squad bot fill** — every live match topped up to 5v5 with AI that paths, calls contacts, strafes, retreats on broken shield, reloads. `src/server/VantageServer/SquadBots.server.luau` (`MatchConfig.BotFill.Enabled = true` today; Studio `/squad` replies shown by `src/client/SquadBotsClient.client.luau`).
- **Combat training dummy (Studio)** — fights back in playtests; auto-tags dropped humanoids. `src/server/VantageServer/CombatBot.server.luau`, `src/server/StudioBotTagger.server.luau`.

## Admin & dev tools

- **Admin panel (F2 / ADMIN)** — announcements for everyone, owner-only grants/kicks; server re-checks every request. `src/server/VantageAdminPanel.server.luau`, `src/client/VantageAdminPanelClient.client.luau`.
- **Skin checker** — live skin swap + inspect while in a match. `src/server/VantageAdminSkins.server.luau`, `src/client/VantageAdminSkinsClient.client.luau`.
- **Dev chat commands** — `/devgrant`, `/req` currency grants (owner-only). `src/server/DevChatCommands.server.luau`.
- **Signature Lab / Skin Range** — lobby + Studio cosmetic test benches. `src/client/VantageSignatureLab.client.luau`, `src/client/VantageSkinRange.client.luau`.
- **Remote bootstrap** — creates the Remotes folder on a fresh build. `src/server/EnsureCoreRemotes.server.luau`, `src/shared/Vantage/RemotesLib.luau` (also the shared rate limiter — per-key isolation enforced by review, not tests).

## Studio build tools (ServerStorage)

- **Map builders** — `ServerStorage/VantageMapTools/VantageMap.luau` (Vantage arena); `ServerStorage/CompoundTools/*` (plot/build/arch language; audit D4: several latent defects + ambiguous command-bar cluster — verify with owner); `ServerStorage/EclipseTools/*` (Greybox/Hero/Heightfield/Dress); LiveFire kit: `ServerStorage/LF_LayoutTools/*`, `ExpansionTools/*`, `LFTerrain.luau`, `LFB.luau`, `Mass3.luau`, `IntB.luau`/`IntRooms.luau`/`KitPlace.luau`, `Detail.luau`, `StairCheek.luau`, `VisScan.luau`; `ServerStorage/SolsticeTools/*`.
- **Map edit-time scanners** (VantageMapTools2) — pad/elevator/gameplay/audit passes over the built place; audit A2 flags live defects: `Plot.luau` M.rail barrier override chain (CompoundTools), `AScale` whole-map rescale without backup, `ASlit` drops gameplay attributes, `AGameplay` live archive dependency, `Base.luau` dead label stub. `ServerStorage/VantageMapTools2/*` (Kit/AAudit dead per audit D4), `CompoundTools/{Plot, Base}.luau`.
- **Lobby builder** — `ServerStorage/VantageLobbyTools/{Kit, Kit3}.luau`.
- **Weapon builders** — VX-01, balisong knife, Forge art direction (one builder per gun), Blender import pipeline, skin concept/forge. `ServerStorage/VantageWeaponTools/{VX01Builder, KnifeBuilder, ForgeKit, ForgeBuilds, BlenderIntegrate, SkinConcepts, SkinForge}.luau`, `ForgeTools/{FB, FK, FP}.luau`, `ServerStorage/WeaponAssetKit/{Build, Specs}.luau`, `ForgeArsenal/`.
- **Character/suit builders** — blocky suit prototype, exosuit mesh fits, reference suits. `ServerStorage/{BlockySuitProto, ExosuitFit, ExosuitFitW2}.luau`.
- **Vehicle builder** — assembles playable vehicle templates from imports. `ServerStorage/Vehicles/VehicleBuilder.luau`.
- **Known stale tools** (audit D4 — do not run): `ServerStorage/Gungnir.luau` (stale v1 of the live Signature FX), `VantageMapTools2/{AAudit, Kit}.luau` (dead), `CompoundTools` ambiguous cluster `owns: owner decision (verify)`.

## Repo plumbing (not player-facing, listed for agents)

- Rojo sync: `default.project.json`, `rokit.toml` (tool pins), `sourcemap.json` (generated).
- Audit gate: `audit/check.sh` (sourcemap → luau-lsp → selene → boundaries → framecost → tests → baseline ratchet), `audit/boundaries.luau`, `audit/framecost.luau`, baselines `audit/baseline.*.txt`, findings `audit/findings.md`.
- Tests (Lune, headless): `tests/run.luau` (runner), `tests/roblox_globals.luau` (engine-type injection helper — Lune `_G` injection does NOT work; uses the documented `luau.load` environment), `tests/weapon-math.test.luau`, `tests/config-canon.test.luau`, `tests/config-sanity.test.luau`, `tests/smoke.test.luau`.
