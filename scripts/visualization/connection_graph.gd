extends Node2D
##
## AION Gym — live plastic-connection graph (functional stub).
##
## Draws nodes and edges from connection.updated events; a state.snapshot with
## a "relationships" document seeds the node set. Nothing is invented: with no
## events the graph draws only an honest "awaiting data" note (display
## integrity law). Edge colour separates the fast/slow layers, width follows
## the reported strength.

const COLOR_FAST := Color(0.4, 0.75, 1.0)
const COLOR_SLOW := Color(1.0, 0.6, 0.35)
const COLOR_NODE := Color(0.85, 0.9, 1.0)
const COLOR_NOTE := Color(0.6, 0.65, 0.7)

const LAYOUT_RADIUS := 260.0
const MAX_EDGE_WIDTH := 6.0

var nodes: Dictionary = {}  # node id -> Vector2 layout position
var edges: Dictionary = {}  # connection_id -> edge record
var events_applied := 0


func _ready() -> void:
	attach(get_node_or_null("/root/EventBus"))


## Explicit bus wiring (used by the autoload layout and by tests).
## Idempotent: safe to call before _ready and again from _ready.
func attach(bus: Node) -> void:
	if bus == null:
		return
	if bus.has_signal("connection_updated") and not bus.connection_updated.is_connected(apply_connection_update):
		bus.connection_updated.connect(apply_connection_update)
	if bus.has_signal("state_snapshot") and not bus.state_snapshot.is_connected(apply_snapshot):
		bus.state_snapshot.connect(apply_snapshot)


## Seed nodes from a state.snapshot payload's "relationships" document.
func apply_snapshot(state_payload: Dictionary) -> void:
	var rels: Variant = state_payload.get("relationships", {})
	if rels is Dictionary:
		for rid in rels.keys():
			_ensure_node(str(rid))
	queue_redraw()


## Apply one connection.updated payload (schema-validated upstream).
func apply_connection_update(payload: Dictionary) -> void:
	events_applied += 1
	var cid := str(payload.get("connection_id", ""))
	if cid == "":
		return
	var from_node := str(payload.get("from_node", ""))
	var to_node := str(payload.get("to_node", ""))
	if from_node == "" or to_node == "":
		return  # cannot place an edge without endpoints; StateCache still journaled it
	_ensure_node(from_node)
	_ensure_node(to_node)
	edges[cid] = {
		"from": from_node,
		"to": to_node,
		"u": _num(payload.get("u_fast_after", payload.get("u_fast_before", 0.0))),
		"theta": _num(payload.get("theta_after", payload.get("theta_before", 0.0))),
		"delta_u_fast": _num(payload.get("delta_u_fast", 0.0)),
		"delta_theta": _num(payload.get("delta_theta", 0.0)),
	}
	queue_redraw()


func node_count() -> int:
	return nodes.size()


func edge_count() -> int:
	return edges.size()


func reset() -> void:
	nodes.clear()
	edges.clear()
	events_applied = 0
	queue_redraw()


func _draw() -> void:
	if nodes.is_empty() and edges.is_empty():
		var font := ThemeDB.fallback_font
		if font != null:
			draw_string(
				font, Vector2(-190, 0),
				"mind viewer: awaiting connection.updated events from the bridge",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_NOTE)
		return
	for cid in edges.keys():
		var edge: Dictionary = edges[cid]
		if not nodes.has(edge["from"]) or not nodes.has(edge["to"]):
			continue
		var a: Vector2 = nodes[edge["from"]]
		var b: Vector2 = nodes[edge["to"]]
		var strength: float = maxf(absf(_num(edge.get("u", 0.0))), absf(_num(edge.get("theta", 0.0))))
		var width: float = clampf(strength * MAX_EDGE_WIDTH, 0.5, MAX_EDGE_WIDTH)
		var col := COLOR_FAST if _num(edge.get("u", 0.0)) >= _num(edge.get("theta", 0.0)) else COLOR_SLOW
		draw_line(a, b, col, width, true)
	for nid in nodes.keys():
		draw_circle(nodes[nid], 6.0, COLOR_NODE)


func _ensure_node(id: String) -> void:
	if nodes.has(id):
		return
	var k := id.hash() % 6283
	var ang := (float(k) / 6283.0) * TAU
	nodes[id] = Vector2(cos(ang), sin(ang)) * LAYOUT_RADIUS


func _num(value: Variant) -> float:
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	return 0.0
