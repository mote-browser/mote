// The light: a ribbon of warm light across the opening, split at its edges
// like light through a prism. All soft glow, so it renders at half resolution
// and 30 frames a second.

import { run } from "./shader";

const fragment = `#version 300 es
precision highp float;
uniform vec2 size;
uniform float time;
out vec4 color;

float glow(float d, float w) { return exp(-d * d / (w * w)); }
float grain(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * size) / size.y;
  float t = time;

  // The ribbon's centre line: a slow diagonal with two waves over it.
  float line = -0.07 * p.x + 0.06 * sin(p.x * 1.5 + t * 0.23) + 0.03 * sin(p.x * 3.1 - t * 0.37 + 1.3);
  // Pinched near the middle, opening toward the edges, breathing.
  float width = 0.008 + 0.03 * smoothstep(0.0, 1.4, abs(p.x + 0.2 * sin(t * 0.11))) + 0.005 * sin(p.x * 2.3 + t * 0.5);
  float split = 0.85 * width + 0.006;
  float d = p.y - line;

  vec3 warm = mix(vec3(1.0, 0.52, 0.34), vec3(1.0, 0.74, 0.56), 0.5 + 0.5 * sin(p.x * 1.7 + t * 0.2));
  vec3 cool = mix(vec3(0.42, 0.52, 1.0), vec3(0.55, 0.84, 1.0), 0.5 + 0.5 * sin(p.x * 1.3 - t * 0.15));
  vec3 rose = vec3(0.95, 0.46, 0.58);
  vec3 haze = vec3(1.0, 0.78, 0.64);

  float core = glow(d, width * 0.55) * 0.9;
  float above = glow(d - split, width) * 0.8;
  float below = glow(d + split, width * 0.9) * 0.6;
  float outer = glow(d - 2.4 * split, width * 1.8) * 0.3;
  float halo = glow(d, width * 9.0) * 0.2;

  float alpha = clamp(core + above + below + outer + halo, 0.0, 1.0);
  vec3 light = vec3(1.0) * core + warm * above + cool * below + rose * outer + haze * halo;
  // Premultiplied, and dithered against banding.
  light = min(light, vec3(alpha)) + (grain(gl_FragCoord.xy + t) - 0.5) / 255.0;
  color = vec4(light, alpha);
}`;

export function light(canvas: HTMLCanvasElement) {
  run(canvas, { fragment, resolution: Math.min(devicePixelRatio, 1.25) * 0.5, fps: 30, start: 14 });
}
