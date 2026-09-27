// The size chart: Mote's pebble and a circle for each other browser, their
// areas in proportion to the installed apps, standing on one line. The
// camera starts close on the pebble and pulls back as the scene is scrolled
// until everything is in view. Drawn on a canvas each time the scroll moves,
// so it stays sharp at any scale and the names stay a readable size.

export interface Body {
  name: string;
  mb: number;
}

// Space between neighbours, as a share of the largest diameter.
const gap = 0.14;
// How much closer the camera starts than where it ends.
const closest = 16;

// The pebble from Mote.icon, in its 564 × 550 box.
const pebble = new Path2D("M234 32C404 0 564 100 560 270C556 420 454 530 284 540C124 550 0 470 2 318C4 170 94 58 234 32Z");

export function zoom(canvas: HTMLCanvasElement, bodies: Body[]) {
  const context = canvas.getContext("2d")!;
  const largest = Math.max(...bodies.map((b) => b.mb));

  // Lay the bodies out left to right on the line y = 0, in units of the
  // largest diameter.
  // Mote gets more room after it than the others: it's tiny, and its name
  // needs space from its neighbour's on a narrow screen.
  let x = 0;
  const laid = bodies.map((body, i) => {
    const d = Math.sqrt(body.mb / largest);
    const centre = x + d / 2;
    x += d + (i === 0 ? gap * 2.4 : gap);
    return { ...body, d, centre };
  });
  const width = x - gap;
  const mote = laid[0];

  let size = { w: 0, h: 0 };
  let eased = 1;
  let font = "system-ui";

  const label = (mb: number) => (mb < 1000 ? `${mb} MB` : `${(mb / 1000).toFixed(2).replace(/0$/, "")} GB`);

  const draw = () => {
    const { w, h } = size;
    if (!w) return;
    const ratio = devicePixelRatio;
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    context.clearRect(0, 0, w, h);

    // At the end, the row fills most of the width; the largest is never
    // taller than a third of the height.
    const unit = Math.min((w * 0.84) / width, h * 0.3);
    // Zoom out at a steady pace: scale falls geometrically, and the point
    // held at the centre moves from the pebble to the middle of the row as
    // the view widens.
    const scale = closest ** (1 - eased);
    const along = (closest / scale - 1) / (closest - 1);
    const focus = {
      x: mote.centre + (width / 2 - mote.centre) * along,
      y: -mote.d / 2 + (-0.5 + mote.d / 2) * along,
    };
    // Where the focus sits on screen: low while close, clear of the words
    // above, and a little higher once everything is in view.
    const anchor = h * (0.68 - 0.04 * along);
    const screen = (px: number, py: number) => ({
      x: w / 2 + (px - focus.x) * unit * scale,
      y: anchor + (py - focus.y) * unit * scale,
    });

    // The ground.
    const ground = screen(0, 0).y;
    context.strokeStyle = "rgba(23, 23, 26, 0.12)";
    context.lineWidth = 1;
    context.beginPath();
    context.moveTo(0, ground + 0.5);
    context.lineTo(w, ground + 0.5);
    context.stroke();

    laid.forEach((body, i) => {
      const centre = screen(body.centre, -body.d / 2);
      const radius = (body.d / 2) * unit * scale;
      if (centre.x + radius < -40 || centre.x - radius > w + 40) return;

      // Each stone fades up into place as it comes in from the right edge.
      const arrived = body === mote ? 1 : Math.min(1, Math.max(0, (w + radius - centre.x) / (radius + 160)));
      context.globalAlpha = arrived;
      const rise = (1 - arrived) * 16;
      drawShadow(centre.x, ground, radius, body === mote);
      if (body === mote) drawStone(centre.x, centre.y, radius, warm, false, undefined, 1 + eased * 0.6);
      else drawStone(centre.x, centre.y + rise, radius, grey, i % 2 === 0, `${Math.round(body.mb / mote.mb)}×`);
      context.globalAlpha = 1;

      // The name under the line, once the body is big enough to have one.
      const shown = Math.min(1, Math.max(0, (radius - 6) / 20)) * arrived;
      if (shown <= 0 && body !== mote) return;
      context.globalAlpha = body === mote ? 1 : shown;
      context.textAlign = "center";
      context.fillStyle = body === mote ? "#c9704f" : "#17171a";
      context.font = `500 14px ${font}`;
      context.fillText(body.name, centre.x, ground + 26);
      context.fillStyle = body === mote ? "#c9704f" : "rgba(23, 23, 26, 0.55)";
      context.font = `400 12px ${font}`;
      context.fillText(label(body.mb), centre.x, ground + 44);
      context.globalAlpha = 1;
    });
  };

  // A stone: the pebble's outline, filled with four pools of light over a
  // base colour, like Mote.icon. Mote's is warm and glows, brighter once the
  // camera has pulled all the way back; the others are the same shape in
  // cool greys, some turned the other way, with how many Motes they weigh
  // pressed into them.
  type Light = readonly [number, number, number, string];
  const warm = {
    base: "#ecc2a6",
    glow: "rgba(217, 135, 106, 0.45)",
    lights: [
      [124, 100, 330, "255, 243, 230"],
      [474, 160, 310, "246, 198, 168"],
      [384, 490, 330, "212, 120, 92"],
      [84, 450, 290, "244, 220, 192"],
    ] as Light[],
  };
  const grey = {
    base: "#dcdce0",
    glow: "",
    lights: [
      [124, 100, 330, "255, 255, 255"],
      [474, 160, 310, "236, 237, 241"],
      [384, 490, 330, "176, 177, 184"],
      [84, 450, 290, "226, 227, 231"],
    ] as Light[],
  };

  const drawStone = (
    cx: number,
    cy: number,
    radius: number,
    look: typeof warm,
    turned: boolean,
    text?: string,
    glow = 1,
  ) => {
    const s = (radius * 2) / 564;
    context.save();
    context.translate(cx, cy);
    context.scale(turned ? -s : s, s);
    context.translate(-282, -275);
    if (look.glow) {
      context.shadowColor = look.glow;
      context.shadowBlur = (60 * s + 12) * glow;
    }
    context.fillStyle = look.base;
    context.fill(pebble);
    context.shadowBlur = 0;
    for (const [x, y, r, colour] of look.lights) {
      const light = context.createRadialGradient(x, y, 0, x, y, r);
      light.addColorStop(0, `rgba(${colour}, 1)`);
      light.addColorStop(0.45, `rgba(${colour}, 0.75)`);
      light.addColorStop(1, `rgba(${colour}, 0)`);
      context.fillStyle = light;
      context.fill(pebble);
    }
    // A thin lit rim along the top, a darker one along the bottom.
    const rim = context.createLinearGradient(0, 0, 0, 550);
    rim.addColorStop(0, "rgba(255, 255, 255, 0.9)");
    rim.addColorStop(0.5, "rgba(255, 255, 255, 0)");
    rim.addColorStop(1, "rgba(0, 0, 0, 0.12)");
    context.strokeStyle = rim;
    context.lineWidth = 1.5 / s;
    context.stroke(pebble);
    context.restore();

    // The ratio, pressed in: a dark letter with a light edge under it.
    if (text && radius > 40) {
      context.save();
      context.textAlign = "center";
      context.textBaseline = "middle";
      context.font = `500 ${Math.round(radius * 0.42)}px ${font}`;
      context.letterSpacing = `${-radius * 0.012}px`;
      context.fillStyle = "rgba(255, 255, 255, 0.75)";
      context.fillText(text, cx, cy + 1.5);
      context.fillStyle = "rgba(23, 23, 26, 0.17)";
      context.fillText(text, cx, cy);
      context.restore();
    }
  };

  // Where a stone meets the ground: a soft dark ellipse, warm under Mote.
  const drawShadow = (cx: number, ground: number, radius: number, lit: boolean) => {
    const width = radius * 1.1;
    const height = Math.max(2, radius * 0.1);
    context.save();
    context.translate(cx, ground);
    context.scale(1, height / width);
    const shade = context.createRadialGradient(0, 0, 0, 0, 0, width);
    shade.addColorStop(0, lit ? "rgba(201, 112, 79, 0.35)" : "rgba(23, 23, 26, 0.22)");
    shade.addColorStop(1, "rgba(23, 23, 26, 0)");
    context.fillStyle = shade;
    context.beginPath();
    context.arc(0, 0, width, 0, Math.PI * 2);
    context.fill();
    context.restore();
  };

  new ResizeObserver(() => {
    size = { w: canvas.clientWidth, h: canvas.clientHeight };
    canvas.width = Math.round(size.w * devicePixelRatio);
    canvas.height = Math.round(size.h * devicePixelRatio);
    // Where the names end once everything is in view (the ground, then two
    // lines of label), for the page to place things under them.
    const unit = Math.min((size.w * 0.84) / width, size.h * 0.3);
    canvas.parentElement!.style.setProperty("--labels", `${size.h * 0.64 + unit / 2 + 50}px`);
    draw();
  }).observe(canvas);

  document.fonts.ready.then(() => {
    font = getComputedStyle(canvas).fontFamily;
    draw();
  });

  // 0 is closest, 1 is everything in view.
  return (progress: number) => {
    const t = Math.min(1, Math.max(0, progress));
    eased = t * t * (3 - 2 * t);
    // How far the camera has pulled back, for the page to bring in what
    // belongs to the finished view.
    canvas.parentElement!.style.setProperty("--pulled", eased.toFixed(3));
    draw();
  };
}
