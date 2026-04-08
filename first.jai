// Voxel Engine - Entry Point
// Windows + DirectX 11 initialisation

#import "Basic";
#import "d3d11"()(INCLUDE_DEBUG_BINDINGS = false);
#import "d3d_compiler";
#import "dxgi";
#import "Windows";
#import "Windows_Utf8";

#load "types.jai";
#load "chunk.jai";
#load "camera.jai";
#load "renderer.jai";
#load "scene.jai";

WINDOW_TITLE  :: "Voxel Engine";
WINDOW_WIDTH  :: 1280;
WINDOW_HEIGHT :: 720;

// Global D3D11 state
hwnd               : HWND;
d3d_device         : *ID3D11Device;
d3d_context        : *ID3D11DeviceContext;
swap_chain         : *IDXGISwapChain;
render_target_view : *ID3D11RenderTargetView;

// Accumulated raw mouse deltas (written by wnd_proc, read + reset each frame)
g_mouse_dx : s32;
g_mouse_dy : s32;

main :: () {
    args := get_command_line_arguments();
    headless, _ := array_find(args, "-headless");

    if headless {
        run_headless_tests();
        return;
    }

    if !init_window() {
        print("init_window failed!\n");
        return;
    }

    if !init_d3d() {
        print("init_d3d failed!\n");
        cleanup();
        return;
    }

    if !init_renderer(WINDOW_WIDTH, WINDOW_HEIGHT) {
        print("init_renderer failed!\n");
        cleanup();
        return;
    }

    ShowCursor(0);  // hide cursor for mouse-look

    scene  := generate_scene();
    camera : Camera;

    print("Voxel engine running. WASD = move, mouse = look, Escape = quit.\n");

    prev_time := seconds_since_init();

    msg: MSG;
    while msg.message != WM_QUIT {
        if PeekMessageW(*msg, null, 0, 0, PM_REMOVE) {
            TranslateMessage(*msg);
            DispatchMessageW(*msg);
        } else {
            now := seconds_since_init();
            dt  := cast(float)(now - prev_time);
            prev_time = now;

            // Consume accumulated mouse deltas
            dx := g_mouse_dx;
            dy := g_mouse_dy;
            g_mouse_dx = 0;
            g_mouse_dy = 0;

            camera_update(*camera, dt, dx, dy);

            view := camera_make_view(camera);
            proj := camera_make_projection(
                0.9,                                        // ~52° vertical FOV
                cast(float) WINDOW_WIDTH / WINDOW_HEIGHT,
                0.1, 500.0
            );

            begin_frame();
            draw_scene(*scene, view, proj);
            end_frame();
        }
    }

    cleanup_renderer();
    cleanup();
}

run_headless_tests :: () {
    print("=== Headless Tests ===\n");

    // --- Meshing test: solid 4x4x4 block at the chunk origin ---
    chunk: Chunk;
    for z: 0..3  for y: 0..3  for x: 0..3
        chunk.voxels[chunk_index(x, y, z)].type = 1;

    mesh := mesh_chunk(*chunk);

    verts_ok   := mesh.vertices.count == 384;
    indices_ok := mesh.indices.count  == 576;

    print("Meshing 4x4x4 block:\n");
    print("  vertices : % (expected 384)  %\n", mesh.vertices.count, ifx verts_ok   then "PASS" else "FAIL");
    print("  indices  : % (expected 576)  %\n", mesh.indices.count,  ifx indices_ok then "PASS" else "FAIL");

    // --- Meshing test: single voxel -> 6 faces ---
    chunk2: Chunk;
    chunk2.voxels[chunk_index(1, 1, 1)].type = 1;
    mesh2 := mesh_chunk(*chunk2);

    single_verts_ok   := mesh2.vertices.count == 24;
    single_indices_ok := mesh2.indices.count  == 36;

    print("Meshing single voxel:\n");
    print("  vertices : % (expected 24)  %\n", mesh2.vertices.count, ifx single_verts_ok   then "PASS" else "FAIL");
    print("  indices  : % (expected 36)  %\n", mesh2.indices.count,  ifx single_indices_ok then "PASS" else "FAIL");

    all_pass := verts_ok && indices_ok && single_verts_ok && single_indices_ok;
    print("=== % ===\n", ifx all_pass then "ALL TESTS PASSED" else "TESTS FAILED");
}


