class_name HttpBrain
extends AiBrain

## POSTs the GameState snapshot to a configurable URL and expects Actions JSON.
## On timeout, transport error, or malformed payload, falls back to RuleBrain.
## Uses HTTPClient (RefCounted), not HTTPRequest, so it never touches scene nodes.

var url: String = ""
var timeout_ms: int = 2500
var last_error: String = ""
var used_fallback: bool = false


func configure(http_url: String, timeout: int = 2500) -> void:
	url = http_url
	timeout_ms = timeout


func decide(state: Dictionary) -> Array:
	used_fallback = false
	last_error = ""
	var remote: Variant = _post_snapshot(state)
	if remote != null:
		return remote
	used_fallback = true
	return RuleBrain.new().decide(state)


func _post_snapshot(state: Dictionary) -> Variant:
	if url.strip_edges() == "":
		last_error = "empty_url"
		return null
	var parsed := _parse_url(url)
	if parsed.is_empty():
		last_error = "bad_url"
		return null
	var client := HTTPClient.new()
	var tls_options: TLSOptions = TLSOptions.client() if bool(parsed["tls"]) else null
	var err := client.connect_to_host(str(parsed["host"]), int(parsed["port"]), tls_options)
	if err != OK:
		last_error = "connect_failed"
		return null
	var started := Time.get_ticks_msec()
	while client.get_status() == HTTPClient.STATUS_RESOLVING or client.get_status() == HTTPClient.STATUS_CONNECTING:
		if Time.get_ticks_msec() - started > timeout_ms:
			last_error = "connect_timeout"
			client.close()
			return null
		client.poll()
		OS.delay_msec(10)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		last_error = "not_connected"
		client.close()
		return null
	var body := JSON.stringify(state)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"User-Agent: Crownfall-HttpBrain/0.1",
	])
	err = client.request(HTTPClient.METHOD_POST, str(parsed["path"]), headers, body)
	if err != OK:
		last_error = "request_failed"
		client.close()
		return null
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		if Time.get_ticks_msec() - started > timeout_ms:
			last_error = "request_timeout"
			client.close()
			return null
		client.poll()
		OS.delay_msec(10)
	if client.get_status() != HTTPClient.STATUS_BODY and client.get_status() != HTTPClient.STATUS_CONNECTED:
		last_error = "bad_status"
		client.close()
		return null
	if client.get_response_code() < 200 or client.get_response_code() >= 300:
		last_error = "http_%d" % client.get_response_code()
		client.close()
		return null
	var raw := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		if Time.get_ticks_msec() - started > timeout_ms:
			last_error = "body_timeout"
			client.close()
			return null
		client.poll()
		var chunk := client.read_response_body_chunk()
		if chunk.size() == 0:
			OS.delay_msec(10)
		else:
			raw.append_array(chunk)
	client.close()
	var text := raw.get_string_from_utf8()
	var decoded: Variant = JSON.parse_string(text)
	var actions: Variant = _extract_actions(decoded)
	if actions == null:
		last_error = "bad_payload"
		return null
	return actions


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
