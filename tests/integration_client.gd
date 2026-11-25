extends SceneTree
##
## GYM-C integration driver: the REAL Godot client stack (ConnectionManager +
## ws/http clients + EventBus + StateCache + the gym dashboard) driven against
## the live Python bridge. No mocks: the ws connects, events arrive over the
## wire, actions go out through the client's own request API.
##
## Run:
##   godot --headless --path . --script res://tests/integration_client.gd -- --token=<bridge token>
##
## Prints one machine-readable line:
##   AION_INTEGRATION_RESULT {json}
## Exit 0 when the full choreography completed; 1 on any hard failure.

const EventBusScript = preload("res://scripts/core/event_bus.gd")
const StateCacheScript = preload("res://scripts/core/state_cache.gd")
const ConnectionManagerScript = preload("res://scripts/core/connection_manager.gd")
const GymScript = preload("res://scripts/gym.gd")
const ConnectionGraphScript = preload("res://scripts/visualization/connection_graph.gd")
const LearningCurvesScript = preload("res://scripts/visualization/learning_curves.gd")

const GYM_ASK_Q := "who operates Tav?"
const GYM_LESSON: String = "Kav operates Tav. Tav routes to relay Kimo. Kimo controls device Zor. Zor produces heat."

var bus: Node
var cache: Node
var mgr: Node
var gym: Node
var graph: Node
var curves: Node

var received: Array = []       # every parsed schema event, in arrival order
var control: Array = []        # every action.result / action.error message
var snap_box := [{}]           # newest state.snapshot payload (reference-shared)
var _token := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--token="):
			_token = a.substr(len("--token="))
	_build()
	_run()


func _build() -> void:
	# Autoload singletons DO load in --script mode and own the canonical node
	# names. The gym resolves /root/EventBus + /root/ConnectionManager itself,
	# so the driver binds to THE SAME instances the dashboard uses — creating
	# duplicates here wires the graph/curves/lambda to a bus nothing publishes
	# to (the exact integration bug the first gate run exposed).
	gym = GymScript.new()
	gym.name = "Gym"
	root.add_child(gym)
	bus = gym._bus if gym._bus != null else EventBusScript.new()
	mgr = gym._manager if gym._manager != null else ConnectionManagerScript.new()
	cache = root.get_node_or_null(NodePath("StateCache"))
	if cache == null:
		cache = StateCacheScript.new()
		cache.name = "StateCache"
		root.add_child(cache)
	cache.attach(bus)
	graph = ConnectionGraphScript.new()
	graph.name = "GateGraph"
	root.add_child(graph)
	graph.attach(bus)
	curves = LearningCurvesScript.new()
	curves.name = "GateCurves"
	root.add_child(curves)
	curves.attach(bus)
	mgr.event_received.connect(func(ev: Dictionary) -> void:
		received.append(ev))
	bus.state_snapshot.connect(func(payload: Dictionary) -> void:
		snap_box[0] = payload)


