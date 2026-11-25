# AION Gym — Architecture & Event Contract

Design principle: **The Gym is the world. AION is the learner. The owner is
the observer, teacher and environment designer.**

Display-integrity law: AION must not fake its learning for the display. Every
visible change corresponds to real state, real events, or an explicitly
labelled visualization. The Gym never reimplements AION's intelligence — it
observes and requests.

---

## 1. Two repos, one contract

```
AION/ (Python, authoritative — owned by its own lane)
├── aion/
│   ├── ...                   # everything built to date
│   └── gym_bridge/           # the event interface (the only new aion code)
│       ├── emitter.py        #   subscribes to runtime state; emits the event stream
│       ├── actions.py        #   permitted-action request API (routes through
│       │                     #   the runtime's authority gates — hostmode law)
│       └── schema.py         #   event payload schemas (versioned)

AION-Gym/ (this repo — the Godot client)
├── project.godot             # portrait-first, mobile + desktop
├── export_presets.cfg        # Android arm64 APK preset ("AION Gym")
├── scenes/                   # gym (root), habitat, mind_viewer,
│                             # training_world, memory_archive, control_room
├── scripts/
│   ├── core/                 # event_bus, state_cache, connection_manager,
│   │                         #   app_shell (pages/back), gym_tabs (tab bar)
│   ├── aion_client/          # ws_client, http_client, schema (THE CONTRACT)
│   ├── visualization/        # connection_graph, learning_curves
│   └── gym.gd                # dashboard + shell pages + reflow
├── assets/                   # concept art (both owner concepts)
├── docs/                     # this file + FORK_NOTES.md (provenance)
└── tests/                    # gate suite + GYM-C integration driver
```

The only new Python code is `aion/gym_bridge/` — an observation-and-request
layer. It contains no learning logic. It reads state (already public to the
project), emits events, and forwards action requests into the runtime's
existing authority gates (the hostmode law: AION proposes, the runtime
disposes; the Gym is just another proposer, with the same zero-direct-write
discipline).

This repo contains **no learning logic and no direct state writes** — it is a
pure client.

## 2. Data flow inside the Gym

```
gym_bridge (Python, ws + http)
        │  JSON envelopes
        ▼
ws_client ──parse──► schema.gd (contract) ──ok──► ConnectionManager
   │                     │                              │
   │                     └──parse_error──► EventBus.parse_error
   ▼                                                    ▼
                                       EventBus (per-type signals + raw_event)
                                                    │
                     ┌──────────────────────────────┼───────────────────────┐
                     ▼                              ▼                       ▼
               StateCache                  connection_graph /            dashboard
        (latest per type + journal)        learning_curves          (Live AION column,
             (replay foundation)            (honest renderings)      journey feed, stages)

http_client ── permitted-action requests ──► runtime authority layer
            ◄─ verdicts/denials with reasons ┘
```

Autoloads (declared in `project.godot`, in this order):
`EventBus` → `StateCache` → `ConnectionManager`. Every script also works
standalone (tests inject dependencies via `attach()` / `attach_bus()`), so the
headless test runner never depends on autoload registration.

## 2b. App shell & navigation (mobile + desktop)

`scripts/core/app_shell.gd` (`AppShell`) hosts full-screen pages with slide
transitions, safe-area placement and back navigation (Android back button,
Escape); `scripts/core/gym_tabs.gd` (`GymTabBar`) is the bottom tab bar.
Pages: the dashboard (home) plus the five surfaces — habitat, mind viewer,
training world, memory archive, control room. Keyboard shortcuts `0–5` remain
for desktop. The dashboard reflows stacked when the viewport is portrait and
side-by-side when landscape, re-filling every widget from the `StateCache`
so a reflow never blanks the display.

Fork provenance for these components: `docs/FORK_NOTES.md`.

## 3. Transport

- **WebSocket** — push event stream, Godot subscribes.
- **HTTP** — request/response for snapshots and permitted actions.

Client-side defaults (the bridge lane may pin different values; override via
`ConnectionManager.connect_to_runtime(host, port)` and the manager's
`http_port`):

