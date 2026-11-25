extends Node2D
##
## AION Gym — "Learning in Real Time" plot (functional stub).
##
## Draws the recent |Δu_fast| activity from real connection.updated events.
## Exam-derived curves (Recognition / Prediction / Combination /
## Self-Correction vs steps) arrive when the bridge defines exam events —
## until then this panel shows real connection activity or an honest empty
## note. No decorative numbers (display integrity law).

const MAX_POINTS := 240
const PLOT_SIZE := Vector2(420, 140)
const COLOR_LINE := Color(0.45, 0.8, 1.0)
const COLOR_AXIS := Color(0.35, 0.4, 0.5)
const COLOR_NOTE := Color(0.6, 0.65, 0.7)

var series: Array = []  # newest last


func _ready() -> void:
	attach(get_node_or_null("/root/EventBus"))


## Explicit bus wiring (used by the autoload layout and by tests).
## Idempotent: safe to call before _ready and again from _ready.
func attach(bus: Node) -> void:
	if bus != null and bus.has_signal("connection_updated") \
			and not bus.connection_updated.is_connected(_on_connection_updated):
		bus.connection_updated.connect(_on_connection_updated)


func _on_connection_updated(payload: Dictionary) -> void:
	var d: Variant = payload.get("delta_u_fast", 0.0)
	if typeof(d) != TYPE_FLOAT and typeof(d) != TYPE_INT:
		return
	series.append(absf(float(d)))
	if series.size() > MAX_POINTS:
		series.pop_front()
	queue_redraw()


func point_count() -> int:
	return series.size()


func reset() -> void:
	series.clear()
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if series.size() < 2:
		if font != null:
			draw_string(
				font, Vector2(0, 12),
				"learning curves: awaiting connection.updated events (exam curves arrive with the bridge)",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_NOTE)
		return
	# axes
	draw_line(Vector2(0, PLOT_SIZE.y), Vector2(PLOT_SIZE.x, PLOT_SIZE.y), COLOR_AXIS, 1.0, true)
	var peak := 0.000001
	for v in series:
		peak = maxf(peak, absf(float(v)))
	var step := PLOT_SIZE.x / float(MAX_POINTS - 1)
	var start_x := PLOT_SIZE.x - step * float(series.size() - 1)
	var points := PackedVector2Array()
	var i := 0
	for v in series:
		var x := start_x + step * float(i)
		var y := PLOT_SIZE.y - (absf(float(v)) / peak) * PLOT_SIZE.y
		points.append(Vector2(x, y))
		i += 1
	for p_i in range(1, points.size()):
		draw_line(points[p_i - 1], points[p_i], COLOR_LINE, 1.5, true)
	if font != null:
		draw_string(
			font, Vector2(0, PLOT_SIZE.y + 16),
			"connection activity |Δu_fast| — last %d events" % series.size(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_NOTE)
