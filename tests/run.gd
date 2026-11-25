extends SceneTree
##
## AION Gym — headless test runner (plain GDScript, no framework needed).
##
## Run from the repo root:
##   godot --headless --path . --script res://tests/run.gd
##
## Exit code 0 = all green, 1 = failures.
## Covers: schema parse (all 11 types + envelope errors + raw passthrough),
## bus routing, state cache, ws frame parsing, http URL/action guards,
## connection-manager reconnect logic (offline mock), and the two
## visualization stores.

const Schema = preload("res://scripts/aion_client/schema.gd")
const EventBusScript = preload("res://scripts/core/event_bus.gd")
const StateCacheScript = preload("res://scripts/core/state_cache.gd")
const WsClientScript = preload("res://scripts/aion_client/ws_client.gd")
const HttpClientScript = preload("res://scripts/aion_client/http_client.gd")
const ConnectionManagerScript = preload("res://scripts/core/connection_manager.gd")
const ConnectionGraphScript = preload("res://scripts/visualization/connection_graph.gd")
const LearningCurvesScript = preload("res://scripts/visualization/learning_curves.gd")
const AppShellScript = preload("res://scripts/core/app_shell.gd")
const GymTabsScript = preload("res://scripts/core/gym_tabs.gd")
const GymScript = preload("res://scripts/gym.gd")

var _passes: int = 0
var _failures: Array = []


func _initialize() -> void:
	print("AION Gym — headless tests")
	_run_schema_tests()
	_run_bus_tests()
	_run_cache_tests()
	_run_ws_tests()
	_run_http_tests()
	_run_connection_manager_tests()
	_run_visualization_tests()
	_run_shell_tests()
	print("---")
	print("passed: %d   failed: %d" % [_passes, _failures.size()])
	for f in _failures:
		printerr("FAILED: " + str(f))
	quit(1 if _failures.size() > 0 else 0)


# ------------------------------------------------------------------ helpers

