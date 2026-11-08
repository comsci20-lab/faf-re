# Microchip classic-client test lab

These are real game clients driven by the repository's `mpemu` local lobby
harness. In a mixed test, player 1 hosts on classic FAF, the last seat runs
our installed x64 engine, and **every other seat uses the installed classic
`FAForever/bin/ForgedAlliance.exe`**. No fake game executable stands in for
those classic clients.

## Start a test

Double-click **Compare 2 players.cmd** for the smaller test, or
**Compare 12 players.cmd** for eleven classic peers and one x64 client.
Each launcher first runs an all-classic control, then the mixed test, for
120 seconds after launch in each case. Loading adds extra time. Clients
launch automatically; no public FAF lobby, account login or extra players
are involved. Keep the game windows visible. Ctrl+C stops the test.
Joins are staggered so the classic lobby forms before the x64 client arrives,
matching a player joining an existing classic lobby. A simultaneous 12-client
join burst stalled on missing classic-to-classic links during validation;
such startup failures are reported separately from gameplay performance.

Results are written under `tools/runs/microchip-<time>-<id>/`:

- `performance.csv`: observed simulation ticks per second per client, excluding
  the first 20 seconds of recorded samples. Normal game speed targets ten.
- `runs.json`, each run's `result.json`, and `journal.jsonl`: launch, crash,
  desync and connection results.
- `game-<uid>.log`: the passive recorder, existing game warnings and diagnostics.
- Each run's replays and private preferences, for reproducing failures.

The launcher refuses to start while another game/test is running. It copies
preferences to private `mpemu-p<uid>.prefs` files and enables only a passive
UI test logger there. It does not edit your normal `Game.prefs`, FAF launch
settings or installed executables. The logger is placed in your Mods folder
but is enabled only by the private test profiles. Temporary game clients are
closed by mpemu when the run finishes.

## Other sizes and longer runs

From PowerShell, for example:

```powershell
.\tools\microchip-tests\Run-Classic-Test.ps1 -Players 4 -Seconds 180 -Compare
.\tools\microchip-tests\Run-Classic-Test.ps1 -Players 12 -Seconds 300
```

Supported sizes are 2, 4, 6, 8 and 12. Without `-Compare`, just the mixed test
runs; `-ClassicOnly` runs just the control. `-GenerateOnly` creates the scenario
files without starting clients. `-FafRoot` selects another FAF data folder.
The DualGap Adaptive v0014 map must already be installed; the test is idle
apart from normal commander simulation, not a scripted large battle.

## Interpret the results carefully

All instances share this PC's CPU, GPU and memory. Twelve local processes can
slow each other down even if x64/classic interoperability is correct. Compare
mixed results with the same-count all-classic control. Loading, shader warm-up,
window occlusion and background work can affect a short run. A measured small
difference is not by itself evidence of an engine defect.

This loopback test does not include the production ICE adapter or internet
routing. It checks local peer compatibility, synchronization and observed tick
progress. A strong internet-routing test needs clients on separate computers.
No additional services are installed and no firewall rules are changed.

## Building the harness

The ready local setup has `tools/bin/mpemu.exe`, `mpemu-server.exe` and
`fakegame.exe`. Rebuild with Go 1.25.5 or later using `tools/build.ps1`.
`fakegame` is used only for harness selftests, not in the real-engine scenarios.
Scenario-generation checks: `Test-ClassicProfiles.ps1`.
