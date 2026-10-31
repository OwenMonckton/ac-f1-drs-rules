F1 DRS Rules (CSP Lua app)
==========================

What it does (offline Race sessions, player + AI cars):
  - No DRS on lap 1 (configurable: "DRS from lap N").
  - From lap 2, DRS opens in a zone only if the car was within 1.0 s (configurable) of the car
    that crossed that zone's DETECTION point just before it. Lapped cars count, like F1.
    The detection crossing must itself be on lap 2+, so a zone straddling the line between
    laps 1 and 2 stays closed.
  - Zones come from content/tracks/<track>/<layout>/data/drs_zones.ini. If a track has no
    zones file, the start/finish line is the detection point and DRS is usable anywhere on the
    following lap if you were within the gap there.
  - Practice / qualifying keep normal AC DRS unless "Race sessions only" is unticked.
  - Online races: does nothing.

Beeps (your car only, toggle + volume + test buttons in the app window):
  - drs_armed.wav (double beep): you crossed a detection point within the gap, DRS is yours
    for the next zone.
  - drs_open.wav (single higher beep): your DRS flap just opened (any session).
  Replace either .wav with your own sound (same file name) to customise.

How: physics.allowCarDRS() adds a lock on top of AC's own zone logic per car;
ac.onTrackPointCrossed() timestamps each car at each detection point.

Turn on/off:
  - In game, open the app "F1 DRS Rules" from the CSP app bar (right side of the screen).
    Untick "Enforce F1 DRS rules" to switch it off; the setting is remembered.
  - To remove it completely, delete or rename this folder (apps/lua/F1DRSRules).
  The rules run even when the window is closed (LAZY = NONE in manifest.ini).

If the window says "Physics API not available", CSP isn't letting apps touch physics in that
session, so the rules can't apply.
