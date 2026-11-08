# Microchip F11 Lag Links

Author: **Microchip**. UI-only; other players do not need to install it.

## Install

1. Finish your match and close the game.
2. Copy `Microchip-F11-Lag-Links` from the package into your Forged Alliance
   **Mods** folder (normally `Documents/My Games/Gas Powered Games/Supreme Commander
   Forged Alliance/Mods`). Keep `mod_info.lua` directly inside that mod folder.
3. For full player-to-player diagnostics, back up your current faf-re
   `bin_x64/main_x64.exe`, then replace it with the included
   `engine-update/main_x64.exe`. This is the previously working 26 October
   faf-re baseline plus a read-only diagnostics bridge. Keep the existing
   initialization scripts, shader libraries and `fafengine` directory.
4. Enable **Microchip F11 Lag Links** in FAF's UI mod manager and launch a new game.
5. Press **F11**. Each player's existing row now includes any detected warning.

The packaged engine is x64 faf-re, not the classic FAF engine. Do not replace
classic FAF's `ForgedAlliance.exe`. Existing FAF launch settings continue to
work because the faf-re executable name stays the same. Installing a stock
upstream engine again removes the added bridge.

## Reading the rows

- `Alice [waits for Bob?]`: for at least 1.5 seconds, Alice's reported incoming
  command buffer from Bob has been empty/behind, while another incoming source
  has at least five more simulation beats buffered. The direction is **Bob to
  Alice**. The worst buffer is shown first; `+1` means an additional suspected
  incoming source. Only the worst source's name is shown to fit the F11 row.
- `[high ping to you]`: that peer's measured RTT to your own machine is at least
  400 ms. This alone does not identify a remote pair or prove it slows the game.
- `[no packets to you]`: your connection has received no packets from that peer
  for at least three seconds. Disconnected and stale rows are excluded from
  remote-pair comparisons.
- Your row says `[local links only]` on classic FAF or an older faf-re engine:
  those engines do not expose the full acknowledgement matrix to UI mods.
  No remote-pair result is invented in that mode.

The question mark is deliberate. These are **suspected data-delivery delays**
from existing F11 acknowledgements, not measured packet loss, proof of a faulty
route, or proof of which player is responsible. A source CPU stall, endpoint
scheduling, a pause, or delayed peer reports can resemble a connection problem.
Several players waiting for the same source may be a source/simulation issue.
Uniformly low buffers are not classified as a bad pair. At least three active
clients are needed for comparative pair warnings. Packet RTTs for remote pairs
are not exposed, so the mod does not display invented remote ping numbers.

The mod reads only existing snapshots while F11 is open. It sends no additional
messages, changes no simulation commands, and does not change disconnect/eject
logic. Names are annotated only inside F11. Closing F11 clears its history.

## Remove

Disable the UI mod. To remove the engine bridge too, close the game and restore
your backed-up `main_x64.exe`.

## Verification

Seven automated tests cover warning persistence/recovery, worst-source selection, uniformly slow buffers,
classic-engine fallback, stale peers, roster/clock changes, and preserving the
original snapshot and F11 close behavior. The engine bridge compiles with the
existing x64 build. Live multiplayer validation is still required.
