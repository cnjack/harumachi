class_name Interactable
extends Node3D
## A point the player can use. The Story node decides the prompt text (empty = disabled).

@export var id := ""
@export var radius := 2.0
## Collision body that belongs to this target; ignored by the line-of-sight ray.
var body: CollisionObject3D


func _ready() -> void:
	add_to_group("interactables")
