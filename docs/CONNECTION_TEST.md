# Lobby connection test

The rebuilt engine's lobby has a **Lag Test** button. Open it, then the host
presses **Lag Test** in the results panel to run the test. Each row shows the
player's lowest score and the peer on that connection:

```text
Alice: 90.0% -> Carol
Bob: 100.0% -> Alice
Carol: 100.0% -> Alice
```

The score is the percentage of 240 round-trip probe replies received within
500 ms, over about one minute. Probes use the actual reliable lobby peer
connections, including their routing and retransmissions. A missing or late
reply counts against the sending player's score. Duplicate replies do not
increase it. Equal scores choose the peer name alphabetically.

This is **not a hidden simulation**, packet-loss measurement, or measurement of
actual in-game command deadlines. Probe RTT includes both network directions
and application scheduling. A bad pair does not identify which person or ISP is
responsible. CPU scores remain unchanged. A score of 100% means all probes met
this test's deadline, not that a match is guaranteed to run without lag.

Every connected participant (observers included) needs the same hook. The host
cannot start while any peer has not advertised support. An unmodified FAF
client is not assigned a made-up score. Each participant reports only its own
outgoing probe results; reports are self-reported diagnostics, not anti-cheat
evidence. A detected local scheduling pause of more than 200 ms makes the run
inconclusive, rather than attributing the pause to a network route. Smaller
endpoint pauses can still affect the score.

Joining or leaving invalidates the results. Missing reports remain unknown and
are labelled after a five-second grace period. Only the host can start a run;
another run can replace the completed results.

## Install

The standard build stages `data/fafengine/` beside the engine executable. For
an already-built engine, copy the **contents** of that directory into the
`fafengine` directory beside the executable, keeping the `lua/ui/lobby/` layout.
Do this on each participating PC. Relaunch the game and create/join a lobby.
FAF's downloaded `lua.nx2`/`lua.nx4` archives are not modified.

Remove the three files under `fafengine/lua/ui/lobby/` to uninstall this feature.

## Tests

Install the Python `lupa` package and run:

```powershell
python tests/lobby/test_connection_score.py
```

The tests use Lua 5.1 and a simulated three-peer transport to check deadlines,
loss, duplicate replies, shared worst-peer results, unsupported clients,
membership changes, scheduling pauses, and malformed reports. These tests do
not replace a live multi-PC lobby test.