| Setting | Default |
|---|---|
| WS URL | `ws://127.0.0.1:7480` (`wss://` when `use_tls`) |
| HTTP base | `http://127.0.0.1:7481` (the bridge serves its request API beside the stream; pinned by the manager on connect) |
| Snapshot | `GET api/snapshot` |
| Actions | `POST api/actions/<action>` with `X-AION-Token` when a token is set |

**Authentication:** actions are authorised by the bridge. The client sends
the token on action requests only — `X-AION-Token` header over HTTP,
`token` field on ws `action.request` control messages (`ConnectionManager.set_token`).
Snapshot reads stay open on the localhost bind per the bridge's auth law.
Every request is validated by the runtime's authority layer; denials return
`reason` + `state_unchanged` and are displayed, never hidden.

**Ws control path (not schema events):** `action.request` out;
`action.result` / `action.error` replies arrive on `ws_client.action_result`
before the schema contract sees the frame — control replies have no event
envelope. Snapshot-over-HTTP is wrapped in a locally-constructed
`state.snapshot` envelope (explicitly marked, real data only) so the whole
pipeline — cache, graph, dashboard — has exactly one path.

Reconnect policy: capped exponential backoff — 0.5s, doubling per attempt,
capped at 30s; unlimited attempts by default (`reconnect_attempts` to limit).
A successful connect resets the backoff. Manual disconnects never reconnect.

## 4. The event contract (versioned envelope)

Both the Gym and the bridge build to this. **Additive-only evolution**: new
optional fields may appear at any time; unknown envelope keys are tolerated;
unknown payload fields always pass through; unknown event types are passed
through as RAW (never dropped); a newer `schema_version` is accepted and
annotated `future_version`, never rejected.

```json
{"schema_version": 1, "type": "<type>", "timestamp": 42.5, "payload": {...}}
```

### Event types

| Event | Emitted when | Payload core |
|---|---|---|
| `state.snapshot` | on connect + on request | full inspectable state: relationships, u_fast/θ strengths, gate states, memory inventory, devhistory stage, mode, uptime |
| `experience.created` | a lesson/observation enters memory | episode id, provenance, fact extracted |
| `connection.updated` | plastic strengths change (throttled) | connection id, endpoints, Δu_fast, Δθ, strengths before/after |
| `memory.consolidated` | a consolidation event fires | what moved u→θ, preservation-verified flag |
| `dream.started` | a dream cycle begins | cycle id, seeds/retrieved experiences |
| `dream.hypothesis` | a hypothesis is proposed | the composed relationship, confidence |
| `dream.evaluated` | reality tests a hypothesis | measured improvement, accepted/rejected + reason |
| `nomen.changed` | NOMEN names or renames | entity id, old name, new name, lineage |
| `nav.action` | AION-NAV chooses an action | decision record (goal, options, choice, outcome) |
| `hostmode.request` | a host-mode proposal is made | proposal, authority verdict (granted/denied + reason) |
| `development.stage` | a gestation transition is recorded | stage name (NOMEN-generated), optional stage_index, evidence |

### Payload field contract

Per type, `required` is the shared minimum both sides build to; `optional`
documents known fields. `schema.gd` (`scripts/aion_client/schema.gd`) is the
single source of truth in this repo.

| Type | required | optional |
|---|---|---|
| `state.snapshot` | — (open document) | state, relationships, u_fast, theta, gates, memory_inventory, devhistory_stage, stage, stage_index, mode, uptime_s, plasticity, experience_steps |
| `experience.created` | episode_id | provenance, fact, source, world_id |
| `connection.updated` | connection_id | from_node, to_node, delta_u_fast, delta_theta, u_fast_before, u_fast_after, theta_before, theta_after, cause_episode_id |
| `memory.consolidated` | moved, preservation_verified | cycle_id, moved_count, detail |
| `dream.started` | cycle_id | seeds, seed_count |
| `dream.hypothesis` | hypothesis_id | cycle_id, relationship, confidence |
| `dream.evaluated` | hypothesis_id, accepted | cycle_id, measured_improvement, reason |
| `nomen.changed` | entity_id | old_name, new_name, lineage |
| `nav.action` | decision_id | goal, options, choice, outcome |
| `hostmode.request` | request_id, verdict | proposal, reason, resource |
| `development.stage` | stage | previous_stage, evidence, stage_index |

