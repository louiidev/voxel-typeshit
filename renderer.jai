// DX11 renderer: shaders, depth buffer, rasteriser state, constant buffer,
// and per-chunk GPU resources.

// d3d11, dxgi, d3d_compiler are imported by first.jai (shared scope via #load)
#import "Basic";
#import "Math";

// -----------------------------------------------------------------
// GPU resource for one meshed chunk
// -----------------------------------------------------------------

Chunk_Renderable :: struct {
    vb          : *ID3D11Buffer;
    ib          : *ID3D11Buffer;
    index_count : u32;
}

// -----------------------------------------------------------------
// Global renderer state (all accessed via d3d_device / d3d_context
// which live in first.jai scope)
// -----------------------------------------------------------------

g_vertex_shader : *ID3D11VertexShader;
g_pixel_shader  : *ID3D11PixelShader;
g_input_layout  : *ID3D11InputLayout;
g_cb_frame      : *ID3D11Buffer;           // constant buffer: one Matrix4 (mvp)
g_raster_state  : *ID3D11RasterizerState;
g_ds_state      : *ID3D11DepthStencilState;
g_depth_view    : *ID3D11DepthStencilView;

// -----------------------------------------------------------------
// Inline HLSL
// -----------------------------------------------------------------

SHADER_SOURCE :: #string HLSL
#pragma pack_matrix(row_major)

cbuffer FrameConstants : register(b0) {
    float4x4 mvp;
};

struct VSInput {
    float3 position : POSITION;
    float3 normal   : NORMAL;
    float2 uv       : TEXCOORD0;
};

struct VSOutput {
    float4 position : SV_POSITION;
    float3 normal   : NORMAL;
};

VSOutput VS(VSInput input) {
    VSOutput o;
    o.position = mul(mvp, float4(input.position, 1.0));
    o.normal   = input.normal;
    return o;
}

float4 PS(VSOutput input) : SV_TARGET {
    float3 light_dir = normalize(float3(1.0, 2.0, 0.5));
    float  diffuse   = saturate(dot(normalize(input.normal), light_dir));
    float3 color     = float3(0.65, 0.58, 0.42) * (0.25 + 0.75 * diffuse);
    return float4(color, 1.0);
}
HLSL;

// -----------------------------------------------------------------
// Initialise renderer (call after init_d3d)
// -----------------------------------------------------------------

init_renderer :: (width: s32, height: s32) -> bool {
    if !_create_shaders()        return false;
    if !_create_states()         return false;
    if !_create_const_buffer()   return false;
    if !_create_depth_buffer(width, height) return false;

    // Bind render target + depth together (replaces the null-depth binding in first.jai)
    ID3D11DeviceContext_OMSetRenderTargets(d3d_context, 1, *render_target_view, g_depth_view);
    return true;
}

// -----------------------------------------------------------------
// Upload mesh to GPU, return a drawable Chunk_Renderable
// -----------------------------------------------------------------

create_chunk_renderable :: (mesh: *Mesh) -> Chunk_Renderable, bool {
    cr: Chunk_Renderable;
    if mesh.vertices.count == 0 || mesh.indices.count == 0  return cr, true;

    cr.index_count = cast(u32) mesh.indices.count;

    // Vertex buffer
    {
        desc: D3D11_BUFFER_DESC;
        desc.ByteWidth = cast(u32)(size_of(Vertex) * mesh.vertices.count);
        desc.Usage     = .IMMUTABLE;
        desc.BindFlags = .VERTEX_BUFFER;

        init: D3D11_SUBRESOURCE_DATA;
        init.pSysMem = mesh.vertices.data;

        hr := ID3D11Device_CreateBuffer(d3d_device, *desc, *init, *cr.vb);
        if FAILED(hr) {
            print("CreateBuffer (vertex) failed: %\n", hr);
            return cr, false;
        }
    }

    // Index buffer
    {
        desc: D3D11_BUFFER_DESC;
        desc.ByteWidth = cast(u32)(size_of(u32) * mesh.indices.count);
        desc.Usage     = .IMMUTABLE;
        desc.BindFlags = .INDEX_BUFFER;

        init: D3D11_SUBRESOURCE_DATA;
        init.pSysMem = mesh.indices.data;

        hr := ID3D11Device_CreateBuffer(d3d_device, *desc, *init, *cr.ib);
        if FAILED(hr) {
            print("CreateBuffer (index) failed: %\n", hr);
            IUnknown_Release(cr.vb);
            cr.vb = null;
            return cr, false;
        }
    }

    return cr, true;
}

