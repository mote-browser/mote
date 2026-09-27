// Generated from Scripts/src/swipe-watch.ts by `pnpm build`. Do not edit.
(function() {

//#region src/swipe-watch/scrollable.ts
/** Whether the page itself may scroll sideways; the body's overflow counts when the root's is `visible`. */
	function rootCanScroll(rootOverflowX, bodyOverflowX) {
		const effective = rootOverflowX === "visible" ? bodyOverflowX : rootOverflowX;
		return effective !== "hidden" && effective !== "clip";
	}
	/** Whether content scrolled to `left` of at most `max` has room to move in the direction of `deltaX`. */
	function hasRoom(left, max, deltaX) {
		if (max <= 1) return false;
		return deltaX > 0 ? left < max - 1 : left > 1;
	}
	/**
	* Whether a horizontal wheel event at `target` would scroll something under the
	* pointer (a carousel, a wide table, the page), so it isn't a swipe to navigate.
	*/
	function scrollTaken(target, deltaX) {
		let element = target instanceof Element ? target : target instanceof Node ? target.parentElement : null;
		for (; element; element = element.parentElement) if (canScroll(element, deltaX)) return true;
		return false;
	}
	function canScroll(element, deltaX) {
		const document = element.ownerDocument;
		const window = document.defaultView;
		if (!window) return false;
		if (element === document.documentElement || element === document.body) {
			const body = document.body ? window.getComputedStyle(document.body).overflowX : "visible";
			if (!rootCanScroll(window.getComputedStyle(document.documentElement).overflowX, body)) return false;
			return hasRoom(window.scrollX || 0, document.documentElement.scrollWidth - window.innerWidth, deltaX);
		}
		const overflow = window.getComputedStyle(element).overflowX;
		if (overflow !== "auto" && overflow !== "scroll") return false;
		return hasRoom(element.scrollLeft, element.scrollWidth - element.clientWidth, deltaX);
	}
	/** How often an unchanged answer is repeated to Swift, in milliseconds. */
	const REPEAT_INTERVAL = 100;
	/** Whether to send `taken` now: when the answer changed, or the last one is older than `REPEAT_INTERVAL`. */
	function shouldReport(last, taken, now) {
		return taken !== last.taken || now - last.at >= 100;
	}

//#endregion
//#region src/swipe-watch.ts
	if (!window.__moteSwipe) {
		window.__moteSwipe = true;
		const last = {
			taken: null,
			at: 0
		};
		addEventListener("wheel", (event) => {
			if (Math.abs(event.deltaX) <= Math.abs(event.deltaY)) return;
			const taken = scrollTaken(event.target, event.deltaX);
			const now = Date.now();
			if (!shouldReport(last, taken, now)) return;
			last.taken = taken;
			last.at = now;
			window.webkit.messageHandlers.moteScroll?.postMessage({ side: taken ? "taken" : "free" });
		}, {
			passive: true,
			capture: true
		});
	}

//#endregion
})();