#scope_file

init_window :: () -> bool {
    wcex: WNDCLASSEXW;
    wcex.cbSize        = size_of(WNDCLASSEXW);
    wcex.style         = CS_HREDRAW | CS_VREDRAW;
    wcex.lpfnWndProc   = xx wnd_proc;
    wcex.hInstance     = null;
    wcex.hCursor       = LoadCursorW(null, IDC_ARROW);
    wcex.hbrBackground = null;
    wcex.lpszClassName = utf8_to_wide("VoxelEngineClass");

    if RegisterClassExW(*wcex) == 0 {
        print("RegisterClassExW failed!\n");
        return false;
    }

    rc: RECT;
    rc.right  = WINDOW_WIDTH;
    rc.bottom = WINDOW_HEIGHT;
    AdjustWindowRect(*rc, WS_OVERLAPPEDWINDOW, BOOL.FALSE);

    hwnd = CreateWindowExW(
        0,
        utf8_to_wide("VoxelEngineClass"),
        utf8_to_wide(WINDOW_TITLE),
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        CW_USEDEFAULT, CW_USEDEFAULT,
        rc.right - rc.left, rc.bottom - rc.top,
        null, null, null, null
    );

    if !hwnd {
        print("CreateWindowExW failed!\n");
        return false;
    }

    // Register for raw mouse input (no OS cursor acceleration)
    rid: RAWINPUTDEVICE;
    rid.usUsagePage = 0x01;   // HID_USAGE_PAGE_GENERIC
    rid.usUsage     = 0x02;   // HID_USAGE_GENERIC_MOUSE
    rid.dwFlags     = 0;
    rid.hwndTarget  = hwnd;
    RegisterRawInputDevices(cast(*void) *rid, 1, size_of(RAWINPUTDEVICE));

    ShowWindow(hwnd, SW_SHOWDEFAULT);
    UpdateWindow(hwnd);
    return true;
}

