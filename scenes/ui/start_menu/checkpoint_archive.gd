extends RefCounted

const SUFFIXES: Array[String] = ["", ".bak", ".tmp", ".pending"]
var error: String = ""
var archive_path: String = ""

func observe(path: String) -> Dictionary:
	error = ""
	var files: Dictionary = {}
	for suffix: String in SUFFIXES:
		if not FileAccess.file_exists(path + suffix):
			continue
		var digest: String = FileAccess.get_sha256(path + suffix)
		if digest.is_empty():
			error = "Could not read the existing save."
			return {}
		files[suffix] = digest
	return files

func archive(path: String, expected: Dictionary) -> bool:
	archive_path = ""
	var current: Dictionary = observe(path)
	if not error.is_empty():
		return false
	if current != expected:
		error = "The save changed. Please choose New Game again."
		return false
	if current.is_empty():
		return true
	var folder: String = path.get_base_dir().path_join("archive/checkpoint-%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()])
	if DirAccess.dir_exists_absolute(folder) or DirAccess.make_dir_recursive_absolute(folder) != OK:
		error = "Could not create a backup folder."
		return false
	var moved: Array[String] = []
	for suffix: String in SUFFIXES:
		if not current.has(suffix):
			continue
		var source: String = path + suffix
		var destination: String = folder.path_join(source.get_file())
		if FileAccess.get_sha256(source) != current[suffix] or DirAccess.rename_absolute(source, destination) != OK:
			for previous: String in moved:
				var original: String = path + previous
				if FileAccess.file_exists(original) or DirAccess.rename_absolute(folder.path_join(original.get_file()), original) != OK:
					push_error("Checkpoint remains in archive: " + folder)
			error = "Could not archive the save. Files were preserved."
			return false
		moved.append(suffix)
	archive_path = folder
	return true
