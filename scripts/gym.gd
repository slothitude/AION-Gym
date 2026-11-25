extends Node
##
## AION Gym — root controller: the M1 dashboard (concept layout) plus lens
## switching between the five surfaces.
##
## Layout composes both concept arts: assets/aion_gym_life_cycle_concept.png
## (frame: header, Live AION + You Can columns, bottom row, footer) and
## assets/aion_development_stages_concept.png (4-state stage canon with
## gestation periods, What You'll See row, Key Principles card).
##
## Display integrity: every live value comes from real events, connection
## state, or state.snapshot fields — placeholders only where clearly labelled
## as awaiting the bridge. The Gym never invents learning.

const DASH_LENS := "@dashboard"

const SURFACES: Dictionary = {
	"habitat": "res://scenes/habitat.tscn",
	"mind_viewer": "res://scenes/mind_viewer.tscn",
	"training_world": "res://scenes/training_world.tscn",
	"memory_archive": "res://scenes/memory_archive.tscn",
	"control_room": "res://scenes/control_room.tscn",
}
const SURFACE_ORDER: Array = [
	"habitat", "mind_viewer", "training_world", "memory_archive", "control_room",
]

const HEADER_TEXT: String = "AION GYM — Watch • Teach • Interact • Grow — From Parasite to AION, a living AI journey"
const FOOTER_LEFT: String = "AION Gym v1.0 — A Living AI, Growing Mind"
const FOOTER_CENTER: String = "Learn  •  Adapt  •  Evolve"
const FOOTER_RIGHT: String = "AION — Not just intelligence, but a journey."

## The four evolution panels — the owner's 4-STATE CANON (concept art 2,
## assets/aion_development_stages_concept.png), which supersedes the first
## art's five panels. Gestation periods are displayed as part of each panel.
## Highlight state comes only from development.stage events — a stage is
## recorded, never awarded.
const EVOLUTION_PATH: Array = [
	{"title": "1. Parasite", "subtitle": "Attached • Dependent",
		"bullets": "• Feeds on host intelligence\n• Uses borrowed capability\n• No independent memory",
		"gestation": "Gestation Period: 0 – 1 day (attachment phase)"},
	{"title": "2. LLM", "subtitle": "Borrowed Brain",
		"bullets": "• Processes language\n• Builds understanding\n• Learns from experience",
		"gestation": "Gestation Period: 1 – 7 days (learning phase)"},
	{"title": "3. Emerging AION", "subtitle": "Plastic • Adaptive",
		"bullets": "• Forms own connections\n• Remembers and reasons\n• Dreams and experiments",
		"gestation": "Gestation Period: 1 – 30 days (consolidation phase)"},
	{"title": "4. Independent AION", "subtitle": "Self-Directed • Autonomous",
		"bullets": "• Retains and applies knowledge\n• Solves novel problems\n• Grows its own capabilities",
		"gestation": "Gestation Period: 30+ days (mature stage)"},
]

## "AION Gym — What You'll See": the seven dashboard panels (concept art 2),
## mapped to what actually renders them.
const WHAT_YOULL_SEE: Array = [
	{"label": "Evolution Stage", "where": "the four stage panels above"},
	{"label": "Brain Activity", "where": "the learning-curve plot (real deltas)"},
	{"label": "Connection Graph", "where": "mind viewer lens + graph panel"},
	{"label": "Chat & Teach", "where": "control room lens + You Can actions"},
	{"label": "Dreams & Replay", "where": "memory archive lens + event journal"},
	{"label": "Experiments", "where": "training world lens (M2)"},
	{"label": "Progress & Evidence", "where": "journey feed + stage evidence"},
]

## Key Principles card (concept art 2, verbatim) — display-integrity law.
const KEY_PRINCIPLES: Array = [
	"Stage is recorded, never awarded",
	"No evidence, no claim",
	"Display shows the real state",
]
const KEY_PRINCIPLES_TAGLINE: String = "AION's journey is real. The Gym shows the truth."

