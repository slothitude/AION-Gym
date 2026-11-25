extends RefCounted
##
## AION Gym — event schema. THE CONTRACT.
##
## Both the Gym (this repo) and the Python gym_bridge (AION repo) build to this
## envelope. Versioned, additive-only evolution: new optional fields may appear
## at any time; unknown event types are passed through as RAW (never dropped);
## a future schema_version is accepted and annotated, never rejected.
##
## Envelope:
##   {"schema_version": 1, "type": "<one of TYPE_*>", "timestamp": <float>, "payload": {...}}
##
## parse()/parse_object() return a result dictionary:
##   ok: bool
##   error: String                      (non-empty only when ok == false)
##   event: Dictionary                  (present only when ok == true)
##     schema_version: int
##     type: String
##     timestamp: float
##     payload: Dictionary
##     known_type: bool                 (false => raw passthrough)
##     is_raw: bool
##     future_version: bool             (schema_version newer than ours)
##     payload_errors: Array[String]    (missing required payload fields)
##
## Envelope problems are fatal (ok == false). Missing required payload fields
## are reported in payload_errors and are only fatal in strict_payload mode —
## the Gym never silently drops a well-formed envelope (display integrity).

const SCHEMA_VERSION: int = 1

const TYPE_STATE_SNAPSHOT: String = "state.snapshot"
const TYPE_EXPERIENCE_CREATED: String = "experience.created"
const TYPE_CONNECTION_UPDATED: String = "connection.updated"
const TYPE_MEMORY_CONSOLIDATED: String = "memory.consolidated"
const TYPE_DREAM_STARTED: String = "dream.started"
const TYPE_DREAM_HYPOTHESIS: String = "dream.hypothesis"
const TYPE_DREAM_EVALUATED: String = "dream.evaluated"
const TYPE_NOMEN_CHANGED: String = "nomen.changed"
const TYPE_NAV_ACTION: String = "nav.action"
const TYPE_HOSTMODE_REQUEST: String = "hostmode.request"
const TYPE_DEVELOPMENT_STAGE: String = "development.stage"

const ALL_TYPES: Array = [
	TYPE_STATE_SNAPSHOT,
	TYPE_EXPERIENCE_CREATED,
	TYPE_CONNECTION_UPDATED,
	TYPE_MEMORY_CONSOLIDATED,
	TYPE_DREAM_STARTED,
	TYPE_DREAM_HYPOTHESIS,
	TYPE_DREAM_EVALUATED,
	TYPE_NOMEN_CHANGED,
	TYPE_NAV_ACTION,
	TYPE_HOSTMODE_REQUEST,
	TYPE_DEVELOPMENT_STAGE,
]

## Per-type payload contract. "required" is the shared minimum both sides
## build to; "optional" documents known fields. Unknown payload fields are
## always passed through untouched (additive-only evolution).
const PAYLOAD_FIELDS: Dictionary = {
	TYPE_STATE_SNAPSHOT: {
		"required": [],
		"optional": [
			"state", "relationships", "u_fast", "theta", "gates",
			"memory_inventory", "devhistory_stage", "stage", "stage_index",
			"mode", "uptime_s", "plasticity", "experience_steps",
		],
	},
	TYPE_EXPERIENCE_CREATED: {
		"required": ["episode_id"],
		"optional": ["provenance", "fact", "source", "world_id"],
	},
	TYPE_CONNECTION_UPDATED: {
		"required": ["connection_id"],
		"optional": [
			"from_node", "to_node", "delta_u_fast", "delta_theta",
			"u_fast_before", "u_fast_after", "theta_before", "theta_after",
			"cause_episode_id",
		],
	},
	TYPE_MEMORY_CONSOLIDATED: {
		"required": ["moved", "preservation_verified"],
		"optional": ["cycle_id", "moved_count", "detail"],
	},
	TYPE_DREAM_STARTED: {
		"required": ["cycle_id"],
		"optional": ["seeds", "seed_count"],
	},
	TYPE_DREAM_HYPOTHESIS: {
		"required": ["hypothesis_id"],
		"optional": ["cycle_id", "relationship", "confidence"],
	},
	TYPE_DREAM_EVALUATED: {
		"required": ["hypothesis_id", "accepted"],
		"optional": ["cycle_id", "measured_improvement", "reason"],
	},
	TYPE_NOMEN_CHANGED: {
		"required": ["entity_id"],
		"optional": ["old_name", "new_name", "lineage"],
	},
	TYPE_NAV_ACTION: {
		"required": ["decision_id"],
		"optional": ["goal", "options", "choice", "outcome"],
	},
	TYPE_HOSTMODE_REQUEST: {
		"required": ["request_id", "verdict"],
		"optional": ["proposal", "reason", "resource"],
	},
	TYPE_DEVELOPMENT_STAGE: {
		"required": ["stage"],
		"optional": ["previous_stage", "evidence", "stage_index"],
	},
}


