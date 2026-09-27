// Generated from Scripts/src/scroll-report.ts by `pnpm build`. Do not edit.
(function() {

//#region src/scroll-report/position.ts
/** Never zero, so Swift can divide by it. */
	function scrollPosition(window) {
		const root = window.document.documentElement;
		return {
			y: window.scrollY || root.scrollTop || 0,
			max: Math.max(1, (root.scrollHeight || 0) - window.innerHeight)
		};
	}

//#endregion
//#region src/scroll-report.ts
	let waiting = false;
	const report = () => {
		window.webkit.messageHandlers.moteScroll?.postMessage(scrollPosition(window));
	};
	addEventListener("scroll", () => {
		if (waiting) return;
		waiting = true;
		requestAnimationFrame(() => {
			waiting = false;
			report();
		});
	}, { passive: true });
	report();

//#endregion
})();