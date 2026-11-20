# VantageShot — game code

Live scripts exported from the Roblox Studio place on 2026-11-20. Code only: there are no maps, models, meshes or UI assets.

Folders follow the Studio Explorer (ReplicatedStorage, ServerScriptService, StarterPlayer, …). File names use the Rojo convention:

- `*.server.luau`: Script (server)
- `*.client.luau`: LocalScript (client)
- `*.luau`: ModuleScript
- `init.*.luau`: a script that has child scripts (the folder is the script)

Most of the game lives in `ReplicatedStorage/Vantage` (shared modules), `ServerScriptService/VantageServer` (server services) and `StarterPlayer/StarterPlayerScripts` (client). `ServerStorage/*Tools` holds Studio-only build and map tools.
