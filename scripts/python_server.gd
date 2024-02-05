extends Node

const HOST := "127.0.0.1"
const PORT := 4911
const MESSAGE_TYPE := {
	PLAY_CLIP = "PLAY_CLIP"
}

signal message_received(message)

func get_global_path(path: String) -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://%s" % path)
	return OS.get_executable_path().get_base_dir().path_join(path)

var pid := -1
var socket := WebSocketPeer.new()
var has_sent_settings := false

@onready var PYTHON_SERVER_PATH := get_global_path("python_server")
var python_cmd: String

func _search_for_python() -> bool:
	for exec in ["py", "python3", "python"]:
		if OS.execute(exec, ["--version"]) == 0:
			python_cmd = exec
			return true
	return false

func _ready():
	set_process(false)
	
	if not _search_for_python():
		%NotificationToast.show_message("Python is not installed! Please install Python and restart!", NotificationToast.TOAST_TYPE.ERROR)
		return
	
	if OS.get_name() in ["Linux", "X11"]:
		OS.execute("bash", [PYTHON_SERVER_PATH.path_join("install.sh")])
		pid = OS.create_process("bash", [PYTHON_SERVER_PATH.path_join("run.sh")])
		
		await get_tree().create_timer(2.0).timeout
	else:
		OS.execute(PYTHON_SERVER_PATH.path_join("install.bat"), [])
		pid = OS.create_process(PYTHON_SERVER_PATH.path_join("run.bat"), [])
	
	set_process(true)
	socket.connect_to_url("ws://%s:%s" % [HOST, PORT])

func _exit_tree():
	if pid > 1:
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
