extends Camera3D

const SPEED := 5.0
const SENSITIVITY := 0.003

func _ready() -> void:
	# Hide the cursor and lock it to the window so the mouse can look around.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	# Runs whenever any input event happens.
	if event is InputEventMouseMotion:
		rotation.y -= event.relative.x * SENSITIVITY
		rotation.x -= event.relative.y * SENSITIVITY
		rotation.x = clamp(rotation.x, -PI / 2, PI / 2)
	if event.is_action_pressed("ui_cancel"):
		# Escape releases the mouse.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	# Runs every frame. delta is the seconds since the last frame.
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S): dir += transform.basis.z
	if Input.is_key_pressed(KEY_A): dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D): dir += transform.basis.x
	if Input.is_key_pressed(KEY_SPACE): dir += Vector3.UP
	if Input.is_key_pressed(KEY_SHIFT): dir -= Vector3.UP
	position += dir.normalized() * SPEED * delta
