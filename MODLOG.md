# MODLOG: Spider-Punk 2077

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

## Melty (connected 2026-10-06)
- game_info cyberpunk-2077: Melty installs CET v1.37.1, RED4ext v1.30.0, redscript v0.5.31, ArchiveXL v1.27.3 and TweakXL v1.11.4. Players are on game version 3.0.80.51928.
- What Melty's notes changed in the build:
  - Reading action names from Observe(PlayerPuppet.OnAction) fails on CET 1.37.1. Input is now polled with scriptInterface:GetActionValue every frame; OnAction is the backup, used only while polling is silent. Sim test: t_input_routes.
  - The camera basis can be turned 90 degrees about Z. api.camera now self-corrects against player:GetWorldForward(). Sim test: t_camera_basis.
- search_mashups: no web-swinging mashup exists. Live Cyberpunk examples: helldivers-night-city (a CET mod with the same recipe shape, one click) and CyberTrap2077.
- Draft listing: modId d01ce41d-35be-4871-85ec-91e0fda0ac49, slug spider-punk-2077, linked to xlosky/melty. Studio: https://melty.gg/studio/d01ce41d-35be-4871-85ec-91e0fda0ac49
- Release 0.1.0: draft. Checks clear; one_click_check yes. The recipe maps only the mod's own CET folder.

## Next
- Listing choices from the user: license, remix permission, and confirmation of the tagline and description.
- The user presses Test on the mashup's page in the Melty app.
- An in-game test, then a screenshot on the user's Windows PC.
