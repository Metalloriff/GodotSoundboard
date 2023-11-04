extends Control

var SORT_METHOD := {
	MODIFIED_DATE = func(a, b): return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b)
}

@onready var tabs := $VBoxContainer/TabContainer
@onready var soundboard_item: Button = Lib.create_item_instance(%SoundboardItem)
@onready var soundboard_dir_item: VBoxContainer = Lib.create_item_instance(%SoundboardDirItem)
@onready var soundboard_tab_item: ScrollContainer = Lib.create_item_instance(%SoundboardTabItem)
@onready var controls_container := $VBoxContainer/Controls
@onready var controls := controls_container.get_node("MarginContainer/HBoxContainer")

var playing_node: Node

func _ready():
	%LocalVolume.value = FS.get_pref("settings.local_volume", 0.5)
	%RemoteVolume.value = FS.get_pref("settings.remote_volume", 0.5)
	%ToggleVolumeLink.button_pressed = FS.get_pref("settings.volume_linked", false)
	%TTSVoiceSelection.selected = FS.get_pref("settings.tts_selected_voice", 0)
	
	_update_directories()
	
	PythonServer.message_received.connect(_server_message_received)

func _update_directories():
	for child in tabs.get_children():
		if child.has_meta("soundboard_directory"):
			child.queue_free()
	await get_tree().create_timer(0.05).timeout
	
	for directory in Soundboard.directories:
		if not DirAccess.dir_exists_absolute(directory):
			print("Directory does not exist! '%s'" % directory)
			continue
		
		var tab_item := soundboard_tab_item.duplicate()
		tabs.add_child(tab_item)
		
		tab_item.set_meta("soundboard_directory", directory)
		tab_item.name = directory.get_file()
		
		var files := Array(DirAccess.get_files_at(directory)).map(func(fn): return directory.path_join(fn))
		files.sort_custom(SORT_METHOD.MODIFIED_DATE)
		
		var tab_items := tab_item.get_node("MarginContainer/VBoxContainer/Items")
		Lib.clear_child_nodes(tab_items)
		
		var dirs := {}
		for dir_fp in Array(DirAccess.get_directories_at(directory)).map(func(fn): return directory.path_join(fn)):
			dirs[dir_fp] = []
			
			var dir_item := soundboard_dir_item.duplicate()
			tab_items.add_child(dir_item)
			
			var dir_files := Array(DirAccess.get_files_at(dir_fp)).map(func(fn): return dir_fp.path_join(fn))
			dir_files.sort_custom(SORT_METHOD.MODIFIED_DATE)
			
			dir_item.get_node("Button").pressed.connect(func():
				var items_container := dir_item.get_node("ItemsContainer")
				items_container.visible = not items_container.visible
			)
			
			var contents := dir_item.get_node("Button/Contents")
			contents.get_node("Name").text = dir_fp.get_file()
			contents.get_node("Count").text = "%s items  " % str(len(dir_files))
			
			var dir_items := dir_item.get_node("ItemsContainer/Items")
			for fp in dir_files:
				add_soundboard_item(dir_items, fp)
		
		tab_item.get_node("MarginContainer/VBoxContainer/SearchField/LineEdit").text_changed.connect(func(search_text):
			search_soundboard(tab_items, search_text)
		)
		
		for fp in files:
			add_soundboard_item(tab_items, fp)
	
	tabs.move_child(tabs.get_node("+"), -1)

func search_soundboard(container, search_text: String):
	for child in container.get_children():
		if child.has_node("ItemsContainer/Items"):
			search_soundboard(child.get_node("ItemsContainer/Items"), search_text)
			continue
		
		if not search_text.strip_edges():
			child.show()
		else:
			child.visible = search_text.to_lower() in child.get_node("Contents/Name").text.to_lower()
	
	for child in container.get_children():
		if not child.has_node("ItemsContainer/Items"): continue
		var visible_items = child.get_node("ItemsContainer/Items").get_children().filter(func(c): return c.visible)
		
		child.get_node("Button/Contents/Count").text = "%s items  " % str(len(visible_items))
		child.visible = len(visible_items) > 0

