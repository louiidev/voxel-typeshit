// Core types shared across the voxel engine.

#import "Math";

CHUNK_SIZE   :: 32;
CHUNK_VOLUME :: CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE;

// ------------------------------------------------------------
// Voxel
// ------------------------------------------------------------

Voxel :: struct {
    type: u8;   // 0 = air
}

is_air :: inline (v: Voxel) -> bool {
    return v.type == 0;
}

// ------------------------------------------------------------
// Vertex  (position + normal + uv)
// ------------------------------------------------------------

Vertex :: struct {
    position : Vector3;
    normal   : Vector3;
    uv       : Vector2;
}

// ------------------------------------------------------------
// Mesh  (dynamic arrays — caller owns the allocator)
// ------------------------------------------------------------

Mesh :: struct {
    vertices : [..] Vertex;
    indices  : [..] u32;
}
