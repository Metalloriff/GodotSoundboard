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

var favorites: Dictionary
var playing_node: Node
var search_tags: Array[String]

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
		
		var search_field_container := tab_item.get_node("MarginContainer/VBoxContainer/SearchField")
		search_field_container.get_node("LineEdit").text_changed.connect(func(search_text):
			search_soundboard(tab_items, search_text)
			search_field_container.get_node("ClearButton").visible = len(search_text) > 0
		)
		
		search_field_container.get_node("ClearButton").pressed.connect(func():
			search_field_container.get_node("LineEdit").text = ""
			search_field_container.get_node("LineEdit").text_changed.emit("")
		)
		
		var tags_container := tab_item.get_node("MarginContainer/VBoxContainer/Tags")
		
		tags_container.get_node("Favorites").pressed.connect(func():
			if "favorites" in search_tags:
				search_tags.erase("favorites")
			else:
				search_tags.append("favorites")
			
			search_soundboard(tab_items, search_field_container.get_node("LineEdit").text)
		)
		
		for fp in files:
			add_soundboard_item(tab_items, fp)
	
	tabs.move_child(tabs.get_node("+"), -1)

func search_soundboard(container, search_text: String):
	var is_favorited := func(item: Node) -> bool:
		var fp: String = item.get_meta("fp")
		return fp in favorites[fp.get_base_dir()]
	
	var validate_tags := func(item: Node) -> bool:
		return \
			("favorites" not in search_tags or is_favorited.call(item))
	
	for child in container.get_children():
		if child.has_node("ItemsContainer/Items"):
			search_soundboard(child.get_node("ItemsContainer/Items"), search_text)
			continue
		
		if not search_text.strip_edges() and validate_tags.call(child):
			child.show()
		else:
			child.visible = search_text.to_lower() in child.get_node("Contents/Name").text.to_lower()
	
	for child in container.get_children():
		if not child.has_node("ItemsContainer/Items"): continue
		var visible_items = child.get_node("ItemsContainer/Items").get_children().filter(func(c): return c.visible)
		
		child.get_node("Button/Contents/Count").text = "%s items  " % str(len(visible_items))
		child.visible = len(visible_items) > 0 and validate_tags.call(child)

func add_soundboard_item(container: Node, _fp: String):
	var item := soundboard_item.duplicate()
	container.add_child(item)
	
	item.name = _fp.validate_node_name()
	item.set_meta("fp", _fp)

	item.pressed.connect(func():
		playing_node = item
		
		if Soundboard.is_playing:
			_on_play_pressed()
		else:
			controls.get_node("Seek").set_value_no_signal(0)
			Soundboard.play(item.get_meta("fp"))
	)
	
	item.get_node("Contents/Name").text = _fp.get_file().get_basename()
	
	var base_dir := _fp.get_base_dir()
	var pref_path := "favorites.%s" % base_dir.get_file()
	if not base_dir in favorites:
		favorites[base_dir] = FS.get_pref(pref_path, [])
	
	var favorite_button := item.get_node("Contents/Right/FavoriteButton")
	favorite_button.pressed.connect(func():
		var fp = item.get_meta("fp")
		var is_favorited = fp in favorites[base_dir]
		is_favorited = not is_favorited
		
		favorite_button.modulate =\
			Color("#ff4f64") if is_favorited\
			else Color.WHITE
		favorite_button.icon = favorite_button.get_meta("icon_filled" if is_favorited else "icon")
		
		if is_favorited and not fp in favorites[base_dir]:
			favorites[base_dir].append(fp)
		if not is_favorited and fp in favorites[base_dir]:
			favorites[base_dir].erase(fp)
		FS.set_pref(pref_path, favorites[base_dir])
	)
	
	var is_favorited = _fp in favorites[base_dir]
	favorite_button.modulate =\
		Color("#ff4f64") if is_favorited\
		else Color.WHITE
	favorite_button.icon = favorite_button.get_meta("icon_filled" if is_favorited else "icon")
	
	item.get_node("Contents/Right/MoreOptions").get_popup().id_pressed.connect(func(id):
		match id:
			0:
				var rename_dialog := $RenameDialog
				var field := $RenameDialog/Field
				var fp = item.get_meta("fp")
				
				field.text = fp.get_file().get_basename()
				rename_dialog.popup()
				
				rename_dialog.canceled.connect(func():
					field.text = ""
					rename_dialog.confirmed.emit()
				)
				
				await rename_dialog.confirmed
				
				if not len(field.text.validate_filename()): return
				
				var new_fp = fp.get_base_dir().path_join(field.text.validate_filename()) + "." + fp.get_extension()
				DirAccess.rename_absolute(fp, new_fp)
				
				if fp in favorites[base_dir]:
					var idx = favorites[base_dir].find(fp)
					
					favorites[base_dir][idx] = new_fp
					FS.set_pref(pref_path, favorites[base_dir])
				
				item.name = new_fp.validate_node_name()
				item.set_meta("fp", new_fp)
				item.get_node("Contents/Name").text = new_fp.get_file().get_basename()
				
				rename_dialog.canceled.emit()
			1:
				open_files_in_audacity([item.get_meta("fp")])
	)

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

func _on_stop_pressed():
	PythonServer.send_message({
		type = "SEEK",
		seek = controls.get_node("Seek").max_value
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

func _on_tts_field_text_submitted(new_text):
	_on_play_tts_pressed()

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

func open_files_in_audacity(files: Array):
	while not FS.get_pref("audio_editor_path", ""):
		$FileDialog.popup_centered()
		FS.set_pref("audio_editor_path", await $FileDialog.file_selected)
		$FileDialog.hide()
	
	var lof = FileAccess.open("user://audacity.lof", FileAccess.WRITE)
	lof.store_line("window")
	for file in files:
		lof.store_line('file "%s"' % file)
	
	OS.create_process(FS.get_pref("audio_editor_path"), [OS.get_user_data_dir().path_join("audacity.lof")])
