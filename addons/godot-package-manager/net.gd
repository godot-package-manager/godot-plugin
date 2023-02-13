extends RefCounted

const CONNECTING_STATUS := [
	HTTPClient.STATUS_CONNECTING,
	HTTPClient.STATUS_RESOLVING
]
const SUCCESS_STATUS := [
	HTTPClient.STATUS_BODY,
	HTTPClient.STATUS_CONNECTED,
]

const HEADERS := [
	"User-Agent: GodotPackageManager/1.0 (godot-package-manager on GitHub)",
	"Accept: */*"
]

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

## Create an HTTPClient that is connected to a given host.
static func _create_client(host: String) -> HTTPClient:
	var client := HTTPClient.new()
	
	var err := client.connect_to_host(host, 443, TLSOptions.client())
	if err != OK:
		printerr("Unable to connect to host %s" % host)
		return null
	
	while client.get_status() in CONNECTING_STATUS:
		client.poll()
		await Engine.get_main_loop().process_frame
	
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		printerr("Bad status while connecting to host %s" % host)
		return null
	
	return client

## Wait for a response after sending a request.
static func _wait_for_response(client: HTTPClient, valid_response_codes: Array[int]) -> int:
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		await Engine.get_main_loop().process_frame
	
	if not client.get_status() in SUCCESS_STATUS:
		return ERR_BUG
	
	if not client.get_response_code() in valid_response_codes:
		return ERR_BUG
	
	return OK

## Read the response body into a PackedByteArray.
static func _read_response_body(client: HTTPClient) -> PackedByteArray:
	var body := PackedByteArray()
	
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		
		var chunk := client.read_response_body_chunk()
		if chunk.is_empty():
			await Engine.get_main_loop().process_frame
		else:
			body.append_array(chunk)
	
	return body

## Convert a response body into a Dictionary.
static func _response_body_to_dict(body: PackedByteArray) -> Dictionary:
	var text := body.get_string_from_utf8()
	
	var response: Variant = JSON.parse_string(text)
	if response == null:
		printerr("Failed to parse response")
		return {}
	if typeof(response) != TYPE_DICTIONARY:
		printerr("Unexpected response %s" % str(response))
		return {}
	
	return response

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Send an HTTP GET request to the given host + path.
##
## @param host: String - The host name.
## @param path: String - The url path.
## @param valid_response_codes: Array[int] - Valid response codes. Any other code will
## be assumed to be an error.
##
## @return PackedByteArray - The response as bytes.
static func get_request(
	host: String,
	path: String,
	valid_response_codes: Array[int]
) -> PackedByteArray:
	var client: HTTPClient = await _create_client(host)
	if client == null:
		printerr("Unable to create client for get request")
		return PackedByteArray()
	
	var err := client.request(HTTPClient.METHOD_GET, "/%s" % path, HEADERS)
	if err != OK:
		printerr("Unable to send GET request to %s/%s" % [host, path])
		return PackedByteArray()
	
	err = await _wait_for_response(client, valid_response_codes)
	if err != OK:
		printerr("Bad response for GET request to %s/%s" % [host, path])
		return PackedByteArray()
	
	var body: PackedByteArray = await _read_response_body(client)
	
	return body

## Send an HTTP GET request to the given host + path and then parsed to a Dictionary.
##
## @param host: String - The host name.
## @param path: String - The url path.
## @param valid_response_codes: Array[int] - Valid response codes. Any other code will
## be assumed to be an error.
##
## @return Dictionary - The response parsed into a Dictionary.
static func get_request_json(host: String, path: String, valid_response_codes: Array[int]) -> Dictionary:
	var body: PackedByteArray = await get_request(host, path, valid_response_codes)
	
	return _response_body_to_dict(body)

## Send an HTTP POST request to the given host + path.
static func post_request(
	host: String,
	path: String,
	request_body: Dictionary,
	valid_response_codes: Array[int]
) -> Dictionary:
	var client: HTTPClient = await _create_client(host)
	if client == null:
		printerr("Unable to create client for get request")
		return {}
	
	var err := client.request(
		HTTPClient.METHOD_POST, "/%s" % path, HEADERS, JSON.stringify(request_body))
	if err != OK:
		printerr("Unable to send POST request to %s/%s" % [host, path])
		return {}
	
	err = await _wait_for_response(client, valid_response_codes)
	if err != OK:
		printerr("Bad response for POST request to %s/%s" % [host, path])
		return {}
	
	var body: PackedByteArray = await _read_response_body(client)
	
	return _response_body_to_dict(body)
