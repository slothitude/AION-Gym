extends Node
##
## AION Gym — in-client event bus.
##
## The aion_client parses transport frames against the schema contract and
## publishes typed results here; every surface subscribes to the signals it
## cares about. The bus holds no state of its own (StateCache does that) and
## never invents events.
##
## Routing:
##   event_received(event)   — every accepted event (known or raw)
##   raw_event(event)        — well-formed envelopes with unknown types (never dropped)
##   parse_error(msg, text)  — envelopes that failed the contract
##   <per-type>(payload)     — the 11 known types, payload only

const Schema = preload("res://scripts/aion_client/schema.gd")

signal event_received(event: Dictionary)
signal raw_event(event: Dictionary)
signal parse_error(error_message: String, raw_text: String)

signal state_snapshot(payload: Dictionary)
signal experience_created(payload: Dictionary)
signal connection_updated(payload: Dictionary)
signal memory_consolidated(payload: Dictionary)
signal dream_started(payload: Dictionary)
signal dream_hypothesis(payload: Dictionary)
signal dream_evaluated(payload: Dictionary)
signal nomen_changed(payload: Dictionary)
signal nav_action(payload: Dictionary)
signal hostmode_request(payload: Dictionary)
signal development_stage(payload: Dictionary)

var _type_signals: Dictionary = {}


func _init() -> void:
	_type_signals = {
		Schema.TYPE_STATE_SNAPSHOT: "state_snapshot",
		Schema.TYPE_EXPERIENCE_CREATED: "experience_created",
		Schema.TYPE_CONNECTION_UPDATED: "connection_updated",
		Schema.TYPE_MEMORY_CONSOLIDATED: "memory_consolidated",
		Schema.TYPE_DREAM_STARTED: "dream_started",
		Schema.TYPE_DREAM_HYPOTHESIS: "dream_hypothesis",
		Schema.TYPE_DREAM_EVALUATED: "dream_evaluated",
		Schema.TYPE_NOMEN_CHANGED: "nomen_changed",
		Schema.TYPE_NAV_ACTION: "nav_action",
		Schema.TYPE_HOSTMODE_REQUEST: "hostmode_request",
		Schema.TYPE_DEVELOPMENT_STAGE: "development_stage",
	}


## Convenience: feed a schema.parse()/parse_object() RESULT straight in.
## Returns true when the event was published.
func publish_parsed(result: Dictionary, raw_text: String = "") -> bool:
	if not result.get("ok", false):
		var msg := str(result.get("error", "unknown parse failure"))
		parse_error.emit(msg, raw_text)
		return false
	publish(result.get("event", {}))
	return true


## Publish a parsed schema event (schema result["event"] shape).
func publish(event: Dictionary) -> void:
	if event.is_empty():
		return
	event_received.emit(event)
	var etype := str(event.get("type", ""))
	if bool(event.get("is_raw", false)):
		raw_event.emit(event)
		return
	var sig_name := str(_type_signals.get(etype, ""))
	if sig_name == "":
		return
	# NOTE: in Godot 4.7 emit_signal() returns ERR_UNAVAILABLE when a declared
	# signal has no connections, so the map is guarded by has_signal() —
	# unconnected per-type signals are normal, missing ones are a bug.
	if has_signal(sig_name):
		emit_signal(sig_name, event.get("payload", {}))
	else:
		push_warning("EventBus: no signal '%s' for event type '%s'" % [sig_name, etype])
