// Runs one fragment shader over a canvas: raw WebGL2, one triangle, no
// library. It draws only while the canvas is on screen and the tab visible,
// at a capped frame rate and resolution, and with reduced motion draws one
// still frame. The shader gets `size` (pixels), `time` (seconds) and
// `pointer` (0–1 across the canvas, eased toward the mouse).

const vertex = `#version 300 es
in vec2 position;
void main() { gl_Position = vec4(position, 0.0, 1.0); }`;

export interface Shader {
  fragment: string;
  /** Canvas pixels per CSS pixel. */
  resolution: number;
  fps: number;
  /** Where time starts, in seconds, so the first frame already has shape. */
  start?: number;
}

export function run(canvas: HTMLCanvasElement, { fragment, resolution, fps, start = 0 }: Shader) {
  const gl = canvas.getContext("webgl2", {
    alpha: true,
    premultipliedAlpha: true,
    antialias: false,
    depth: false,
    stencil: false,
    powerPreference: "low-power",
  });
  if (!gl) return;

  const program = gl.createProgram();
  for (const [type, source] of [
    [gl.VERTEX_SHADER, vertex],
    [gl.FRAGMENT_SHADER, fragment],
  ] as const) {
    const shader = gl.createShader(type)!;
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    gl.attachShader(program, shader);
  }
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) return;
  gl.useProgram(program);

  // One triangle that covers the whole canvas.
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const position = gl.getAttribLocation(program, "position");
  gl.enableVertexAttribArray(position);
  gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
  const size = gl.getUniformLocation(program, "size");
  const time = gl.getUniformLocation(program, "time");
  const pointer = gl.getUniformLocation(program, "pointer");

  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const interval = 1000 / fps;
  const origin = performance.now();
  const aim = { x: 0.35, y: 0.7 };
  const eased = { ...aim };
  let visible = false;
  let frame = 0;
  let last = 0;

  const draw = (now: number) => {
    eased.x += (aim.x - eased.x) * 0.08;
    eased.y += (aim.y - eased.y) * 0.08;
    gl.uniform1f(time, start + (still ? 0 : (now - origin) / 1000));
    gl.uniform2f(pointer, eased.x, eased.y);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  };

  const tick = (now: number) => {
    frame = requestAnimationFrame(tick);
    if (now - last < interval - 2) return;
    last = now;
    draw(now);
  };

  const play = () => {
    if (frame || still || !visible || document.hidden) return;
    frame = requestAnimationFrame(tick);
  };

  const pause = () => {
    cancelAnimationFrame(frame);
    frame = 0;
  };

  // Only runs when the window resizes: nothing resizes a canvas on scroll.
  new ResizeObserver(() => {
    const width = Math.max(1, Math.round(canvas.clientWidth * resolution));
    const height = Math.max(1, Math.round(canvas.clientHeight * resolution));
    if (width === canvas.width && height === canvas.height) return;
    canvas.width = width;
    canvas.height = height;
    gl.viewport(0, 0, width, height);
    gl.uniform2f(size, width, height);
    draw(performance.now());
    canvas.classList.add("is-lit");
  }).observe(canvas);

  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    if (visible) play();
    else pause();
  }).observe(canvas);

  document.addEventListener("visibilitychange", () => (document.hidden ? pause() : play()));

  if (pointer) {
    addEventListener(
      "pointermove",
      (event) => {
        if (!visible) return;
        const box = canvas.getBoundingClientRect();
        aim.x = Math.min(1.5, Math.max(-0.5, (event.clientX - box.left) / box.width));
        aim.y = Math.min(1.5, Math.max(-0.5, 1 - (event.clientY - box.top) / box.height));
      },
      { passive: true },
    );
  }
}
