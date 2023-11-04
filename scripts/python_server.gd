extends Node

const HOST := "127.0.0.1"
const PORT := 4911
const MESSAGE_TYPE := {
	PLAY_CLIP = "PLAY_CLIP"
}

signal message_received(message)

func get_global_path(path: String):
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://%s" % path)
	return OS.get_executable_path().get_base_dir().path_join(path)

var pid := -1
var socket := WebSocketPeer.new()
var has_sent_settings := false

func _ready():
	if OS.has_feature("editor"):
		var python_server_path = get_global_path("python_server")
		pid = OS.create_process(python_server_path.path_join("venv/Scripts/python.exe"), [python_server_path])
	else:
		pid = OS.create_process(OS.get_executable_path().get_base_dir().path_join("python_server.exe"), [])
	socket.connect_to_url("ws://%s:%s" % [HOST, PORT])

func _exit_tree():
	OS.kill(pid)

func _process(_delta):
	socket.poll()
	
	var state := socket.get_ready_state()
	
	match state:
		WebSocketPeer.STATE_OPEN:
			if not has_sent_settings:
				$/root/main._init_settings()
				has_sent_settings = true
			
			while socket.get_available_packet_count():
				var packet = socket.get_packet().get_string_from_utf8()
				var data = JSON.parse_string(packet)
				
				message_received.emit(data)
				prints("DATA RECEIVED", data)
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			var code = socket.get_close_code()
			var reason = socket.get_close_reason()
			
			prints("CLOSED", code, reason)
			set_process(false)

func send_message(message: Dictionary):
	while socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		await get_tree().process_frame
	
	socket.send_text(JSON.stringify(message))
