extends "test_runner.gd"
## Unit tests for hud/toast_view.gd badge rendering selection.

const ToastView = preload("../hud/toast_view.gd")
const NotificationRequest = preload("../notifications/notification_request.gd")


func _texture() -> Texture2D:
	return ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))


func _request(icon_texture = null) -> NotificationRequest:
	var request = NotificationRequest.new(
		NotificationRequest.KIND_REACTION,
		"over_9000",
		"IT'S OVER 9000!",
		"detail",
	)
	request.icon_texture = icon_texture
	return request


func test_present_with_texture_hides_badge_label() -> void:
	var view = ToastView.new()
	var tex := _texture()
	view.present(_request(tex))
	assert_eq(view._badge_texture, tex)
	assert_false(view._badge_label.visible)
	view.free()


func test_present_without_texture_shows_badge_label() -> void:
	var view = ToastView.new()
	view.present(_request(null))
	assert_eq(view._badge_texture, null)
	assert_true(view._badge_label.visible)
	view.free()
