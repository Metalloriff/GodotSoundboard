extends Node

var _cache = {}

func _cache_directory(path: String):
	var dir = DirAccess.open(path)
	if not dir:
		print("Directory not found! Directory: " + path)
		
		return {
			"directories": [],
			"files": []
		}
	
	dir.list_dir_begin()
	
	var _files = dir.get_files()
	var files = []
	
	for file_name in _files:
		files.append(file_name.replace(".import", "").replace(".remap", ""))
	
	dir.list_dir_end()
	
	_cache[path] = {
		"directories": dir.get_directories(),
		"files": files
	}
	
	return _cache[path]

func mkdir(path: String):
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)

func get_files(path: String, use_cache: bool = true):
	var files = []
	
	if not use_cache or path not in _cache:
		files = _cache_directory(path).files
	else:
		files = _cache[path].files
	
	return files

func get_files_recursive(path: String):
	var files = []
	var dir = DirAccess.open(path)
	
	dir.list_dir_begin()
	
	while true:
		var file_name = dir.get_next()
		if file_name == "": break
		
		var file_path = path + file_name
		if not path.ends_with("/"): file_path = path + "/" + file_name
		
		if dir.current_is_dir():
			files += get_files_recursive(file_path)
		else:
			files.append(file_path.replace(".remap", ""))
	
	return files

func get_directories(path: String, use_cache: bool = true):
	var dirs = []
	
	if not use_cache or path not in _cache:
		dirs = _cache_directory(path).directories
	else:
		dirs = _cache[path].directories
	
	return dirs

func ls(path: String, use_cache: bool = true):
	if not use_cache or path not in _cache:
		return _cache_directory(path)
	else:
		return _cache[path]

func save_data(path: String, data: Variant):
	if "contains_errors" in data and data.contains_errors == true:
		print("Warning! Not saving data at ", path, " because it contains errors from previous load!")
		return
	
	path = "user://" + path
	var dir = path.split("/")
	var file_name = dir[-1]
	dir.remove_at(len(dir) - 1)
	FS.mkdir("/".join(dir))
	
	if "." not in file_name:
		path += ".json"
	
	var save = FileAccess.open(path, FileAccess.WRITE)
	save.store_line(JSON.stringify(data))
	save.close()

func load_data(path: String, default: Variant = {}):
	path = "user://" + path
	var dir = path.split("/")
	var file_name = dir[-1]
	dir.remove_at(len(dir) - 1)
	FS.mkdir("/".join(dir))
	
	if "." not in file_name:
		path += ".json"
	
	if not FileAccess.file_exists(path):
		return default
	
	var save = FileAccess.open(path, FileAccess.READ)
	var json_string = save.get_line()
	save.close()
	
	var json = JSON.new()
	var result = json.parse(json_string)
	
	if result != OK:
		print("Error loading save data at ", path)
		print("JSON parse error: ", json.get_error_message())
		print("JSON data: ", json_string)
		
		default.merge({
			"contains_errors": true
		})
		
		return default
	return json.get_data()

func get_pref(prop_name: String, default_value: Variant = null, save_if_default: bool = false) -> Variant:
	var split = prop_name.split(".")
	var file_name = split[0] if len(split) > 1 else "prefs"
	var pref_name = split[1] if len(split) > 1 else split[0]
	
	var data = load_data("prefs/" + file_name)
	
	if pref_name in data:
		return data[pref_name]
	else:
		if save_if_default:
			set_pref(prop_name, default_value)
		
		return default_value

func set_pref(prop_name: String, value: Variant) -> void:
	var split = prop_name.split(".")
	var file_name = split[0] if len(split) > 1 else "prefs"
	var pref_name = split[1] if len(split) > 1 else split[0]
	
	var data = load_data("prefs/" + file_name)
	data[pref_name] = value
	save_data("prefs/" + file_name, data)

func join_path(paths: Array[String]) -> String:
	var output = ""
	
	for path in paths:
		output += path if path.ends_with("/") or path == paths[-1] else (path + "/")
	
	return output