// -----------------------------------------------------------------
// Frame lifecycle
// -----------------------------------------------------------------

begin_frame :: () {
    clear_color: [4] float = .[0.53, 0.81, 0.98, 1.0];
    ID3D11DeviceContext_ClearRenderTargetView(d3d_context, render_target_view, *clear_color);
    ID3D11DeviceContext_ClearDepthStencilView(d3d_context, g_depth_view, cast(u32) D3D11_CLEAR_FLAG.DEPTH, 1.0, 0);

    // Bind shaders and pipeline state once per frame
    ID3D11DeviceContext_VSSetShader(d3d_context, g_vertex_shader, null, 0);
    ID3D11DeviceContext_PSSetShader(d3d_context, g_pixel_shader,  null, 0);
    ID3D11DeviceContext_IASetInputLayout(d3d_context, g_input_layout);
    ID3D11DeviceContext_IASetPrimitiveTopology(d3d_context, .TRIANGLELIST);
    ID3D11DeviceContext_RSSetState(d3d_context, g_raster_state);
    ID3D11DeviceContext_OMSetDepthStencilState(d3d_context, g_ds_state, 0);
    ID3D11DeviceContext_VSSetConstantBuffers(d3d_context, 0, 1, *g_cb_frame);
}

draw_chunk :: (cr: *Chunk_Renderable, mvp: Matrix4) {
    if cr.index_count == 0  return;

    // Update constant buffer
    mapped: D3D11_MAPPED_SUBRESOURCE;
    hr := ID3D11DeviceContext_Map(d3d_context, cast(*ID3D11Resource) g_cb_frame,
                                  0, .WRITE_DISCARD, 0, *mapped);
    if SUCCEEDED(hr) {
        (cast(*Matrix4) mapped.pData).* = mvp;
        ID3D11DeviceContext_Unmap(d3d_context, cast(*ID3D11Resource) g_cb_frame, 0);
    }

    stride : u32 = size_of(Vertex);
    offset : u32 = 0;
    ID3D11DeviceContext_IASetVertexBuffers(d3d_context, 0, 1, *cr.vb, *stride, *offset);
    ID3D11DeviceContext_IASetIndexBuffer(d3d_context, cr.ib, .R32_UINT, 0);
    ID3D11DeviceContext_DrawIndexed(d3d_context, cr.index_count, 0, 0);
}

end_frame :: () {
    hr := IDXGISwapChain_Present(swap_chain, 1, 0);
    if FAILED(hr)  print("Present failed: %\n", hr);
}

cleanup_renderer :: () {
    if g_depth_view    IUnknown_Release(g_depth_view);
    if g_ds_state      IUnknown_Release(g_ds_state);
    if g_raster_state  IUnknown_Release(g_raster_state);
    if g_cb_frame      IUnknown_Release(g_cb_frame);
    if g_input_layout  IUnknown_Release(g_input_layout);
    if g_pixel_shader  IUnknown_Release(g_pixel_shader);
    if g_vertex_shader IUnknown_Release(g_vertex_shader);
}

// -----------------------------------------------------------------
// Private helpers
// -----------------------------------------------------------------

#scope_file

_compile_shader :: (source: string, entry: string, profile: string) -> string, bool {
    flags: D3DCOMPILE = .ENABLE_STRICTNESS;
    defines: [] string;
    bytecode, errors, hr := D3DCompile(source, "voxel_shader", defines, null, entry, profile, xx flags, 0);
    defer free(errors);
    if FAILED(hr) {
        if errors  print("Shader error (%): %\n", entry, errors);
        free(bytecode);
        return "", false;
    }
    return bytecode, true;
}