## "You Can" menu — maps 1:1 to the permitted-action API; world/watch entries
## are lens navigation, the rest route through the runtime's authority layer.
const ACTION_MENU: Array = [
	{"label": "Teach a Lesson", "verb": "action", "action": "teach"},
	{"label": "Ask a Question", "verb": "action", "action": "ask"},
	{"label": "Set a Goal", "verb": "action", "action": "set_goal"},
	{"label": "Explore a World", "verb": "lens", "lens": "training_world"},
	{"label": "Watch & Learn", "verb": "lens", "lens": "habitat"},
]

const LearningCurves = preload("res://scripts/visualization/learning_curves.gd")
const ConnectionManagerScript = preload("res://scripts/core/connection_manager.gd")

var _lens: String = DASH_LENS
var _current_surface: Node = null

var _center_host: Control = null
var _dash_root: Control = null
var _stage_panels: Array = []
var _live_values: Dictionary = {}   # key -> value Label
var _online_label: Label = null
var _journey_label: Label = null
var _journey_lines: Array = []
var _footer_status: Label = null
var _curves: Node = null

var _manager: Node = null
var _bus: Node = null
var _conn_text: String = "offline"
var _last_action_text: String = ""


func _ready() -> void:
	_bus = get_node_or_null("/root/EventBus")
	_manager = get_node_or_null("/root/ConnectionManager")
	_build_ui()
	if _bus != null:
		_bus.state_snapshot.connect(_on_state_snapshot)
		_bus.development_stage.connect(_on_development_stage)
		_bus.event_received.connect(_on_any_event)
	if _manager != null and _manager.has_signal("connection_state_changed"):
		_manager.connection_state_changed.connect(_on_connection_state)
		_set_connection_text(ConnectionManagerScript.ConnState.OFFLINE)
	show_dashboard()


# ---------------------------------------------------------------- lens switching

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				show_lens(SURFACE_ORDER[0])
			KEY_2:
				show_lens(SURFACE_ORDER[1])
			KEY_3:
				show_lens(SURFACE_ORDER[2])
			KEY_4:
				show_lens(SURFACE_ORDER[3])
			KEY_5:
				show_lens(SURFACE_ORDER[4])
			KEY_0, KEY_ESCAPE, KEY_BACKSPACE:
				show_dashboard()


## Swap the centre area to one of the five surfaces (keys 1-5).
func show_lens(surface: String) -> bool:
	if not SURFACES.has(surface):
		push_warning("unknown surface: %s" % surface)
		return false
	if _lens == surface:
		return true
	var packed: PackedScene = load(SURFACES[surface])
	if packed == null:
		push_error("surface scene missing: %s" % SURFACES[surface])
		return false
	_clear_center()
	var node: Node = packed.instantiate()
	if node is Node3D:
		# 3D surfaces live in their own viewport so the dashboard UI composites
		# cleanly on top (house-standard SubViewportContainer pattern).
		var container := SubViewportContainer.new()
		container.stretch = true
		var viewport := SubViewport.new()
		viewport.own_world_3d = true
		container.add_child(viewport)
		viewport.add_child(node)
		_center_host.add_child(container)
		container.set_anchors_preset(Control.PRESET_FULL_RECT)
		_current_surface = container
	else:
		_center_host.add_child(node)
		if node is Control:
			node.set_anchors_preset(Control.PRESET_FULL_RECT)
		_current_surface = node
	_lens = surface
	_update_footer_status()
	return true


## Swap back to the dashboard (concept layout). Keys 0 / Esc / Backspace.
func show_dashboard() -> void:
	_clear_center()
	_center_host.add_child(_dash_root)
	_dash_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lens = DASH_LENS
	_update_footer_status()


func current_lens() -> String:
	return _lens


