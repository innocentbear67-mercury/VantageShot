# VantageShot — Studio measurement kit

The repo fixes land in your game only when you sync this branch into the place
(`rojo serve` or rebuild). Until then, your live place still runs the OLD code —
which is exactly what makes a clean A/B possible:

- **Session A (BEFORE)**: open the place as it is today. Record the numbers below.
- **Session B (AFTER)**: connect the same place to this repo
  (`rojo serve default.project.json` from the repo root, connect in Studio),
  or `rojo build -o place.rbxl` and open that. Record the same numbers.

Every engine number below is Roblox's own output, not a claim from the audit.

## 0. What was changed (the things these measurements target)

| Fix (commit) | Plane | Expected effect — verify, don't trust |
|---|---|---|
| A1 lifts/ambient RunContext (`96de740`) | export fidelity | no-op in your live place (its instances were already set correctly — the export had lost the setting); fresh rojo builds now match; confirm lifts/ambient unchanged after sync |
| B1/B5 HUD chain + parked clusters (`0627ee4`) | client frame | smaller, steadier client frame during a match |
| B2 TagCache loops + RayOBB hoist (`2ed2211`) | client+server | less GC churn; GC bars thinner in the timeline |
| B3/B6 write-on-change (`0f32e03`) | client frame | fewer per-frame string/GUI writes in lobby |
| C1 HitValidation (`8f4703a`) | server tick | shorter server frame with a full lobby |
| C2 TimeLeft 1 Hz (`8f4703a`) | replication | ~19× fewer TimeLeft attribute updates |
| C3 pellet batching (`8f4703a`) | replication | shotgun fights: 23 instead of 207 messages per blast |
| C4 JumpPad poll, cheaper (`8f4703a` + post-review revert) | server tick | same 10 Hz exemption timing as the original (Touched could not work: 70/88 pads have CanTouch off), minus the per-tick allocations |
| D1 dead shared modules (`c073a69`) | join | ~60 KB less replicated Luau per join |

## 1. Client measurements (do these twice: A then B)

**Tools:** MicroProfiler `Ctrl/⌘+F6` (pause `Ctrl/⌘+P` for detailed mode),
Performance Summary `Shift+F2`, Developer Console `F9`.

Run each session the same way: join LiveFire with the same player count
(Studio "Start" + a few clients, or Team Test), pick the same weapon (try
Breacher — the 9-pellet shotgun), fight for ~60 s, then record:

1. **Frame time bars** (MicroProfiler): overall bar height during combat and
   during a quiet corner. Look for: consistency (bar heights even), and the
   orange "Jobs" section vs blue "Render". Script cost shows up orange.
2. **GC churn** (MicroProfiler, search `Ctrl+F` for `gc`): count/size of GC
   steps across 128 frames. The B-plane fixes should shrink this.
3. **Performance Summary**: average FPS + frame time, client, during combat.
4. Optional per-scope timing: temporarily wrap `Hud:Step`
   (`src/client/VantageWeaponClient/Hud.luau`) with
   `debug.profilebegin("VS Hud:Step")` / `debug.profileend()` and the Skins
   pattern loop (`src/shared/Vantage/Weapons/Skins.luau`) likewise — the
   labeled bars appear in the MicroProfiler timeline. Remove the wraps after
   measuring (they are measurement aids, not permanent code).

**Expected:** B shows lower/steadier frame time and thinner GC activity under
combat; the parked-cluster and write-on-change fixes mostly help the quiet
lobby (open the lobby screen and compare idle frame time).

## 2. Server measurements (Studio server view or the "Current: Server" view)

1. **Server frame / Heartbeat**: MicroProfiler on the server (Studio server
   view, `Ctrl+F6`) during a live match with a full bot lobby
   (`/squad` in chat tops teams up). Compare the `RunService.PostSimulation`
   (Heartbeat) band between A and B — C1/C4 should shrink it.
2. **JumpPad**: the 10 Hz proximity poll is back (post-review revert — most pads
   have CanTouch off, so Touched never fires for them); it now iterates the
   signal-maintained TagCache set instead of allocating per tick. Exemption
   timing is identical to the original.
3. **Sanity checks (A1):** lifts already launch in your live place and ambient
   props already animate — both were correct in Studio and only the exported
   copy had lost the setting. After syncing, simply confirm both still work
   (the repo fix is what makes fresh rojo builds behave the same).

## 3. Replication measurements (the network wins)

**Network view:** Studio → View → Performance/Network (or the MicroProfiler
`replication` tags; Developer Console → PerformanceStats).

1. **TimeLeft**: with the match live, watch Match.TimeLeft attribute update
   rate on a client — A ≈ 20 updates/s, B ≈ 1/s (score-check cadence is
   unchanged, so end-of-match timing behaves identically).
2. **Shotgun fan-out**: with two clients, fire one Breacher blast while
   recording remote traffic — A sends 9 "Shot" messages per spectator, B
   sends 1 (payload is a table of 9 pellet ends; visuals are identical).
3. **Join payload**: the shared Luau folder shrank ~60 KB (dead modules) —
   minor, but visible as slightly less "waiting for replication" time.

## 4. Before / after table (fill in)

| Measurement | A (live place) | B (this branch) | Notes |
|---|---|---|---|
| Client FPS — combat avg | | | same map, same lobby size |
| Client FPS — lobby idle | | | lobby screen open |
| MicroProfiler GC steps / 128 frames | | | search "gc" |
| Server Heartbeat band (full lobby) | | | server MicroProfiler |
| TimeLeft updates / s on client | | | expect 20 → 1 |
| "Shot" messages per blast per spectator | | | expect 9 → 1 |
| Gravity lift launches you? | yes (already correct in place) | | confirm unchanged after sync |
| Ambient props animate? | yes (already correct in place) | | confirm unchanged after sync |
| Join time to playable (rough) | | | ~60 KB less replicated code |

## 5. Honest limits

- Numbers recorded on your Mac are directional; most Roblox players are on
  phones — the mobile MicroProfiler (in-game Settings → MicroProfiler on,
  then browse to the shown IP:port from this Mac) is the number that matters
  for real players.
- Nothing here proves player-visible smoothness on its own: frame-time
  *consistency* (MicroProfiler bar evenness) is the better indicator.
- If any B number regresses, that is a bug in the fix batch — tell Hermes
  which row regressed and the labeled MicroProfiler bars.
