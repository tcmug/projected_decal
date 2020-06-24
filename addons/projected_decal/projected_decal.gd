tool
extends MeshInstance

# Projected material.
export (Material) var material: Material 
# Extents of the projection.
export (Vector3) var extents: Vector3 = Vector3(1, 1, 1) setget set_extents, get_extents
# Cull faces are at an angle less than this, 180 effectively disables culling.
export (float) var angle_cutoff: float = 90
# How far to pop the face off the original face to remove z-fighting issues.
export (float) var face_bias: float = 0.001

var sliced_mesh: PoolVector3Array = []
var slicing_planes = []
var changed = true

func set_extents(next: Vector3):
	extents = next
	update_on_change()

func get_extents():
	return extents

func _notification(what):
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		update_on_change()

func update_on_change():
	if Engine.is_editor_hint():
		update_slicing_planes()
		scan()
		draw_editor_hint()
	else:
		changed = true

func _process(delta):
	if changed:
		update_slicing_planes()
		scan()
		changed = false

# Update editor helper to match extents.
func draw_editor_hint():
	var ig
	if has_node("_editor_hint"):
		ig = get_node("_editor_hint")
		ig.clear()
	else:
		ig = ImmediateGeometry.new()
		ig.name = "_editor_hint"
		ig.material_override = SpatialMaterial.new()
		ig.material_override.vertex_color_use_as_albedo = true
		ig.material_override.albedo_color = Color.white
		ig.material_override.flags_unshaded = true
		add_child(ig)
		
	ig.begin(Mesh.PRIMITIVE_LINES, null)
	
	ig.add_vertex(Vector3(-extents.x, extents.y, extents.z * -2))
	ig.add_vertex(Vector3(extents.x, extents.y, extents.z * -2))
	ig.add_vertex( Vector3(extents.x, -extents.y, extents.z * -2))
	ig.add_vertex(Vector3(-extents.x, -extents.y, extents.z * -2))
	
	ig.add_vertex(Vector3(-extents.x, -extents.y, extents.z *- 2))
	ig.add_vertex(Vector3(-extents.x, extents.y, extents.z * -2))
	ig.add_vertex( Vector3(extents.x, -extents.y, extents.z * -2))
	ig.add_vertex(Vector3(extents.x, extents.y, extents.z * -2))

	ig.add_vertex(Vector3(-extents.x, extents.y, 0))
	ig.add_vertex(Vector3(extents.x, extents.y, 0))
	ig.add_vertex(Vector3(extents.x, -extents.y, 0))
	ig.add_vertex(Vector3(-extents.x, -extents.y, 0))

	ig.add_vertex(Vector3(-extents.x, -extents.y, 0))
	ig.add_vertex(Vector3(-extents.x, extents.y, 0))
	ig.add_vertex(Vector3(extents.x, extents.y, 0))
	ig.add_vertex(Vector3(extents.x, -extents.y, 0))

	ig.end()

func get_aabb():
	var m = max(extents.x, max(extents.y, extents.z)) * 2
	return get_global_transform().xform(AABB(Vector3(-m / 2, -m / 2, -m / 2), Vector3(m, m, m)))

func scan():

	var uvs: PoolVector2Array = []
	mesh = null
	sliced_mesh = []
	var elements = [get_parent()]
	var projection_aabb = get_aabb()

	while elements.size() > 0:
		var child = elements.pop_front()

		if child is GridMap:
			var tx: Transform
			for item in child.get_meshes():
				if typeof(item) == TYPE_TRANSFORM:
					tx = item
				else:
					var m = item.get_aabb().get_longest_axis_size() * 2
					var aabb = tx.xform(AABB(Vector3(-m / 2, -m / 2, -m / 2), Vector3(m, m, m)))
					if projection_aabb.intersects(aabb):
						sliced_mesh.append_array(slice_mesh(tx, item.get_faces()))

		if child is MeshInstance and child.mesh:
			var tx = child.get_global_transform()
			var aabb = tx.xform(child.mesh.get_aabb())
			if projection_aabb.intersects(aabb):
				sliced_mesh.append_array(slice_mesh(tx, child.mesh.get_faces()))

		else:
			for i in range(child.get_child_count()):
				elements.push_back(child.get_child(i))

	if sliced_mesh.size() > 0:
		sliced_mesh = get_global_transform().xform_inv(sliced_mesh)
		for vertex in sliced_mesh:
			var uv = ((vertex + extents) / (extents * 2))
			uvs.append(Vector2(uv.x, 1.0 - uv.y))
		create_mesh(sliced_mesh, uvs, material)

# Clips polygons defined by vertices against a given plane.
func clip_against(verts, plane):
	var new_verts: PoolVector3Array = []
	for i in range(0, verts.size() / 3):
		var iv = i * 3;
		var triangle = [verts[iv], verts[iv + 1], verts[iv + 2]]
		var points = Geometry.clip_polygon(triangle, plane)
		if points.size() == 3:
			new_verts.append(points[0])
			new_verts.append(points[1])
			new_verts.append(points[2])
		elif points.size() == 4:
			new_verts.append(points[0])
			new_verts.append(points[1])
			new_verts.append(points[2])
			new_verts.append(points[0])
			new_verts.append(points[2])
			new_verts.append(points[3])
		else:
			if points.size() > 0:
				print("not handled ",  points.size())
	return new_verts

# Update slicing plane based on node params.
func update_slicing_planes():
	# Generate plane and transform them to global space.
	var box_planes = Geometry.build_box_planes(extents)
	# Move the slicing planes to be in front.
	box_planes[5].d *= 2
	box_planes[4].d = 0
	slicing_planes = []
	var t = get_global_transform()
	for plane in box_planes:
		slicing_planes.append(t.xform(plane))

# Slices given mesh with slicing_planes & cull faces not facing the origin.
func slice_mesh(mesh_transform: Transform, mesh_vertices: PoolVector3Array) -> PoolVector3Array:
	var sliced: PoolVector3Array = []
	var t = get_global_transform()
	for i in range(mesh_vertices.size() / 3):
		var vi = i * 3;
		var va: Vector3 = mesh_transform.xform(mesh_vertices[vi])
		var vb: Vector3 = mesh_transform.xform(mesh_vertices[vi + 1])
		var vc: Vector3 = mesh_transform.xform(mesh_vertices[vi + 2])
		var fn = (vc - va).cross(vb - va).normalized()
		var angle = rad2deg(acos(t.basis.z.dot(fn)))
		if angle < angle_cutoff:
			var push: Vector3 = fn * face_bias
			var tris: PoolVector3Array = [va + push, vb + push, vc + push]
			for plane in slicing_planes:
				tris = clip_against(tris, plane)
				if tris.size() == 0:
					break
			sliced.append_array(tris)
	return sliced
	
# Create a mesh out of vertices and uvs and give it material.
func create_mesh(vertices: PoolVector3Array, uv: PoolVector2Array, mat: Material):
	mesh = Mesh.new()
	var UVs = PoolVector2Array()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in vertices.size(): 
		st.add_uv(uv[v])
		st.add_vertex(vertices[v])
	st.generate_normals()
	st.generate_tangents()
	st.set_material(mat)
	st.commit(mesh)


