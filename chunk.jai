// Chunk storage and culled-face meshing.

#import "Basic";

// ------------------------------------------------------------
// Chunk
// ------------------------------------------------------------

Chunk :: struct {
    voxels: [CHUNK_VOLUME] Voxel;
}

chunk_index :: inline (x: int, y: int, z: int) -> int {
    return (y * CHUNK_SIZE * CHUNK_SIZE) + (z * CHUNK_SIZE) + x;
}

// Returns an air voxel for any coordinate that is out of bounds,
// so edge-facing faces are always emitted (correct for chunk borders).
voxel_at :: inline (chunk: *Chunk, x: int, y: int, z: int) -> Voxel {
    if x < 0 || x >= CHUNK_SIZE ||
       y < 0 || y >= CHUNK_SIZE ||
       z < 0 || z >= CHUNK_SIZE  return .{};
    return chunk.voxels[chunk_index(x, y, z)];
}

// ------------------------------------------------------------
// Culled meshing
// ------------------------------------------------------------
// Iterates every solid voxel and emits a quad for each face
// whose neighbour is air (or out of bounds).  Uses
// context.allocator for the output arrays — callers swap in
// their frame arena before calling this.

mesh_chunk :: (chunk: *Chunk) -> Mesh {
    mesh: Mesh;

    for z: 0..CHUNK_SIZE-1 {
        for y: 0..CHUNK_SIZE-1 {
            for x: 0..CHUNK_SIZE-1 {
                voxel := voxel_at(chunk, x, y, z);
                if is_air(voxel) continue;

                for face: 0..5 {
                    // Neighbour in the direction of this face
                    nx := x + FACE_NEIGHBOR[face*3 + 0];
                    ny := y + FACE_NEIGHBOR[face*3 + 1];
                    nz := z + FACE_NEIGHBOR[face*3 + 2];

                    if !is_air(voxel_at(chunk, nx, ny, nz)) continue;

                    // Append 4 vertices for this quad
                    base_index := cast(u32) mesh.vertices.count;
                    normal     := FACE_NORMALS[face];

                    for vi: 0..3 {
                        v: Vertex;
                        v.position.x = cast(float)(x + FACE_VERTS[(face*4 + vi)*3 + 0]);
                        v.position.y = cast(float)(y + FACE_VERTS[(face*4 + vi)*3 + 1]);
                        v.position.z = cast(float)(z + FACE_VERTS[(face*4 + vi)*3 + 2]);
                        v.normal     = normal;
                        v.uv.x       = FACE_UVS[vi*2 + 0];
                        v.uv.y       = FACE_UVS[vi*2 + 1];
                        array_add(*mesh.vertices, v);
                    }

                    // Append 6 indices (two CW triangles)
                    for qi: 0..5 {
                        array_add(*mesh.indices, base_index + QUAD_INDICES[qi]);
                    }
                }
            }
        }
    }

    return mesh;
}


// ------------------------------------------------------------
// Face tables  (file-private)
// ------------------------------------------------------------

#scope_file

// Neighbour delta per face: +X -X +Y -Y +Z -Z
// Flat: [face*3 + coord]
FACE_NEIGHBOR :: s8.[
     1,  0,  0,   // +X
    -1,  0,  0,   // -X
     0,  1,  0,   // +Y
     0, -1,  0,   // -Y
     0,  0,  1,   // +Z
     0,  0, -1,   // -Z
];

// 4 vertex corner offsets per face (unit cube, 0 or 1 per axis).
// CCW winding order in LH Y-up Z-forward screen space (DX11 with FrontCounterClockwise=TRUE).
// Flat: [(face*4 + vertex)*3 + coord]
FACE_VERTS :: s8.[
    // +X  (right wall, x = 1)  screen-right=+Z, screen-up=+Y
    1,0,0,  1,0,1,  1,1,1,  1,1,0,
    // -X  (left wall, x = 0)   screen-right=-Z, screen-up=+Y
    0,0,0,  0,1,0,  0,1,1,  0,0,1,
    // +Y  (ceiling, y = 1)     screen-right=+X, screen-up=+Z
    0,1,0,  1,1,0,  1,1,1,  0,1,1,
    // -Y  (floor, y = 0)       screen-right=+X, screen-up=-Z
    0,0,1,  1,0,1,  1,0,0,  0,0,0,
    // +Z  (back wall, z = 1)   screen-right=-X, screen-up=+Y
    0,0,1,  0,1,1,  1,1,1,  1,0,1,
    // -Z  (front wall, z = 0)   screen-right=+X, screen-up=+Y
    0,0,0,  1,0,0,  1,1,0,  0,1,0,
];

// UV layout per vertex index (same for every face)
// Flat: [vi*2 + 0=u, vi*2 + 1=v]
FACE_UVS :: float.[
    0.0, 1.0,  // vi=0
    0.0, 0.0,  // vi=1
    1.0, 0.0,  // vi=2
    1.0, 1.0,  // vi=3
];

// Outward normals per face
FACE_NORMALS :: Vector3.[
    .{ 1,  0,  0},   // +X
    .{-1,  0,  0},   // -X
    .{ 0,  1,  0},   // +Y
    .{ 0, -1,  0},   // -Y
    .{ 0,  0,  1},   // +Z
    .{ 0,  0, -1},   // -Z
];

// Index pattern for one quad (two triangles, CW)
QUAD_INDICES :: u32.[0, 1, 2, 0, 2, 3];