func check(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  PASS  " + label)
	else:
		_failures.append(label)
		printerr("  FAIL  " + label)


func _envelope(etype: String, payload: Dictionary) -> Dictionary:
	return {"schema_version": 1, "type": etype, "timestamp": 42.5, "payload": payload}


## A schema-shaped parsed event (the shape bus.publish expects).
func _event(etype: String, payload: Dictionary) -> Dictionary:
	var result: Dictionary = Schema.parse_object(_envelope(etype, payload))
	if not bool(result.get("ok", false)):
		return {}
	return result.get("event", {})


func _expect_error(input: Variant, label: String) -> void:
	var result: Dictionary
	if typeof(input) == TYPE_STRING:
		result = Schema.parse(str(input))
	else:
		result = Schema.parse_object(input)
	if not bool(result.get("ok", false)) and str(result.get("error", "")) != "":
		check(true, label + " (explicit error)")
	else:
		check(false, label + " (explicit error)")


func _sample_payloads() -> Dictionary:
	return {
		Schema.TYPE_STATE_SNAPSHOT: {
			"relationships": {"kav": {"red": 0.3}},
			"u_fast": {"kav": 0.5}, "theta": {"kav": 0.2},
			"gates": {"kav": "open"}, "memory_inventory": {"facts": 4},
			"devhistory_stage": "nascent", "mode": "interactive",
			"uptime_s": 42, "experience_steps": 7,
		},
		Schema.TYPE_EXPERIENCE_CREATED: {
			"episode_id": "ep-001", "provenance": "PLASTIC", "fact": "kav means red",
		},
		Schema.TYPE_CONNECTION_UPDATED: {
			"connection_id": "c-001", "from_node": "kav", "to_node": "red",
			"delta_u_fast": 0.05, "u_fast_before": 0.1, "u_fast_after": 0.15,
		},
		Schema.TYPE_MEMORY_CONSOLIDATED: {
			"moved": ["ep-001"], "preservation_verified": true,
		},
		Schema.TYPE_DREAM_STARTED: {"cycle_id": "d-001", "seeds": ["ep-001"]},
		Schema.TYPE_DREAM_HYPOTHESIS: {
			"hypothesis_id": "h-001", "cycle_id": "d-001",
			"relationship": "kav~red", "confidence": 0.7,
		},
		Schema.TYPE_DREAM_EVALUATED: {
			"hypothesis_id": "h-001", "accepted": false,
			"measured_improvement": -0.01, "reason": "no improvement measured",
		},
		Schema.TYPE_NOMEN_CHANGED: {
			"entity_id": "e-1", "old_name": "unnamed", "new_name": "kav",
			"lineage": ["seed"],
		},
		Schema.TYPE_NAV_ACTION: {
			"decision_id": "nd-001", "goal": "reach-object",
			"options": ["approach", "wait"], "choice": "approach", "outcome": "ok",
		},
		Schema.TYPE_HOSTMODE_REQUEST: {
			"request_id": "hm-001", "verdict": "denied",
			"proposal": "open-socket", "reason": "outside permitted window",
		},
		Schema.TYPE_DEVELOPMENT_STAGE: {
			"stage": "listening", "previous_stage": "nascent",
			"evidence": ["3 episodes"], "stage_index": 1,
		},
	}


# ------------------------------------------------------------------ suites

func _run_schema_tests() -> void:
	print("[schema]")
	check(Schema.ALL_TYPES.size() == 11, "contract defines exactly 11 event types")
	check(Schema.PAYLOAD_FIELDS.size() == 11, "payload contract covers all 11 types")
	var unique := {}
	for t in Schema.ALL_TYPES:
		unique[str(t)] = true
	check(unique.size() == 11, "event types are unique")

	var samples := _sample_payloads()
	for t in Schema.ALL_TYPES:
		var etype := str(t)
		var result: Dictionary = Schema.parse_object(_envelope(etype, samples[etype]))
		var label := "parses %s" % etype
		if not bool(result.get("ok", false)):
			label += " — got: " + str(result.get("error", "?"))
		check(bool(result.get("ok", false)), label)
		if bool(result.get("ok", false)):
			var ev: Dictionary = result["event"]
			check(bool(ev.get("known_type", false)) and not bool(ev.get("is_raw", true)),
				"%s is known, not raw" % etype)
			check(str(ev.get("type", "")) == etype, "%s type round-trips" % etype)
			check(absf(float(ev.get("timestamp", 0.0)) - 42.5) < 0.0001,
				"%s timestamp normalized to float" % etype)
			check(int(ev.get("schema_version", 0)) == 1, "%s schema_version normalized" % etype)

	var text_result: Dictionary = Schema.parse(
		JSON.stringify(_envelope(Schema.TYPE_NOMEN_CHANGED, samples[Schema.TYPE_NOMEN_CHANGED])))
	check(bool(text_result.get("ok", false)), "parse() accepts JSON text")

	var raw: Dictionary = Schema.parse_object({
		"schema_version": 1, "type": "vendor.custom", "timestamp": 7, "payload": {"x": 1},
	})
	check(bool(raw.get("ok", false)), "unknown type parses OK")
	if bool(raw.get("ok", false)):
		var raw_event: Dictionary = raw["event"]
		check(bool(raw_event.get("is_raw", false)), "unknown type flagged is_raw")
		check(not bool(raw_event.get("known_type", true)), "unknown type not marked known")
		var raw_payload: Dictionary = raw_event.get("payload", {})
		check(int(raw_payload.get("x", 0)) == 1, "raw payload preserved verbatim")

	var future: Dictionary = Schema.parse_object({
		"schema_version": 99, "type": Schema.TYPE_NAV_ACTION,
		"timestamp": 1, "payload": {"decision_id": "d"},
	})
	check(bool(future.get("ok", false)) and bool(future["event"].get("future_version", false)),
		"future schema_version accepted and annotated")

	var extra: Dictionary = Schema.parse_object({
		"schema_version": 1, "type": Schema.TYPE_DREAM_STARTED,
		"timestamp": 1, "payload": {"cycle_id": "c"}, "emitter": "bridge-test",
	})
	check(bool(extra.get("ok", false)), "extra envelope keys tolerated (additive-only)")

	_expect_error("not json at all", "invalid JSON rejected")
	_expect_error("[1, 2, 3]", "non-object envelope rejected")
	_expect_error({"type": "state.snapshot", "timestamp": 1, "payload": {}}, "missing schema_version rejected")
	_expect_error({"schema_version": "1", "type": "state.snapshot", "timestamp": 1, "payload": {}}, "non-numeric schema_version rejected")
	_expect_error({"schema_version": 1, "timestamp": 1, "payload": {}}, "missing type rejected")
	_expect_error({"schema_version": 1, "type": 5, "timestamp": 1, "payload": {}}, "non-string type rejected")
	_expect_error({"schema_version": 1, "type": "state.snapshot", "payload": {}}, "missing timestamp rejected")
	_expect_error({"schema_version": 1, "type": "state.snapshot", "timestamp": "x", "payload": {}}, "non-numeric timestamp rejected")
	_expect_error({"schema_version": 1, "type": "state.snapshot", "timestamp": 1}, "missing payload rejected")
	_expect_error({"schema_version": 1, "type": "state.snapshot", "timestamp": 1, "payload": [1]}, "non-object payload rejected")

	var lenient: Dictionary = Schema.parse_object(
		_envelope(Schema.TYPE_CONNECTION_UPDATED, {"delta_u_fast": 0.1}))
	check(bool(lenient.get("ok", false)), "missing required payload field is non-fatal by default")
	if bool(lenient.get("ok", false)):
		var payload_errors: Array = lenient["event"].get("payload_errors", [])
		check(payload_errors.size() == 1, "missing required field reported in payload_errors")

	var strict: Dictionary = Schema.parse_object(
		_envelope(Schema.TYPE_CONNECTION_UPDATED, {"delta_u_fast": 0.1}), true)
	check(not bool(strict.get("ok", false)), "strict mode makes missing required field fatal")

	var extra_field: Dictionary = Schema.parse_object(
		_envelope(Schema.TYPE_NAV_ACTION, {"decision_id": "d", "custom_bonus": true}), true)
	check(bool(extra_field.get("ok", false)), "unknown payload fields never rejected (additive-only)")

	var prov: Dictionary = Schema.parse_object(_envelope(Schema.TYPE_CONNECTION_UPDATED,
		{"connection_id": "c-9", "provenance": "CONSOLIDATED"}))
	check(bool(prov.get("ok", false)), "connection.updated carries provenance (canon colour field)")


func _run_bus_tests() -> void:
	print("[event bus]")
	var bus := EventBusScript.new()
	var seen: Array = []
	var raws: Array = []
	var parse_errors: Array = []
	var hits: Dictionary = {}
	bus.event_received.connect(func(ev): seen.append(ev))
	bus.raw_event.connect(func(ev): raws.append(ev))
	bus.parse_error.connect(func(msg, text): parse_errors.append(msg))
	for t in Schema.ALL_TYPES:
		var sig := str(t).replace(".", "_")
		var target := str(t)
		bus.connect(sig, func(payload): hits[target] = int(hits.get(target, 0)) + 1)

	var samples := _sample_payloads()
	for t in Schema.ALL_TYPES:
		bus.publish(_event(str(t), samples[str(t)]))
	check(seen.size() == 11, "every event reaches event_received")
	check(raws.is_empty(), "known types are not routed to raw_event")
	check(hits.size() == 11, "routing reaches all 11 per-type signals")
	for t in Schema.ALL_TYPES:
		check(int(hits.get(str(t), 0)) == 1, "signal %s fired exactly once" % str(t).replace(".", "_"))

	bus.publish(_event("vendor.custom", {"x": 1}))
	check(raws.size() == 1, "unknown type surfaces on raw_event (never dropped)")
	check(hits.size() == 11, "unknown type does not touch per-type signals")

	var bad := bus.publish_parsed({"ok": false, "error": "bad envelope"})
	check(not bad, "publish_parsed returns false on a failed parse result")
	check(parse_errors.size() == 1, "failed parse surfaces on parse_error")
	var good := bus.publish_parsed({"ok": true, "event": _event(Schema.TYPE_NAV_ACTION, {"decision_id": "n1"})})
	check(good, "publish_parsed accepts a good parse result")
	# nav.action already fired once in the loop above; this is its second hit
	check(int(hits.get(Schema.TYPE_NAV_ACTION, 0)) == 2, "publish_parsed routes to the per-type signal")
	bus.free()


func _run_cache_tests() -> void:
	print("[state cache]")
	var bus := EventBusScript.new()
	var cache := StateCacheScript.new()
	cache.attach(bus)
	bus.publish(_event(Schema.TYPE_STATE_SNAPSHOT, {
		"relationships": {"kav": {"red": 0.3}}, "mode": "interactive",
		"memory_inventory": {"facts": 12},
	}))
	check(not cache.get_state().is_empty(), "state.snapshot payload cached")
	check(str(cache.get_state_value("mode", "—")) == "interactive", "state value readable")
	check(str(cache.get_state_value("uptime_s", "MISSING")) == "MISSING", "absent state value falls back")
	check(not cache.get_latest(Schema.TYPE_STATE_SNAPSHOT).is_empty(), "latest state.snapshot event kept")

	bus.publish(_event(Schema.TYPE_CONNECTION_UPDATED, {"connection_id": "c1"}))
	check(not cache.get_latest(Schema.TYPE_CONNECTION_UPDATED).is_empty(), "latest per-type event kept")
	check(cache.get_latest("never.seen").is_empty(), "unseen type has empty latest")
	check(cache.event_count() == 2, "journal counts every event")

	bus.publish(_event(Schema.TYPE_STATE_SNAPSHOT, {"mode": "dreaming"}))
	check(str(cache.get_state_value("mode", "—")) == "dreaming", "newest snapshot wins")
	check(cache.event_count() == 3, "journal keeps appending in order")

	cache.clear()
	check(cache.event_count() == 0, "clear empties the journal")
	check(cache.get_state().is_empty(), "clear empties the snapshot state")
	bus.free()
	cache.free()


func _run_ws_tests() -> void:
	print("[ws client]")
	var ws := WsClientScript.new()
	var events: Array = []
	var errors: Array = []
	ws.event_received.connect(func(ev): events.append(ev))
	ws.parse_error.connect(func(msg, text): errors.append(msg))

	ws._handle_text(JSON.stringify(
		_envelope(Schema.TYPE_DREAM_STARTED, {"cycle_id": "d-1"})))
	check(events.size() == 1, "valid frame parses into an event")
	if events.size() == 1:
		check(str(events[0].get("type", "")) == Schema.TYPE_DREAM_STARTED, "event keeps its type")

	ws._handle_text("{not json")
	check(errors.size() == 1, "invalid JSON surfaces as parse_error, not a crash")

	ws._handle_text(JSON.stringify(
		_envelope("vendor.custom", {"x": 1})))
	check(events.size() == 2 and bool(events[1].get("is_raw", false)),
		"unknown type passes through as RAW")

	ws.free()


func _run_http_tests() -> void:
	print("[http client]")
	var hc := HttpClientScript.new()
	check(hc.action_url("teach") == "http://127.0.0.1:7480/api/actions/teach",
		"action URL builds on the default base")
	check(hc.snapshot_url() == "http://127.0.0.1:7480/api/snapshot",
		"snapshot URL builds on the default base")
	hc.base_url = "https://gym.example.com"
	check(hc.action_url("ask") == "https://gym.example.com/api/actions/ask",
		"action URL honors base_url override")

	var results: Array = []
	hc.request_completed.connect(func(action, ok, data, err):
		results.append({"action": action, "ok": ok, "error": err}))
	hc.send_action("reboot_everything", {}, Callable())
	check(results.size() == 1, "non-permitted action refused locally (no network)")
	if results.size() == 1:
		check(not bool(results[0]["ok"]), "refused action reports failure")
		check(str(results[0]["action"]) == "reboot_everything", "refusal names the action")
	check(HttpClientScript.ACTIONS.size() == 8, "8 permitted actions defined")
	hc.free()


func _run_connection_manager_tests() -> void:
	print("[connection manager]")
	var mgr := ConnectionManagerScript.new()
	mgr.auto_reconnect = true
	# No add_child here: in --script mode the tree is not active during
	# _initialize, and the manager's retry state machine is observable offline
	# (wait_time is set explicitly; start() is gated on is_inside_tree()).

	check(mgr.ws_url() == "ws://127.0.0.1:7480", "default ws URL")
	mgr.use_tls = true
	mgr.host = "aion.example"
	mgr.port = 9000
	check(mgr.ws_url() == "wss://aion.example:9000", "ws URL honors host/port/tls")

	check(absf(mgr._next_backoff() - 0.5) < 0.0001, "backoff attempt 1 = 0.5s")
	check(absf(mgr._next_backoff() - 1.0) < 0.0001, "backoff attempt 2 = 1.0s")
	check(absf(mgr._next_backoff() - 2.0) < 0.0001, "backoff attempt 3 = 2.0s")
	for i in range(10):
		mgr._next_backoff()
	check(absf(mgr._next_backoff() - 30.0) < 0.0001, "backoff caps at 30s")

	mgr._attempt = 0
	mgr._on_ws_disconnected(1006, "mock drop", true)
	check(mgr.get_state() == ConnectionManagerScript.ConnState.RETRY_WAITING,
		"mock disconnect schedules a retry (RETRY_WAITING)")
	check(mgr._retry_pending, "retry pending flag set")
	check(mgr._retry_timer != null and absf(mgr._retry_timer.wait_time - 0.5) < 0.0001,
		"retry timer waits one backoff step (0.5s)")

	var timers_after_first := _count_timers(mgr)
	mgr._on_ws_disconnected(1006, "mock drop again", true)
	check(_count_timers(mgr) == timers_after_first, "repeat disconnects do not stack retry timers")

	mgr._on_ws_connected()
	check(mgr.get_state() == ConnectionManagerScript.ConnState.CONNECTED, "connect reaches CONNECTED")
	check(not mgr._retry_pending, "retry cleared on successful connect")

	mgr.disconnect_runtime()
	check(mgr.get_state() == ConnectionManagerScript.ConnState.OFFLINE, "manual disconnect goes OFFLINE")
	mgr._on_ws_disconnected(1000, "clean close", false)
	check(mgr.get_state() == ConnectionManagerScript.ConnState.OFFLINE and not mgr._retry_pending,
		"no reconnect after a manual disconnect")

	var mgr2 := ConnectionManagerScript.new()
	mgr2.reconnect_attempts = 2
	mgr2._attempt = 2
	mgr2._state = ConnectionManagerScript.ConnState.CONNECTED
	var states2: Array = []
	mgr2.connection_state_changed.connect(func(s, d): states2.append(s))
	mgr2._on_ws_disconnected(1006, "mock drop", true)
	check(mgr2.get_state() == ConnectionManagerScript.ConnState.OFFLINE and not mgr2._retry_pending,
		"gives up after reconnect_attempts")
	check(states2.has(ConnectionManagerScript.ConnState.OFFLINE), "give-up emits OFFLINE")

	var mgr3 := ConnectionManagerScript.new()
	mgr3.auto_reconnect = false
	mgr3._state = ConnectionManagerScript.ConnState.CONNECTED
	mgr3._on_ws_disconnected(1006, "drop", true)
	check(mgr3.get_state() == ConnectionManagerScript.ConnState.OFFLINE and not mgr3._retry_pending,
		"auto_reconnect=false stays offline after a drop")

	mgr.free()
	mgr2.free()
	mgr3.free()


func _count_timers(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is Timer:
			count += 1
	return count


func _run_visualization_tests() -> void:
	print("[visualization stores]")
	var bus := EventBusScript.new()
	var graph := ConnectionGraphScript.new()
	graph.attach(bus)

	bus.publish(_event(Schema.TYPE_CONNECTION_UPDATED, {
		"connection_id": "c-1", "from_node": "kav", "to_node": "red",
		"delta_u_fast": 0.05, "u_fast_after": 0.25, "theta_after": 0.1,
	}))
	check(graph.edge_count() == 1, "connection.updated creates an edge")
	check(graph.node_count() == 2, "edge endpoints become nodes")

	bus.publish(_event(Schema.TYPE_STATE_SNAPSHOT, {
		"relationships": {"a": {}, "b": {}, "c": {}},
	}))
	check(graph.node_count() == 5, "state.snapshot relationships seed extra nodes")

	var no_endpoints := ConnectionGraphScript.new()
	no_endpoints.attach(bus)
	bus.publish(_event(Schema.TYPE_CONNECTION_UPDATED, {"connection_id": "c-2"}))
	check(no_endpoints.edge_count() == 0, "edge without endpoints is not drawn (event still journaled)")
	no_endpoints.free()

	var curves := LearningCurvesScript.new()
	curves.attach(bus)
	for i in range(3):
		bus.publish(_event(Schema.TYPE_CONNECTION_UPDATED, {
			"connection_id": "c-%d" % i, "from_node": "a", "to_node": "b",
			"delta_u_fast": 0.01 * float(i + 1),
		}))
	check(curves.point_count() == 3, "curves sample real connection.updated deltas")

	bus.publish(_event("vendor.custom", {"x": 1}))
	check(curves.point_count() == 3, "raw events do not touch the curves")

	graph.reset()
	check(graph.edge_count() == 0 and graph.node_count() == 0, "graph reset clears stores")
	bus.free()
	graph.free()
	curves.free()


func _run_shell_tests() -> void:
	print("[app shell]")
	var shell := AppShellScript.new()
	var seen: Array = []
	shell.page_changed.connect(func(page_id): seen.append(page_id))
	var home := Control.new()
	var page_b := Control.new()
	var page_c := Control.new()
	shell.register_page(AppShellScript.HOME_PAGE, home)
	shell.register_page("b", page_b)
	shell.register_page("c", page_c)
	check(shell.current_page_id() == AppShellScript.HOME_PAGE, "home page active after registration")
	check(shell.has_page("b") and not shell.has_page("nope"), "has_page reflects registration")

	check(shell.show_page("b"), "show_page navigates to a registered page")
	check(shell.current_page_id() == "b", "current page updates on navigation")
	check(seen.has("b"), "page_changed emitted with the page id")
	check(not shell.visible_pages_overlap(), "exactly one page is visible")

	check(shell.show_page("nope") == false, "unknown page rejected")
	check(shell.current_page_id() == "b", "unknown page leaves state untouched")

	check(shell.back() and shell.current_page_id() == AppShellScript.HOME_PAGE, "back returns home")
	check(seen.count(AppShellScript.HOME_PAGE) >= 1, "page_changed emits on back")
	check(not shell.back(), "back at home is a no-op")
	shell.free()  # frees the registered pages with it

	print("[navigation data]")
	var tab_ids: Array = []
	for t in GymTabsScript.TABS:
		tab_ids.append(str(t[0]))
	var expected: Array = [AppShellScript.HOME_PAGE]
	for s in GymScript.SURFACE_ORDER:
		expected.append(str(s))
	check(tab_ids == expected, "tab ids match dashboard + surface order")
	check(GymScript.SURFACES.has("mind_viewer"), "mind viewer surface exists (code-built page)")
