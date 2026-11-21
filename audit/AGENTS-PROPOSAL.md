# PROPOSED AGENTS.md content — promote on approval

> This file is the drafted AGENTS.md from the slop cleanup (Phase 5). Writing
> `AGENTS.md` itself requires owner approval (agent-instruction file). On
> approval, copy this file to the repo root as `AGENTS.md` and delete it.

# AGENTS.md — VantageShot

Short map of the architecture and the checks that keep it clean. Every rule
points at the check that enforces it. This file describes the repo as it IS
after the 2026-11-20/21 slop cleanup (branch `slop-cleanup`); it deliberately
carries no history of that cleanup — `git log` is the archive.

## Layout

- `src/client/**` → StarterPlayerScripts (LocalScripts + client modules)
- `src/server/**` → ServerScriptService (services; `EnsureCoreRemotes.server.luau` boots every core remote)
- `src/shared/**` → ReplicatedStorage.Vantage (replicates to EVERY client — size and purity matter)
- `ReplicatedFirst/`, `StarterPlayer/StarterCharacterScripts/` → their containers
- `Workspace/Map_LiveFire/Systems/` → map scripts; the two client-run scripts
  are Scripts with `RunContext=Client` declared in `default.project.json`
  (file extension names the CLASS; project.json owns the run CONTEXT)
- `ServerStorage/**` → Studio-only build tools (never ship)

Player-facing vocabulary: `FEATURES.md`. Audit findings and ranking:
`audit/findings.md`. Toolchain pinned in `rokit.toml`; the whole gate is
`bash audit/check.sh` (CI: `.github/workflows/audit.yml`).

## Rules → enforcing checks

1. **No new analyzer warnings.** luau-lsp + Selene ratchet against
   `audit/baseline.{luau,selene}.txt`; any NEW (path: code: message) key fails
   `audit/check.sh` and CI. Removals are always fine.
2. **No inline remote factories.** Every remote is created/found via
   `src/shared/Vantage/RemotesLib.luau` (`RemotesLib.get(name, class?)`);
   the boundary checker fails on `Instance.new("RemoteEvent"/"RemoteFunction")`
   in `src/server` outside the library. Throttles go through
   `RemotesLib.rate(player, key, window)` — one KEY per remote+action
   (never share one cooldown table across remotes).
3. **No `GetTagged` inside frame loops.** Frame loops iterate
   `TagCache.get(tag)` (signal-maintained array, empty-set early-out).
   `audit/framecost.luau` fails on new occurrences; its allowlist is
   `audit/frame_violations.txt` (currently one grandfathered GrappleFX site).
4. **Client code stays client-side, server code stays server-side.**
   `.server.luau` must never read `Players.LocalPlayer` / `RenderStepped`;
   `.client.luau` files live only under `src/client`, `ReplicatedFirst/`,
   `StarterPlayer/`. `audit/boundaries.luau` fails on new violations
   (RunContext=Client files declared in `default.project.json` are exempt
   from the server-state rule). A client-run script in Workspace is a plain
   `.server.luau` file + `$properties: {"RunContext": "Client"}` in the
   project — never a runtime relocation hack.
5. **Frame-loop discipline.** Render/Heartbeat bodies early-out before
   allocating; instance references are cached (stale-checked); UI and
   attribute writes are write-on-change; parked-invisible UI is not stepped.
   Partially enforced by rule 3; the rest is review — the Phase-1 hunt is the
   backstop (see below).
6. **Retired code is deleted, not parked.** No `_2` copies, no stub-then-keep,
   no `false and X`, no constructing a module to overwrite it. Git is the
   only archive; comments never justify keeping dead code. Enforced by
   review/hunt; the gate's ratchet makes new dead code at least visible.
7. **Configs carry one definition per key.** Luau table-assignment is
   last-wins; duplicate keys silently discard authored values (see the
   Vanguard sound-pitch bug). New `TableLiteral`/`DuplicateFunction`
   diagnostics fail rule 1's gate.
8. **Deprecations migrate forward.** `LoadCharacterAsync`,
   `GroupService:GetRolesInGroupAsync`, one-arg `Instance.new` + `.Parent=`.
   New `DeprecatedApi` diagnostics fail rule 1's gate.
9. **Tests prove the pure core.** `lune run tests/run.luau` (runs in the
   gate): WeaponMath vs an independent slab reference, config canon
   (weapon ids ↔ catalogs ↔ FX files), NaN/hostile config scans,
   EffectCatalog default. Engine-bound code is covered by review + the hunt.

## Judgment calls (documented intent, no tool can enforce)

- `Elimination/EffectCatalog.luau`: the effect picker is OFF by design
  (`Catalog.PlayerChoice = false`) — the 18 other definitions are a
  documented re-enable path, not dead code.
- `TeamSpawnServer` `MATCHMAKING` and `EliminationService` `ULT_ON=false`:
  deliberate toggles.
- Placeholders ship by design (PoseController procedural joints, Announcer
  sting, ShopHS/SignatureReveal art, infinite reserve) — the content
  pipeline owns replacing them; tracked in code comments.
- `VantageSignatureLab` / `VantageSkinRange`: self-gated Studio/allow-list
  dev tools that ship in the client bundle (owner accepted).
- CompoundTools command-bar cluster (Base, Angular, Arch, BlueLayout,
  BuildBlock, Constructs, Hall, Mega, Props, Types, Kit, Kit2, Kit3),
  VantageMapTools vs VantageMapTools2 generations: zero in-repo requirers but
  plausible command-bar use — deletion is an owner decision, not automated.
- The live place's `Vantage.Remotes` folder is saved-place state;
  `EnsureCoreRemotes.server.luau` + `RemotesLib` make fresh builds
  self-sufficient. Never let a module occupy the folder's path.

- **Rojo live-sync safety:** every project node carries
  `$ignoreUnknownInstances` — a sync must never delete untracked place content
  (models, saved folders, backups). Keep the guards when editing
  `default.project.json`.
- **Jump pads exempt via the proximity poll, never Touched** — most pads in the
  place have `CanTouch` off (a property a code-only export cannot see), so touch
  events never fire for them.

## The standing hunt (re-run on demand)

New slop categories arrive with new code. Periodically (or after a batch of
PRs) ask Hermes to run the Phase-1 hunt again: four read-only subagents
(client / server / shared / tools) hunting the pattern list in
`audit/findings.md`, each claim re-read by a hostile skeptic, new categories
become new gate rules exactly like rules 2–4 did. `audit/STUDIO-MEASUREMENTS.md`
holds the Studio A/B kit — engine numbers, not claims.