static func parse(text: String, strict_payload: bool = false) -> Dictionary:
	var parsed = JSON.parse_string(text)
	if parsed == null:
		return _error_result("invalid JSON text")
	return parse_object(parsed, strict_payload)


static func parse_object(data: Variant, strict_payload: bool = false) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return _error_result("envelope must be a JSON object, got %s" % _type_name(typeof(data)))
	if not data.has("schema_version"):
		return _error_result("envelope missing 'schema_version'")
	var sv: Variant = data["schema_version"]
	if typeof(sv) != TYPE_INT and typeof(sv) != TYPE_FLOAT:
		return _error_result("'schema_version' must be a number, got %s" % _type_name(typeof(sv)))
	if not data.has("type"):
		return _error_result("envelope missing 'type'")
	var etype: Variant = data["type"]
	if typeof(etype) != TYPE_STRING:
		return _error_result("'type' must be a string, got %s" % _type_name(typeof(etype)))
	if not data.has("timestamp"):
		return _error_result("envelope missing 'timestamp'")
	var ts: Variant = data["timestamp"]
	if typeof(ts) != TYPE_INT and typeof(ts) != TYPE_FLOAT:
		return _error_result("'timestamp' must be a number, got %s" % _type_name(typeof(ts)))
	if not data.has("payload"):
		return _error_result("envelope missing 'payload'")
	var payload: Variant = data["payload"]
	if typeof(payload) != TYPE_DICTIONARY:
		return _error_result("'payload' must be an object, got %s" % _type_name(typeof(payload)))

	var known: bool = ALL_TYPES.has(etype)
	var payload_errors: Array[String] = []
	if known:
		payload_errors = _check_payload(str(etype), payload)
	if strict_payload and payload_errors.size() > 0:
		return _error_result("payload field check failed: " + ", ".join(payload_errors))

	var event: Dictionary = {
		"schema_version": int(sv),
		"type": str(etype),
		"timestamp": float(ts),
		"payload": payload,
		"known_type": known,
		"is_raw": not known,
		"future_version": int(sv) > SCHEMA_VERSION,
		"payload_errors": payload_errors,
	}
	return {"ok": true, "error": "", "event": event}


static func is_known_type(etype: String) -> bool:
	return ALL_TYPES.has(etype)


static func payload_fields(etype: String) -> Dictionary:
	return PAYLOAD_FIELDS.get(etype, {"required": [], "optional": []})


static func _check_payload(etype: String, payload: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var fields: Dictionary = payload_fields(etype)
	var required: Array = fields.get("required", [])
	for req in required:
		if not payload.has(str(req)):
			errors.append("%s missing required field '%s'" % [etype, str(req)])
	return errors


static func _error_result(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "event": {}}


static func _type_name(t: int) -> String:
	match t:
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "bool"
		TYPE_INT:
			return "int"
		TYPE_FLOAT:
			return "float"
		TYPE_STRING:
			return "string"
		TYPE_DICTIONARY:
			return "object"
		TYPE_ARRAY:
			return "array"
		_:
			return "type(%d)" % t
