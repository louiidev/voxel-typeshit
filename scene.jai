// Test scene: a 3x3 grid of 32^3 chunks with sinusoidal terrain.

#import "Basic";
#import "Math";

SCENE_W :: 3;
SCENE_D :: 3;

Scene :: struct {
    renderables : [SCENE_W * SCENE_D] Chunk_Renderable;
}

generate_scene :: () -> Scene {
    scene: Scene;

    for cz: 0..SCENE_D-1 {
        for cx: 0..SCENE_W-1 {
            chunk: Chunk;

            // Height field: sinusoidal surface
            for z: 0..CHUNK_SIZE-1 {
                for x: 0..CHUNK_SIZE-1 {
                    wx := cast(float)(cx * CHUNK_SIZE + x);
                    wz := cast(float)(cz * CHUNK_SIZE + z);

                    height := cast(int)(9.0 + 5.0 * sin(wx / 10.0) + 5.0 * cos(wz / 10.0));
                    if height < 1           height = 1;
                    if height >= CHUNK_SIZE height = CHUNK_SIZE - 1;

                    for y: 0..height {
                        chunk.voxels[chunk_index(x, y, z)].type = 1;
                    }
                }
            }

            mesh := mesh_chunk(*chunk);
            idx  := cz * SCENE_W + cx;

            ok: bool;
            scene.renderables[idx], ok = create_chunk_renderable(*mesh);
            if !ok  print("Failed to upload chunk (%,%)\n", cx, cz);
        }
    }

    return scene;
}

// Draw every chunk with a per-chunk world translation applied to the mvp.
draw_scene :: (scene: *Scene, view: Matrix4, proj: Matrix4) {
    for cz: 0..SCENE_D-1 {
        for cx: 0..SCENE_W-1 {
            world := make_translation_matrix4(
                .{cast(float)(cx * CHUNK_SIZE), 0.0, cast(float)(cz * CHUNK_SIZE)}
            );
            mvp := proj * view * world;
            draw_chunk(*scene.renderables[cz * SCENE_W + cx], mvp);
        }
    }
}