func add_soundboard_item(container: Node, fp: String):
	var item := soundboard_item.duplicate()
	container.add_child(item)

	var play = func():
		playing_node = item
		
		if Soundboard.is_playing:
			_on_play_pressed()
		else:
			controls.get_node("Seek").set_value_no_signal(0)
			Soundboard.play(fp)

	item.pressed.connect(play)
	item.get_node("Contents/Name").text = fp.split("/")[-1].split(".")[0]

func _init_settings():
	PythonServer.send_message({
		type = "RECEIVE_SETTINGS",
		local_volume = %LocalVolume.value,
		remote_volume = %RemoteVolume.value
	})

func _input(event):
	if event.is_action_pressed("ui_refresh"):
		_update_directories()

func _server_message_received(data):
	match data.type:
		"STATUS_UPDATE":
			match data.status:
				"playing":
					controls.get_node("Play").icon = controls.get_node("Play").get_meta("pause_icon")
					if playing_node: playing_node.get_node("Contents/PlayIcon").texture = controls.get_node("Play").icon
					
					controls_container.show()
					get_tree().create_tween().tween_property(controls_container, "modulate:a", 1.0, 0.2)
				"paused":
					controls.get_node("Play").icon = controls.get_node("Play").get_meta("play_icon")
					if playing_node: playing_node.get_node("Contents/PlayIcon").texture = controls.get_node("Play").icon
				"stopped":
					if playing_node: playing_node.get_node("Contents/PlayIcon").texture = controls.get_node("Play").get_meta("play_icon")
					await get_tree().create_tween().tween_property(controls_container, "modulate:a", 0.0, 0.5).finished
					controls_container.hide()
		"SEEK":
			controls.get_node("Seek").max_value = data.max
			controls.get_node("Seek").set_value_no_signal(data.seek)
		"ERROR":
			$NotificationToast.show_message(data.error, NotificationToast.TOAST_TYPE.ERROR)
		"MESSAGE":
			$NotificationToast.show_message(data.message, NotificationToast.TOAST_TYPE[data.message_type])

func _on_seek_value_changed(value):
	PythonServer.send_message({
		type = "SEEK",
		seek = value
	})

func _on_play_pressed():
	PythonServer.send_message({
		type = "PAUSE_PLAY"
	})

func _on_local_volume_value_changed(value):
	PythonServer.send_message({
		type = "SET_VOLUME",
		device = "local",
		volume = value
	})
	
	if %ToggleVolumeLink.button_pressed:
		%RemoteVolume.value = value
	
	FS.set_pref("settings.local_volume", value)

func _on_remote_volume_value_changed(value):
	PythonServer.send_message({
		type = "SET_VOLUME",
		device = "remote",
		volume = value
	})
	
	if %ToggleVolumeLink.button_pressed:
		%LocalVolume.value = value
	
	FS.set_pref("settings.remote_volume", value)

func _on_play_tts_pressed():
	controls.get_node("Seek").set_value_no_signal(0)
	
	PythonServer.send_message({
		type = "GEN_TTS",
		text = %TTSField.text,
		voice = %TTSVoiceSelection.get_item_text(%TTSVoiceSelection.selected)
	})

func _on_toggle_volume_link_toggled(button_pressed):
	if button_pressed:
		%RemoteVolume.value = %LocalVolume.value
		FS.set_pref("settings.volume_linked", button_pressed)

func _on_tab_container_tab_clicked(tab_index):
	var tab = tabs.get_child(tab_index)
	
	if tab.name == "+":
		tabs.current_tab = tabs.get_previous_tab()
		
		$DirectoryDialog.popup()
		var directory = await $DirectoryDialog.dir_selected
		
		if directory in Soundboard.directories: return
		Soundboard.directories.append(directory)
		
		_update_directories()
		
		FS.set_pref("settings.soundboard_directories", Soundboard.directories)


func _on_tts_voice_selection_item_selected(index):
	FS.set_pref("settings.tts_selected_voice", index)

func _on_export_tts_pressed():
	$SaveFileDialog.popup()
	var file_path = await $SaveFileDialog.file_selected
	
	PythonServer.send_message({
		type = "GEN_TTS",
		text = %TTSField.text,
		voice = %TTSVoiceSelection.get_item_text(%TTSVoiceSelection.selected),
		export = file_path
	})
