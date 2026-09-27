// Generated from Scripts/src/floating-video.ts by `pnpm build`. Do not edit.
var moteFloatingVideo = (function(exports) {

Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' });
//#region src/floating-video/video.ts
/** Marks the video that stays visible while the page floats. */
	const MARK = "data-mote-float";
	/** Set on <html> while the page floats; every rule below hangs on it. */
	const FLOATING_CLASS = "mote-floating";
	/** The <style> element holding `FLOAT_STYLE`. */
	const STYLE_ID = "mote-float";
	/**
	* Hides everything but the marked video with `visibility`, leaving the DOM intact
	* so the player keeps streaming, and stretches the video over the whole window.
	*/
	const FLOAT_STYLE = [
		"html.mote-floating, html.mote-floating body {",
		"background:#000 !important; overflow:hidden !important; margin:0 !important}",
		"html.mote-floating body > * { visibility:hidden !important }",
		"html.mote-floating [data-mote-float] {",
		"visibility:visible !important; position:fixed !important;",
		"left:0 !important; top:0 !important; right:0 !important; bottom:0 !important;",
		"width:100vw !important; height:100vh !important;",
		"max-width:none !important; max-height:none !important;",
		"transform:none !important;",
		"object-fit:contain !important; z-index:2147483647 !important}",
		"html.mote-floating [data-mote-float] ~ .player-timedtext,",
		"html.mote-floating :has(> [data-mote-float]) > .player-timedtext,",
		"html.mote-floating :has([data-mote-float]) > .player-timedtext {",
		"visibility:visible !important; z-index:2147483647 !important}",
		"html.mote-floating body :has([data-mote-float]) {",
		"overflow:visible !important}",
		"html.mote-floating [data-mote-float]::-webkit-media-controls {",
		"display:none !important}"
	].join("");
	/** `HTMLMediaElement.HAVE_CURRENT_DATA`: a frame is ready to show. */
	const HAVE_CURRENT_DATA = 2;
	/** Whether a video is playing with a frame to show. */
	function isPlaying(video) {
		return !video.paused && !video.ended && video.readyState >= HAVE_CURRENT_DATA;
	}
	/** The largest playing video; of equal ones, the last in document order. */
	function largestPlayingVideo(document) {
		let best = null;
		let bestArea = 0;
		for (const video of document.querySelectorAll("video")) {
			if (!isPlaying(video)) continue;
			const box = video.getBoundingClientRect();
			const area = box.width * box.height;
			if (area > 0 && area >= bestArea) {
				bestArea = area;
				best = video;
			}
		}
		return best;
	}
	/** The floating video, or else the page's first video, for the panel's controls. */
	function controlledVideo(document) {
		return document.querySelector(`[${"data-mote-float"}]`) ?? document.querySelector("video");
	}
	/**
	* The fraction of `video` played and whether it plays: 0 played when the length
	* is unknown or endless (a live stream), and `[0, true]` without a video.
	*/
	function progress(video) {
		if (!video) return [0, true];
		return [!!video.duration && Number.isFinite(video.duration) ? video.currentTime / video.duration : 0, !video.paused];
	}

//#endregion
//#region src/floating-video.ts
/**
	* `on` isolates the largest playing video ('floating', or 'none' when nothing
	* plays); `off` restores the page ('landed'); `toggle` plays or pauses and returns
	* whether it now plays; `progress` returns `[fraction played, playing]`; `skip`
	* seeks by `seconds` and returns whether there was a video.
	*/
	function run(command, seconds = 0) {
		switch (command) {
			case "on": return isolate();
			case "off": return restore();
			case "toggle": return toggle();
			case "progress": return progress(controlledVideo(document));
			case "skip": return skip(seconds);
		}
	}
	function isolate() {
		const best = largestPlayingVideo(document);
		if (!best) return "none";
		best.setAttribute(MARK, "");
		let sheet = document.getElementById(STYLE_ID);
		if (!sheet) {
			sheet = document.createElement("style");
			sheet.id = STYLE_ID;
			(document.head || document.documentElement).appendChild(sheet);
		}
		sheet.textContent = FLOAT_STYLE;
		document.documentElement.classList.add(FLOATING_CLASS);
		clearInterval(window.__moteFloatWatch ?? void 0);
		window.__moteFloatWatch = window.setInterval(() => {
			if (document.querySelector(`[${"data-mote-float"}]`)) return;
			largestPlayingVideo(document)?.setAttribute(MARK, "");
		}, 250);
		return "floating";
	}
	function restore() {
		try {
			const out = document.querySelector(`video[${"data-mote-float"}]`) || document.querySelector("video");
			if (out) {
				if (out.webkitPresentationMode === "picture-in-picture") out.webkitSetPresentationMode("inline");
				if (document.pictureInPictureElement && document.exitPictureInPicture) document.exitPictureInPicture().catch(() => {});
			}
		} catch {}
		clearInterval(window.__moteFloatWatch ?? void 0);
		window.__moteFloatWatch = null;
		document.documentElement.classList.remove(FLOATING_CLASS);
		const sheet = document.getElementById(STYLE_ID);
		if (sheet) sheet.textContent = "";
		document.querySelector(`[${MARK}]`)?.removeAttribute(MARK);
		return "landed";
	}
	function toggle() {
		const video = controlledVideo(document);
		if (!video) return true;
		if (video.paused) video.play();
		else video.pause();
		return !video.paused;
	}
	function skip(seconds) {
		const video = controlledVideo(document);
		if (!video) return false;
		video.currentTime = Math.max(0, video.currentTime + seconds);
		return true;
	}

//#endregion
exports.run = run;
return exports;
})({});