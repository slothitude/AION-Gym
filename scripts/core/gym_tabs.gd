extends Control
##
## AION Gym — bottom navigation bar: multi-tap tabs that switch the shell's
## pages. Asset-free by design: text tabs with an active accent underline.
##
## Fork provenance: the bottom multi-tap tab bar PATTERN is adapted from the
## Ant's Godot console's tab bar and rebuilt here as an AION Gym component —
## renamed, no Ant's art or code. See docs/FORK_NOTES.md.

signal tab_changed(tab_id: String)

const TAB_HEIGHT: float = 56.0
const COLOR_BG := Color("101418")
const COLOR_ACCENT := Color("5aa9ff")
const COLOR_TEXT := Color("f5f5f5")
const COLOR_SUB := Color("7d8b99")

const TABS: Array = [
	["dashboard", "Dashboard"],
	["habitat", "Habitat"],
	["mind_viewer", "Mind"],
	["training_world", "Training"],
	["memory_archive", "Memory"],
	["control_room", "Control"],
]

var _buttons: Dictionary = {}    # tab id -> Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(0, TAB_HEIGHT)
	var bg := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG
	bg.add_theme_stylebox_override("panel", style)
	add_child(bg)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	for tab in TABS:
		row.add_child(_make_tab(str(tab[0]), str(tab[1])))


## Mark a tab active without emitting (sync when navigation happens elsewhere,
## e.g. keyboard shortcuts or in-page buttons).
func reflect(tab_id: String) -> void:
	for tid in _buttons.keys():
		var b: Button = _buttons[tid]
		_style_tab(b, tid == tab_id)


func _make_tab(tab_id: String, label_text: String) -> Button:
	var b := Button.new()
	b.text = label_text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, TAB_HEIGHT)
	b.pressed.connect(func() -> void: tab_changed.emit(tab_id))
	_buttons[tab_id] = b
	_style_tab(b, tab_id == "dashboard")
	return b


func _style_tab(b: Button, active: bool) -> void:
	b.flat = true
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", COLOR_ACCENT if active else COLOR_SUB)
	b.add_theme_color_override("font_hover_color", COLOR_TEXT)
	b.add_theme_color_override("font_pressed_color", COLOR_ACCENT)
