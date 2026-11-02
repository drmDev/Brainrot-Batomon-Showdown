extends Node
## NotificationHost - owns the NotificationManager and the toast views.
##
## Glue only: ticks the manager each frame, maps presented/expired signals to
## ToastView.present()/dismiss(), and restacks visible toasts bottom-up. The
## manager owns scheduling; the view owns rendering. No game-state knowledge.

const ToastView = preload("../hud/toast_view.gd")
const Styles = preload("../hud/styles.gd")

var _manager = null
var _layer: CanvasLayer = null
var _views: Array = []


## manager: a NotificationManager. layer: the CanvasLayer that hosts the views.
func _init(manager = null, layer: CanvasLayer = null) -> void:
	_manager = manager
	_layer = layer
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	if _manager == null:
		return
	if not _manager.presented.is_connected(_on_presented):
		_manager.presented.connect(_on_presented)
	if not _manager.expired.is_connected(_on_expired):
		_manager.expired.connect(_on_expired)
	_build_views()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.connect(_on_viewport_resized)


func _exit_tree() -> void:
	if _manager != null:
		if _manager.presented.is_connected(_on_presented):
			_manager.presented.disconnect(_on_presented)
		if _manager.expired.is_connected(_on_expired):
			_manager.expired.disconnect(_on_expired)
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.disconnect(_on_viewport_resized)


func _process(_delta: float) -> void:
	if _manager != null:
		_manager.tick()


## Forward a request to the manager. Returns the manager's Result, or -1 when the
## host has no manager (should not happen in production).
func submit(request) -> int:
	if _manager == null:
		return -1
	return _manager.submit(request)


func _build_views() -> void:
	if _layer == null or not _views.is_empty():
		return
	for i in range(_manager.max_visible()):
		var view = ToastView.new()
		view.name = "Toast%d" % i
		_layer.add_child(view)
		_views.append(view)


func _on_presented(request, slot: int) -> void:
	if slot < 0 or slot >= _views.size():
		return
	_views[slot].present(request)
	_restack()


func _on_expired(_request, slot: int) -> void:
	if slot < 0 or slot >= _views.size():
		return
	_views[slot].dismiss()
	_restack()


## Stack visible toasts bottom-up: slot 0 sits on the bottom margin, each later
## slot sits above the accumulated height of the ones below it.
func _restack() -> void:
	var offset := 0.0
	for slot in range(_views.size()):
		var view = _views[slot]
		if not view.visible:
			continue
		view.layout()
		view.place_bottom_right(offset)
		offset += view.size.y + Styles.STACK_GAP


func _on_viewport_resized() -> void:
	_restack()
