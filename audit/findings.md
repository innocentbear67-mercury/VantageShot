# VantageShot audit findings — Phases 1–2

Method: 4 read-only hunter subagents (client / server / shared / tools) returned 41
categories; 4 hostile skeptic subagents with fresh context re-read every cited
occurrence trying to disprove them; the orchestrator hand-verified every
load-bearing claim against the tree. Verdict: 41/41 CONFIRMED, 0 disproved.
Machine reports: hunt_*.json (hunt), skeptic_*.json (skeptic) in the audit
scratch; baselines: audit/baseline.{luau,selene}.txt, audit/boundary_violations.txt.

## Corrections ledger (absorbed into everything below)

1. Shotgun fires 9 pellets (Breacher) → **207 FireClient messages per blast**, not 184.
2. `CompoundTools/Base.luau` has no in-repo driver → its label-stub and slit defects
   are latent (manual command-bar use only). The LIVE tool defect is the `Plot M.rail`
   BARRIER_OVERRIDE via LFB→Build→Plot.
3. `VantageMapTools/Kit` is LIVE (VantageMap.luau:12 requires it); only
   `VantageMapTools2/Kit` is dead.
4. AGameplay reads the dated archive BEFORE `ClearAllChildren` → aborts before wiping
   (less severe than first claimed; still a fragile live archive dependency).
5. MenuFrames is dead by transitivity: MenuBackdrop.luau:42 requires it (both dead).
6. Actual path is `src/client/VantageWeaponClient/Armory/ArmourBay.luau` (not Armour/;
   boundary_violations.txt line for it must be re-seeded on any regeneration).
7. SignatureClient: only 2 of 3 render-step loops are always-on (Bifrost bind is scoped).
8. Purity strict split: 41 pure / 54 engine-bound; 17 modules blocked only by
   script-Parent requires (shimmable).
9. CrateConfig: 169 Weapon/Skin pairs (all resolve in Skins.luau) + 4 Equipment pairs.
10. Combat remotes: both hunters AND the skeptic's adversarial sampling found
    validation present at every client→server site (83 sites). Residual gaps are
    rate-limiting only: MatchRequest (none), ProfileBanner (none), and
    SignatureService's ONE shared cooldown table across FOUR remotes.
11. Zero bare wait()/spawn()/delay() in client/server/shared (all task.*). Deprecated
    elsewhere: LoadCharacter ×6 + GetRankInGroup ×1 (server), two-arg Instance.new ×7 (tools).
12. Client-side radar stub nuance: the parked Radar cluster is NOT updated
    (empty `_stepRadar`); VisorClient:737's "radar keeps detecting" comment is false.
13. Comment archive pointers (ServerStorage._*Backup*) reference Studio-place state
    not present in the repo — verifying them needs Studio, not source.

## Phase 2 — two-plane ranking

### Plane A — correctness (player-visible breakage)
- **A1 Misplaced client scripts [P1, live]**: gravity lifts dead
  (`MapClient.server.luau:3` LocalPlayer in a server Touched handler — errors on
  first touch) and ambient props frozen (`AmbientClient.server.luau:18`
  RenderStepped server-side); `VantageControl` works only via a runtime
  LocalScript-relocation hack (`init.server.luau:60-79`). Tools already bake these
  correctly today (RunContext.Client at Greybox:104 / Hero:578) — the repo copies
  predate that fix.
- **A2 Map-tool defects baked into the shipped place [P0-tools]**: Plot `M.rail`
  override (live chain: barriers where rails were specified), `C.label()` empty stub
  (latent, Base dead), `Base:235` always-15.5 and/or (latent), AScale in-place
  whole-map rescale with no backup, ASlit drops gameplay attributes, AGameplay
  live archive dependency. Fixes need a Studio map rebuild to reach the shipped place.

### Plane B — client-frame cost (every player, every frame)
- **B1** Hud:Step chain: `init.client.luau:198` BindToRenderStep → `Loadout:345` →
  `Hud:1683+`: FindFirstChild("Match") + ≥6 attribute reads + fresh pair-table per
  frame; rainbow() rebuilds ColorSequence per frame while a Signature charges.
- **B2** Always-on loops with per-frame work: shared `Skins:587` / `SkinKits:390` /
  `EquipmentBuild:357` (GetTagged fresh array per frame, from require time, never
  stopped); SignatureClient ×2; RampChevronScroller; Scoreboard / MatchResults /
  MatchEvents / OperativeIntro Heartbeat writes every frame.
- **B3** Lobby renderStep rewrites identical strings every frame (string.format/rep
  in the idle branch too).
- **B4** Vehicle session: per-frame rayParams/cameraExclude table rebuilds (incl.
  Players:GetPlayers() array), GetGamepadState table, HUD info table + Seats scan,
  hideHud PlayerGui scan — every frame of a session.
- **B5** Hidden HUD clusters parked invisible but still computed every frame
  (shield easing, streak, score bars, timer, 4Hz avatar rows with per-player table +
  sort closures). Headers admit "still updated, never shown".
