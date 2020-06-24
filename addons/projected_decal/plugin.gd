tool
extends EditorPlugin

func _enter_tree():
	name = "ProjectedDecalPlugin"
	add_custom_type("ProjectedDecal", "MeshInstance", preload("projected_decal.gd"), null)

func _exit_tree():
	remove_custom_type("ProjectedDecal")
