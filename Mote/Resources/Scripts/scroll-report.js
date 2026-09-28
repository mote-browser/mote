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
	/** How far through the page, in whole percent: the steps the reading bar moves in (readingFraction in Swift). */
	function readingStep({ y, max }) {
		return Math.round(Math.min(1, Math.max(0, y / max)) * 100);
	}

//#endregion
//#region src/scroll-report.ts
	const root = document.documentElement;
	let max = 1;
	let told = -1;
	const report = () => {
		const position = {
			y: window.scrollY || root.scrollTop || 0,
			max
		};
		const step = readingStep(position);
		if (step === told) return;
		told = step;
		window.webkit.messageHandlers.moteScroll?.postMessage(position);
	};
	const measure = () => {
		max = scrollPosition(window).max;
		report();
	};
	new ResizeObserver(measure).observe(root);
	addEventListener("resize", measure, { passive: true });
	addEventListener("scroll", report, { passive: true });

//#endregion
})();