_create_shaders :: () -> bool {
    vs_bc, vs_ok := _compile_shader(SHADER_SOURCE, "VS", "vs_5_0");
    if !vs_ok  return false;
    defer free(vs_bc);

    ps_bc, ps_ok := _compile_shader(SHADER_SOURCE, "PS", "ps_5_0");
    if !ps_ok  return false;
    defer free(ps_bc);

    hr := ID3D11Device_CreateVertexShader(d3d_device, vs_bc.data, cast(u64) vs_bc.count, null, *g_vertex_shader);
    if FAILED(hr) {
        print("CreateVertexShader failed: %\n", hr);
        return false;
    }

    hr  = ID3D11Device_CreatePixelShader(d3d_device, ps_bc.data, cast(u64) ps_bc.count, null, *g_pixel_shader);
    if FAILED(hr) {
        print("CreatePixelShader failed: %\n", hr);
        return false;
    }

    // Input layout must match Vertex struct:
    //   position : Vector3  offset  0  (R32G32B32_FLOAT)
    //   normal   : Vector3  offset 12  (R32G32B32_FLOAT)
    //   uv       : Vector2  offset 24  (R32G32_FLOAT)
    layout: [3] D3D11_INPUT_ELEMENT_DESC;
    layout[0].SemanticName         = "POSITION";
    layout[0].Format               = .R32G32B32_FLOAT;
    layout[0].AlignedByteOffset    = 0;
    layout[0].InputSlotClass       = .VERTEX_DATA;

    layout[1].SemanticName         = "NORMAL";
    layout[1].Format               = .R32G32B32_FLOAT;
    layout[1].AlignedByteOffset    = 12;
    layout[1].InputSlotClass       = .VERTEX_DATA;

    layout[2].SemanticName         = "TEXCOORD";
    layout[2].Format               = .R32G32_FLOAT;
    layout[2].AlignedByteOffset    = 24;
    layout[2].InputSlotClass       = .VERTEX_DATA;

    hr = ID3D11Device_CreateInputLayout(d3d_device, layout.data, cast(u32) layout.count,
                                        vs_bc.data, cast(u64) vs_bc.count, *g_input_layout);
    if FAILED(hr) {
        print("CreateInputLayout failed: %\n", hr);
        return false;
    }

    return true;
}

_create_states :: () -> bool {
    // Rasteriser: CCW front face (matches our meshing winding), back-face cull
    {
        desc: D3D11_RASTERIZER_DESC;
        desc.FillMode              = .SOLID;
        desc.CullMode              = .BACK;
        desc.FrontCounterClockwise = BOOL.TRUE;
        desc.DepthClipEnable       = BOOL.TRUE;
        hr := ID3D11Device_CreateRasterizerState(d3d_device, *desc, *g_raster_state);
        if FAILED(hr) {
            print("CreateRasterizerState failed: %\n", hr);
            return false;
        }
    }

    // Depth stencil: standard less-than depth test, write enabled
    {
        desc: D3D11_DEPTH_STENCIL_DESC;
        desc.DepthEnable    = BOOL.TRUE;
        desc.DepthWriteMask = .ALL;
        desc.DepthFunc      = .LESS;
        hr := ID3D11Device_CreateDepthStencilState(d3d_device, *desc, *g_ds_state);
        if FAILED(hr) {
            print("CreateDepthStencilState failed: %\n", hr);
            return false;
        }
    }

    return true;
}

_create_const_buffer :: () -> bool {
    desc: D3D11_BUFFER_DESC;
    desc.ByteWidth      = size_of(Matrix4);   // 64 bytes, already 16-byte aligned
    desc.Usage          = .DYNAMIC;
    desc.BindFlags      = .CONSTANT_BUFFER;
    desc.CPUAccessFlags = .WRITE;

    hr := ID3D11Device_CreateBuffer(d3d_device, *desc, null, *g_cb_frame);
    if FAILED(hr) {
        print("CreateBuffer (constant) failed: %\n", hr);
        return false;
    }
    return true;
}

_create_depth_buffer :: (width: s32, height: s32) -> bool {
    tex_desc: D3D11_TEXTURE2D_DESC;
    tex_desc.Width          = cast(u32) width;
    tex_desc.Height         = cast(u32) height;
    tex_desc.MipLevels      = 1;
    tex_desc.ArraySize      = 1;
    tex_desc.Format         = .D24_UNORM_S8_UINT;
    tex_desc.SampleDesc.Count = 1;
    tex_desc.Usage          = .DEFAULT;
    tex_desc.BindFlags      = .DEPTH_STENCIL;

    depth_tex: *ID3D11Texture2D;
    hr := ID3D11Device_CreateTexture2D(d3d_device, *tex_desc, null, *depth_tex);
    if FAILED(hr) {
        print("CreateTexture2D (depth) failed: %\n", hr);
        return false;
    }
    defer IUnknown_Release(depth_tex);

    dsv_desc: D3D11_DEPTH_STENCIL_VIEW_DESC;
    dsv_desc.Format             = .D24_UNORM_S8_UINT;
    dsv_desc.ViewDimension      = .TEXTURE2D;
    dsv_desc.Texture2D.MipSlice = 0;

    hr = ID3D11Device_CreateDepthStencilView(d3d_device, cast(*ID3D11Resource) depth_tex, *dsv_desc, *g_depth_view);
    if FAILED(hr) {
        print("CreateDepthStencilView failed: %\n", hr);
        return false;
    }

    return true;
}
