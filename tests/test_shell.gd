extends SceneTree
# AION Gym shell/layout gate: boots the real dashboard,
# walks shell pages, and exercises both dashboard rebuild paths headless.

var _gym: Node = null
var _frames := 0
var _checks := 0
var _fails: Array = []


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/gym.tscn")
	_check(scene != null, "gym.tscn loads")
	if scene == null:
		quit(1)
		return
	_gym = scene.instantiate()
	root.add_child(_gym)
	process_frame.connect(_tick)


func _tick() -> void:
	_frames += 1
	if _frames > 40:
		printerr("LAYOUT GATE RED - probe overran (frames never completed)")
		quit(1)
		return
	match _frames:
		5:
			var shell: Control = _gym.get("_shell")
			_check(shell != null, "app shell built")
			_check(shell.current_page_id() == "dashboard", "dashboard is home")
			_check(_gym._live_values.size() == 6, "portrait dashboard builds 6 live values")
			_check(_gym._stage_panels.size() == 4, "4 stage panels (owner canon)")
			_gym.show_lens("mind_viewer")
		10:
			_check(_gym.current_lens() == "mind_viewer", "lens navigation reaches the mind page")
			_gym.show_lens("habitat")
		15:
			_check(_gym.current_lens() == "habitat", "habitat page (3D viewport) loads")
			_gym.show_dashboard()
		20:
			_check(_gym.current_lens() == "dashboard", "back to dashboard")
			_gym._built_portrait = false
			_gym._rebuild_dashboard()
		25:
			_check(_gym._live_values.size() == 6, "landscape rebuild re-creates live values")
			_check(_gym._stage_panels.size() == 4, "landscape rebuild keeps the stage panels")
			_gym._built_portrait = true
			_gym._rebuild_dashboard()
		30:
			_check(_gym._live_values.size() == 6, "portrait rebuild re-creates live values")
			_check(_gym._journey_label != null and _gym._footer_status != null,
				"journey + footer widgets survive rebuilds")
			_finish()


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("  ok   " + what)
	else:
		_fails.append(what)
		printerr("  FAIL " + what)


func _finish() -> void:
	print("---")
	if _fails.is_empty():
		print("LAYOUT GATE GREEN - %d checks" % _checks)
		quit(0)
	else:
		printerr("LAYOUT GATE RED - %d of %d failed" % [_fails.size(), _checks])
		quit(1)
