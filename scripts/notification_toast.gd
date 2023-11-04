extends MarginContainer
class_name NotificationToast

static var TOAST_TYPE := {
	ERROR = {
		color = "#ff5555",
		label = "ERROR"
	},
	SUCCESS = {
		color = "#55ff55",
		label = "SUCCESS"
	}
}

@onready var timer := $Timer

func _ready():
	modulate.a = 0.0
	hide()

func show_message(message: String, type: Dictionary):
	modulate = Color(type.color, modulate.a)
	$PanelContainer/MarginContainer/VBoxContainer/Label.text = type.label
	$PanelContainer/MarginContainer/VBoxContainer/Body.text = message
	
	show()
	await get_tree().create_tween().tween_property(self, "modulate:a", 1.0, 0.75).finished
	
	timer.wait_time = len(message) / 10.0
	timer.start()

func _on_timer_timeout():
	await get_tree().create_tween().tween_property(self, "modulate:a", 0.0, 2.0).finished
	hide()
