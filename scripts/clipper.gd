extends ScrollContainer

@onready var clips_container := %ClipperClipsContainer
@onready var clip_item: HBoxContainer = Lib.create_item_instance(%ClipperClipItem)
@onready var status_text := %ClipperStatusText

var _busy := false
var _running: bool:
	get: return _running
	set(value):
		_running = value
		_busy = false
		
		$MarginContainer/VBoxContainer/HBoxContainer2/ClipperStartButton.disabled = _running
		$MarginContainer/VBoxContainer/HBoxContainer2/ClipperStopButton.disabled = not _running
		$MarginContainer/VBoxContainer/ClipperExportButton.disabled = not _running

func _ready():
	PythonServer.message_received.connect(_server_message_received)
	_render_clips()
	
	%ClipperDevicesList.text = FS.get_pref("settings.clipper_devices", "")
	
	_running = false
	
	if FS.get_pref("clipper.last_running", false) == true:
		_on_clipper_start_button_pressed()

func _server_message_received(data):
	match data.type:
		"CLIPPER_EXPORT_COMPLETE":
			_render_clips()
			_busy = false
		"CLIPPER_SET_STATUS":
			status_text.text = "Status: [color=%s]%s[/color]" % [
				"#ff7777" if data.status == "STOPPED" else "#77ff77",
				data.status
			]
			
			_running = data.status == "RUNNING"

func _render_clips():
	var directory := "user://exported_clips"
	
	Lib.clear_child_nodes(clips_container)
	if not DirAccess.dir_exists_absolute(directory): return
	
	await get_tree().create_timer(0.05).timeout
	
	var files = Array(DirAccess.get_files_at(directory)).map(func(fn): return FS.join_path([directory, fn]))
	files.sort_custom($/root/main.SORT_METHOD.MODIFIED_DATE)
	
	var clips := {}
	
	for fp in files:
		var clip_name = fp.split("/")[-1].split(" - ")[0]
		
		if not clip_name in clips:
			clips[clip_name] = []
		clips[clip_name].append(fp.replace("user:/", OS.get_user_data_dir()))
		
		if clips_container.has_node(clip_name): continue
		
		var item := clip_item.duplicate()
		clips_container.add_child(item)
		
		item.name = clip_name
		item.get_node("ClipButton").text = clip_name
		
		item.get_node("ClipButton").pressed.connect(func():
			while not FS.get_pref("audio_editor_path", ""):
				$FileDialog.popup_centered()
				FS.set_pref("audio_editor_path", await $FileDialog.file_selected)
				$FileDialog.hide()
			
			var lof = FileAccess.open("user://audacity.lof", FileAccess.WRITE)
			lof.store_line("window")
			for clip in clips[clip_name]:
				lof.store_line('file "%s"' % clip)
			
			OS.create_process(FS.get_pref("audio_editor_path"), [OS.get_user_data_dir().path_join("audacity.lof")])
		)
		
		item.get_node("DeleteButton").pressed.connect(func():
			for clip in clips[clip_name]:
				DirAccess.remove_absolute(clip)
			
			_render_clips()
		)

func _on_clipper_start_button_pressed():
	if _busy: return
	_busy = true
	
	PythonServer.send_message({
		type = "CLIPPER_START",
		devices = %ClipperDevicesList.text.split(",")
	})
	
	FS.set_pref("clipper.last_running", true)

func _on_clipper_stop_button_pressed():
	if _busy: return
	_busy = true
	
	PythonServer.send_message({
		type = "CLIPPER_STOP"
	})
	
	FS.set_pref("clipper.last_running", false)

func _on_clipper_export_button_pressed():
	if _busy: return
	_busy = true
	
	var dir = OS.get_user_data_dir().path_join("exported_clips")
	FS.mkdir(dir)
	
	PythonServer.send_message({
		type = "CLIPPER_EXPORT",
		directory = dir
	})

func _on_clipper_devices_list_focus_exited():
	FS.set_pref("settings.clipper_devices", %ClipperDevicesList.text)