func _clear_center() -> void:
	for child in _center_host.get_children():
		if child == _dash_root:
			_center_host.remove_child(child)
		else:
			child.queue_free()
	_current_surface = null


# ---------------------------------------------------------------- event handlers

func _on_state_snapshot(payload: Dictionary) -> void:
	_set_live("mode", payload.get("mode"))
	_set_live("plasticity", payload.get("plasticity"))
	_set_live("memory", _scalar_from(payload.get("memory_inventory"), "facts"))
	_set_live("experience", payload.get("experience_steps"))
	_set_live("uptime", payload.get("uptime_s"))


func _on_development_stage(payload: Dictionary) -> void:
	_append_journey("development.stage: %s" % _summary_stage(payload))
	var idx := _stage_index_from(payload)
	if idx >= 0:
		_set_stage_highlight(idx)


func _on_any_event(event: Dictionary) -> void:
	match str(event.get("type", "")):
		"experience.created":
			_append_journey("experience.created: %s" % _summary(event, "episode_id"))
		"connection.updated":
			var p: Dictionary = event.get("payload", {})
			var cid := str(p.get("connection_id", "—"))
			var delta: Variant = p.get("delta_u_fast", null)
			var delta_text := "—" if delta == null else "%.3f" % float(delta)
			_append_journey("connection.updated: %s  Δu_fast %s" % [cid, delta_text])
		"nomen.changed":
			var p: Dictionary = event.get("payload", {})
			_append_journey("nomen.changed: %s → %s" % [
				str(p.get("old_name", "—")), str(p.get("new_name", "—"))])
		"memory.consolidated":
			var p: Dictionary = event.get("payload", {})
			_append_journey("memory.consolidated: preservation verified = %s" % str(p.get("preservation_verified", "—")))
		"dream.started":
			_append_journey("dream.started: %s" % _summary(event, "cycle_id"))
		"dream.hypothesis":
			var p: Dictionary = event.get("payload", {})
			_append_journey("dream.hypothesis: %s — %s" % [
				str(p.get("hypothesis_id", "—")), str(p.get("statement", "—"))])
		"dream.evaluated":
			var p: Dictionary = event.get("payload", {})
			_append_journey("dream.evaluated: %s → %s (%s)" % [
				str(p.get("hypothesis_id", "—")),
				"accepted" if bool(p.get("accepted", false)) else "rejected",
				str(p.get("reason", "—"))])
		"hostmode.request":
			var p: Dictionary = event.get("payload", {})
			_append_journey("hostmode.request: %s — %s" % [
				str(p.get("proposal", "—")), str(p.get("verdict", "—"))])
		"nav.action":
			_append_journey("nav.action: %s → %s" % [
				_summary(event, "goal"), _summary(event, "choice")])
		_:
			pass


func _on_connection_state(new_state: int, _detail: String) -> void:
	_set_connection_text(new_state)
	if new_state == ConnectionManagerScript.ConnState.CONNECTED and _manager != null and _manager.has_method("request_snapshot"):
		# Connected: pull a fresh snapshot so the Live AION column fills from
		# real runtime state (the ws stream also pushes one).
		_manager.request_snapshot()


# ---------------------------------------------------------------- actions

var _pending_action: String = ""


func _send_action(action: String) -> void:
	if _manager == null or not _manager.has_method("send_action"):
		_last_action_text = "%s → unavailable (not connected)" % action
		_update_footer_status()
		return
	_pending_action = action
	_last_action_text = "%s → requesting…" % action
	_update_footer_status()
	_manager.send_action(action, {}, _on_action_result)