### Parse rules (`schema.gd`)

- Envelope problems are **fatal**: not an object, missing/non-numeric
  `schema_version`, missing/non-string `type`, missing/non-numeric
  `timestamp`, missing/non-object `payload`, invalid JSON.
- Missing required payload fields are reported in `payload_errors`; fatal only
  in `strict_payload` mode. A well-formed envelope is **never dropped**
  (display integrity).
- Unknown types parse OK with `is_raw: true` and route on `EventBus.raw_event`.

## 5. Request API (permitted actions only)

`teach(experience)`, `ask(question)`, `correct(fact)`, `pause()`,
`resume()`, `set_goal(goal)`, `approve_request(id)`, `deny_request(id)`,
`snapshot()`.

Every request is validated by the runtime's authority layer; denials return
reasons and are displayed in the Gym, never hidden. Non-permitted actions are
refused locally by `http_client` before any network traffic.

## 6. Surfaces

1. **Habitat** (immersive) — a living 3D environment with AION's visible
   presence. Cosmetic presence, honest representation: visuals may develop
   with real developmental events but never invent capability.
2. **Mind viewer** (scientific) — the live plastic graph: connections as
   edges, thickness = strength, fast/slow layers, γ-gates when the bridge
   reports them. Inspect a connection's history and its causing experience.
3. **Training worlds** — create tasks and challenges; introduce objects and
   concepts; ask questions. Watch the attempts, not just the answers.
   Batteries from `aion/worlds/` plug in directly.
4. **Memory archive & dream laboratory** — browse experiences, corrections,
   provenance (PLASTIC/CONSOLIDATED/RETRIEVED never conflated), patterns,
   dream acceptance trails.
5. **Control room** — chat, teach, correct, pause/resume, set goals,
   approve/deny host-mode resource requests. Every owner action routes
   through the runtime's authority layer — the owner has the largest
   permitted menu, still not a bypass.
6. **Event history & replay** — every event is journaled (`StateCache`,
   capped at 1000 entries); replay arrives in the vertical slice.

## 7. Dashboard (two concepts, composed)

The dashboard composes both owner concept arts:

- **Concept 1** (`assets/aion_gym_life_cycle_concept.png`) — the layout frame:
  header, right-hand Live AION column, You Can action column, learning /
  worlds / journey bottom row, footer.
- **Concept 2** (`assets/aion_development_stages_concept.png`) — the stage
  presentation: the owner's **4-STATE CANON** with gestation periods, the
  "What You'll See" panel row, and the Key Principles card. This supersedes
  concept 1's five-panel evolution path.

### Stage presentation (4-state canon — recorded, never awarded)

| # | Stage | Trait | Gestation period | Phase |
|---|---|---|---|---|
| 1 | Parasite | Attached • Dependent | 0 – 1 day | attachment phase |
| 2 | LLM | Borrowed Brain | 1 – 7 days | learning phase |
| 3 | Emerging AION | Plastic • Adaptive | 1 – 30 days | consolidation phase |
| 4 | Independent AION | Self-Directed • Autonomous | 30+ days | mature stage |

Gestation periods are displayed as part of each stage panel. The active stage
is highlighted only by real `development.stage` events (via `stage_index` or
stage-name keywords); with no events, nothing is highlighted. A stage is
**recorded, never awarded** — the client never promotes AION on its own.

### "What You'll See" — the seven panels and what renders them

| Panel | Rendered by |
|---|---|
| Evolution Stage | the four stage panels (this dashboard) |
| Brain Activity | `learning_curves.gd` — real `|Δu_fast|` activity; exam-derived curves arrive when the bridge defines exam events |
| Connection Graph | `connection_graph.gd` — mind viewer lens; real `connection.updated` edges |
| Chat & Teach | control room lens + You Can actions (permitted-action API) |
| Dreams & Replay | memory archive lens + the `StateCache` journal (replay) |
| Experiments | training world lens (M2) |
| Progress & Evidence | journey feed (real nomen/dream/hostmode events) + stage evidence |

### Key Principles (display-integrity law, verbatim from the concept)

