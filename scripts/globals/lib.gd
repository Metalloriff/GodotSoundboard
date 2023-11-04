extends Node

func create_uid(length: int = 7):
	const characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	var id = ""
	
	for i in range(length):
		id += characters.substr(randi() % len(characters), 1)
	
	return id

func rand_chance(chance: float):
	if chance >= 100.0:
		return true
	
	return randf() <= (chance / 100.0)

func time(): return Time.get_ticks_msec() / 1000.0

func wait_for_seconds(length: float):
	await get_tree().create_timer(length).timeout

func transition(length: float, callback: Callable, backwards: bool = false):
	var start = time()
	
	while time() - start < length:
		var val = clampf((time() - start) / length, 0.0, 1.0)
		callback.call(val if not backwards else 1.0 - val)
		
		await get_tree().process_frame
	
	callback.call(1.0 if not backwards else 0.0)

func debounce(length: float, action: Callable) -> Callable:
	var _debouncer := {
		timer = null
	}
	
	return func(args = null):
		if is_instance_valid(_debouncer.timer) and not _debouncer.timer.is_stopped():
			_debouncer.timer.stop()
			_debouncer.timer.queue_free()
		
		_debouncer.timer = Timer.new()
		_debouncer.timer.wait_time = length
		_debouncer.timer.timeout.connect(func():
			_debouncer.timer.queue_free()
			
			if action.get_object() == null:
				return
			
			if args is Array:
				action.callv(args)
			else:
				action.call()
		)
		
		add_child(_debouncer.timer)
		_debouncer.timer.start()

func find_parent_node(node: Node, condition: Callable) -> Variant:
	var parent = node.get_parent()
	
	while parent != $/root:
		if condition.call(parent):
			return parent
		parent = parent.get_parent()
	
	return null

func find_child_nodes(parent_node: Node, condition: Variant = null) -> Array:
	var nodes = []
	var children = parent_node.get_children()
	
	for child in children:
		if not condition or condition.call(child):
			nodes.append(child)
		
		if child.get_child_count() > 0:
			nodes += find_child_nodes(child, condition)
	
	return nodes

func clear_child_nodes(parent_node: Node) -> void:
	for node in parent_node.get_children():
		node.queue_free()

# Regex functions
func regex_get_matches(pattern: String, search: String) -> Array:
	var regex = RegEx.new()
	regex.compile(pattern)
	
	return regex.search_all(search)

func regex_get_matches_str(pattern: String, search: String):
	var output = []
	
	for m in regex_get_matches(pattern, search):
		output.append(m.get_string())
	
	return output

# Other functions
func pascal_case_to_spaces(input: String) -> String:
	return " ".join(regex_get_matches_str("[A-Z][^A-Z]*", input))

func get_prop(dictionary: Dictionary, path: Array) -> Variant:
	var walk = dictionary
	
	for entry in path:
		if entry == path[-1]: return walk[entry]
		if entry not in walk: return null
		
		walk = walk[entry]
	return null

func set_prop(dictionary: Dictionary, path: Array, new_value: Variant) -> Dictionary:
	var walk = dictionary
	
	for entry in path:
		if typeof(entry) == typeof(path[-1]) and entry == path[-1]:
			walk[entry] = new_value
			return dictionary
		
		if entry not in walk: walk[entry] = {}
		walk = walk[entry]
	return dictionary

func play_audio_at_point(point: Vector3, audio: Variant, volume_range: Array[float] = [50, 50],\
						pitch_range: Array[float] = [1, 1], max_distance: float = 20) -> void:
	if audio is String: audio = load(audio)
	var player = AudioStreamPlayer3D.new()
	
	player.stream = audio
	player.max_distance = max_distance
	player.pitch_scale = randf_range(pitch_range[0], pitch_range[1])
	player.volume_db = randf_range(volume_range[0], volume_range[1])
	player.finished.connect(player.queue_free)
	
	get_tree().get_root().add_child(player)
	player.global_transform.origin = point
	player.play()

func extend(input: Variant, properties: Dictionary) -> Variant:
	for prop_name in properties:
		if not prop_name in input: continue
		
		input[prop_name] = properties[prop_name]
	return input

func create_item_instance(node):
	var new_node = node.duplicate()
	new_node.show()
	
	node.queue_free()
	return new_node

func add_timer(target: Node, wait_time: float, callback: Callable) -> Timer:
	var timer := Timer.new()
	timer.wait_time = wait_time
	timer.autostart = true
	timer.timeout.connect(callback)
	target.add_child(timer)
	
	return timer
