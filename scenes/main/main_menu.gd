extends Control

@onready var new_game_button: Button = $VBoxContainer/NewGameButton
@onready var quit_button: Button = $VBoxContainer/QuitButton

func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game)
	quit_button.pressed.connect(_on_quit)

func _on_new_game() -> void:
	GameManager.new_game()

func _on_quit() -> void:
	get_tree().quit()
