extends RefCounted
var t: Node
func _init(runner: Node) -> void: t = runner
func run() -> void:
	GameState.new_game()
	GameState.clock_paused = true
	GameState.quests.Q00 = {"state": "done", "step": 2}
	GameState.quests.Q11 = {"state": "done", "step": 3}
	GameState.quests.Q13 = {"state": "active", "step": 1}
	GameState.minute = 10 * 60
	await t.main.go_farm()
	await t.use("tanaka", [0, 0])
	t.check("SPACE_ENTRY", "new space practice starts in daytime without six wood deliveries", str(GameState.flags.get("summer_space", {}).get("phase", "invitation")) != "invitation" and GameState.at_step("Q13", "carry_wood") and not GameState.has("wood"))
