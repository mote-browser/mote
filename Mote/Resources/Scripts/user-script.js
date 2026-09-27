// Generated from Scripts/src/user-script.ts by `pnpm build`. Do not edit.
var moteUserScript = (function(exports) {

Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' });
//#region src/lib/user-scripts.ts
/** The prefix of a port's name opened from the USER_SCRIPT world. */
	const USER_SCRIPT_PORT_PREFIX = "mote-us:";

//#endregion
//#region src/user-script/chrome.ts
/**
	* Chrome's USER_SCRIPT world, over `runtime` of the isolated world the script
	* runs in: messages go tagged, so the extension's worker hands them to
	* onUserScriptMessage and onUserScriptConnect rather than onMessage and onConnect.
	*/
	function userScriptChrome(runtime) {
		return { runtime: {
			id: runtime.id,
			getURL: (path) => runtime.getURL(path),
			get lastError() {
				return runtime.lastError;
			},
			sendMessage: (message, ...rest) => runtime.sendMessage({
				__moteUserScript: true,
				message
			}, ...rest.filter((r) => typeof r === "function" || r && typeof r === "object")),
			connect: (info) => runtime.connect({
				...info,
				name: USER_SCRIPT_PORT_PREFIX + (info && info.name || "")
			})
		} };
	}

//#endregion
//#region src/user-script/globs.ts
/**
	* A glob of chrome.userScripts' includeGlobs and excludeGlobs as a regular
	* expression for a whole URL: `*` is any run of characters, `?` any one.
	*/
	function globPattern(glob) {
		return new RegExp("^" + glob.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".") + "$");
	}
	/** Whether a user script runs at `href`: some include glob matches, if any are given, and no exclude glob. */
	function globsAllow(href, include, exclude) {
		return !(include.length && !include.some((g) => globPattern(g).test(href)) || exclude.some((g) => globPattern(g).test(href)));
	}

//#endregion
//#region src/user-script.ts
	function run(includeGlobs, excludeGlobs, userWorld) {
		if (!globsAllow(location.href, includeGlobs, excludeGlobs)) return null;
		return userWorld ? { chrome: userScriptChrome(globalThis.chrome.runtime) } : {};
	}

//#endregion
exports.run = run;
return exports;
})({});