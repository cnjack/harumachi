class_name GameSaveStore
extends Node
## SQLite owns persistent progress and settings. Legacy JSON files stay untouched.
## Each operation closes its connection; backups use SQLite's consistent backup API.

const SCHEMA_VERSION := 1
const MAX_SLOTS := 6
var active_slot: int = 1
var _selection_ready := false
var directory := "user://"
var database_path := "user://harumachi.db"
var backup_path := "user://harumachi.backup.db"
var error_message := ""
var recovered_database := false


func _init() -> void:
	var override := OS.get_environment("HARUMACHI_SAVE_DIR")
	if not override.is_empty() and not OS.has_feature("web"):
		set_directory(override)


func set_directory(path: String) -> void:
	active_slot=1;_selection_ready=false
	directory = path
	database_path = path.path_join("harumachi.db")
	backup_path = path.path_join("harumachi.backup.db")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))


func _connect(path: String, create: bool = true) -> SQLite:
	if not create and not FileAccess.file_exists(path):
		return null
	var db := SQLite.new()
	db.path = path
	db.verbosity_level = 0
	if not db.open_db():
		error_message = "无法打开存档数据库：" + db.error_message
		return null
	if not db.query("PRAGMA quick_check"):
		error_message = "存档数据库损坏：" + db.error_message
		db.close_db()
		return null
	var health: Array = db.query_result
	if health.is_empty() or str(health[0].get("quick_check", "")) != "ok":
		error_message = "存档数据库校验失败"
		db.close_db()
		return null
	for sql in [
		"PRAGMA journal_mode=DELETE", "PRAGMA synchronous=FULL", "PRAGMA busy_timeout=3000",
		"CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
		"CREATE TABLE IF NOT EXISTS snapshots (slot TEXT PRIMARY KEY, version INTEGER NOT NULL, payload TEXT NOT NULL, checksum TEXT NOT NULL, saved_at INTEGER NOT NULL)",
		"CREATE TABLE IF NOT EXISTS save_slots (slot INTEGER PRIMARY KEY CHECK(slot BETWEEN 1 AND 6), version INTEGER NOT NULL, payload TEXT NOT NULL, checksum TEXT NOT NULL, saved_at INTEGER NOT NULL)",
		"CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
		"INSERT OR IGNORE INTO metadata(key,value) VALUES ('schema_version','1')",
	]:
		if not db.query(sql):
			error_message = "无法初始化存档数据库：" + db.error_message
			db.close_db()
			return null
	if not db.query("SELECT value FROM metadata WHERE key='schema_version'"):
		db.close_db()
		return null
	var schema: Array = db.query_result
	if schema.is_empty() or int(schema[0].value) != SCHEMA_VERSION:
		error_message = "存档数据库版本不兼容"
		db.close_db()
		return null
	return db


func _open() -> SQLite:
	error_message = ""
	var db := _connect(database_path)
	if db == null and error_message == "存档数据库版本不兼容":
		return null
	if db == null and FileAccess.file_exists(backup_path):
		var backup := _connect(backup_path, false)
		if backup == null:
			return null
		backup.close_db()
		var bad_path := directory.path_join("harumachi.corrupt.%d.db" % Time.get_ticks_usec())
		if FileAccess.file_exists(database_path):
			var moved := DirAccess.rename_absolute(ProjectSettings.globalize_path(database_path), ProjectSettings.globalize_path(bad_path))
			if moved != OK:
				error_message = "无法保留损坏的存档数据库"
				return null
		var copied := DirAccess.copy_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(database_path))
		if copied != OK:
			error_message = "无法恢复存档数据库备份"
			return null
		db = _connect(database_path, false)
		recovered_database = db != null
	if db != null and not _migrate_legacy(db):
		db.close_db()
		return null
	if db!=null:
		# Existing progress becomes position one; migration never overwrites named saves.
		if db.query("SELECT value FROM metadata WHERE key='slots_imported'") and db.query_result.is_empty():
			if db.query("SELECT version,payload,checksum,saved_at FROM snapshots ORDER BY CASE slot WHEN 'current' THEN 0 ELSE 1 END"):
				var original_rows: Array=db.query_result.duplicate(true)
				for row: Dictionary in original_rows:
					var text:=str(row.payload);var data: Variant=JSON.parse_string(text)
					if text.sha256_text()==str(row.checksum) and data is Dictionary and _valid_snapshot(data):
						db.query_with_bindings("INSERT OR IGNORE INTO save_slots VALUES (1,?,?,?,?)",[int(row.version),text,str(row.checksum),int(row.saved_at)])
						break
			db.query("INSERT OR REPLACE INTO metadata(key,value) VALUES ('slots_imported','1')")
		if not _selection_ready:
			if db.query("SELECT value FROM metadata WHERE key='active_slot'") and not db.query_result.is_empty():active_slot=clampi(int(db.query_result[0].value),1,MAX_SLOTS)
			_selection_ready=true
	return db


