"""Subtract rectangular voids from an open triangle shell without boolean caps.

Clip triangles, interpolate original UVs, retain every exterior fragment. This
does not assume the provider mesh is a closed solid, unlike a boolean solver.
"""
import bpy
from mathutils import Vector

def split(poly, axis, bound, sign):
    inside, outside = [], []
    for i, point in enumerate(poly):
        previous = poly[i-1]
        d = (point[0][axis]-bound)*sign
        dp = (previous[0][axis]-bound)*sign
        current_in, previous_in = d >= -1e-10, dp >= -1e-10
        if current_in != previous_in:
            t = dp/(dp-d)
            crossing = (previous[0].lerp(point[0],t), [a.lerp(b,t) for a,b in zip(previous[1],point[1])])
            inside.append(crossing); outside.append(crossing)
        (inside if current_in else outside).append(point)
    return inside, outside

def subtract(poly, low, high):
    if any(max(p[0][a] for p in poly) <= low[a] or min(p[0][a] for p in poly) >= high[a] for a in range(3)):
        return [poly]
    kept=[]
    for axis,bound,sign in [(a,low[a],1) for a in range(3)]+[(a,high[a],-1) for a in range(3)]:
        poly, outside = split(poly,axis,bound,sign)
        if len(outside)>=3:kept.append(outside)
        if len(poly)<3:break
    return kept

def clear_boxes(ob, boxes):
    old = ob.data
    matrix = ob.matrix_world
    inverse = matrix.inverted()
    vertices, faces, materials, smooth, corner_uvs = [], [], [], [], []
    uv_names=[layer.name for layer in old.uv_layers]
    vertex_map={}
    for face in old.polygons:
        poly=[(matrix@old.vertices[old.loops[li].vertex_index].co,[Vector(layer.data[li].uv) for layer in old.uv_layers]) for li in face.loop_indices]
        fragments=[poly]
        for low,high in boxes:
            fragments=[fragment for current in fragments for fragment in subtract(current,low,high)]
        for fragment in fragments:
            for i in range(1,len(fragment)-1):
                tri=[fragment[0],fragment[i],fragment[i+1]]
                if (tri[1][0]-tri[0][0]).cross(tri[2][0]-tri[0][0]).length<1e-12:continue
                indices=[]
                for point,uvs in tri:
                    co=inverse@point
                    key=tuple(round(c,8) for c in co)+tuple(round(c,8) for uv in uvs for c in uv)
                    if key not in vertex_map:
                        vertex_map[key]=len(vertices);vertices.append(tuple(co))
                    indices.append(vertex_map[key]);corner_uvs.append(uvs)
                faces.append(indices);materials.append(face.material_index);smooth.append(face.use_smooth)
    mesh=bpy.data.meshes.new(old.name+'_open_display')
    mesh.from_pydata(vertices,[],faces);mesh.update()
    for mat in old.materials:mesh.materials.append(mat)
    for i,name in enumerate(uv_names):
        layer=mesh.uv_layers.new(name=name)
        layer.data.foreach_set('uv',[c for uvs in corner_uvs for c in uvs[i]])
    mesh.polygons.foreach_set('material_index',materials)
    mesh.polygons.foreach_set('use_smooth',smooth)
    ob.data=mesh
