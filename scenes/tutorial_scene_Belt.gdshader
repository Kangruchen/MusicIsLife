shader_type canvas_item;

// 可以在检查器中随时调整滚动的方向和速度，正数向左，负数向右
uniform float speed = 0.5;

void fragment() {
    vec2 shifted_uv = UV;
    // 使用内置的 TIME 变量让 X 轴坐标随着时间不断偏移
    shifted_uv.x += TIME * speed;

    vec4 color = texture(TEXTURE, shifted_uv);
    COLOR = color;
}