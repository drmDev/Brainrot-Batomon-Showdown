extends RefCounted
## NotificationManager - schedules toasts: FIFO queue, N visible slots, expiry.
##
## Pure scheduling: no nodes, no UI, no repo dependencies. The host calls tick()
## each frame; the manager decides what is visible and when a slot frees.
##
## Rules:
## - At most max_visible toasts are visible at once (default 3, clamped to >= 1).
## - Extra requests wait in a FIFO queue and are promoted when a slot frees.
## - A promoted toast's timer starts when it is promoted, not when it was submitted.
## - A request whose event_key is already visible or pending is dropped, unless
##   request.allow_duplicate is true. Dropped requests are never queued.
## - An invalid request (empty event_key or title) is rejected.
##
## Signals are the seam for sound and animation: they fire independently of the
## queue state. submitted fires for every request, including queued and dropped.

signal submitted(request, result)
signal presented(request, slot)
signal expired(request, slot)

enum Result { REJECTED_INVALID, DROPPED_DUPLICATE, SHOWN, QUEUED }

const DEFAULT_MAX_VISIBLE := 3
const FALLBACK_DURATION_MS := 4000  # matches NotificationRequest.DEFAULT_DURATION_MS

var _max_visible: int
var _now_fn: Callable
var _pending: Array = []   # FIFO of requests waiting for a slot
var _visible: Array = []   # slot index -> request or null
var _expires: Array = []   # slot index -> expiry time in ms (0 when empty)


## max_visible: simultaneous toast slots. now_fn: optional clock (tests inject).
func _init(max_visible: int = DEFAULT_MAX_VISIBLE, now_fn: Callable = Callable()) -> void:
	_max_visible = maxi(1, max_visible)
	_now_fn = now_fn
	_visible.resize(_max_visible)
	_expires.resize(_max_visible)


## Submit one request. Returns a Result value describing what happened.
func submit(request) -> int:
	if request == null or not request.is_valid():
		submitted.emit(request, Result.REJECTED_INVALID)
		return Result.REJECTED_INVALID

	if not request.allow_duplicate and _is_duplicate(request):
		submitted.emit(request, Result.DROPPED_DUPLICATE)
		return Result.DROPPED_DUPLICATE

	var slot := _free_slot()
	if slot >= 0 and _pending.is_empty():
		_show(request, slot)
		submitted.emit(request, Result.SHOWN)
		return Result.SHOWN

	_pending.append(request)
	submitted.emit(request, Result.QUEUED)
	return Result.QUEUED


## Expire due toasts, then promote queued requests into freed slots. Call each frame.
func tick() -> void:
	var now := _now()
	for slot in range(_max_visible):
		var request = _visible[slot]
		if request == null:
			continue
		if now >= int(_expires[slot]):
			_visible[slot] = null
			_expires[slot] = 0
			expired.emit(request, slot)
	if not _pending.is_empty():
		_promote()


func max_visible() -> int:
	return _max_visible


func _show(request, slot: int) -> void:
	_visible[slot] = request
	_expires[slot] = _now() + _duration_for(request)
	presented.emit(request, slot)


func _promote() -> void:
	while not _pending.is_empty():
		var slot := _free_slot()
		if slot < 0:
			return
		_show(_pending.pop_front(), slot)


func _free_slot() -> int:
	for slot in range(_max_visible):
		if _visible[slot] == null:
			return slot
	return -1


func _is_duplicate(request) -> bool:
	var key := str(request.event_key)
	for visible in _visible:
		if visible != null and str(visible.event_key) == key:
			return true
	for pending in _pending:
		if str(pending.event_key) == key:
			return true
	return false


func _duration_for(request) -> int:
	var duration := int(request.duration_ms)
	if duration <= 0:
		duration = FALLBACK_DURATION_MS
	return duration


func _now() -> int:
	if _now_fn.is_valid():
		return int(_now_fn.call())
	return Time.get_ticks_msec()