- Stage is recorded, never awarded
- No evidence, no claim
- Display shows the real state

> *AION's journey is real. The Gym shows the truth.*

### Layout frame (concept 1)

- **Header** — "AION GYM — Watch • Teach • Interact • Grow — From Parasite to
  AION, a living AI journey"
- **Live AION column** — Online (connection state), Mode, Plasticity, Memory,
  Experience, Uptime — all from `state.snapshot`; `—` until real values
  arrive.
- **You Can column** — Teach a Lesson / Ask a Question / Set a Goal /
  Explore a World / Watch & Learn — 1:1 with the permitted-action API; the
  action trio routes through the runtime's authority layer and surfaces
  verdicts verbatim.
- **Learning in Real Time** · **Explore Worlds** · **Watch the Journey** — as
  mapped above.
- **Footer** — "AION Gym v1.0 — A Living AI, Growing Mind" · Learn • Adapt •
  Evolve · "AION — Not just intelligence, but a journey." + connect button
  and status line.

## 8. Tests

```sh
godot --headless --path . --script res://tests/run.gd
```

Covers: schema parse for all 11 types; envelope error cases; unknown-type RAW
passthrough; future-version and additive-key tolerance; bus routing to all 11
per-type signals + raw + parse-error paths; state cache (latest per type,
snapshot state, journal, clear); ws frame parsing offline; http URL building
and local refusal of non-permitted actions; connection-manager backoff
progression, retry scheduling, give-up, manual-disconnect and
auto_reconnect=false paths (offline mock — no sockets); visualization stores.

## 8b. The 3D organism view — honest-visualization mapping (owner canon)

Binding mapping for the Gym's 3D organism rendering (the owner sketches the
prototype scene + mapping script next; this section is the law it builds to):

| Visual | Maps to |
|---|---|
| node | Node3D instance (MultiMesh for bulk) |
| position | layout projection |
| size | scale from strength (\|u_fast\| or consolidated magnitude) |
| orientation | look_at toward the strongest connection |
| connection | line / thin cylinder, width + opacity from weight |
| color | provenance (PLASTIC / CONSOLIDATED / RETRIEVED) |
| change over time | Tween from old to new transform, only on real state deltas from the event stream |

**Three honesty rules (binding):**

1. **Position is a layout, not a measurement.** Distance between nodes does
   not mean similarity unless computed that way — and viewers will read it
   as if it does. Label the layout method on screen (e.g. "PCA of weight
   vectors, seed 0") or use a fixed arbitrary layout and say so. Every run
   records which it used, so replays don't differ for no reason.
2. **Rotation needs a defined quantity.** Plastic nodes have no intrinsic
   orientation; look_at is meaningful only toward a real relationship (e.g.
   the strongest connection). Otherwise it is decoration, and decoration
   must be labelled.
3. **Animation is a diff, not a loop.** Tweens only in response to a change
   event with a real before/after state. An idle AION that spins or pulses
   would be the misleading representation the Gym design warns against.

**Practical notes:** the event stream drives transforms, not polling — every
visible movement traces to a ledger entry and replay reproduces the motion;
raw values are one click away next to the visual (a large-looking node shows
its number); **prototype on the small fixed 20-relationship world first**
(replay of one recorded run) to check the mapping reads correctly before
scaling.

**Where it lands:** the Gym page (transplant build step 3) and the
new-section spec's AionModel + 3D visualization layer. The 2D connection
graph already obeys what applies to it: the layout method is labelled on
screen (fixed deterministic hash-circle layout), colour follows provenance
when events carry it (unrecognized values render grey, fallback fast/slow is
labelled), and nothing animates except on real deltas. The shell's page-slide
tweens are interface chrome, not organism-state animation — they carry no
state meaning and animate nothing about AION.

## 9. Laws

1. Display integrity (no faked learning; explicit labelling of any
   visualization)
2. Authority (Godot requests; the runtime disposes; zero direct plastic
   writes)
3. Register (the Gym reports results in the corrected register — it inherits
   the honesty laws, being the public face)
4. Single-writer, stay-in-lane (bridge code lives in the AION repo; the Gym
   repo is separate)
5. No automatic progression between milestones without reviewing the previous
   milestone's report
