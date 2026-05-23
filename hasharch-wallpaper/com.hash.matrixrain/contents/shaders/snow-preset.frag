#version 440

// GPU weather background. One procedural fragment shader for every condition;
// driven entirely by uniforms so the GPU renders at vsync with near-zero CPU.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float time;        // seconds (animated from QML)
    float condition;   // 0 clear, 1 clouds, 2 rain, 3 snow, 4 storm, 5 fog
    float isDay;       // 1 day, 0 night
    float windFactor;  // 0..1
    float aspect;      // width / height
};

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    float a = hash21(i), b = hash21(i + vec2(1, 0));
    float c = hash21(i + vec2(0, 1)), d = hash21(i + vec2(1, 1));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.0; a *= 0.5; }
    return v;
}

void setSky(int c, bool day, out vec3 top, out vec3 bot) {
    if (c == 0)      { top = day ? vec3(0.11,0.42,0.90) : vec3(0.015,0.024,0.06); bot = day ? vec3(0.86,0.93,1.0)  : vec3(0.04,0.08,0.19); }
    else if (c == 1) { top = day ? vec3(0.52,0.59,0.66) : vec3(0.04,0.06,0.09);  bot = day ? vec3(0.76,0.81,0.84) : vec3(0.11,0.15,0.19); }
    else if (c == 2) { top = day ? vec3(0.27,0.32,0.37) : vec3(0.10,0.13,0.15);  bot = day ? vec3(0.49,0.54,0.58) : vec3(0.17,0.21,0.24); }
    else if (c == 3) { top = day ? vec3(0.52,0.57,0.63) : vec3(0.11,0.14,0.17);  bot = day ? vec3(0.80,0.84,0.87) : vec3(0.18,0.23,0.27); }
    else if (c == 4) { top = day ? vec3(0.09,0.11,0.14) : vec3(0.02,0.027,0.043);bot = day ? vec3(0.18,0.20,0.25) : vec3(0.09,0.11,0.14); }
    else             { top = day ? vec3(0.60,0.64,0.66) : vec3(0.14,0.16,0.17);  bot = day ? vec3(0.81,0.83,0.84) : vec3(0.23,0.25,0.27); }
}

