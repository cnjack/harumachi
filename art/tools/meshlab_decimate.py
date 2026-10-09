"""Quadric decimation that copes with the dense, non-manifold meshes Pixal3D returns.
python meshlab_decimate.py <in.obj> <out.obj> <target_faces>   (needs pymeshlab)"""
import sys
import pymeshlab

src, dst, target = sys.argv[1], sys.argv[2], int(sys.argv[3])
ms = pymeshlab.MeshSet()
ms.load_new_mesh(src)
# OBJ exported without UVs can still have separate coincident vertices inherited
# from glTF UV seams. Collapsing those disconnected chart edges first used to
# turn intact scans into hundreds of holes. This copy has no texture attributes,
# so exact welding is safe; the high textured mesh stays untouched for baking.
verts_before = ms.current_mesh().vertex_number()
ms.meshing_remove_duplicate_vertices()
ms.meshing_remove_unreferenced_vertices()
print('WELD EXACT', verts_before, '->', ms.current_mesh().vertex_number())
ms.meshing_decimation_quadric_edge_collapse(targetfacenum=target, qualitythr=0.3, preserveboundary=False,
                                            preservenormal=True, optimalplacement=True, planarquadric=True, autoclean=True)
ms.save_current_mesh(dst, save_textures=False, save_wedge_texcoord=False, save_vertex_color=False, save_vertex_normal=False)
print("MESHLAB", ms.current_mesh().face_number())
