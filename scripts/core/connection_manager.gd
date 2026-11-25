extends Node
##
## AION Gym — connection manager.
##
## Owns the WebSocket event stream and the HTTP request API, routes parsed
## events onto the in-client EventBus, and reconnects with capped exponential
## backoff. The Gym never writes plastic state directly: every action goes
## through the permitted-action HTTP API and the runtime's authority layer
## decides (hostmode law — AION proposes, the runtime disposes).

signal connection_state_changed(new_state: int, detail: String)
signal event_received(event: Dictionary)

const WsClientScript = preload("res://scripts/aion_client/ws_client.gd")
const HttpClientScript = preload("res://scripts/aion_client/http_client.gd")

enum ConnState { OFFLINE, CONNECTING, CONNECTED, RETRY_WAITING }

## Client-side default; the bridge lane owns the server side and may pin a
## different port — connect_to_runtime() overrides.
const DEFAULT_HOST: String = "127.0.0.1"
const DEFAULT_PORT: int = 7480

const BACKOFF_BASE_SECONDS: float = 0.5
const BACKOFF_FACTOR: float = 2.0
const BACKOFF_MAX_SECONDS: float = 30.0

var host: String = DEFAULT_HOST
var port: int = DEFAULT_PORT
var use_tls: bool = false
var auto_reconnect: bool = true
var reconnect_attempts: int = 0  # 0 = unlimited

var ws_client: Node = null
var http_client: Node = null

var _state: int = ConnState.OFFLINE
var _attempt: int = 0
var _manual_disconnect := false
var _retry_pending := false
var _retry_timer: Timer = null
var _bus: Node = null


func _ready() -> void:
	_bus = get_node_or_null("/root/EventBus")


## Explicit bus wiring (used by the autoload layout and by tests).
func attach_bus(bus: Node) -> void:
	_bus = bus


func get_bus() -> Node:
	return _bus


func ws_url() -> String:
	var scheme := "wss" if use_tls else "ws"
	return "%s://%s:%d" % [scheme, host, port]


func is_connected_runtime() -> bool:
	return _state == ConnState.CONNECTED


func get_state() -> int:
	return _state


## Public entry: (re)connect to the runtime. Optional host/port override.
func connect_to_runtime(p_host: String = "", p_port: int = 0) -> Error:
	if p_host != "":
		host = p_host
	if p_port > 0:
		port = p_port
	_manual_disconnect = false
	_attempt = 0
	return _start_connect()


## Owner-requested stop: no reconnect will follow. The state reflects offline
## immediately; the ws close (when a socket exists) follows behind.
func disconnect_runtime() -> void:
	_manual_disconnect = true
	_cancel_retry()
	_set_state(ConnState.OFFLINE, "client requested")
	if ws_client != null:
		ws_client.close(1000, "client requested")


# ---- permitted-action convenience wrappers (routed through the authority layer)

func request_snapshot(callback: Callable = Callable()) -> void:
	_ensure_clients()
	http_client.fetch_snapshot(callback)


func send_action(action: String, body: Dictionary = {}, callback: Callable = Callable()) -> void:
	_ensure_clients()
	http_client.send_action(action, body, callback)


# ---- internals

func _start_connect() -> Error:
	_ensure_clients()
	_cancel_retry()
	_set_state(ConnState.CONNECTING, ws_url())
	return ws_client.connect_to_url(ws_url())


func _ensure_clients() -> void:
	if ws_client == null:
		ws_client = WsClientScript.new()
		ws_client.name = "WsClient"
		add_child(ws_client)
		ws_client.connected.connect(_on_ws_connected)
		ws_client.disconnected.connect(_on_ws_disconnected)
		ws_client.event_received.connect(_on_ws_event)
		ws_client.parse_error.connect(_on_ws_parse_error)
		ws_client.transport_error.connect(_on_ws_transport_error)
	if http_client == null:
		http_client = HttpClientScript.new()
		http_client.name = "HttpClient"
		add_child(http_client)


func _on_ws_connected() -> void:
	_attempt = 0
	_retry_pending = false
	_set_state(ConnState.CONNECTED, ws_url())


func _on_ws_disconnected(code: int, reason: String, was_error: bool) -> void:
	_set_state(ConnState.OFFLINE, "closed code=%d %s" % [code, reason])
	if auto_reconnect and not _manual_disconnect:
		_schedule_retry()


func _on_ws_event(event: Dictionary) -> void:
	event_received.emit(event)
	if _bus != null:
		_bus.publish(event)


func _on_ws_parse_error(error_message: String, _raw_text: String) -> void:
	push_warning("event stream contract violation: %s" % error_message)
	if _bus != null and _bus.has_signal("parse_error"):
		_bus.parse_error.emit(error_message, _raw_text)


func _on_ws_transport_error(message: String) -> void:
	push_warning("event stream transport error: %s" % message)


## Capped exponential backoff. Advances the attempt counter.
func _next_backoff() -> float:
	var wait: float = BACKOFF_BASE_SECONDS * pow(BACKOFF_FACTOR, float(_attempt))
	if wait > BACKOFF_MAX_SECONDS:
		wait = BACKOFF_MAX_SECONDS
	_attempt += 1
	return wait


func _schedule_retry() -> void:
	if _retry_pending:
		return  # already waiting for the next attempt
	if reconnect_attempts > 0 and _attempt >= reconnect_attempts:
		_set_state(ConnState.OFFLINE, "gave up after %d attempts" % _attempt)
		return
	var wait := _next_backoff()
	if _retry_timer == null:
		_retry_timer = Timer.new()
		_retry_timer.one_shot = true
		add_child(_retry_timer)
		_retry_timer.timeout.connect(_retry_now)
	# wait_time is set explicitly so the retry state machine is fully
	# observable even outside the tree (tests); start() needs the tree.
	_retry_timer.wait_time = wait
	_retry_pending = true
	_set_state(ConnState.RETRY_WAITING, "retry in %.1fs (attempt %d)" % [wait, _attempt])
	if is_inside_tree():
		_retry_timer.start(wait)


func _retry_now() -> void:
	_retry_pending = false
	_start_connect()


func _cancel_retry() -> void:
	_retry_pending = false
	if _retry_timer != null:
		_retry_timer.stop()


func _set_state(new_state: int, detail: String) -> void:
	if new_state == _state:
		return
	_state = new_state
	connection_state_changed.emit(_state, detail)