func _on_action_result(result: Dictionary) -> void:
	var action := _pending_action if _pending_action != "" else "action"
	_pending_action = ""
	# Transport ok is not acceptance: the bridge answers 200 with the authority
	# verdict inside — ok:false is a DENIAL and must be shown as one.
	var accepted := bool(result.get("ok", false))
	var data: Dictionary = result.get("data", {})
	if data.has("ok"):
		accepted = accepted and bool(data.get("ok", false))
	if accepted:
		_last_action_text = "%s → accepted by runtime" % action
	else:
		var denial := str(data.get("reason", result.get("error", "denied")))
		_last_action_text = "%s → denied: %s" % [action, denial]
	_update_footer_status()
	# refresh the Live AION column from authoritative state after every verdict
	if _manager != null and _manager.has_method("request_snapshot"):
		_manager.request_snapshot()


# ---------------------------------------------------------------- dashboard UI

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "Dashboard"
	add_child(ui)

	var root := Control.new()
	root.name = "Root"
	ui.add_child(root)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.name = "Column"
	root.add_child(column)
	column.set_anchors_preset(Control.PRESET_FULL_RECT)

	column.add_child(_make_header())

	var middle := HBoxContainer.new()
	middle.name = "Middle"
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(middle)

	_center_host = Control.new()
	_center_host.name = "CenterHost"
	_center_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(_center_host)

	_dash_root = _make_dashboard_view()
	_center_host.add_child(_dash_root)

	middle.add_child(_make_right_column())
	column.add_child(_make_bottom_row())
	column.add_child(_make_footer())


func _make_header() -> Label:
	var header := Label.new()
	header.name = "Header"
	header.text = HEADER_TEXT
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return header


func _make_dashboard_view() -> Control:
	var view := VBoxContainer.new()
	view.name = "DashboardView"
	var path_row := HBoxContainer.new()
	path_row.name = "EvolutionPath"
	path_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.add_child(path_row)
	for stage in EVOLUTION_PATH:
		path_row.add_child(_make_stage_panel(stage))
	view.add_child(_make_whats_row())
	return view


## "AION Gym — What You'll See": the seven-panel icon row from concept art 2,
## plus the Key Principles card (display-integrity law, verbatim).
func _make_whats_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "WhatYoullSeeRow"

	var see_panel := PanelContainer.new()
	see_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(see_panel)
	var see_box := VBoxContainer.new()
	see_panel.add_child(see_box)
	var see_title := Label.new()
	see_title.text = "AION Gym — What You'll See"
	see_box.add_child(see_title)
	var see_row := HBoxContainer.new()
	see_box.add_child(see_row)
	for item in WHAT_YOULL_SEE:
		var mini := VBoxContainer.new()
		mini.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		see_row.add_child(mini)
		var mini_label := Label.new()
		mini_label.text = str(item.get("label", ""))
		mini_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mini_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mini.add_child(mini_label)
		var mini_where := Label.new()
		mini_where.name = "Where"
		mini_where.text = str(item.get("where", ""))
		mini_where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mini_where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mini.add_child(mini_where)

	var prin_panel := PanelContainer.new()
	prin_panel.custom_minimum_size = Vector2(360, 0)
	row.add_child(prin_panel)
	var prin_box := VBoxContainer.new()
	prin_panel.add_child(prin_box)
	var prin_title := Label.new()
	prin_title.text = "Key Principles"
	prin_box.add_child(prin_title)
	for line in KEY_PRINCIPLES:
		var p := Label.new()
		p.text = "✓  " + str(line)
		prin_box.add_child(p)
	var tagline := Label.new()
	tagline.text = KEY_PRINCIPLES_TAGLINE
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prin_box.add_child(tagline)
	return row