- **B6** `WeaponMath.RayOBB` allocates its axis table per call (per pellet, on BOTH
  client prediction and server validation); Lobby re-asserts MouseIconEnabled every
  Heartbeat (state fight with overlays).
- Join-time: 59.3KB of dead shared Luau ships to every client (see D1).

### Plane C — server-tick cost (scales with players)
- **C1** `HitValidation.record()` at 60Hz: GetPlayers + 2×GetTagged fresh arrays +
  `seen` table + one CFrame insert per character, every Heartbeat (lag-comp history).
- **C2** `MatchService:632` TimeLeft SetAttribute ~20Hz replicated to all clients
  (loop waits 0.05s); publishQueue rewrites one Queue_<mode> attribute per mode.
- **C3** `WeaponService:813` per-pellet×per-player "Shot" FireClient fan-out
  (207 messages per shotgun blast).
- **C4** Polling that should be events: JumpPadServer 10Hz forever; VantageControl
  2.5Hz wake (work Live-gated); TutorialService 4Hz falls-check.
- **C5** Ordering sleeps with player symptoms: IntroService flat 0.35s (slow joins
  spawn unarmed); CrateService 30s silent give-up (missed grandfathering).

### Plane D — dead weight / agent-facing
- **D1** Dead shared modules (59,312B to every client): AbilityFX, MenuBackdrop,
  MenuFrames, MapPlan; server-only ProgressionConfig in shared.
- **D2** Dead server code: Progression_2 (byte-identical), MapService_2 (stale, −192
  lines), unused Ledger import in MatchService, groundPath/aimGround (zero callers),
  TeamSpawnServer MATCHMAKING dead branch, commented-out reserve blocks ×2.
- **D3** Dead client wiring: SuitUp required + Preload() at require time though
  disabled; LoadoutScreen fully built then overwritten by LoadoutHS; CrateOpening
  built though CasesHS prefers UnboxHS; SeasonPassHS v1 unread fallback;
  `false and ShopScreen` tombstone; AddFeed no-op + server FireAllClients("Feed")
  per kill into it; ShotSeen write-only growth table (per killed character);
  HitMarkerLegacy/KillRing frames; ArmourBay inert stub; VantageSignatureLab +
  SkinRange dev tools shipping to clients (self-gated Studio-only).
- **D4** Dead/stale tools: ServerStorage/Gungnir.luau (stale v1 of the live FX
  module, hard-errors in place), CompoundTools Mass/Kit2, VantageLobbyTools
  Kit2/HyperKit, VantageMapTools2/{AAudit,Kit}; ambiguous command-bar cluster
  (Base, Angular, Arch, BlueLayout, BuildBlock, Constructs, Hall, Mega, Props,
  Types, Kit, Kit2-Compound, Kit3) — owner must confirm before deletion.
- **D5** Remote factory re-implemented in 16 files (20 sites) instead of one module;
  rate-limit gaps: MatchRequest (none), ProfileBanner (none), SignatureService one
  shared `last[p]` across four remotes (cross-remote lockout).
- **D6** Deprecated: LoadCharacter ×6, GetRankInGroup ×1, two-arg Instance.new ×7.
- **D7** `--!nocheck` on 22 client files (17,874 lines) incl. the whole Lobby kit —
  ratchet new occurrences; conversion deferred.
- **D8** Config: Vanguard duplicate sound keys silently discard authored pitch (the
  one real config defect — id canon verified consistent everywhere); CrateConfig
  C.Pool ×3 / C.Count ×2 last-wins redefinitions; Knife/Vanguard hand-rolled off
  ConfigBase; two parallel reload-clip systems (WeaponClips vs ReloadChoreo).
- **D9** Comments-as-changelog: 37 client + 11 shared + 18 tools sites; three
  headers contradict live behaviour (MinimalHud "visor disabled", SquadBots "Studio
  only" vs BotFill.Enabled=true, Lobby:1264 "CrateOpening for now" vs Unbox preferred).
- **D10** Purity map: 41 modules testable under Lune today (feeds Phase 4).
- Deferred with reasons: split-brain _G animators (working, refactor risk),
  EffectCatalog picker flag (documented intent to re-enable), Studio per-run cost +
  unsafe-by-design command-bar destroys (Studio QoL), 3,915 ratcheted style
  diagnostics (no formatter; reformat = 87-file churn, zero player value),
  placeholders-as-production (content pipeline, not code).

## Phase 3 fix order (impact-ranked; one commit per category)

1. **A1** misplaced client scripts (RunContext fix + packaging) — broken gameplay.
2. **D1–D4** dead-code sweep (removes bad examples first, shrinks every later diff;
   ambiguous tools held for owner decision).
3. **B1–B6** client-frame fixes (the FPS plane).
4. **C1–C5** server-tick fixes.
5. **D5** remote factory + rate limiter.
6. **D6/D8/D9** deprecated APIs, config defects, contradicted comments.
7. **A2** tool defects + Studio rebuild instructions.