init_d3d :: () -> bool {
    hr: HRESULT;

    driver_types   := D3D_DRIVER_TYPE.[.HARDWARE, .WARP, .REFERENCE];
    feature_levels := D3D_FEATURE_LEVEL.[._11_1, ._11_0, ._10_1, ._10_0];

    feature_level: D3D_FEATURE_LEVEL;
    for dt: driver_types {
        hr = D3D11CreateDevice(null, dt, null, 0, feature_levels.data, xx feature_levels.count,
                               D3D11_SDK_VERSION, *d3d_device, *feature_level, *d3d_context);
        if hr == E_INVALIDARG {
            hr = D3D11CreateDevice(null, dt, null, 0, feature_levels.data + 1, xx (feature_levels.count - 1),
                                   D3D11_SDK_VERSION, *d3d_device, *feature_level, *d3d_context);
        }
        if SUCCEEDED(hr) break;
    }
    if FAILED(hr) {
        print("D3D11CreateDevice failed: %\n", hr);
        return false;
    }
    print("D3D11 device created. Feature level: %\n", feature_level);

    dxgi_factory: *IDXGIFactory1;
    {
        dxgi_device: *IDXGIDevice;
        hr = IUnknown_QueryInterface(d3d_device, *uid(IDXGIDevice_UUID), xx *dxgi_device);
        if SUCCEEDED(hr) {
            adapter: *IDXGIAdapter;
            hr = IDXGIDevice_GetAdapter(dxgi_device, *adapter);
            if SUCCEEDED(hr) {
                hr = IDXGIObject_GetParent(adapter, *uid(IDXGIFactory1_UUID), xx *dxgi_factory);
                IUnknown_Release(adapter);
            }
            IUnknown_Release(dxgi_device);
        }
    }
    if FAILED(hr) || dxgi_factory == null {
        print("Failed to obtain IDXGIFactory1: %\n", hr);
        return false;
    }

    rc: RECT;
    GetClientRect(hwnd, *rc);

    sd: DXGI_SWAP_CHAIN_DESC;
    sd.BufferCount                        = 1;
    sd.BufferDesc.Width                   = xx (rc.right  - rc.left);
    sd.BufferDesc.Height                  = xx (rc.bottom - rc.top);
    sd.BufferDesc.Format                  = .R8G8B8A8_UNORM;
    sd.BufferDesc.RefreshRate.Numerator   = 60;
    sd.BufferDesc.RefreshRate.Denominator = 1;
    sd.BufferUsage                        = .RENDER_TARGET_OUTPUT;
    sd.OutputWindow                       = hwnd;
    sd.SampleDesc.Count                   = 1;
    sd.SampleDesc.Quality                 = 0;
    sd.Windowed                           = BOOL.TRUE;

    hr = IDXGIFactory_CreateSwapChain(dxgi_factory, d3d_device, *sd, *swap_chain);
    IDXGIFactory_MakeWindowAssociation(dxgi_factory, hwnd, cast(u32) DXGI_MWA.NO_ALT_ENTER);
    IUnknown_Release(dxgi_factory);

    if FAILED(hr) {
        print("CreateSwapChain failed: %\n", hr);
        return false;
    }

    if !create_render_target_view() return false;

    vp: D3D11_VIEWPORT;
    vp.Width    = xx (rc.right  - rc.left);
    vp.Height   = xx (rc.bottom - rc.top);
    vp.MinDepth = 0.0;
    vp.MaxDepth = 1.0;
    ID3D11DeviceContext_RSSetViewports(d3d_context, 1, *vp);

    return true;
}

create_render_target_view :: () -> bool {
    back_buffer: *ID3D11Texture2D;
    hr := IDXGISwapChain_GetBuffer(swap_chain, 0, *uid(ID3D11Texture2D_UUID), xx *back_buffer);
    if FAILED(hr) {
        print("GetBuffer failed: %\n", hr);
        return false;
    }

    hr = ID3D11Device_CreateRenderTargetView(d3d_device, back_buffer, null, *render_target_view);
    IUnknown_Release(back_buffer);
    if FAILED(hr) {
        print("CreateRenderTargetView failed: %\n", hr);
        return false;
    }

    // Note: OMSetRenderTargets is called in init_renderer (with depth stencil view)
    return true;
}

cleanup :: () {
    if d3d_context        ID3D11DeviceContext_ClearState(d3d_context);
    if render_target_view IUnknown_Release(render_target_view);
    if swap_chain         IUnknown_Release(swap_chain);
    if d3d_context        IUnknown_Release(d3d_context);
    if d3d_device         IUnknown_Release(d3d_device);
}

wnd_proc :: (hWnd: HWND, message: u32, wParam: WPARAM, lParam: LPARAM) -> LRESULT #c_call {
    if message == {
    case WM_DESTROY;
        PostQuitMessage(0);

    case WM_KEYDOWN;
        if wParam == VK_ESCAPE  PostQuitMessage(0);

    case WM_INPUT;
        raw_size : u32 = size_of(RAWINPUT);
        raw      : RAWINPUT;
        GetRawInputData(cast(HRAWINPUT) lParam, RID_INPUT, *raw, *raw_size, size_of(RAWINPUTHEADER));
        if raw.header.dwType == RIM_TYPEMOUSE {
            if (raw.data.mouse.usFlags & MOUSE_MOVE_ABSOLUTE) == 0 {
                g_mouse_dx = g_mouse_dx + raw.data.mouse.lLastX;
                g_mouse_dy = g_mouse_dy + raw.data.mouse.lLastY;
            }
        }

    case;
        return DefWindowProcW(hWnd, message, wParam, lParam);
    }

    return 0;
}