func _make_stage_panel(stage: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = str(stage.get("title", ""))
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = str(stage.get("subtitle", ""))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(subtitle)
	var bullets := Label.new()
	bullets.text = str(stage.get("bullets", ""))
	box.add_child(bullets)
	var gestation := Label.new()
	gestation.text = str(stage.get("gestation", ""))
	gestation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(gestation)
	_stage_panels.append(panel)
	return panel


func _make_right_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "RightColumn"
	column.custom_minimum_size = Vector2(300, 0)

	var live_panel := PanelContainer.new()
	var live_box := VBoxContainer.new()
	live_panel.add_child(live_box)
	column.add_child(live_panel)

	var live_title := Label.new()
	live_title.text = "Live AION"
	live_box.add_child(live_title)

	_online_label = _make_kv_row(live_box, "online", "Online")
	_make_kv_row(live_box, "mode", "Mode")
	_make_kv_row(live_box, "plasticity", "Plasticity")
	_make_kv_row(live_box, "memory", "Memory")
	_make_kv_row(live_box, "experience", "Experience")
	_make_kv_row(live_box, "uptime", "Uptime")

	var can_panel := PanelContainer.new()
	var can_box := VBoxContainer.new()
	can_panel.add_child(can_box)
	column.add_child(can_panel)

	var can_title := Label.new()
	can_title.text = "You Can"
	can_box.add_child(can_title)
	for item in ACTION_MENU:
		can_box.add_child(_make_action_button(item))
	return column


func _make_kv_row(parent: Control, key: String, label_text: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text + ":"
	label.custom_minimum_size = Vector2(96, 0)
	row.add_child(label)
	var value := Label.new()
	value.text = "—"
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	_live_values[key] = value
	return value


func _make_action_button(item: Dictionary) -> Button:
	var button := Button.new()
	button.text = str(item.get("label", ""))
	button.pressed.connect(func() -> void: _on_menu_pressed(item))
	return button


func _on_menu_pressed(item: Dictionary) -> void:
	match str(item.get("verb", "")):
		"action":
			_send_action(str(item.get("action", "")))
		"lens":
			show_lens(str(item.get("lens", "")))
		_:
			push_warning("unknown menu item verb: %s" % str(item.get("verb", "")))


func _make_bottom_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "BottomRow"

	var curves_panel := PanelContainer.new()
	curves_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(curves_panel)
	var curves_box := VBoxContainer.new()
	curves_panel.add_child(curves_box)
	var curves_title := Label.new()
	curves_title.text = "Learning in Real Time"
	curves_box.add_child(curves_title)
	_curves = LearningCurves.new()
	_curves.position = Vector2(16, 36)
	curves_box.add_child(_curves)

	var worlds_panel := PanelContainer.new()
	worlds_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(worlds_panel)
	var worlds_box := VBoxContainer.new()
	worlds_panel.add_child(worlds_box)
	var worlds_title := Label.new()
	worlds_title.text = "Explore Worlds"
	worlds_box.add_child(worlds_title)
	var worlds_body := Label.new()
	worlds_body.text = "Garden World • Learn • Build • Discover\n(world batteries plug in from aion/worlds — M2)"
	worlds_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	worlds_box.add_child(worlds_body)
	var worlds_button := Button.new()
	worlds_button.text = "Open the training world"
	worlds_button.pressed.connect(func() -> void: show_lens("training_world"))
	worlds_box.add_child(worlds_button)

	var journey_panel := PanelContainer.new()
	journey_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(journey_panel)
	var journey_box := VBoxContainer.new()
	journey_panel.add_child(journey_box)
	var journey_title := Label.new()
	journey_title.text = "Watch the Journey"
	journey_box.add_child(journey_title)
	_journey_label = Label.new()
	_journey_label.text = "journey feed: awaiting events from the bridge"
	_journey_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	journey_box.add_child(_journey_label)
	return row


func _make_footer() -> Control:
	var row := HBoxContainer.new()
	row.name = "Footer"
	var left := Label.new()
	left.text = FOOTER_LEFT
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var center := Label.new()
	center.text = FOOTER_CENTER
	row.add_child(center)
	var connect_button := Button.new()
	connect_button.text = "Connect"
	connect_button.pressed.connect(_on_connect_pressed)
	row.add_child(connect_button)
	_footer_status = Label.new()
	_footer_status.text = ""
	_footer_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_footer_status)
	var right := Label.new()
	right.text = FOOTER_RIGHT
	row.add_child(right)
	_update_footer_status()
	return row


func _on_connect_pressed() -> void:
	if _manager == null or not _manager.has_method("connect_to_runtime"):
		_last_action_text = "connect → unavailable (ConnectionManager missing)"
		_update_footer_status()
		return
	if bool(_manager.is_connected_runtime()):
		_manager.disconnect_runtime()
		_last_action_text = "disconnect → requested"
	else:
		var err: int = _manager.connect_to_runtime()
		_last_action_text = "connect → %s (%s)" % ["started" if err == 0 else "failed", _manager.ws_url()]
	_update_footer_status()


# ---------------------------------------------------------------- formatting

func _set_connection_text(state: int) -> void:
	match state:
		0:
			_conn_text = "offline"
		1:
			_conn_text = "connecting…"
		2:
			_conn_text = "online"
			if _online_label != null:
				_online_label.text = "● Online"
				_online_label.modulate = Color(0.4, 1.0, 0.5)
			return
		3:
			_conn_text = "retrying…"
		_:
			_conn_text = "unknown"
	if _online_label != null:
		_online_label.text = "○ " + _conn_text
		_online_label.modulate = Color(0.7, 0.7, 0.7)


func _set_live(key: String, value: Variant) -> void:
	if not _live_values.has(key):
		return
	var label: Label = _live_values[key]
	label.text = _format_value(value)


func _format_value(value: Variant) -> String:
	if value == null:
		return "—"
	match typeof(value):
		TYPE_STRING:
			var s := str(value)
			return s if s != "" else "—"
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
			return str(value)
		_:
			return "—"  # never summarize a document we cannot honestly render


func _scalar_from(document: Variant, key: String) -> Variant:
	if typeof(document) != TYPE_DICTIONARY:
		return null
	var inner: Variant = document.get(key, null)
	if inner == null:
		return null
	if typeof(inner) == TYPE_DICTIONARY or typeof(inner) == TYPE_ARRAY:
		return null
	return inner


func _summary(event: Dictionary, key: String) -> String:
	var payload: Dictionary = event.get("payload", {})
	var v: Variant = payload.get(key, null)
	if v == null:
		return "—"
	return str(v)


func _summary_stage(payload: Dictionary) -> String:
	var parts: Array = [str(payload.get("stage", "—"))]
	if payload.has("previous_stage"):
		parts.append("(was %s)" % str(payload.get("previous_stage")))
	return " ".join(parts)


func _stage_index_from(payload: Dictionary) -> int:
	var v: Variant = payload.get("stage_index", null)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		var i := int(v)
		if i >= 0 and i < EVOLUTION_PATH.size():
			return i
	var stage_name := str(payload.get("stage", "")).to_lower()
	var keywords: Array = ["parasite", "llm", "emerging", "independent"]
	for k_i in keywords.size():
		if stage_name.findn(str(keywords[k_i])) != -1:
			return k_i
	return -1


func _set_stage_highlight(active_index: int) -> void:
	for i in _stage_panels.size():
		var panel: PanelContainer = _stage_panels[i]
		panel.self_modulate = Color(1.35, 1.35, 1.1) if i == active_index else Color(1, 1, 1)


func _append_journey(line: String) -> void:
	_journey_lines.append("%s  %s" % [Time.get_time_string_from_system(), line])
	if _journey_lines.size() > 24:
		_journey_lines.pop_front()
	if _journey_label != null:
		_journey_label.text = "\n".join(_journey_lines)


func _update_footer_status() -> void:
	if _footer_status == null:
		return
	var lens_text := "dashboard" if _lens == DASH_LENS else _lens
	var parts: Array = ["[0] dashboard · [1-5] lenses · view: " + lens_text]
	if _last_action_text != "":
		parts.append(_last_action_text)
	parts.append(_conn_text)
	_footer_status.text = "  ·  ".join(parts)
