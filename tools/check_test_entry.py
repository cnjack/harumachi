#!/usr/bin/env python3
"""Check accidental tests.tscn launch with a disposable database and real SceneTree."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PROBE = '''extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var scene: Node = load("res://scenes/tests.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for index in 8: await process_frame
	var at_title: bool = current_scene != null and current_scene.scene_file_path == "res://scenes/title.tscn"
	var main_started: bool = not root.find_children("World", "Node3D", true, false).is_empty()
	print("TEST_ENTRY_PROBE " + JSON.stringify({"at_title":at_title,"main_started":main_started}))
	quit(0 if at_title and not main_started else 1)
'''


def main():
    with tempfile.TemporaryDirectory(prefix="harumachi-test-entry-") as directory:
        folder = Path(directory)
        script = folder / "probe.gd"
        script.write_text(PROBE)
        database = folder / "harumachi.db"
        with sqlite3.connect(database) as connection:
            connection.execute("CREATE TABLE guard_marker (value TEXT)")
            connection.execute("INSERT INTO guard_marker VALUES ('preserve this database')")
        result = subprocess.run(
            [str(ROOT / "tools/godot"), "--headless", "--audio-driver", "Dummy",
             "--path", str(ROOT / "game"), "--script", str(script)],
            cwd=ROOT, env=dict(os.environ, HARUMACHI_SAVE_DIR=directory),
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180,
        )
        records = [line.removeprefix("TEST_ENTRY_PROBE ") for line in result.stdout.splitlines()
                   if line.startswith("TEST_ENTRY_PROBE ")]
        observed = json.loads(records[-1]) if records else {}
        with sqlite3.connect(database) as connection:
            marker_exists = connection.execute(
                "SELECT count(*) FROM sqlite_master WHERE name='guard_marker'"
            ).fetchone()[0]
            marker = connection.execute("SELECT value FROM guard_marker").fetchone()[0] if marker_exists else None
        passed = (result.returncode == 0 and observed.get("at_title") is True
                  and observed.get("main_started") is False and marker == "preserve this database"
                  and "SCRIPT ERROR" not in result.stdout)
        print(json.dumps({"passed": passed, "exit_code": result.returncode,
                          "database_preserved": marker == "preserve this database", **observed}, indent=2))
        if not passed:
            print(result.stdout)
        return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
