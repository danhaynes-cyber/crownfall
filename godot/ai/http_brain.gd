class_name HttpBrain
extends AiBrain

## POSTs the GameState snapshot to a configurable URL and expects Actions JSON.
## On timeout, transport error, or malformed payload, falls back to RuleBrain.
## Uses HTTPClient (RefCounted), not HTTPRequest, so it never touches scene nodes.
##
## decide() stays snapshot-in / actions-out. The match should call
## begin_decide + poll_decide so the UI can keep rendering; poll_decide
## never calls OS.delay_msec.

var url: String = ""
var timeout_ms: int = 2500
var last_error: String = ""
var used_fallback: bool = false

var _client: HTTPClient
var _state: Dictionary = {}
var _started_ms: int = 0
var _requested: bool = false
var _raw: PackedByteArray = PackedByteArray()
var _parsed_url: Dictionary = {}


func configure(http_url: String, timeout: int = 2500) -> void:
	url = http_url
	timeout_ms = timeout


func begin_decide(state: Dictionary) -> void:
	used_fallback = false
	last_error = ""
	_ready_actions = null
	_state = state
	_requested = false
	_raw = PackedByteArray()
	_started_ms = Time.get_ticks_msec()
	_client = HTTPClient.new()
	if url.strip_edges() == "":
		_fail_to_rule("empty_url")
		return
	_parsed_url = _parse_url(url)
	if _parsed_url.is_empty():
		_fail_to_rule("bad_url")
		return
	var tls_options: TLSOptions = TLSOptions.client() if bool(_parsed_url["tls"]) else null
	var err := _client.connect_to_host(str(_parsed_url["host"]), int(_parsed_url["port"]), tls_options)
	if err != OK:
		_fail_to_rule("connect_failed")


func poll_decide() -> Variant:
	if _ready_actions != null:
		return _ready_actions
	if _client == null:
		_fail_to_rule("no_client")
		return _ready_actions
	if Time.get_ticks_msec() - _started_ms > timeout_ms:
		_fail_to_rule("timeout")
		return _ready_actions
	_client.poll()
	var status := _client.get_status()
	if status == HTTPClient.STATUS_RESOLVING or status == HTTPClient.STATUS_CONNECTING:
		return null
	if status == HTTPClient.STATUS_CONNECTED:
		if not _requested:
			var body := JSON.stringify(_state)
			var headers := PackedStringArray([
				"Content-Type: application/json",
				"Accept: application/json",
				"User-Agent: Crownfall-HttpBrain/0.1",
			])
			var err := _client.request(HTTPClient.METHOD_POST, str(_parsed_url["path"]), headers, body)
			if err != OK:
				_fail_to_rule("request_failed")
				return _ready_actions
			_requested = true
			return null
		_finish_body()
		return _ready_actions
	if status == HTTPClient.STATUS_REQUESTING:
		return null
	if status == HTTPClient.STATUS_BODY:
		var chunk := _client.read_response_body_chunk()
		if chunk.size() > 0:
			_raw.append_array(chunk)
		return null
	if status == HTTPClient.STATUS_DISCONNECTED:
		if _requested:
			_finish_body()
		else:
			_fail_to_rule("disconnected")
		return _ready_actions
	if status == HTTPClient.STATUS_CANT_CONNECT or status == HTTPClient.STATUS_CANT_RESOLVE or status == HTTPClient.STATUS_CONNECTION_ERROR or status == HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
		_fail_to_rule("transport")
		return _ready_actions
	_fail_to_rule("bad_status")
	return _ready_actions


func _finish_body() -> void:
	if _client.get_response_code() < 200 or _client.get_response_code() >= 300:
		_fail_to_rule("http_%d" % _client.get_response_code())
		return
	var text := _raw.get_string_from_utf8()
	var decoded: Variant = JSON.parse_string(text)
	var actions: Variant = _extract_actions(decoded)
	_client.close()
	if actions == null:
		_fail_to_rule("bad_payload")
		return
	_ready_actions = actions


func _fail_to_rule(error: String) -> void:
	last_error = error
	used_fallback = true
	if _client != null:
		_client.close()
	_ready_actions = RuleBrain.new().compute_actions(_state)


func _extract_actions(decoded) -> Variant:
	if typeof(decoded) == TYPE_ARRAY:
		return decoded
	if typeof(decoded) == TYPE_DICTIONARY:
		if decoded.has("actions") and typeof(decoded["actions"]) == TYPE_ARRAY:
			return decoded["actions"]
	return null


func _parse_url(raw: String) -> Dictionary:
	var tls := raw.begins_with("https://")
	var rest := raw
	if raw.begins_with("https://"):
		rest = raw.substr(8)
	elif raw.begins_with("http://"):
		rest = raw.substr(7)
	else:
		return {}
	var slash := rest.find("/")
	var hostport := rest if slash < 0 else rest.substr(0, slash)
	var path := "/" if slash < 0 else rest.substr(slash)
	if path == "":
		path = "/"
	var host := hostport
	var port := 443 if tls else 80
	if hostport.contains(":"):
		var bits := hostport.split(":")
		host = bits[0]
		port = int(bits[1])
	if host == "":
		return {}
	return {"host": host, "port": port, "path": path, "tls": tls}