func _legacy_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}


func _valid_snapshot(data: Dictionary) -> bool:
	if int(data.get("version", -1)) not in [1, 2, 3, 4]:
		return false
	for key in ["coins", "inventory", "key_items", "quests", "flags", "affinity", "placements", "next_uid", "crop_stage", "phase", "player"]:
		if not data.has(key):
			return false
	for key in ["inventory", "key_items", "quests", "flags", "affinity", "player"]:
		if not data[key] is Dictionary:
			return false
	return data.placements is Array


func _insert_snapshot(db: SQLite, slot: String, data: Dictionary) -> bool:
	var text := JSON.stringify(data)
	return db.query_with_bindings("INSERT OR REPLACE INTO snapshots(slot,version,payload,checksum,saved_at) VALUES (?,?,?,?,?)", [slot, int(data.version), text, text.sha256_text(), int(Time.get_unix_time_from_system())])


func _migrate_legacy(db: SQLite) -> bool:
	if not db.query("SELECT value FROM metadata WHERE key='legacy_imported'"):
		return false
	if not db.query_result.is_empty():
		return true
	var main := _legacy_dict(directory.path_join("save.json"))
	var prior := _legacy_dict(directory.path_join("save.bak"))
	var old_settings := _legacy_dict(directory.path_join("settings.json"))
	if not db.query("BEGIN IMMEDIATE"):
		return false
	var ok := true
	if _valid_snapshot(main):
		ok = _insert_snapshot(db, "current", main)
	elif _valid_snapshot(prior):
		ok = _insert_snapshot(db, "current", prior)
	if ok and _valid_snapshot(prior):
		ok = _insert_snapshot(db, "previous", prior)
	for key in old_settings:
		if ok:
			ok = db.query_with_bindings("INSERT OR REPLACE INTO settings(key,value) VALUES (?,?)", [str(key), JSON.stringify(old_settings[key])])
	if ok:
		ok = db.query("INSERT INTO metadata(key,value) VALUES ('legacy_imported','1')")
	return _finish(db, ok)


func _finish(db: SQLite, ok: bool) -> bool:
	if ok and db.query("COMMIT"):
		return true
	error_message = "存档写入失败：" + db.error_message
	db.query("ROLLBACK")
	return false


func save_snapshot(data: Dictionary, requested_slot: int=0) -> bool:
	if requested_slot<0 or requested_slot>MAX_SLOTS:
		error_message="最多支持六个存档位置";return false
	if not _valid_snapshot(data):
		error_message = "存档内容不完整，未覆盖原有进度"
		return false
	var db := _open()
	if db == null:
		return false
	var target: int=requested_slot if requested_slot!=0 else active_slot
	if not db.backup_to(ProjectSettings.globalize_path(backup_path)):
		error_message = "无法备份原有存档：" + db.error_message
		db.close_db()
		return false
	var ok := db.query("BEGIN IMMEDIATE")
	var working_slot:=1
	if ok and db.query("SELECT value FROM metadata WHERE key='active_slot'") and not db.query_result.is_empty():working_slot=int(db.query_result[0].value)
	var valid_current := false
	if ok: ok = db.query("SELECT payload,checksum FROM snapshots WHERE slot='current'")
	if ok and not db.query_result.is_empty():
		var current_row: Dictionary = db.query_result[0]
		var current_payload: String = str(current_row.payload)
		var current_value: Variant = JSON.parse_string(current_payload)
		valid_current = current_payload.sha256_text() == str(current_row.checksum) and current_value is Dictionary and _valid_snapshot(current_value)
	# After recovery, preserve the valid previous snapshot instead of rotating corrupt current over it.
	if ok and (working_slot != target or valid_current):
		ok = db.query("DELETE FROM snapshots WHERE slot='previous'")
	if ok and working_slot==target and valid_current:
		ok = db.query("INSERT INTO snapshots SELECT 'previous',version,payload,checksum,saved_at FROM snapshots WHERE slot='current'")
	if ok:
		ok = _insert_snapshot(db, "current", data)
	if ok:
		var text:=JSON.stringify(data)
		ok=db.query_with_bindings("INSERT OR REPLACE INTO save_slots(slot,version,payload,checksum,saved_at) VALUES (?,?,?,?,?)",[target,int(data.version),text,text.sha256_text(),int(Time.get_unix_time_from_system())])
	if ok:ok=db.query_with_bindings("INSERT OR REPLACE INTO metadata(key,value) VALUES ('active_slot',?)",[str(target)])
	ok = _finish(db, ok)
	db.close_db()
	if ok:
		active_slot=target;_selection_ready=true
		_notify_browser_sync()
	return ok


