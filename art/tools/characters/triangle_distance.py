"""Exact point-to-triangle distances with a read-only C++ BVH.

closest_points(vertices[N,3], faces[F,3], queries[Q,3]) returns
(distance[Q], source_face[Q], closest_xyz[Q,3]). Face IDs refer to the input
face order. It includes interiors, edges and degenerate triangles. This is
unsigned Euclidean distance, not an inside/outside or penetration test.

The first call compiles the sibling C++ source into the OS temporary directory.
Only numpy and a C++17 compiler are required; no Godot process is started.
"""
import ctypes
import hashlib
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import numpy as np

_LIBRARY = None


def _library():
    global _LIBRARY
    if _LIBRARY is not None:
        return _LIBRARY
    source = Path(__file__).with_suffix('.cpp')
    compiler = shutil.which('clang++') or shutil.which('g++')
    if not compiler:
        raise RuntimeError('triangle_distance requires clang++ or g++')
    key = hashlib.sha256(source.read_bytes() + (platform.machine() + platform.system()).encode()).hexdigest()[:20]
    suffix = '.dylib' if platform.system() == 'Darwin' else '.so'
    cache = Path(tempfile.gettempdir()) / ('harumachi-triangle-distance-' + str(os.getuid()))
    cache.mkdir(exist_ok=True)
    output = cache / (key + suffix)
    if not output.exists():
        with tempfile.TemporaryDirectory(prefix='build-', dir=cache) as directory:
            candidate = Path(directory) / output.name
            flags = ['-dynamiclib'] if platform.system() == 'Darwin' else ['-shared', '-fPIC']
            result = subprocess.run([compiler, '-std=c++17', '-O3', *flags, str(source), '-o', str(candidate)], capture_output=True, text=True, timeout=60)
            if result.returncode:
                raise RuntimeError('triangle_distance compile failed:\n' + result.stderr)
            os.replace(candidate, output)
    library = ctypes.CDLL(str(output))
    double_pointer = ctypes.POINTER(ctypes.c_double)
    int_pointer = ctypes.POINTER(ctypes.c_int64)
    library.triangle_closest.argtypes = [double_pointer, int_pointer, ctypes.c_int64, double_pointer,
                                         ctypes.c_int64, double_pointer, int_pointer, double_pointer]
    library.triangle_closest.restype = ctypes.c_int
    _LIBRARY = library
    return library


def closest_points(vertices, faces, queries):
    vertices = np.ascontiguousarray(vertices, dtype=np.float64)
    queries = np.ascontiguousarray(queries, dtype=np.float64)
    original_faces = np.asarray(faces)
    if original_faces.dtype.kind not in 'iu':
        raise ValueError('faces must contain integer vertex indices')
    faces = np.ascontiguousarray(original_faces, dtype=np.int64)
    for name, array in [('vertices', vertices), ('faces', faces), ('queries', queries)]:
        if array.ndim != 2 or array.shape[1] != 3:
            raise ValueError(name + ' must have shape [count,3]')
    if not len(vertices) or not len(faces):
        raise ValueError('A nonempty triangle surface is required')
    if not np.isfinite(vertices).all() or not np.isfinite(queries).all():
        raise ValueError('Vertices and queries must be finite')
    if np.min(faces) < 0 or np.max(faces) >= len(vertices):
        raise ValueError('Triangle index outside the vertex array')
    distances = np.empty(len(queries), dtype=np.float64)
    source_faces = np.empty(len(queries), dtype=np.int64)
    closest = np.empty_like(queries)
    if not len(queries):
        return distances, source_faces, closest
    double_pointer = ctypes.POINTER(ctypes.c_double)
    int_pointer = ctypes.POINTER(ctypes.c_int64)
    status = _library().triangle_closest(vertices.ctypes.data_as(double_pointer), faces.ctypes.data_as(int_pointer), len(faces),
        queries.ctypes.data_as(double_pointer), len(queries), distances.ctypes.data_as(double_pointer),
        source_faces.ctypes.data_as(int_pointer), closest.ctypes.data_as(double_pointer))
    if status:
        raise RuntimeError('triangle_distance native status ' + str(status))
    return distances, source_faces, closest
