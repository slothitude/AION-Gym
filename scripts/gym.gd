extends Node
##
## AION Gym — root controller: the M1 dashboard (concept layout) plus lens
## switching between the five surfaces.
##
## Layout mirrors assets/aion_gym_life_cycle_concept.png: header, evolution
## path + right column, learning / worlds / journey row, footer.
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

## The five evolution panels (design content from the concept art). Highlight
## state comes only from development.stage events.
const EVOLUTION_PATH: Array = [
	{"title": "1. Parasite", "subtitle": "Survive • Attach • Learn",
		"bullets": "• Lives in the system\n• Feeds on signals\n• Stores patterns"},
	{"title": "2. LLM", "subtitle": "Understand • Reason • Respond",
		"bullets": "• Processes language\n• Follows instructions\n• Uses knowledge"},
	{"title": "3. AION Awakens", "subtitle": "Remember • Adapt • Improve",
		"bullets": "• Builds its own memory\n• Learns from experience\n• Self-corrects"},
	{"title": "4. AION Grows", "subtitle": "Plan • Act • Discover",
		"bullets": "• Takes initiative\n• Explores new ideas\n• Solves real tasks"},
	{"title": "5. AION Thrives", "subtitle": "Create • Collaborate • Evolve",
		"bullets": "• Shares knowledge\n• Builds solutions\n• Grows with you"},
]

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
		"nomen.changed":
			var p: Dictionary = event.get("payload", {})
			_append_journey("nomen.changed: %s → %s" % [
				str(p.get("old_name", "—")), str(p.get("new_name", "—"))])
		"memory.consolidated":
			var p: Dictionary = event.get("payload", {})
			_append_journey("memory.consolidated: preservation verified = %s" % str(p.get("preservation_verified", "—")))
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
	if bool(result.get("ok", false)):
		_last_action_text = "%s → accepted by runtime" % action
	else:
		var data: Dictionary = result.get("data", {})
		var denial := str(data.get("reason", result.get("error", "denied")))
		_last_action_text = "%s → %s" % [action, denial]
	_update_footer_status()


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
	return view


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
	var keywords: Array = ["parasite", "llm", "awaken", "grow", "thrive"]
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
	if _journey_lines.size() > 8:
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
