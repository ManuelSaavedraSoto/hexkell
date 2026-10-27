extends ColorRect

@onready var camera: Camera2D = %HexCamera

func _process(_delta: float) -> void:
	# Pass camera properties to the shader every frame
	material.set_shader_parameter("cam_pos", camera.global_position)
	material.set_shader_parameter("zoom", camera.zoom.x)
	material.set_shader_parameter("screen_size", get_viewport_rect().size)
