extends HBoxContainer

signal on_Matchmake_pressed
signal on_Create_pressed
signal on_Join_pressed
onready var button_matchmake = $Matchmake
onready var button_create = $Create
onready var button_join = $VBoxContainer/Join
onready var edit = $VBoxContainer/LineEdit


func _on_Matchmake_pressed():
	emit_signal("on_Matchmake_pressed")


func _on_Create_pressed():
	emit_signal("on_Create_pressed")


func _on_Join_pressed():
	emit_signal("on_Join_pressed")
