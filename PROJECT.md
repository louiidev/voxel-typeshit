# Project: Voxel Engine (Jai + DX11)

## Tech Stack
- **Language:** Jai (Beta)
- **Graphics API:** DirectX 11 (via `Direct3D11` and `Direct3D11_Helpers` modules)
- **Windowing:** `Window_Creation` module
- **Math:** `Math` and `Linear_Algebra` modules
- **Memory Management:** Arena-based (Pools) using the `Pool` module

## Core Architecture & Memory Strategy
- **Zero-Heap Policy:** Avoid `basic.alloc` or `libc.malloc`. Use the Jai `context.allocator` pattern.
- **Arena Lifetimes:**
  1. **Main Arena (Persistent):** Used for world data, chunk storage, and long-lived resources.
  2. **Frame Arena (Transient):** Resets every frame. Use for meshing buffers, temporary strings, and per-frame DX11 updates.
- **Context Handling:** Every frame must start with a `reset(*frame_arena)` followed by a `push_context` that sets the `context.allocator` to the `pool_allocator` of the `frame_arena`.

## Voxel Specifications
- **Chunk Size:** 32x32x32 nodes.
- **Data Layout:** Flat 1D array of `u8` or packed structs for cache efficiency. 
- **Indexing:** `(y * CHUNK_SIZE * CHUNK_SIZE) + (z * CHUNK_SIZE) + x`.
- **Meshing:** Culled meshing (greedy meshing planned). Avoid redundant face generation between opaque blocks.

## Verification & Testing Protocol
- **Post-Prompt Verification:** After every code modification, Claude must verify the changes by compiling the project.
- **Headless Testing:** Use a `-headless` flag in the `main.jai` or a dedicated `tests.jai` to run logic-heavy code (meshing, noise generation, world loading) without initializing a DX11 window/device.
- **Validation:** Run `jai build.jai` and execute the binary in headless mode to ensure no memory access violations or logic regressions were introduced.

## Development Patterns
- **Build System:** Use a `build.jai` metaprogram for compilation.
- **Error Handling:** Check `HRESULT` for all DX11 calls. Use `assert` for internal logic.
- **Shaders:** HLSL 5.0. Prefer runtime compilation using `D3DCompileFromFile` for fast iteration during dev.
- **Naming Convention:** `snake_case` for variables and functions; `PascalCase` for Structs and Types.

## Command Reference
- **Build:** `jai build.jai`
- **Run (Test):** `jai main.jai -- -headless`
- **Clean:** Delete the `.exe` and `.pdb` files.

## High-Priority Constraints for Claude
1. NEVER use `free()`. Always rely on Arena/Pool resets.
2. When creating a new module, ensure it takes an `Allocator` as a parameter if it needs to persist data.
3. Keep the rendering loop lean. Do not perform heavy logic inside the `draw` call.
4. If code affects the World or Meshing, MUST run a headless test before finishing the task.