vec3 drawSun(vec2 uv, vec3 col) {
    vec2 sp = vec2(0.74, 0.26);
    float d = length((uv - sp) * vec2(aspect, 1.0));
    float core = smoothstep(0.072, 0.058, d);
    float glow = pow(max(0.0, 1.0 - d / 0.55), 2.0) * 0.32;        // dimmer glow
    float ang  = atan(uv.y - sp.y, (uv.x - sp.x) * aspect);
    float rays = (0.5 + 0.5 * sin(ang * 14.0 + time * 0.6)) * pow(max(0.0, 1.0 - d / 0.40), 3.0) * 0.11;
    col += vec3(1.0, 0.92, 0.65) * (glow + rays);
    // a bright shine that travels around the sun in a circle
    float sa = time * 0.7;
    vec2 shp = sp + 0.12 * vec2(cos(sa) / aspect, sin(sa));
    float shine = pow(max(0.0, 1.0 - length((uv - shp) * vec2(aspect, 1.0)) / 0.10), 3.0) * 0.35;
    col += vec3(1.0, 0.96, 0.75) * shine;
    col = mix(col, vec3(1.0, 0.96, 0.80), core * 0.9);             // softer core
    return col;
}
vec3 drawMoonStars(vec2 uv, vec3 col) {
    vec2 g = uv * vec2(aspect, 1.0) * 40.0;
    float s = hash21(floor(g));
    float star = step(0.985, s) * (0.5 + 0.5 * sin(time * 2.0 + s * 30.0));
    col += vec3(star) * step(uv.y, 0.7);
    vec2 mp = vec2(0.76, 0.24);
    float d = length((uv - mp) * vec2(aspect, 1.0));
    col += vec3(0.8, 0.85, 1.0) * pow(max(0.0, 1.0 - d / 0.35), 2.0) * 0.15;
    col = mix(col, vec3(0.96, 0.97, 1.0), smoothstep(0.075, 0.06, d));
    return col;
}
float clouds(vec2 uv) {
    vec2 p = uv * vec2(aspect, 1.0) * vec2(1.8, 3.0);
    p.x += time * 0.015 * (1.0 + windFactor * 3.0);
    float n = fbm(p);
    n *= smoothstep(0.98, 0.10, uv.y);   // concentrate toward the top of the sky
    return smoothstep(0.32, 0.62, n);
}
float rain(vec2 uv, float speed, float cols) {
    vec2 p = vec2(uv.x * aspect, uv.y);
    p.x += windFactor * 0.18 * (1.0 - uv.y);            // slight wind slant
    float c = floor(p.x * cols);
    float ch = hash21(vec2(c, 7.0));
    float hasRain = step(0.55, fract(ch * 13.7));
    float fx = fract(p.x * cols) - 0.5;
    float y = p.y * 3.0 - time * speed * (0.8 + ch * 0.5) + ch * 17.0;
    float fy = fract(y) - 0.5;
    // bigger, see-through water droplet: bright glassy rim + faint fill
    float d = length(vec2(fx * 1.6, fy * cols * 0.42));
    float rim  = smoothstep(0.5, 0.40, d) * smoothstep(0.22, 0.40, d) * 1.6;
    float body = smoothstep(0.5, 0.0, d) * 0.15;
    return (rim + body) * hasRain;
}
// SNOW PRESET: soft round dots, gentle sway, slow fall (the look you liked)
float snow(vec2 uv) {
    float cols = 45.0;
    vec2 p = vec2(uv.x * aspect, uv.y);
    p.x += sin(uv.y * 5.0 + time * 0.4) * 0.015 + windFactor * time * 0.05;   // gentle sway
    float c = floor(p.x * cols);
    float ch = hash21(vec2(c, 7.0));
    float has = step(0.50, fract(ch * 13.7));
    float fx = fract(p.x * cols) - 0.5;
    float y = p.y * 2.5 - time * 0.45 * (0.7 + ch * 0.5) + ch * 17.0;          // slow fall
    float fy = fract(y) - 0.5;
    return smoothstep(0.5, 0.0, length(vec2(fx * 2.0, fy * cols * 0.55))) * has;
}

void main() {
    vec2 uv = qt_TexCoord0;
    int c = int(condition + 0.5);
    bool day = isDay > 0.5;

    vec3 top, bot;
    setSky(c, day, top, bot);
    vec3 col = mix(top, bot, uv.y);

    if (c == 0) {
        col = day ? drawSun(uv, col) : drawMoonStars(uv, col);
    } else if (c == 1) {
        col = day ? drawSun(uv, col) : drawMoonStars(uv, col);
        col = mix(col, day ? vec3(0.95) : vec3(0.18, 0.22, 0.28), clouds(uv) * 0.9);
    } else if (c == 2) {
        col = mix(col, vec3(0.55, 0.59, 0.63), clouds(uv) * 0.8);
        col += vec3(0.72, 0.77, 0.82) * rain(uv, 1.5, 38.0) * 0.7;
    } else if (c == 3) {
        col = mix(col, vec3(0.8, 0.83, 0.86), clouds(uv) * 0.6);
        col += vec3(1.0) * snow(uv) * 0.9;
    } else if (c == 4) {
        col = mix(col, vec3(0.10, 0.12, 0.16), clouds(uv * 1.2));
        col += vec3(0.72, 0.77, 0.85) * rain(uv, 2.2, 55.0) * 0.7;
        float t = time * 0.5;
        float flash = step(0.96, hash21(vec2(floor(t), 3.0))) * (1.0 - fract(t)) * 0.85;
        col += vec3(0.85, 0.9, 1.0) * flash;
    } else {
        for (int k = 0; k < 4; k++) {
            float fk = float(k);
            float band = smoothstep(0.12, 0.0, abs(uv.y - (0.25 + fk * 0.18)));
            float n = fbm(vec2(uv.x * 3.0 + time * 0.05 * (1.0 + fk) + windFactor * time * 0.1, fk * 5.0));
            col = mix(col, vec3(0.82, 0.84, 0.86), band * n * 0.5);
        }
    }

    float vig = smoothstep(1.2, 0.3, length(uv - 0.5));
    col *= mix(0.82, 1.0, vig);
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