func _run() -> void:
	var report: Dictionary = {"steps": [], "actions": [], "ws_actions": []}
	var ok := true
	mgr.set_token(_token)
	var err: int = mgr.connect_to_runtime()
	print("[driver] connect_to_runtime err=%d url=%s" % [err, mgr.ws_url()])
	report["ws_url"] = mgr.ws_url()
	var connected: bool = await _wait_state(ConnectionManagerScript.ConnState.CONNECTED, 15.0)
	report["connect_ok"] = connected
	ok = ok and connected
	if connected:
		mgr.ws_client.action_result.connect(func(m: Dictionary) -> void:
			control.append(m))
		var got_snapshot: bool = await _wait_type("state.snapshot", 10.0)
		await _wait_live_values_filled(5.0)
		report["snapshot_ok"] = got_snapshot
		ok = ok and got_snapshot
		report["pre_dashboard"] = _dashboard_values()

		# -- the 5-step teaching arc -------------------------------------- #
		var teach: Dictionary = await _send_action("teach", {"text": GYM_LESSON})
		report["actions"].append(_action_row("teach", teach))
		var exp_seen: bool = await _wait_type("experience.created", 15.0)
		var conn_seen: bool = await _wait_type("connection.updated", 15.0)
		var conn_n := _type_count("connection.updated")
		print("[driver] teach ok=%s | experience.created=%s | connection.updated x%d" %
			[_ok(teach), exp_seen, conn_n])
		ok = ok and _ok(teach) and exp_seen and conn_seen

		var ask: Dictionary = await _send_action("ask", {"question": GYM_ASK_Q})
		report["actions"].append(_action_row("ask", ask))
		var ask_res: Dictionary = _result_of(ask)
		print("[driver] ask verdict=%s student=%s" % [str(ask_res.get("verdict")),
			str(ask_res.get("student_answer"))])
		ok = ok and _ok(ask) and str(ask_res.get("verdict")) == "confirmed"

		# -- pause -> denied teach -> resume ------------------------------- #
		var pause: Dictionary = await _send_action("pause", {})
		report["actions"].append(_action_row("pause", pause))
		var denied: Dictionary = await _send_action("teach", {"text": "a sneaky lesson while paused"})
		report["actions"].append(_action_row("teach_while_paused (expected denial)", denied))
		var denial_ok: bool = not _ok(denied) \
			and str(_result_of(denied).get("reason")) == "paused" \
			and bool(_result_of(denied).get("state_unchanged", false))
		print("[driver] paused-teach denial: ok=%s reason=%s state_unchanged=%s" %
			[_ok(denied), str(_result_of(denied).get("reason")),
			str(_result_of(denied).get("state_unchanged"))])
		ok = ok and _ok(pause) and denial_ok
		var resume: Dictionary = await _send_action("resume", {})
		report["actions"].append(_action_row("resume", resume))
		ok = ok and _ok(resume)

		# -- ws action path (authorized + unauthorized) -------------------- #
		var ws_ok: Dictionary = await _ws_action("set_goal",
			{"goal": "answer reach questions"}, "ws-gate-1", _token)
		report["ws_actions"].append(_action_row("ws set_goal (authorized)", ws_ok))
		var ws_bad: Dictionary = await _ws_action("set_goal",
			{"goal": "evil overwrite"}, "ws-gate-2", "WRONG-TOKEN")
		report["ws_actions"].append(_action_row("ws set_goal (bad token)", ws_bad))
		var ws_ok_pass: bool = _ok(ws_ok)
		var ws_bad_pass: bool = not _ok(ws_bad) \
			and str(_result_of(ws_bad).get("reason")) == "unauthenticated" \
			and bool(_result_of(ws_bad).get("state_unchanged", false))
		print("[driver] ws authorized=%s | ws bad-token denial=%s" %
			[ws_ok_pass, str(_result_of(ws_bad).get("reason"))])
		ok = ok and ws_ok_pass and ws_bad_pass

		# -- hostmode: real gate + gym-level refusal ------------------------ #
		var approve: Dictionary = await _send_action("approve_request",
			{"op": "WRITE_FILE", "args": {"path": "gate.txt", "content": "hello"},
			"arm": "godot"})
		report["actions"].append(_action_row("approve_request WRITE_FILE", approve))
		var gate_executed: bool = _ok(approve) \
			and str(_result_of(approve).get("outcome_status")) == "executed"
		var deny_req: Dictionary = await _send_action("deny_request",
			{"request_id": "req-gate-9", "op": "RUN_SCRIPT", "reason": "host veto"})
		report["actions"].append(_action_row("deny_request RUN_SCRIPT", deny_req))
		print("[driver] gate executed=%s | deny_by_gym ok=%s" % [gate_executed, _ok(deny_req)])
		ok = ok and gate_executed and _ok(deny_req)

		# -- wait for the runtime-lane events (dream/nomen/stage/cons/nav) -- #
		var all_seen: bool = await _wait_all_types(30.0)
		report["all_11_types"] = all_seen
		ok = ok and all_seen

		# -- final authoritative refresh, then read the dashboard ---------- #
		mgr.request_snapshot()
		await _sleep(1.0)
		report["dashboard"] = _dashboard_values()
		report["final_snapshot"] = snap_box[0]
		report["conn_state"] = mgr.get_state()
		report["gym_conn_text"] = gym._conn_text
		report["journey"] = gym._journey_label.text if gym._journey_label != null else ""
		report["graph_edges"] = graph.edge_count()
		report["graph_nodes"] = graph.node_count()
		var edge_rows: Array = []
		for cid in graph.edges.keys():
			var e: Dictionary = graph.edges[cid]
			edge_rows.append({"connection_id": str(cid), "from": str(e.get("from")),
				"to": str(e.get("to")), "u": e.get("u")})
		report["edge_rows"] = edge_rows
		report["curve_points"] = curves.point_count()
		report["journal_count"] = cache.event_count()
		report["stage_highlight"] = _stage_highlight()
		report["footer"] = gym._footer_status.text if gym._footer_status != null else ""

	report["types"] = _type_counts()
	report["order"] = _type_order()
	_finish(report, 0 if ok else 1)


