# FORK NOTES — provenance, component mapping, leave-behind

**Direction (owner, refined):** Ant's Godot 4.7 project is the **fork's
starting codebase** — a development shortcut, not an architectural
dependency. The finished product is **AION Gym**, an entirely independent
application. Ant's repositories (`C:\Users\aaron\nm_agent\` Godot console,
`C:\Users\aaron\ants\` Python colony) are **read-only references**; nothing
is copied verbatim-with-Ant's-branding — every reused pattern is renamed,
adapted and tested as an AION Gym component.

**Authority (unchanged):** the Python AION runtime remains authoritative.
The Gym communicates only through its own authenticated bridge
(`aion/gym_bridge`). No dependency on the Ant's Python colony. The Gym never
writes plastic state directly; denials surface with reasons.

---

## 1. Provenance of this repo's own code

The client core (`schema.gd`, `event_bus.gd`, `state_cache.gd`,
`ws_client.gd`, `http_client.gd`, `connection_manager.gd`,
`connection_graph.gd`, `learning_curves.gd`, the dashboard, all scenes,
both concept arts, and the gate suite) was **built here, for AION, from
scratch** — it is not derived from Ant's. It is the validated transplant
seed (145-check gate, green twice across refactors). Nothing Ant's-specific
leaked into it: `grep -ri "ant\b|necro|soul|colony|minion|pheromone"` over
the repo returns only AION-Gym-own strings (the word "Ant's" appears solely
in this file and in ARCHITECTURE.md's provenance notes).

## 2. Component mapping — Ant's pattern → AION Gym component

| Ant's pattern (read-only reference) | AION Gym component | Rename / adaptation | Tested |
|---|---|---|---|
| Portrait project config: 540×960 base, `canvas_items` stretch, `expand` aspect, handheld portrait | `project.godot [display]` | Adopted as-is pattern with AION values; pairs with the dashboard's portrait/landscape reflow | boot gate + reflow path |
| Console page system: safe-area placement (`_place`/`_compute_safe_margins`), tween slide with instant headless transitions, `WM_GO_BACK_REQUEST` handling | `scripts/core/app_shell.gd` (`AppShell`) | Rebuilt from the pattern, asset-free: page registry, exclusive-visibility invariant (`visible_pages_overlap`), back-to-home semantics | gate suite (`[app shell]`) + boot |
| Bottom multi-tap tab bar (`NecroTabBar`, icon tabs) | `scripts/core/gym_tabs.gd` (`GymTabBar`) | Rebuilt text-tab bar, AION accent colours, no Ant's art; tab ids data-checked against the shell's page set | gate suite (`[navigation data]`) + boot |
| Android export preset (arm64-v8a, gradle, portrait, immersive, internet) | `export_presets.cfg` | Re-branded: `com.slothitude.aiongym`, "AION Gym", `builds/aion_gym.apk`; **PyBridge plugin dropped** | file verified; APK build is an owner action (needs Android export templates) |
| Telegram lobby/chat slide navigation | superseded by the shell's page system; the future chat/teach page will be a shell page | — | — |
| Sequenced ring + `since`-marker incremental reads (`EventBus.emit_event` + `GET /events?since=`) | pattern reserved for replay: the Gym's `StateCache` journal is the client-side store; the bridge pushes events, so no client ring is needed. If the bridge later exposes replay-by-sequence, the client adopts the same `since`-marker contract | documented, not duplicated | journal covered by gate suite |
| `ChatPanel` (one-true-transcript widget) and `MarkdownLabel` addon | candidates for the future Chat & Teach page — to be rebuilt/renamed as AION Gym components when that surface is built (next milestone), never copied with branding | planned | not yet built |
| GraphEdit nest canvas | not taken; the relationship graph is the Gym's own `connection_graph.gd` renderer fed by `connection.updated` | — | gate suite |

## 3. Leave-behind (honoured)

None of the following exists anywhere in this repo (verified by grep):
ant colony · agent/soul management · the NecroMancer console · minion/worker
orchestration · the pheromone field · CLI/SSH agent management · Ant's domain
model or branding · Ant's art (`art/`, tab icons) · `keys.json` · the MCP
client/bridge · PyBridge (on-device CPython/llama JNI — the Gym talks to the
bridge over the network; on-device Python would be an explicit future
decision, not an inherited dependency).

## 4. Concurrent-lane forensics (recorded for the evidence trail)

During the skeleton session, companion lanes landed work directly in this
repo's working tree, which commit `f5fa97f` swept in alongside the concept-2
fold-in. Reviewed and accepted as part of the fork:

- **Authenticated bridge support** (GYM-B/C companion): `http_client.gd`
  token + `X-AION-Token` header on action POSTs; `ws_client.gd` control path
  (`action.request` out, `action.result`/`action.error` in via
  `action_result` — control replies are not schema events);
  `connection_manager.gd` `set_token()`, http base pinned to the bridge's
  request API port (:7481 beside the ws stream :7480), and
  `request_snapshot()` routing the authoritative document onto the bus under
  the same parse contract.
- **tests/integration_client.gd** — the GYM-C end-to-end driver (real client
  stack against the live bridge; teaching arc, paused-teach denial, ws
  authorized/bad-token, hostmode gate, all-11-types, dashboard equality).
  Compiles against the current core (`--check-only` green); run is a
  GYM-C/owner action with a live bridge and token.
- **`_int_if_integral` display fix** in the dashboard (JSON float 4 renders
  as "4", never "4.0").
- **Removed:** `tests/_probe_frames.gd` (scratch probe swept in by the same
  staging).

Gate status after all of the above: 145/145 + shell/navigation suites green;
boot smoke clean; no errors or warnings.
