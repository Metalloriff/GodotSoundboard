extends Node

@onready var directories: Array = FS.get_pref("settings.soundboard_directories", [])

var current_fp: String
var is_playing: bool

func _ready():
	PythonServer.message_received.connect(_on_server_message_received)

func _on_server_message_received(data):
	match data.type:
		"STATUS_UPDATE":
			is_playing = data.status != "stopped"

func play(fp: String):
	current_fp = fp
	
	PythonServer.send_message({
		type = PythonServer.MESSAGE_TYPE.PLAY_CLIP,
		fp = fp
	})
