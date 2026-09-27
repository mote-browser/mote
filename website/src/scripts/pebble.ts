// The pebble, alive: the logomark's outline filled with the icon's warm light,
// its four glows drifting inside it, shaded like glass and lit from wherever
// the pointer is. Drawn at full resolution (it has a crisp edge) but small.

import { run } from "./shader";

const fragment = `#version 300 es
precision highp float;
uniform vec2 size;
uniform float time;
uniform vec2 pointer;
out vec4 color;

const vec3 base = vec3(0.937, 0.812, 0.722);
const vec3 cream = vec3(1.0, 0.953, 0.902);
const vec3 peach = vec3(0.965, 0.776, 0.659);
const vec3 coral = vec3(0.867, 0.561, 0.463);
const vec3 sand = vec3(0.957, 0.863, 0.753);

// Signed distance to the pebble: a circle pushed out to the right and at the
// top left, like pebble.svg, breathing a little.
float pebble(vec2 p, float t) {
  float a = atan(p.y, p.x);
  float r = 0.6 * (1.0 + 0.035 * cos(a - 0.5) + 0.03 * cos(2.0 * a + 0.9) + 0.012 * sin(3.0 * a + t * 0.6));
  return length(p * vec2(0.98, 1.02)) - r;
}

vec3 pool(vec3 into, vec3 tint, vec2 p, vec2 at, float r) {
  return mix(into, tint, smoothstep(r, 0.0, length(p - at)) * 0.9);
}

void main() {
  float unit = 0.5 * min(size.x, size.y);
  vec2 p = (gl_FragCoord.xy - 0.5 * size) / unit;
  float t = time;
  p.y -= 0.015 * sin(t * 0.8);

  float d = pebble(p, t);
  vec2 e = vec2(0.002, 0.0);
  vec2 slope = normalize(vec2(pebble(p + e.xy, t) - pebble(p - e.xy, t), pebble(p + e.yx, t) - pebble(p - e.yx, t)));

  // The icon's four glows, drifting.
  vec3 fill = base;
  fill = pool(fill, sand, p, vec2(-0.28, -0.22) + 0.08 * vec2(sin(t * 0.31), cos(t * 0.27)), 0.6);
  fill = pool(fill, coral, p, vec2(0.22, -0.34) + 0.09 * vec2(cos(t * 0.23 + 1.0), sin(t * 0.29)), 0.62);
  fill = pool(fill, peach, p, vec2(0.34, 0.18) + 0.08 * vec2(sin(t * 0.26 + 2.0), cos(t * 0.33 + 1.0)), 0.6);
  fill = pool(fill, cream, p, vec2(-0.24, 0.3) + 0.07 * vec2(cos(t * 0.35 + 3.0), sin(t * 0.24 + 2.0)), 0.55);

  // Flat like a pebble: level across the middle, curving away near the edge.
  float curve = 1.0 - smoothstep(0.0, 0.16, -d);
  vec3 normal = normalize(vec3(slope * curve * 1.4, 1.0));
  vec3 lamp = normalize(vec3((pointer - 0.5) * 2.4, 1.1));
  float diffuse = max(dot(normal, lamp), 0.0);
  float shine = pow(max(dot(reflect(-lamp, normal), vec3(0.0, 0.0, 1.0)), 0.0), 28.0);

  vec3 body = fill * (0.9 + 0.14 * diffuse);
  body = mix(body, coral * 0.85, smoothstep(-0.08, 0.0, d) * 0.3 * (1.0 - diffuse));
  body += shine * 0.35 + smoothstep(-0.02, 0.0, d) * 0.1;

  float px = 1.5 / unit;
  float inside = 1.0 - smoothstep(-px, px, d);
  // The glow dies out well inside the canvas, so its edges never show.
  float reach = max(d, 0.0);
  vec3 halo = peach * exp(-reach * 7.0) * 0.32 * (1.0 - smoothstep(0.18, 0.36, reach));
  color = vec4(body * inside + halo * (1.0 - inside), inside + (1.0 - inside) * min(1.0, length(halo)));
}`;

export function pebble(canvas: HTMLCanvasElement) {
  run(canvas, { fragment, resolution: Math.min(devicePixelRatio, 2), fps: 60, start: 4 });
}
