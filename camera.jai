// Fly camera: Y-up, left-handed Z-forward coordinate system.
// Controls: WASD to move, Space/Shift for up/down, mouse to look.

#import "Math";
#import "Windows";

Camera :: struct {
    position    : Vector3 = .{48.0, 35.0, -20.0};
    yaw         : float   = 0.0;    // rotation around world Y (radians)
    pitch       : float   = -0.45;  // rotation around local X (radians), clamped ±85°
    move_speed  : float   = 20.0;
    sensitivity : float   = 0.002;
}

// Forward direction derived purely from yaw/pitch.
camera_forward :: inline (using cam: Camera) -> Vector3 {
    return .{
        sin(yaw) * cos(pitch),
        sin(pitch),
        cos(yaw) * cos(pitch),
    };
}

// Right direction is always horizontal (no pitch applied to right vector).
camera_right :: inline (using cam: Camera) -> Vector3 {
    return .{cos(yaw), 0.0, -sin(yaw)};
}

// Row-major view matrix for LH Y-up system.
// With #pragma pack_matrix(row_major) in HLSL and mul(mvp, pos),
// this produces the correct camera-space transform.
camera_make_view :: (using cam: Camera) -> Matrix4 {
    fwd   := camera_forward(cam);
    right := camera_right(cam);
    up    := cross_product(fwd, right);  // LH: fwd × right = world up

    m: Matrix4;
    m._11 = right.x;  m._12 = right.y;  m._13 = right.z;  m._14 = -dot_product(right, position);
    m._21 = up.x;     m._22 = up.y;     m._23 = up.z;     m._24 = -dot_product(up, position);
    m._31 = fwd.x;    m._32 = fwd.y;    m._33 = fwd.z;    m._34 = -dot_product(fwd, position);
    m._41 = 0.0;      m._42 = 0.0;      m._43 = 0.0;      m._44 = 1.0;
    return m;
}

// LH perspective projection, depth range [0,1] (DX11 standard).
camera_make_projection :: (fov_y: float, aspect: float, near: float, far: float) -> Matrix4 {
    f := 1.0 / tan(fov_y * 0.5);
    m: Matrix4;
    m._11 = f / aspect;
    m._22 = f;
    m._33 = far / (far - near);
    m._34 = -(near * far) / (far - near);
    m._43 = 1.0;  // sends z → w for perspective divide
    return m;
}

camera_update :: (cam: *Camera, dt: float, mouse_dx: s32, mouse_dy: s32) {
    // Mouse look
    cam.yaw   = cam.yaw   + cam.sensitivity * cast(float) mouse_dx;
    cam.pitch = cam.pitch - cam.sensitivity * cast(float) mouse_dy;
    if cam.pitch < -1.48  cam.pitch = -1.48;   // clamp ±85°
    if cam.pitch >  1.48  cam.pitch =  1.48;

    // Keyboard movement
    fwd   := camera_forward(cam.*);
    right := camera_right(cam.*);
    spd   := cam.move_speed * dt;

    if GetAsyncKeyState(#char "W") < 0  cam.position = cam.position + fwd   * spd;
    if GetAsyncKeyState(#char "S") < 0  cam.position = cam.position - fwd   * spd;
    if GetAsyncKeyState(#char "D") < 0  cam.position = cam.position + right * spd;
    if GetAsyncKeyState(#char "A") < 0  cam.position = cam.position - right * spd;
    if GetAsyncKeyState(VK_SPACE)  < 0  cam.position.y = cam.position.y + spd;
    if GetAsyncKeyState(VK_SHIFT)  < 0  cam.position.y = cam.position.y - spd;
}
