shader_type canvas_item;

uniform vec2 cam_pos = vec2(0.0, 0.0);
uniform float zoom = 1.0;
// LOGICAL viewport size (e.g. 1920×1080 from `get_viewport_rect().size`),
// not the physical window. With `window/stretch/mode = canvas_items` the
// actual render target is the window, but canvas items are pre-scaled to
// look like they're drawn at the logical viewport — so the world-units
// per "logical pixel" stay constant regardless of how the user resized.
uniform vec2 screen_size = vec2(1920.0, 1080.0);

uniform float hex_size = 64.0;
uniform float line_thickness = 2.0; // Stays exactly this thick in screen pixels!
uniform vec4 grid_color : source_color = vec4(0.4, 0.6, 1.0, 0.2); // Soft blueish grid
uniform vec4 bg_color : source_color = vec4(0.12, 0.12, 0.14, 1.0); // Dark background

void fragment() {
    // 1. Convert screen pixel to world coordinates.
    //    SCREEN_UV is 0..1 across the ACTUAL rendered screen, regardless
    //    of `window/stretch/mode`. Multiplying by the LOGICAL viewport
    //    size gives the matching logical pixel position, which is what
    //    the world / Camera2D coordinate system uses. FRAGCOORD would
    //    give actual-window pixels and desync with the Camera2D when the
    //    user resizes the window away from the design size.
    vec2 world_pos = (SCREEN_UV - vec2(0.5)) * screen_size / zoom + cam_pos;

    // 2. Pointy-top hex tiling math (matches your HexMath perfectly)
    // A pointy top hex repeats every sqrt(3)*R horizontally and 3*R vertically.
    vec2 r = vec2(1.73205080757 * hex_size, 3.0 * hex_size);
    vec2 h = r * 0.5;

    // We overlap two staggered rectangular grids to create the hex centers
    vec2 a = mod(world_pos + h, r) - h;
    vec2 b = mod(world_pos, r) - h;

    // 'gv' is the vector from the current pixel to the nearest hex center
    vec2 gv = dot(a, a) < dot(b, b) ? a : b;

    // 3. Distance to the pointy-top hex edge
    vec2 p = abs(gv);
    float apothem = hex_size * 0.86602540378; // hex_size * sqrt(3)/2
    
    // For pointy top, edges are defined by horizontal distance (p.x) 
    // and the angled faces (dot product with 30 degree normal)
    float dist = max(p.x, dot(p, vec2(0.5, 0.86602540378)));
    float edge_dist = apothem - dist;

    // 4. Zoom-independent anti-aliased lines
    float pixel_size = 1.0 / zoom; // Size of 1 screen pixel in world space
    float half_thick = (line_thickness * 0.5) * pixel_size;
    
    // Smoothstep creates a perfect, crisp edge blending across exactly 2 pixels
    float line_alpha = smoothstep(half_thick + pixel_size, half_thick - pixel_size, edge_dist);

    // Mix the background color with the grid line color
    COLOR = mix(bg_color, vec4(grid_color.rgb, 1.0), line_alpha * grid_color.a);
}