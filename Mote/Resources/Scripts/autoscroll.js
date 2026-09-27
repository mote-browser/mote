// Generated from Scripts/src/autoscroll.ts by `pnpm build`. Do not edit.
(function() {

//#region src/autoscroll/scrolling.ts
/** Pointer distance, in points, that still scrolls nothing. */
	const DEAD_ZONE = 12;
	/** Fastest scroll per frame, in points. */
	const MAX_SPEED = 60;
	/** Elements whose own middle-click behavior wins over autoscroll. */
	const INTERACTIVE = "a[href], area[href], input, textarea, select, button, video, audio, iframe, [contenteditable=\"\"], [contenteditable=\"true\"]";
	/** Scroll speed per frame for a pointer `distance` from the anchor, faster with distance. */
	function speed(distance) {
		const beyond = Math.abs(distance) - 12;
		return beyond > 0 ? Math.sign(distance) * Math.min(60, Math.pow(beyond / 10, 1.4)) : 0;
	}
	/** The nearest ancestor that scrolls, or the document's scrolling element. */
	function scrollContainer(start) {
		for (let element = start; element; element = element.parentElement) {
			if (element === document.body || element === document.documentElement) break;
			const style = getComputedStyle(element);
			const scrollable = /(auto|scroll|overlay)/.test(style.overflowY + style.overflowX);
			const overflows = element.scrollHeight > element.clientHeight + 1 || element.scrollWidth > element.clientWidth + 1;
			if (scrollable && overflows) return element;
		}
		return document.scrollingElement ?? document.documentElement;
	}
	/** The anchor badge, in a closed shadow root that the page's styles can't reach. */
	function anchorBadge(x, y) {
		const host = document.createElement("div");
		host.style.cssText = `all:initial;position:fixed;z-index:2147483647;pointer-events:none;left:${x - 15}px;top:${y - 15}px;width:30px;height:30px;`;
		host.attachShadow({ mode: "closed" }).innerHTML = "<svg viewBox=\"0 0 30 30\" width=\"30\" height=\"30\" style=\"filter:drop-shadow(0 2px 6px rgba(0,0,0,.25))\"><circle cx=\"15\" cy=\"15\" r=\"13.5\" fill=\"rgba(255,255,255,.94)\" stroke=\"rgba(0,0,0,.18)\"/><path d=\"M15 6.5l3.5 4.5h-7zM15 23.5l3.5-4.5h-7z\" fill=\"rgba(0,0,0,.62)\"/><circle cx=\"15\" cy=\"15\" r=\"1.6\" fill=\"rgba(0,0,0,.62)\"/></svg>";
		document.documentElement.append(host);
		return host;
	}

//#endregion
//#region src/autoscroll.ts
	const MIDDLE_BUTTON = 1;
	window.__moteAutoScrollOff = false;
	if (!window.__moteAutoScroll) {
		window.__moteAutoScroll = true;
		let active = null;
		let swallowButton = -1;
		const tick = () => {
			if (!active) return;
			active.target.scrollBy(speed(active.dx), speed(active.dy));
			active.frame = requestAnimationFrame(tick);
		};
		const move = (event) => {
			if (!active) return;
			active.dx = event.clientX - active.x;
			active.dy = event.clientY - active.y;
		};
		const stop = () => {
			if (!active) return;
			cancelAnimationFrame(active.frame);
			active.badge.remove();
			document.documentElement.style.cursor = active.cursor;
			removeEventListener("mousemove", move, true);
			active = null;
		};
		addEventListener("mousedown", (event) => {
			swallowButton = -1;
			if (active) {
				event.preventDefault();
				event.stopPropagation();
				stop();
				swallowButton = event.button;
				return;
			}
			if (event.button !== MIDDLE_BUTTON || window.__moteAutoScrollOff) return;
			const target = event.target instanceof Element ? event.target : null;
			if (target?.closest("a[href], area[href], input, textarea, select, button, video, audio, iframe, [contenteditable=\"\"], [contenteditable=\"true\"]")) return;
			event.preventDefault();
			active = {
				x: event.clientX,
				y: event.clientY,
				dx: 0,
				dy: 0,
				since: performance.now(),
				target: scrollContainer(target),
				badge: anchorBadge(event.clientX, event.clientY),
				cursor: document.documentElement.style.cursor,
				frame: 0
			};
			document.documentElement.style.cursor = "all-scroll";
			addEventListener("mousemove", move, true);
			active.frame = requestAnimationFrame(tick);
		}, true);
		addEventListener("mouseup", (event) => {
			if (active && event.button === MIDDLE_BUTTON && performance.now() - active.since > 250 && (Math.abs(active.dx) > 12 || Math.abs(active.dy) > 12)) {
				stop();
				swallowButton = MIDDLE_BUTTON;
			}
		}, true);
		const swallowClick = (event) => {
			if (event.button === swallowButton) {
				swallowButton = -1;
				event.preventDefault();
				event.stopPropagation();
			} else if (event.button === MIDDLE_BUTTON && active) event.preventDefault();
		};
		addEventListener("click", swallowClick, true);
		addEventListener("auxclick", swallowClick, true);
		addEventListener("keydown", (event) => {
			if (active && event.key === "Escape") {
				event.preventDefault();
				stop();
			}
		}, true);
		addEventListener("wheel", stop, {
			capture: true,
			passive: true
		});
		addEventListener("blur", stop);
		document.addEventListener("visibilitychange", stop);
	}

//#endregion
})();