# F1 DRS Rules for Assetto Corsa

A Custom Shaders Patch (CSP) Lua app that enforces F1-style DRS rules in offline races, for both the player and AI cars:

- No DRS on lap 1.
- From lap 2 onwards, DRS opens in a zone only if the car was within 1.0 s of the car ahead at that zone's detection point (from the track's `data/drs_zones.ini`).
- A double beep plays when you earn DRS at a detection point, and a single beep when the flap opens.

Verified in game on CSP 0.3.1 with the `fn_bahrain` (gp) track. See [`apps/lua/F1DRSRules/README.txt`](apps/lua/F1DRSRules/README.txt) for the full rules and settings.

## Restore after reinstalling the game

Copy the `apps` folder from this repo into the Assetto Corsa folder and let it merge, so you end up with:

```
D:\SteamLibrary\steamapps\common\assettocorsa\apps\lua\F1DRSRules\
```

Or run this from the repo folder in PowerShell:

```powershell
Copy-Item -Recurse -Force .\apps\lua\F1DRSRules "D:\SteamLibrary\steamapps\common\assettocorsa\apps\lua\"
```

CSP must be installed. The app loads with the game; open **F1 DRS Rules** from the CSP app bar to see its settings. Those settings live in `Documents\Assetto Corsa\cfg\extension\state\lua`, not in this repo.

## Tests

`tests/run.py` runs simulated races against the real script with mocked CSP APIs (LuaJIT via `lupa`):

```
pip install lupa
python tests/run.py
```

`tests/make_beeps.py <folder>` regenerates the two `.wav` files.

## History

- `3d61cad`: v1, DRS rules only.
- `16e68f4`: adds the beeps.
