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
├── project.godot
├── scenes/                   # gym (dashboard), habitat, mind_viewer,
│                             # training_world, memory_archive, control_room
├── scripts/
│   ├── core/                 # event_bus, state_cache, connection_manager
│   ├── aion_client/          # ws_client, http_client, schema (THE CONTRACT)
│   ├── visualization/        # connection_graph, learning_curves
│   └── gym.gd                # dashboard + lens switching
├── assets/                   # concept art
├── docs/                     # this file
└── tests/                    # headless GDScript test runner
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

## 3. Transport

- **WebSocket** — push event stream, Godot subscribes.
- **HTTP** — request/response for snapshots and permitted actions.

Client-side defaults (the bridge lane may pin different values; override via
`ConnectionManager.connect_to_runtime(host, port)` and `http_client.base_url`):

| Setting | Default |
|---|---|
| WS URL | `ws://127.0.0.1:7480` (`wss://` when `use_tls`) |
| HTTP base | `http://127.0.0.1:7480` |
| Snapshot | `GET api/snapshot` |
| Actions | `POST api/actions/<action>` |

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

### Snapshot over HTTP

`GET api/snapshot` returns the state document (the `state.snapshot` payload).
The client wraps it in a locally-constructed `state.snapshot` envelope
(explicitly marked, real data only) so the whole pipeline — cache, graph,
dashboard — has exactly one path.

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

## 7. Dashboard (concept layout)

`scenes/gym.tscn` mirrors `assets/aion_gym_life_cycle_concept.png`:

- **Header** — "AION GYM — Watch • Teach • Interact • Grow — From Parasite to
  AION, a living AI journey"
- **Evolution path** — five panels: Parasite → LLM → AION Awakens → AION
  Grows → AION Thrives. The active panel is highlighted only by real
  `development.stage` events (via `stage_index` or stage-name keywords); with
  no events, nothing is highlighted.
- **Live AION column** — Online (connection state), Mode, Plasticity, Memory,
  Experience, Uptime — all from `state.snapshot`; `—` until real values
  arrive.
- **You Can column** — Teach a Lesson / Ask a Question / Set a Goal /
  Explore a World / Watch & Learn — 1:1 with the permitted-action API; the
  action trio routes through the runtime's authority layer and surfaces
  verdicts verbatim.
- **Learning in Real Time** — plots real `|Δu_fast|` activity from
  `connection.updated`; exam-derived curves (Recognition / Prediction /
  Combination / Self-Correction) arrive when the bridge defines exam events.
- **Explore Worlds** — training-world lens entry (M2 plugs in world
  batteries).
- **Watch the Journey** — feed of real nomen/devhistory/dream/hostmode events.
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
