extends Node
##
## AION Gym — WebSocket client for the gym_bridge event stream.
##
## Connects to ws://host:port, parses every text frame through the schema
## contract and emits typed results. Never invents events: malformed frames
## surface as parse_error, unknown-but-well-formed types pass through as RAW.
##
## The peer is polled from _process while inside the tree; tests can drive
## poll_transport() and _handle_text() directly without any socket.

signal connected()
signal disconnected(code: int, reason: String, was_error: bool)
signal event_received(event: Dictionary)
signal parse_error(error_message: String, raw_text: String)
signal transport_error(message: String)

const Schema = preload("res://scripts/aion_client/schema.gd")

var url: String = ""

var _peer: WebSocketPeer = WebSocketPeer.new()
var _open_notified := false
var _close_notified := true


## Start connecting. Returns OK once the request was handed to the peer —
## actual success arrives via the connected() signal after polling.
func connect_to_url(target_url: String) -> Error:
	url = target_url
	_open_notified = false
	_close_notified = false
	var err: int = _peer.connect_to_url(url)
	if err != OK:
		_close_notified = true
		var msg := "WebSocket connect failed: %s" % error_string(err)
		transport_error.emit(msg)
		return err
	return OK


func close(code: int = 1000, reason: String = "") -> void:
	if _peer.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_peer.close(code, reason)


func is_open() -> bool:
	return _peer.get_ready_state() == WebSocketPeer.STATE_OPEN


func poll_transport() -> void:
	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _open_notified:
				_open_notified = true
				connected.emit()
			while _peer.get_available_packet_count() > 0:
				var packet: PackedByteArray = _peer.get_packet()
				_handle_text(packet.get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			if not _close_notified:
				_close_notified = true
				disconnected.emit(_peer.get_close_code(), _peer.get_close_reason(), true)


func _process(_delta: float) -> void:
	poll_transport()


## Contract parse of one text frame. Kept separate so it is testable offline.
func _handle_text(text: String) -> void:
	var result: Dictionary = Schema.parse(text)
	if not bool(result.get("ok", false)):
		parse_error.emit(str(result.get("error", "unknown parse failure")), text)
		return
	event_received.emit(result.get("event", {}))
