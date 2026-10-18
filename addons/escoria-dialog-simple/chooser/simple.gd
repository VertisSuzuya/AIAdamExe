# A simple dialog chooser that shows selectable lines of text
# Supports timeout and avatar display
extends ESCDialogOptionsChooser


@export var color_normal = Color(1.0,1.0,1.0,1.0) # (Color, RGB)
@export var color_hover = Color(0.0, 0.792157, 0.803922, 1.0) # (Color, RGB)
@export var font_size: int = 32


var _no_more_options: bool = false


# Hide the chooser at the start just to be safe
func _ready() -> void:
	hide_chooser()
	process_mode = PROCESS_MODE_PAUSABLE


# Process the timeout display
func _process(_delta: float) -> void:
	if $choices_panel.visible and self.dialog and self.dialog.timeout > 0:
		$TimerProgress.value = (
			self.dialog.timeout - $Timer.time_left
		) / self.dialog.timeout * 100


# Show the chooser
func show_chooser():
	var vbox = $choices_panel/ScrollContainer/VBoxContainer
	for option_node in vbox.get_children():
		vbox.remove_child(option_node)

	_remove_avatar()

	for option in self.dialog.options:
		if option.is_valid():
			var option_node = Button.new()
			option_node.text = (option as ESCDialogOption).option
			option_node.flat = true
			option_node.alignment = HORIZONTAL_ALIGNMENT_LEFT
			option_node.add_theme_font_size_override("font_size", font_size)
			option_node.add_theme_color_override("font_color", color_normal)
			option_node.add_theme_color_override("font_hover_color", color_hover)
			option_node.add_theme_color_override("font_pressed_color", color_hover)
			vbox.add_child(option_node)

			option_node.pressed.connect(_on_answer_selected.bind(option))

	# If we've no options left, signify as much and start the timer with a
	# very short interval so the appropriate signal can be fired. Note that
	# we have to fire the signal AFTER this method returns as the caller
	# is almost certainly yielding after this method returns.
	if vbox.get_child_count() == 0:
		_no_more_options = true
		$Timer.start(0.05)
		return

	if self.dialog.avatar != "-":
		$AvatarContainer.add_child(
			ResourceLoader.load(self.dialog.avatar).instantiate()
		)

	$choices_panel.show()

	if self.dialog.timeout > 0 and self.dialog.get_timeout_option():
		$Timer.start(self.dialog.timeout)
	else:
		$TimerProgress.value = 0


# Hide the chooser
func hide_chooser():
	$choices_panel.hide()


# An option was choosen, emit the option
#
# #### Parameters
# - option: Option that was chosen
func _option_chosen(option: ESCDialogOption):
	_remove_avatar()
	$TimerProgress.value = 0
	option_chosen.emit(option)


# An option was chosen directly from the list
#
# #### Parameters
# - option: Option that was chosen
func _on_answer_selected(option: ESCDialogOption):
	_option_chosen(option)


# The timeout came and a option was selected
func _on_Timer_timeout() -> void:
	var option_chosen = null if _no_more_options else self.dialog.get_timeout_option()
	_no_more_options = false
	_option_chosen(option_chosen)


# Remove the avatar
func _remove_avatar():
	if $AvatarContainer.get_child_count() > 0:
		$AvatarContainer.remove_child($AvatarContainer.get_child(0))
