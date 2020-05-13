extends Control

signal message_sent(text)
onready var button = $Chat/LineEdit/ChatButton
onready var chat = $Chat
onready var edit = $Chat/LineEdit


func _on_ChatButton_pressed():
	if edit.text.empty():
		return
	var text = edit.text
	edit.clear()
	emit_signal("message_sent", text)
