extends SceneTree

var _n := 0

func _initialize() -> void:
	print("probe: init")
	_go()

func _go() -> void:
	print("probe: before await")
	await process_frame
	_n += 1
	print("probe: frame %d" % _n)
	if _n >= 3:
		quit(0)
		return
	_go()
