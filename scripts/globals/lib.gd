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

func create_item_instance(node):
	var new_node = node.duplicate()
	new_node.show()
	
	node.queue_free()
	return new_node
