extends Control
##
## AION Gym — application shell: a full-rect page container with slide
## transitions, safe-area placement and back navigation (Android back button,
## Escape).
##
## Fork provenance: the page/navigation PATTERN is adapted from the Ant's
## Godot console (safe-area placement, tween slide with instant headless
## transitions, WM_GO_BACK_REQUEST handling) and rebuilt here as an AION Gym
## component — renamed, asset-free, no Ant's code or branding. See
## docs/FORK_NOTES.md.
##
## Pages are registered Controls; exactly one is on screen. `back()` returns
## to the home page. Transitions animate with tweens in a GUI session and are
## instant under --headless so gates stay deterministic.

signal page_changed(page_id: String)

const HOME_PAGE: String = "dashboard"
const SLIDE_SECONDS: float = 0.22

var _pages: Dictionary = {}      # id -> Control
var _order: Array = []           # registration order; index 0 = home
var _current_id: String = ""

var m_left := 0.0
var m_top := 0.0
var m_right := 0.0
var m_bottom := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_on_resized)
	# layout runs after the tree enters; compute margins once size is real
	_on_resized.call_deferred()


## Register a page (a full-rect Control). Index 0 registered becomes home.
func register_page(page_id: String, page: Control) -> void:
	if _pages.has(page_id):
		push_warning("AppShell: page '%s' already registered" % page_id)
		return
	_pages[page_id] = page
	_order.append(page_id)
	add_child(page)
	var offscreen := _page_width() if page_id != HOME_PAGE else 0.0
	page.visible = page_id == HOME_PAGE
	_place(page, offscreen)
	if page_id == HOME_PAGE:
		_current_id = page_id


func current_page_id() -> String:
	return _current_id


func has_page(page_id: String) -> bool:
	return _pages.has(page_id)


## Bring a registered page on screen; the previous page slides out and is
## hidden when its transition ends (exclusive visibility at rest).
func show_page(page_id: String, animate := true) -> bool:
	if not _pages.has(page_id):
		push_warning("AppShell: unknown page '%s'" % page_id)
		return false
	if page_id == _current_id:
		return true
	var old: Control = null
	if _current_id != "" and _pages.has(_current_id):
		old = _pages[_current_id]
	var page: Control = _pages[page_id]
	_slide(page, _page_width(), 0.0, animate)
	if old != null:
		_slide(old, 0.0, -_page_width(), animate, true)
	_current_id = page_id
	page_changed.emit(page_id)
	return true


## Return to the home page. Returns true when a navigation happened.
func back() -> bool:
	if _current_id == HOME_PAGE or _current_id == "":
		return false
	show_page(HOME_PAGE)
	return true


## Integrity check: true when more than one registered page is visible at
## once (which would mean the shell's exclusive-page invariant broke).
func visible_pages_overlap() -> bool:
	var visible := 0
	for page_id in _pages.keys():
		var page: Control = _pages[page_id]
		if page.visible:
			visible += 1
	return visible > 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()


func _page_width() -> float:
	return size.x


func _compute_safe_margins() -> void:
	var screen := DisplayServer.screen_get_size()
	if screen.x <= 0:
		return
	var safe := DisplayServer.get_display_safe_area()
	var k := size.x / float(screen.x)
	m_left = safe.position.x * k
	m_top = safe.position.y * k
	m_right = (screen.x - safe.end.x) * k
	m_bottom = (screen.y - safe.end.y) * k


func _on_resized() -> void:
	_compute_safe_margins()
	for page_id in _pages.keys():
		var page: Control = _pages[page_id]
		_place(page, 0.0 if page_id == _current_id else _page_width())


## Places a page at horizontal offset x, respecting safe-area margins.
func _place(page: Control, x: float) -> void:
	page.offset_left = x + m_left
	page.offset_right = x - m_right
	page.offset_top = m_top
	page.offset_bottom = -m_bottom


## Slide one page between horizontal offsets. Instant under --headless so
## gate assertions stay deterministic. hide_after hides the page when the
## transition ends (used for the outgoing page).
func _slide(page: Control, from_x: float, to_x: float, animate: bool, hide_after := false) -> void:
	page.visible = true
	if not animate or DisplayServer.get_name() == "headless":
		_place(page, to_x)
		if hide_after:
			page.visible = false
		return
	page.offset_left = from_x + m_left
	page.offset_right = from_x - m_right
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(page, "offset_left", to_x + m_left, SLIDE_SECONDS) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(page, "offset_right", to_x - m_right, SLIDE_SECONDS) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	if hide_after:
		tw.finished.connect(func() -> void: page.visible = false)
