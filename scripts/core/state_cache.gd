extends Node
##
## AION Gym — latest-known AION state, per event type.
##
## A read-only view of what the runtime has actually reported. Nothing here
## generates or infers state: it stores events it has seen, nothing else.
## The capped journal is the foundation for event history & replay (plan §4.6).

const Schema = preload("res://scripts/aion_client/schema.gd")

const JOURNAL_LIMIT: int = 1000

signal cache_updated(event: Dictionary)

var _latest: Dictionary = {}        # type -> newest event dict
var _journal: Array = []            # ordered events, capped at JOURNAL_LIMIT
var _snapshot_state: Dictionary = {}  # payload of the newest state.snapshot


func _ready() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		attach(bus)


## Explicit wiring (used by the autoload layout and by tests).
func attach(bus: Node) -> void:
	if bus != null and bus.has_signal("event_received"):
		bus.event_received.connect(_on_event)


func _on_event(event: Dictionary) -> void:
	if event.is_empty():
		return
	var etype := str(event.get("type", ""))
	_latest[etype] = event
	_journal.append(event)
	if _journal.size() > JOURNAL_LIMIT:
		_journal.pop_front()
	if etype == Schema.TYPE_STATE_SNAPSHOT:
		var payload: Variant = event.get("payload", {})
		if payload is Dictionary:
			_snapshot_state = payload
	cache_updated.emit(event)


## Newest event seen for a type, or {} when never seen.
func get_latest(etype: String) -> Dictionary:
	var found: Variant = _latest.get(etype, {})
	return found if found is Dictionary else {}


## Payload of the newest state.snapshot — the live inspectable state document.
func get_state() -> Dictionary:
	return _snapshot_state


## A single field from the newest state.snapshot, or fallback when absent.
func get_state_value(key: String, fallback: Variant = null) -> Variant:
	if _snapshot_state.has(key):
		return _snapshot_state[key]
	return fallback


func journal() -> Array:
	return _journal


func known_types() -> Array:
	return _latest.keys()


func event_count() -> int:
	return _journal.size()


func clear() -> void:
	_latest.clear()
	_journal.clear()
	_snapshot_state = {}
