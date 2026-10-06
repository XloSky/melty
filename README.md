# Spider-Punk 2077

Marvel's Spider-Man 2 style web-swinging for Cyberpunk 2077. V can swing between Night City's megabuildings, fling off the top of each swing with their momentum, glide on web wings and zip to whatever they're aiming at.

**Status: v0.1.0. It passes the offline simulator but hasn't been tested in the game yet.**

## What you get

| Move | How (default game bindings) | What it does |
|---|---|---|
| Web Swing | Hold **Jump** in the air | The web finds an anchor above and ahead by itself, so you don't aim. You swing like a pendulum, and the web shortens so you never scrape the street. |
| Momentum Release | Let go of **Jump** | Keeps your speed, with an extra fling if you let go on the up-swing. Hold Jump again to grab the next web. |
| Web Wings | Press **Crouch** in the air | A fast, shallow glide you steer by looking. Press Crouch again to fold the wings. |
| Web Zip | **Aim**, then press **Jump** | Zips to the point under your crosshair and pops you up off it. |
| Soft Landing | Automatic | Puts you on the ground with no fall damage. |

Tapping Jump on the ground is still a normal jump. A swing only starts once you've been in the air for a moment.

The Cyber Engine Tweaks overlay has a **Spider-Punk 2077** window. Use it to switch the mod on or off, adjust gravity, top speed, web range, swing pump, release fling, glide speed and sink, and zip range, or log input action names. Settings are saved to `settings.json` in the mod folder. If you'd rather use your own keys, you can also bind swing, wings and zip under CET's Bindings.

## Requirements

- Cyberpunk 2077 (PC). It's a single-player mod.
- [Cyber Engine Tweaks](https://github.com/maximegmd/CyberEngineTweaks) (Melty installs it for you).

Marvel's Spider-Man 2 is the inspiration, not a requirement. No files from either game are included.

## How it's built

- `design/sheets/*.json` is the source of truth: abilities, tuning, inputs, game hooks, visuals and tests. Each row becomes one Lua table in `generated/sheets.lua` (via `tools/gen.py`).
- `tools/preflight.py` checks every sheet cell and every cross-sheet reference before a build.
- `tests/run_sim.py` runs the real mod code under LuaJIT, with a mocked CET/game API, in a box city. It checks every row of the tests sheet.
- `tools/package.py` runs all three, then builds `dist/spider_punk_2077-<version>.zip`, laid out from the game folder root.

## Credits

- Built with AI (Claude Code), using the [universal-modder](https://github.com/rehan-remade/universal-modder) toolkit's method.
- API usage was checked against the sources of [Cyber Engine Tweaks](https://github.com/maximegmd/CyberEngineTweaks), [psiberx's input sample](https://gist.github.com/psiberx/0e94bc93ed40a70a93a410734a5f5ade) and [entSpawner](https://github.com/justarandomguyintheinternet/CP77_entSpawner). No code from them is included.
- Inspired by Insomniac Games' Marvel's Spider-Man 2. This is not affiliated with or endorsed by Marvel, Sony, Insomniac or CD PROJEKT RED.
