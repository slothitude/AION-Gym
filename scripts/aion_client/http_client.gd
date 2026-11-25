extends Node
##
## AION Gym — HTTP request client for the gym_bridge request API.
##
## Permitted actions only. Every request is validated by the runtime's
## authority layer; denials come back with reasons and are surfaced here,
## never hidden — the Gym is just another proposer (plan §2, hostmode law).

signal request_completed(action: String, ok: bool, data: Dictionary, error_message: String)

const SNAPSHOT_ENDPOINT: String = "api/snapshot"

const ACTIONS: Array = [
	"teach", "ask", "correct", "pause", "resume",
	"set_goal", "approve_request", "deny_request",
]

const ACTION_ENDPOINTS: Dictionary = {
	"teach": "api/actions/teach",
	"ask": "api/actions/ask",
	"correct": "api/actions/correct",
	"pause": "api/actions/pause",
	"resume": "api/actions/resume",
	"set_goal": "api/actions/set_goal",
	"approve_request": "api/actions/approve_request",
	"deny_request": "api/actions/deny_request",
}

var base_url: String = "http://127.0.0.1:7480"
var timeout_seconds: float = 10.0


func snapshot_url() -> String:
	return "%s/%s" % [base_url, SNAPSHOT_ENDPOINT]


func action_url(action: String) -> String:
	var endpoint := str(ACTION_ENDPOINTS.get(action, ""))
	return "%s/%s" % [base_url, endpoint]


## GET the full inspectable state document. callback receives
## {"ok": bool, "error": String, "data": Dictionary, "response_code": int}.
func fetch_snapshot(callback: Callable = Callable()) -> void:
	_request(HTTPClient.METHOD_GET, SNAPSHOT_ENDPOINT, {}, "snapshot", callback)


## POST one permitted action. Unknown actions are refused locally before any
## network traffic happens.
func send_action(action: String, body: Dictionary = {}, callback: Callable = Callable()) -> void:
	if not ACTION_ENDPOINTS.has(action):
		var msg := "refused: '%s' is not a permitted action" % action
		push_warning(msg)
		_finish(action, false, {}, msg, 0, callback)
		return
	_request(HTTPClient.METHOD_POST, str(ACTION_ENDPOINTS[action]), body, action, callback)


func _request(method: int, endpoint: String, body: Dictionary, action: String, callback: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = timeout_seconds
	add_child(http)
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var body_text := ""
	if method == HTTPClient.METHOD_POST:
		body_text = JSON.stringify(body)
	var err: int = http.request("%s/%s" % [base_url, endpoint], headers, method, body_text)
	if err != OK:
		http.queue_free()
		_finish(action, false, {}, "request failed to start: %s" % error_string(err), 0, callback)
		return
	http.request_completed.connect(_on_request_done.bind(action, callback, http))


func _on_request_done(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, action: String, callback: Callable, http: HTTPRequest) -> void:
	http.queue_free()
	var data: Dictionary = {}
	var error_message := ""
	if result != HTTPRequest.RESULT_SUCCESS:
		error_message = "transport failure (result %d)" % result
	elif response_code < 200 or response_code >= 300:
		error_message = "HTTP %d" % response_code
	else:
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if parsed == null:
			error_message = "invalid JSON in response"
		elif typeof(parsed) != TYPE_DICTIONARY:
			error_message = "response is not a JSON object"
		else:
			data = parsed
	_finish(action, error_message == "", data, error_message, response_code, callback)


func _finish(action: String, ok: bool, data: Dictionary, error_message: String, response_code: int, callback: Callable) -> void:
	request_completed.emit(action, ok, data, error_message)
	if callback.is_valid():
		callback.call({
			"ok": ok,
			"error": error_message,
			"data": data,
			"response_code": response_code,
		})