func select_slot(slot: int) -> bool:
	if slot<1 or slot>MAX_SLOTS:error_message="最多支持六个存档位置";return false
	active_slot=slot;_selection_ready=true;return true


func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary]=[]
	for index in MAX_SLOTS:out.append({"slot":index+1,"empty":true})
	var db:=_open()
	if db==null:return out
	if db.query("SELECT slot,payload,checksum,saved_at FROM save_slots ORDER BY slot"):
		for row: Dictionary in db.query_result:
			var text:=str(row.payload);var data: Variant=JSON.parse_string(text)
			var valid: bool=text.sha256_text()==str(row.checksum) and data is Dictionary and _valid_snapshot(data)
			var slot:=int(row.slot)
			if slot<1 or slot>MAX_SLOTS:continue
			out[slot-1]={"slot":slot,"empty":false,"valid":valid,"day":int(data.get("day",1)) if data is Dictionary else 0,"minute":float(data.get("minute",480)) if data is Dictionary else 0.0,"coins":int(data.get("coins",0)) if data is Dictionary else 0,"region":str(data.get("player_region","town")) if data is Dictionary else "town","saved_at":int(row.saved_at)}
	db.close_db();return out


func load_slot(slot: int) -> Dictionary:
	if slot<1 or slot>MAX_SLOTS:error_message="最多支持六个存档位置";return {}
	var db:=_open()
	if db==null:return {}
	var row: Dictionary={}
	if db.query_with_bindings("SELECT payload,checksum FROM save_slots WHERE slot=?",[slot]) and not db.query_result.is_empty():row=db.query_result[0]
	if row.is_empty():error_message="这个位置还没有存档";db.close_db();return {}
	var text:=str(row.payload);var data: Variant=JSON.parse_string(text)
	if text.sha256_text()!=str(row.checksum) or not data is Dictionary or not _valid_snapshot(data):error_message="这个存档无法读取，原有进度已保留";db.close_db();return {}
	var ok:=db.query("BEGIN IMMEDIATE")
	if ok:ok=db.query("DELETE FROM snapshots")
	if ok:ok=_insert_snapshot(db,"current",data)
	if ok:ok=db.query_with_bindings("INSERT OR REPLACE INTO metadata(key,value) VALUES ('active_slot',?)",[str(slot)])
	ok=_finish(db,ok);db.close_db()
	if not ok:return {}
	active_slot=slot;_selection_ready=true;_notify_browser_sync();return data


func load_candidates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var db := _open()
	if db == null:
		return out
	if db.query("SELECT slot,payload,checksum FROM snapshots ORDER BY CASE slot WHEN 'current' THEN 0 ELSE 1 END"):
		var rows: Array = db.query_result
		for row in rows:
			var text := str(row.payload)
			if text.sha256_text() != str(row.checksum):
				continue
			var data: Variant = JSON.parse_string(text)
			if data is Dictionary and _valid_snapshot(data):
				out.append({"slot": str(row.slot), "data": data})
	db.close_db()
	return out


func has_save() -> bool:
	return not load_candidates().is_empty()


func load_settings() -> Dictionary:
	var out := {}
	var db := _open()
	if db == null:
		return out
	if db.query("SELECT key,value FROM settings"):
		var rows: Array = db.query_result
		for row in rows:
			out[str(row.key)] = JSON.parse_string(str(row.value))
	db.close_db()
	return out


func save_settings(values: Dictionary) -> bool:
	var db := _open()
	if db == null:
		return false
	var ok := db.query("BEGIN IMMEDIATE")
	for key in values:
		if ok:
			ok = db.query_with_bindings("INSERT OR REPLACE INTO settings(key,value) VALUES (?,?)", [str(key), JSON.stringify(values[key])])
	ok = _finish(db, ok)
	db.close_db()
	if ok:
		_notify_browser_sync()
	return ok


func _notify_browser_sync() -> void:
	if not OS.has_feature("web"):
		return
	# SQLite writes through libc; this FileAccess close also marks Godot's user FS dirty.
	var marker := FileAccess.open(directory.path_join(".sqlite-sync"), FileAccess.WRITE)
	if marker:
		marker.store_64(int(Time.get_unix_time_from_system()))
		marker.close()
