shader_type canvas_item;

// Wire visual shader. The base color matches the previous
// Line2D.default_color setting (and is multiplied by the per-vertex
// COLOR so the player can still fade lines via vertex modulate). When
// `pulse_enabled` is true, a soft band travels along UV.x at
// `pulse_speed` cycles per second; `flow_forward` flips the direction
// so the band always reads output → input regardless of which slot the
// player clicked first when laying the wire.

uniform vec4 base_color : source_color = vec4(1.0);
uniform float pulse_speed = 0.45;       // cycles per second
uniform float pulse_width = 0.25;       // fraction of the line length
uniform float pulse_brightness = 0.55;
uniform bool  pulse_enabled = false;
uniform bool  flow_forward = true;

void fragment() {
    vec4 col = base_color * COLOR;
    if (pulse_enabled) {
        float u = flow_forward ? UV.x : 1.0 - UV.x;
        float t = fract(u - TIME * pulse_speed);
        // Soft triangular pulse: rises from 0 → 1 over `pulse_width`,
        // falls back over the next `pulse_width`.
        float band = smoothstep(0.0, pulse_width, t)
                   * (1.0 - smoothstep(pulse_width, 2.0 * pulse_width, t));
        col.rgb -= vec3(pulse_brightness) * band;
    }
    COLOR = col;
}
