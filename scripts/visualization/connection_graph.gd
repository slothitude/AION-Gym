extends Node2D
##
## AION Gym — live plastic-connection graph (functional stub).
##
## Draws nodes and edges from connection.updated events; a state.snapshot with
## a "relationships" document seeds the node set. Nothing is invented: with no
## events the graph draws only an honest "awaiting data" note (display
## integrity law).
##
## Honesty rules binding this visual (owner canon, docs/ARCHITECTURE.md §8):
## - POSITION IS A LAYOUT: this graph uses a FIXED deterministic hash-circle
##   layout and says so on screen — distance is not a similarity measure.
## - NO idle animation: the graph redraws only from real event deltas.
## - COLOUR = PROVENANCE when the event carries it (PLASTIC / CONSOLIDATED /
##   RETRIEVED per the owner's mapping); unrecognized provenance renders grey.
##   Without a provenance field it falls back to the fast/slow layer colours
##   and the on-screen legend says which is in effect.
## The 3D organism view (Node3D/MultiMesh, size=strength, look_at=strongest
## connection, tween-on-delta) follows the same canon when built.

const COLOR_FAST := Color(0.4, 0.75, 1.0)
const COLOR_SLOW := Color(1.0, 0.6, 0.35)
const COLOR_NODE := Color(0.85, 0.9, 1.0)
const COLOR_NOTE := Color(0.6, 0.65, 0.7)

## Provenance colours (owner mapping: colour = provenance).
const COLOR_PLASTIC := Color(0.4, 0.75, 1.0)
const COLOR_CONSOLIDATED := Color(0.45, 0.9, 0.55)
const COLOR_RETRIEVED := Color(0.7, 0.55, 1.0)
const COLOR_UNKNOWN_PROVENANCE := Color(0.6, 0.6, 0.6)

const LAYOUT_NOTE := "layout: fixed circular (deterministic hash order) — position is not a similarity measure"

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
		"provenance": str(payload.get("provenance", "")),
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
	var font := ThemeDB.fallback_font
	if nodes.is_empty() and edges.is_empty():
		if font != null:
			draw_string(
				font, Vector2(-190, 0),
				"mind viewer: awaiting connection.updated events from the bridge",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_NOTE)
			draw_string(
				font, Vector2(-190, 20),
				LAYOUT_NOTE,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_NOTE)
		return
	# which colour law is in effect, labelled on screen (honesty rule 1 + canon)
	var provenance_coloured := false
	for cid in edges.keys():
		if str(edges[cid].get("provenance", "")) != "":
			provenance_coloured = true
			break
	for cid in edges.keys():
		var edge: Dictionary = edges[cid]
		if not nodes.has(edge["from"]) or not nodes.has(edge["to"]):
			continue
		var a: Vector2 = nodes[edge["from"]]
		var b: Vector2 = nodes[edge["to"]]
		var strength: float = maxf(absf(_num(edge.get("u", 0.0))), absf(_num(edge.get("theta", 0.0))))
		var width: float = clampf(strength * MAX_EDGE_WIDTH, 0.5, MAX_EDGE_WIDTH)
		var col := _edge_colour(edge, provenance_coloured)
		draw_line(a, b, col, width, true)
	for nid in nodes.keys():
		draw_circle(nodes[nid], 6.0, COLOR_NODE)
	if font != null:
		draw_string(
			font, Vector2(-LAYOUT_RADIUS, LAYOUT_RADIUS + 26),
			LAYOUT_NOTE + "  ·  colour: " + ("provenance" if provenance_coloured else "fast/slow layer"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_NOTE)


## Canon: colour = provenance (PLASTIC / CONSOLIDATED / RETRIEVED); an
## unrecognized provenance value renders grey rather than borrowing a real
## category's colour. Without provenance fields, edges fall back to the
## fast/slow layer colours — and the on-screen label says which is in effect.
func _edge_colour(edge: Dictionary, provenance_coloured: bool) -> Color:
	var provenance := str(edge.get("provenance", ""))
	if provenance != "":
		match provenance:
			"PLASTIC":
				return COLOR_PLASTIC
			"CONSOLIDATED":
				return COLOR_CONSOLIDATED
			"RETRIEVED":
				return COLOR_RETRIEVED
			_:
				return COLOR_UNKNOWN_PROVENANCE
	return (COLOR_FAST if _num(edge.get("u", 0.0)) >= _num(edge.get("theta", 0.0)) else COLOR_SLOW) \
			if not provenance_coloured else COLOR_UNKNOWN_PROVENANCE


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
