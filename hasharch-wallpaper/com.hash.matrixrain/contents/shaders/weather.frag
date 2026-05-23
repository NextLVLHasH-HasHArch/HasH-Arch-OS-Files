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
    vec4  rainColor;   // configurable rain droplet colour
    float moonPhase;   // 0=new, 0.25=first quarter, 0.5=full, 0.75=last quarter
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
    if (c == 0)      { top = day ? vec3(0.10,0.40,0.86) : vec3(0.015,0.024,0.06); bot = day ? vec3(0.42,0.70,0.98) : vec3(0.04,0.08,0.19); }
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
    float glow = pow(max(0.0, 1.0 - d / 0.50), 2.0) * 0.20;        // dimmer
    float ang  = atan(uv.y - sp.y, (uv.x - sp.x) * aspect);
    float rays = (0.5 + 0.5 * sin(ang * 14.0 + time * 0.6)) * pow(max(0.0, 1.0 - d / 0.38), 3.0) * 0.07;
    col += vec3(1.0, 0.80, 0.30) * (glow + rays);                  // warm yellow glow
    // a soft shine that travels around the sun in a circle (dim, yellow)
    float sa = time * 0.7;
    vec2 shp = sp + 0.12 * vec2(cos(sa) / aspect, sin(sa));
    float shine = pow(max(0.0, 1.0 - length((uv - shp) * vec2(aspect, 1.0)) / 0.10), 3.0) * 0.20;
    col += vec3(1.0, 0.85, 0.40) * shine;
    col = mix(col, vec3(1.0, 0.84, 0.30), core);                   // yellow sun disc
    return col;
}
vec3 drawMoonStars(vec2 uv, vec3 col) {
    // Soft round stars: at most one per grid cell, placed at a random sub-cell
    // position with a smooth radial falloff. (The old version lit the whole cell,
    // which rendered as white SQUARES.)
    vec2 g  = uv * vec2(aspect, 1.0) * 40.0;
    vec2 gi = floor(g);
    vec2 gf = fract(g) - 0.5;
    float s = hash21(gi);
    vec2  sp2 = (vec2(hash21(gi + 1.3), hash21(gi + 2.7)) - 0.5) * 0.7;
    vec2  lp  = gf - sp2;                               // offset from the star centre
    // X / sparkle shape: two DIAGONAL arms (offset rotated 45°), kept small so the
    // stars stay the size they already are.
    vec2  rp   = vec2(lp.x + lp.y, lp.x - lp.y) * 0.70711;
    float thin = 0.028, arm = 0.12;
    float a1 = smoothstep(thin, 0.0, abs(rp.x)) * smoothstep(arm, 0.0, abs(rp.y));
    float a2 = smoothstep(thin, 0.0, abs(rp.y)) * smoothstep(arm, 0.0, abs(rp.x));
    float core = smoothstep(0.035, 0.0, length(lp));
    float shape = clamp(a1 + a2 + core, 0.0, 1.0);
    // each star twinkles at its OWN speed and phase, so they visibly alternate.
    float tw = 0.5 + 0.5 * sin(time * (1.0 + s * 3.0) + s * 40.0);
    tw = tw * tw;                                       // sharper, more obvious twinkle
    float star = step(0.985, s) * shape * (0.2 + 1.0 * tw);
    col += vec3(star) * smoothstep(0.78, 0.66, uv.y);   // fade out toward the horizon

    // ----- moon with the real lunar phase (crescent / half / gibbous / full) -----
    vec2  mp = vec2(0.76, 0.24);
    float R  = 0.075;
    vec2  rel = (uv - mp) * vec2(aspect, 1.0);
    float d   = length(rel);
    float litAmt = clamp(sin(3.14159265 * moonPhase), 0.0, 1.0);   // 0 new .. 1 full
    col += vec3(0.8, 0.85, 1.0) * pow(max(0.0, 1.0 - d / 0.35), 2.0) * 0.15 * (0.25 + 0.75 * litAmt);
    if (d < R * 1.25) {
        vec2  nrm = rel / R;                            // disc-normalised, [-1,1]
        float z   = sqrt(max(0.0, 1.0 - dot(nrm, nrm)));
        float phi = 6.28318531 * moonPhase;
        float illum = nrm.x * sin(phi) - cos(phi) * z;  // >0 -> sun-facing (lit)
        float face  = smoothstep(R, R * 0.93, d);       // antialiased disc edge
        float litMask = smoothstep(-0.05, 0.06, illum); // soft terminator
        // Paint ONLY the lit crescent over the sky; the dark side stays the night
        // sky itself, so it blends in (no flat dark disc that mismatches the sky).
        col = mix(col, vec3(0.96, 0.97, 1.0), face * litMask);
    }
    return col;
}
float clouds(vec2 uv) {
    vec2 p = uv * vec2(aspect, 1.0) * vec2(1.7, 2.8);
    p.x += time * 0.02 * (1.0 + windFactor * 3.0);    // drift across the sky
    // domain-warped fbm -> billowy, voluminous clouds instead of flat haze.
    vec2 q = vec2(fbm(p + vec2(0.0, time * 0.012)), fbm(p + vec2(5.2, 1.3)));
    float n = fbm(p + 1.6 * q);
    n *= smoothstep(1.0, 0.12, uv.y);                 // thick up top, gone by the horizon
    return smoothstep(0.34, 0.68, n);                 // puffier with softer edges
}
float rain(vec2 uv, float speed, float cols) {
    vec2 p = vec2(uv.x * aspect, uv.y);
    p.x += windFactor * 0.18 * (1.0 - uv.y);            // slight wind slant
    float c = floor(p.x * cols);
    float ch = hash21(vec2(c, 7.0));
    float hasRain = step(0.40, fract(ch * 13.7));     // fewer active columns
    float xoff = (hash21(vec2(c, 3.0)) - 0.5) * 0.5;  // random horizontal jitter
    float fx = fract(p.x * cols) - 0.5 - xoff;
    float line = smoothstep(0.16, 0.0, abs(fx));      // thin vertical line
    float freq = 5.0 + ch * 8.0;                      // random vertical spacing
    float spd  = speed * (0.7 + ch * 0.8);            // random fall speed
    float len  = 0.35 + hash21(vec2(c, 5.0)) * 0.5;   // random streak length
    float y = uv.y * freq - time * spd + ch * 20.0;
    float d = fract(y);
    float streak = smoothstep(0.0, 0.06, d) * (1.0 - smoothstep(0.06, len, d));
    float op = 0.3 + hash21(vec2(c, 9.0)) * 0.4;      // random opacity
    return line * streak * hasRain * op;
}
// splash, fired exactly when a column's drop reaches the bottom (synced to rain())
float splash(vec2 uv, float speed, float cols) {
    float base = 0.985;
    if (uv.y < base - 0.05) return 0.0;
    float pxx = uv.x * aspect + windFactor * 0.12 * (1.0 - uv.y);
    float c = floor(pxx * cols);
    float ch = hash21(vec2(c, 7.0));
    float hasRain = step(0.40, fract(ch * 13.7));
    // same vertical phase as rain(): a drop head is at the baseline when fract == 0
    float freq = 5.0 + ch * 8.0;
    float spd  = speed * (0.7 + ch * 0.8);
    float yb = base * freq - time * spd + ch * 20.0;
    float land = fract(yb);                            // 0 = just landed
    if (land > 0.35) return 0.0;                        // only briefly after landing
    float cxp = (c + 0.5) / cols;
    float dy = base - uv.y;
    float rad = land * 0.10;                            // ring expands after landing
    float ring = smoothstep(0.010, 0.0, abs(length(vec2(pxx - cxp, dy)) - rad));
    return ring * (1.0 - land / 0.35) * hasRain;
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
        col += rainColor.rgb * rain(uv, 0.75, 60.0) * 0.9;                       // rain BEHIND the clouds
        col = mix(col, vec3(0.50, 0.54, 0.59), clamp(clouds(uv) * 1.6, 0.0, 1.0)); // opaque clouds fully occlude the rain
        col += rainColor.rgb * splash(uv, 0.75, 60.0) * 0.7;                     // ground splash (front)
    } else if (c == 3) {
        col += vec3(1.0) * snow(uv) * 0.9;                                       // snow BEHIND the clouds
        col = mix(col, vec3(0.78, 0.81, 0.85), clamp(clouds(uv) * 1.5, 0.0, 1.0)); // opaque clouds fully occlude the snow
    } else if (c == 4) {
        col += rainColor.rgb * rain(uv, 1.1, 80.0) * 0.9;           // rain BEHIND the storm clouds
        col = mix(col, vec3(0.10, 0.12, 0.16), clouds(uv * 1.2));   // dark clouds in front
        col += rainColor.rgb * splash(uv, 1.1, 80.0) * 0.6;
        float t = time * 0.5;
        float flash = step(0.96, hash21(vec2(floor(t), 3.0))) * (1.0 - fract(t)) * 0.85;
        col += vec3(0.85, 0.9, 1.0) * flash;
    } else {
        // FOG: thick, soft, VOLUMETRIC cloud cover (not blurry bands). Two layers of
        // the cloud field at different scales/drift make a dense fog bank that's
        // heavier toward the bottom, like ground fog rolling up.
        vec3 fogCol = day ? vec3(0.84, 0.86, 0.89) : vec3(0.20, 0.23, 0.27);
        float f1 = clouds(uv);
        float f2 = clouds(uv * vec2(1.6, 1.2) + vec2(3.1, 0.7));
        float fog = clamp(f1 * 0.7 + f2 * 0.6, 0.0, 1.0);
        fog = mix(fog, 1.0, smoothstep(0.55, 1.0, uv.y) * 0.5);
        col = mix(col, fogCol, fog * 0.92);
    }

    float vig = smoothstep(1.2, 0.3, length(uv - 0.5));
    col *= mix(0.82, 1.0, vig);
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
