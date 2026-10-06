# MODLOG: Web of Night City

## Intake (2026-10-06)
- Mashup: Marvel's Spider-Man 2 traversal brought into Cyberpunk 2077. The user picked "web-swinging Night City" (swing, web wings, zip).
- Host game: Cyberpunk 2077 (REDengine 4). Spider-Man 2 is the inspiration only: no files from it are read or shipped.
- Solo: Cyberpunk 2077 is single-player and has no anti-cheat, so there's no account risk.

## Route
- Cyber Engine Tweaks Lua mod. Melty installs CET by itself (as listed in the Melty prompt's game info). No redscript, RED4ext, ArchiveXL or TweakXL is needed for v1.
- Why: CET gives per-frame updates, Observe hooks on game script methods, teleport, raycasts, camera access and an ImGui overlay. That covers swinging without new assets.
- Spider-Man 2 PC route (for the record): the Overstrike mod manager (needs .NET 7). Melty doesn't install it, so Spider-Man 2 isn't used as a host.

## Environment facts
- The work happens in a Linux cloud container. Neither game is installed here, so there's no in-game testing from this session.
- Egress blocks melty.gg, wiki.redmodding.org, nativedb.red4ext.com and codeberg.org. GitHub git clones work.
- API calls were verified against cloned sources (see `design/sheets/hooks.json`, evidence column):
  - CET (maximegmd/CyberEngineTweaks): registerForEvent/registerInput/Observe, GetDisplayResolution, ImGui draw list, json, sandboxed io;
  - entSpawner: Teleport, RaycastWithASingleGroup through LocomotionEventsTransition.OnUpdate's script interface, ProjectPoint to NDC, camera matrix axes;
  - psiberx gist 0e94bc93: PlayerPuppet.OnAction and the Jump action's BUTTON_PRESSED/RELEASED.

## Verification so far
- Offline simulator (`tests/run_sim.py`, LuaJIT 2.1 through lupa) runs the real mod code with strict globals: 5/5 pass.
- The first sim pass hid two problems that a stricter test then exposed:
  - the swing's arc reached 8 m above the street. Fixed with `swing_floor_clearance` and `rope_fast_reel`;
  - the release timing in the test was wrong.

## Still to verify in the real game (preflight lists these as PENDING)
- Action names `ToggleCrouch`/`Crouch` and `CameraAim`. Turn on "Log input action names" in the overlay to confirm them.
- `IsGamePaused` and `Game.GetMountedVehicle` (both wrapped in pcall, with fallbacks).
- Whether teleporting every frame looks smooth, and whether the game keeps any velocity of its own between teleports.
- Whether LocomotionEventsTransition.OnUpdate keeps firing while airborne. If it doesn't, raycasts fall back to SyncRaycastByCollisionGroup.
- The landing snap at high speed: the sim shows a single-frame drop of up to 1.2 m at landing.

## Next
- Melty: game_info, search_mashups, list_my_mods, inspect_package, validate_recipe, one_click_check and a draft listing. These need melty.gg allowed in this environment's network settings.
- An in-game test, then a screenshot on the user's Windows PC.
