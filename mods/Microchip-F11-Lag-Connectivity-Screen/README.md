# Microchip F11 Lag Connectivity Screen - version 3

The UI-only mod replaces the contents of the game's Connectivity window with a table in the existing metallic game frame. Press F11 to open or close it.

## Table and ranking

Remote players are ranked **worst waiting percentage first**, then longest wait, with names as a stable tie-breaker. Ping does not determine the ranking. Your own row is separate and unranked. Disconnected peers are listed last.

- **Time waiting:** percentage of observed active gameplay, within the trailing 30 wall-clock seconds, during which your engine needed its next simulation update but that peer's commands or confirmations were missing.
- **Longest wait:** longest continuous such interval inside that window, in milliseconds. A continuing wait is clipped to the 30-second window.
- **Current ping:** the existing RTT measurement between your PC and that peer, in milliseconds.
- **Zero:** required remote data was ready when needed. Normal command lead/buffering is not counted, and the code does not subtract a fixed 500 ms from ping.

Shared waits are attributed to each missing peer, so percentages can overlap. Pauses and pre-game readiness are excluded. The UI says when it is still collecting its first 30 seconds of history. Older engines show `--` and a timing-unavailable notice, never an invented zero. Ping remains usable there.

Waits identify whose data your client is missing, not whether internet routing, packet delivery, the remote CPU, or endpoint scheduling caused the delay. They do not measure other players' waiting on you. Existing sustained comparative-buffer warnings such as `[waits for Bob?]` remain on the secondary line; those are separate suspected-link diagnostics, not the source of the measured percentages.

Longest-wait display colours use provisional thresholds: below 100 ms green, below 250 ms yellow, below 500 ms orange, otherwise red. Waiting-percentage colours use below 1%, below 5%, below 15%, and 15% or greater respectively. These are display choices, not official FAF ratings.

## Installation

1. Close the game.
2. Copy `Microchip-F11-Lag-Connectivity-Screen` to the normal FAF UI Mods folder.
3. For measured waits, back up `FAForever/bin_x64/main_x64.exe` and replace it with the included `engine-update/main_x64.exe`. This is the working e4cc5d8b engine base plus passive Microchip diagnostics. Preserve your existing init scripts, shader libraries and `fafengine` folder. Classic peers need no update. Do not replace classic `ForgedAlliance.exe`.
4. Enable **Microchip F11 Lag Connectivity Screen** in your UI mod manager and launch a new game.
5. Open F11. No rebuild is needed for other players.

The included executable is x64 faf-re. Reinstalling a stock upstream engine removes this custom measurement API; the mod will then display unavailable timing. Existing builder choices and the local checksum toggle are separate features.

## How it is measured

The render/session loop records when a next update is actually demanded and no sync packet is ready. The driver identifies that demanded beat, excludes paused/non-network sessions, and the client manager attributes only missing remote data/ACK readiness. If that beat has already been dispatched for CPU processing, no network wait is charged. Local command-issuance shortages are not charged to remote peers.

The client manager updates intervals as delivery/readiness changes. A passive sidecar keeps a rolling 30-second timeline outside the ABI-sensitive engine object. UI reads do not create or end waits. The Lua snapshot exposes `fafReNetwork.waitVersion`, `waitObservedSeconds`, `waitPercent`, and `longestWaitMs`. The window refreshes twice a second; engine timing is independent of that refresh. Timing starts at observed frame demand and ends at engine readiness processing, so it has frame/event scheduling resolution rather than packet-capture precision.

No new network packets, simulation commands, or remote mods are required. The instrumentation does not change simulation state, protocol, pacing, checksum settings or CPU affinity.

## Validation

- Engine network suite: 269 checks, zero failures, including demand gating, timely delivery, pause exclusion, overlapping waits, continuous longest waits, expiry and clock reset.
- Lua tests cover ranking by wait rather than ping, valid zero versus unavailable data, window lifecycle, the existing suspected-link logic, and passive recording.
- Real classic + x64 direct test completed at about 9.85 ticks/second on the x64 client.
- A private loopback relay test injected 800 ms one-way delay for 20 seconds. The remote classic peer's observed wait peaked at 23.379%, with a longest observed interval of 552.245 ms. After recovery and history expiry the sample returned to 0% and 0 ms. The run reported no crash or desync.
- Actual game UI creation/update/close is checked separately with private preferences. Tests do not contact a public FAF lobby.

The local tests are short and share one PC. They validate this implementation's behaviour, not every internet or mod combination.