# ------------------------------------------------------------------ helpers

func _ok(res: Dictionary) -> bool:
	if res.is_empty():
		return false
	var accepted := bool(res.get("ok", false))
	var data: Dictionary = res.get("data", {})
	if data.has("ok"):
		accepted = accepted and bool(data.get("ok", false))
	return accepted


func _result_of(res: Dictionary) -> Dictionary:
	var data: Dictionary = res.get("data", {})
	return data.get("result", {}) if data.has("result") else data


func _action_row(label: String, res: Dictionary) -> Dictionary:
	var data: Dictionary = res.get("data", {})
	# HTTP replies carry the verdict inside data; ws control replies carry it
	# at the top level — read whichever is populated.
	var src: Dictionary = data if not data.is_empty() else res
	return {"step": label, "transport_ok": bool(res.get("ok", false)),
		"ok": _ok(res), "reason": str(src.get("reason", "")),
		"status": str(src.get("status", "")),
		"state_unchanged": bool(src.get("state_unchanged", false))}


func _wait_state(state: int, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if mgr.get_state() == state:
			return true
		await process_frame
	return false


func _wait_type(t: String, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _type_count(t) > 0:
			return true
		await process_frame
	return false


func _wait_all_types(timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _type_counts().size() >= 11:
			return true
		await process_frame
	return false


func _wait_live_values_filled(timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if str(_live_value("mode")) != "—":
			return true
		await process_frame
	return false


func _sleep(seconds: float) -> void:
	await create_timer(seconds).timeout


func _send_action(action: String, body: Dictionary) -> Dictionary:
	var done := [false, {}]
	mgr.send_action(action, body, func(r: Dictionary) -> void:
		done[0] = true
		done[1] = r
	)
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline and not bool(done[0]):
		await process_frame
	return done[1]


func _ws_action(action: String, args: Dictionary, rid: String, tok: String) -> Dictionary:
	mgr.ws_client.send_action_request(action, args, rid, tok)
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		for m in control:
			if str(m.get("request_id", "")) == rid:
				return m
		await process_frame
	return {}


func _type_count(t: String) -> int:
	var n := 0
	for ev in received:
		if str(ev.get("type", "")) == t:
			n += 1
	return n


func _type_counts() -> Dictionary:
	var counts := {}
	for ev in received:
		var t := str(ev.get("type", ""))
		counts[t] = int(counts.get(t, 0)) + 1
	return counts


func _type_order() -> Array:
	var order: Array = []
	for ev in received:
		order.append(str(ev.get("type", "")))
	return order


func _live_value(key: String) -> String:
	var v: Variant = gym._live_values.get(key, null)
	if v is Label:
		return (v as Label).text
	return ""


func _dashboard_values() -> Dictionary:
	return {
		"online": _live_value("online"),
		"mode": _live_value("mode"),
		"plasticity": _live_value("plasticity"),
		"memory": _live_value("memory"),
		"experience": _live_value("experience"),
		"uptime": _live_value("uptime"),
	}


func _stage_highlight() -> int:
	for i in gym._stage_panels.size():
		var panel: PanelContainer = gym._stage_panels[i]
		if panel.self_modulate.r > 1.2:
			return i
	return -1


func _finish(report: Dictionary, code: int) -> void:
	report["received_total"] = received.size()
	print("---")
	print("AION_INTEGRATION_RESULT " + JSON.stringify(report))
	quit(code)
