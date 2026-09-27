// Generated from Scripts/src/extension-shims.ts by `pnpm build`. Do not edit.
(function() {

//#region src/extension-shims/callbacks.ts
/** The native messaging application that is the browser itself (`ExtensionShims.application`). */
	const APPLICATION = "mote";
	/** Takes a trailing callback off `args`, or null when the last argument isn't a function. */
	function takeCallback(args) {
		return args.length && typeof args[args.length - 1] === "function" ? args.pop() : null;
	}
	/** A request to the browser. Its arguments go as JSON: what can't be said in JSON is left out. */
	function nativeRequest(api, args) {
		return {
			api,
			args: JSON.parse(JSON.stringify(args ?? []))
		};
	}
	/** The value of the browser's answer, or its error thrown. */
	function replyValue(reply) {
		if (reply && reply.error) throw new Error(reply.error);
		return reply ? reply.value : void 0;
	}
	/** The message Chrome gives `runtime.lastError` for a failure. */
	function errorMessage(error) {
		return String(error && error.message || error);
	}
	/** Settles `callback` with what `promise` resolves to, or with `lastError` set when it fails. */
	function settleCallback(shim, promise, callback) {
		promise.then((value) => callback(value), (error) => shim.withLastError(error, callback));
	}
	/** `f`, taking a callback last as well as returning a promise. */
	function withCallback(shim, f) {
		return (...args) => {
			const callback = takeCallback(args);
			const promise = f(...args);
			if (!callback) return promise;
			settleCallback(shim, promise, callback);
		};
	}
	/** A method the browser answers: `api` is `namespace.method`. */
	function nativeCall(shim, api) {
		return withCallback(shim, (...args) => shim.native(api, args));
	}
	/**
	* Something only Chrome can do, answered the way Chrome answers when
	* it can't: a rejection, or lastError for a callback.
	*/
	function refuse(shim, what) {
		return (...args) => {
			const callback = takeCallback(args);
			const error = /* @__PURE__ */ new Error(what + " isn't available in Mote");
			if (!callback) return Promise.reject(error);
			shim.withLastError(error, callback);
		};
	}
	/**
	* A method that answers at once with `value`, or with what `value` returns for
	* the arguments; a callback is called in a later turn.
	*/
	function resolved(value) {
		return (...args) => {
			const callback = takeCallback(args);
			const v = typeof value === "function" ? value(...args) : value;
			if (!callback) return Promise.resolve(v);
			setTimeout(() => callback(v));
		};
	}

//#endregion
//#region src/extension-shims/events.ts
	function createEvent() {
		const listeners = /* @__PURE__ */ new Set();
		return {
			addListener: (listener) => listeners.add(listener),
			removeListener: (listener) => listeners.delete(listener),
			hasListener: (listener) => listeners.has(listener),
			hasListeners: () => listeners.size > 0,
			listeners
		};
	}
	/** Whether `key` names an event (`onMessage`, `onClicked`). */
	function isEventName(key) {
		return /^on[A-Z]/.test(key);
	}
	/** Every property name of `target` and its prototypes, up to `Object.prototype`. */
	function memberNames(target) {
		const names = /* @__PURE__ */ new Set();
		for (let o = target; o && o !== Object.prototype; o = Object.getPrototypeOf(o)) for (const key of Object.getOwnPropertyNames(o)) names.add(key);
		return names;
	}
	/** Throws `error` outside the current call, so a failing listener is reported but stops nothing. */
	function rethrowLater(error) {
		setTimeout(() => {
			throw error;
		});
	}

//#endregion
//#region src/extension-shims/members.ts
/** Sets each member `chrome[name]` doesn't have. */
	function fill({ chrome, put }, name, members) {
		const target = chrome[name];
		if (!target) return;
		for (const [key, value] of Object.entries(members)) {
			let there;
			try {
				there = target[key];
			} catch {}
			if (there === void 0) put(target, key, value);
		}
	}
	/**
	* Chrome's enum of `values`: `main_frame` as `MAIN_FRAME`, `per-origin` as
	* `PER_ORIGIN`, `firstParty` as `FIRST_PARTY`. Words are split before the
	* value is upper-cased, which would leave no lower case to split at.
	*/
	function enumOf(...values) {
		return Object.fromEntries(values.map((v) => [v.replace(/[-.]/g, "_").replace(/([a-z0-9])([A-Z])/g, "$1_$2").toUpperCase(), v]));
	}
	/** The resource types of web requests, shared by webRequest and declarativeNetRequest. */
	function resourceTypes() {
		return enumOf("main_frame", "sub_frame", "stylesheet", "script", "image", "font", "object", "xmlhttprequest", "ping", "csp_report", "media", "websocket", "webtransport", "webbundle", "other");
	}
	function fillRuntime(shim) {
		fill(shim, "runtime", {
			onUpdateAvailable: createEvent(),
			onRestartRequired: createEvent(),
			onSuspend: createEvent(),
			onSuspendCanceled: createEvent(),
			onBrowserUpdateAvailable: createEvent(),
			onConnectNative: createEvent(),
			onUserScriptConnect: createEvent(),
			onUserScriptMessage: createEvent(),
			requestUpdateCheck: (callback) => {
				if (typeof callback === "function") {
					setTimeout(() => callback("no_update", {}));
					return;
				}
				return Promise.resolve({ status: "no_update" });
			},
			restart: () => {},
			restartAfterDelay: resolved(void 0),
			getPackageDirectoryEntry: refuse(shim, "runtime.getPackageDirectoryEntry"),
			OnInstalledReason: enumOf("install", "update", "chrome_update", "shared_module_update"),
			OnRestartRequiredReason: enumOf("app_update", "os_update", "periodic"),
			PlatformArch: {
				ARM: "arm",
				ARM64: "arm64",
				X86_32: "x86-32",
				X86_64: "x86-64",
				MIPS: "mips",
				MIPS64: "mips64"
			},
			PlatformNaclArch: {
				ARM: "arm",
				X86_32: "x86-32",
				X86_64: "x86-64",
				MIPS: "mips",
				MIPS64: "mips64"
			},
			PlatformOs: {
				MAC: "mac",
				WIN: "win",
				ANDROID: "android",
				CROS: "cros",
				LINUX: "linux",
				OPENBSD: "openbsd",
				FUCHSIA: "fuchsia"
			},
			RequestUpdateCheckStatus: enumOf("throttled", "no_update", "update_available"),
			ContextType: {
				TAB: "TAB",
				POPUP: "POPUP",
				BACKGROUND: "BACKGROUND",
				OFFSCREEN_DOCUMENT: "OFFSCREEN_DOCUMENT",
				SIDE_PANEL: "SIDE_PANEL",
				DEVELOPER_TOOLS: "DEVELOPER_TOOLS"
			}
		});
	}
	function fillExtension(shim) {
		const { runtime } = shim;
		fill(shim, "extension", {
			getURL: (path) => runtime.getURL(path),
			ViewType: {
				TAB: "tab",
				POPUP: "popup"
			},
			sendRequest: (...args) => runtime.sendMessage(...args),
			onRequest: createEvent(),
			onRequestExternal: createEvent(),
			getExtensionTabs: () => [],
			setUpdateUrlData: () => {}
		});
	}
	function fillWindows(shim) {
		fill(shim, "windows", {
			onBoundsChanged: createEvent(),
			CreateType: enumOf("normal", "popup", "panel"),
			WindowType: enumOf("normal", "popup", "panel", "app", "devtools"),
			WindowState: {
				NORMAL: "normal",
				MINIMIZED: "minimized",
				MAXIMIZED: "maximized",
				FULLSCREEN: "fullscreen",
				LOCKED_FULLSCREEN: "locked-fullscreen"
			}
		});
	}
	function fillScripting(shim) {
		fill(shim, "scripting", {
			ExecutionWorld: {
				ISOLATED: "ISOLATED",
				MAIN: "MAIN",
				USER_SCRIPT: "USER_SCRIPT"
			},
			StyleOrigin: {
				AUTHOR: "AUTHOR",
				USER: "USER"
			}
		});
	}
	function fillWebNavigation(shim) {
		fill(shim, "webNavigation", {
			onCreatedNavigationTarget: createEvent(),
			onHistoryStateUpdated: createEvent(),
			onReferenceFragmentUpdated: createEvent(),
			onTabReplaced: createEvent(),
			TransitionType: enumOf("link", "typed", "auto_bookmark", "auto_subframe", "manual_subframe", "generated", "start_page", "form_submit", "reload", "keyword", "keyword_generated"),
			TransitionQualifier: enumOf("client_redirect", "server_redirect", "forward_back", "from_address_bar")
		});
	}

//#endregion
//#region src/extension-shims/action.ts
/**
	* The popup an extension sets for its button, told to the browser too:
	* Mote opens a popup itself (see Extensions.press), and has to know
	* which page it is now. The browser is told the page and the tab's index,
	* or -1 for every tab (`action.popup`).
	*/
	function tellPopups({ chrome, put, native }) {
		for (const name of ["action", "browserAction"]) {
			const action = chrome[name];
			if (!action || typeof action.setPopup !== "function") continue;
			const setPopup = action.setPopup.bind(action);
			put(action, "setPopup", (details = {}, callback) => {
				const tell = (index) => native("action.popup", [details.popup || "", index]).catch(() => {});
				if (typeof details.tabId === "number" && chrome.tabs) chrome.tabs.get(details.tabId).then((t) => tell(t.index), () => {});
				else tell(-1);
				return setPopup(details, callback);
			});
		}
	}
	function fillAction(shim) {
		fill(shim, "action", {
			getUserSettings: resolved({ isOnToolbar: true }),
			onUserSettingsChanged: createEvent(),
			setBadgeTextColor: resolved(void 0),
			getBadgeTextColor: resolved([
				255,
				255,
				255,
				255
			])
		});
	}

//#endregion
//#region src/extension-shims/declarative-net-request.ts
	function fillDeclarativeNetRequest(shim, resourceTypes) {
		fill(shim, "declarativeNetRequest", {
			GUARANTEED_MINIMUM_STATIC_RULES: 3e4,
			MAX_NUMBER_OF_REGEX_RULES: 1e3,
			MAX_NUMBER_OF_SESSION_RULES: 5e3,
			MAX_NUMBER_OF_UNSAFE_DYNAMIC_RULES: 5e3,
			MAX_NUMBER_OF_UNSAFE_SESSION_RULES: 5e3,
			MAX_GETMATCHEDRULES_CALLS_PER_INTERVAL: 20,
			GETMATCHEDRULES_QUOTA_INTERVAL: 10,
			DYNAMIC_RULESET_ID: "_dynamic",
			SESSION_RULESET_ID: "_session",
			getAvailableStaticRuleCount: resolved(3e4),
			getDisabledRuleIds: resolved([]),
			updateStaticRules: resolved(void 0),
			testMatchOutcome: refuse(shim, "declarativeNetRequest.testMatchOutcome"),
			onRuleMatchedDebug: createEvent(),
			RuleActionType: {
				BLOCK: "block",
				REDIRECT: "redirect",
				ALLOW: "allow",
				UPGRADE_SCHEME: "upgradeScheme",
				MODIFY_HEADERS: "modifyHeaders",
				ALLOW_ALL_REQUESTS: "allowAllRequests"
			},
			ResourceType: resourceTypes,
			HeaderOperation: enumOf("append", "set", "remove"),
			DomainType: {
				FIRST_PARTY: "firstParty",
				THIRD_PARTY: "thirdParty"
			},
			RequestMethod: enumOf("connect", "delete", "get", "head", "options", "patch", "post", "put", "other"),
			UnsupportedRegexReason: {
				SYNTAX_ERROR: "syntaxError",
				MEMORY_LIMIT_EXCEEDED: "memoryLimitExceeded"
			}
		});
	}
	/** Resource types WebKit has no name for. */
	const UNKNOWN_TYPES = /* @__PURE__ */ new Set([
		"webtransport",
		"webbundle",
		"object"
	]);
	/**
	* A rule put the way WebKit takes it: a redirect to one of the extension's
	* own files by path rather than by address (`base` is the extension's root
	* URL), and without the resource types it has no name for. Null when no
	* resource type is left for it.
	*/
	function mendRule(rule, base) {
		if (!rule || typeof rule !== "object") return rule;
		const given = rule;
		const r = {
			...given,
			action: given.action && { ...given.action },
			condition: given.condition && { ...given.condition }
		};
		const redirect = r.action && r.action.redirect;
		if (redirect && typeof redirect.url === "string" && base && redirect.url.startsWith(base)) r.action.redirect = { extensionPath: "/" + redirect.url.slice(base.length) };
		const c = r.condition;
		if (c && Array.isArray(c.resourceTypes)) {
			c.resourceTypes = c.resourceTypes.filter((t) => !UNKNOWN_TYPES.has(t));
			if (!c.resourceTypes.length) return null;
		}
		if (c && Array.isArray(c.excludedResourceTypes)) c.excludedResourceTypes = c.excludedResourceTypes.filter((t) => !UNKNOWN_TYPES.has(t));
		return r;
	}
	/** The index of the rule WebKit refused, from its error. */
	function refusedRuleIndex(error) {
		const at = /rule at index (\d+)/.exec(String(error && error.message));
		return at ? Number(at[1]) : null;
	}
	/**
	* Rules WebKit can't carry out — a header it doesn't know how to set,
	* say — are refused one by one, where Chrome would take them all. The
	* rest still go in: one rule Mote can't honour shouldn't cost an
	* extension every other rule, or its startup.
	* Before WebKit sees them, rules are put the way it takes them (`mendRule`).
	*/
	function mendRules(shim) {
		const { chrome, runtime, put, native } = shim;
		const dnr = chrome.declarativeNetRequest;
		const base = (() => {
			try {
				return runtime.getURL("");
			} catch {
				return "";
			}
		})();
		if (dnr && typeof dnr.isRegexSupported === "function") {
			const original = dnr.isRegexSupported.bind(dnr);
			put(dnr, "isRegexSupported", (options, callback) => {
				const p = Promise.resolve(original(options)).then((r) => r || {
					isSupported: false,
					reason: "syntaxError"
				}, () => ({
					isSupported: false,
					reason: "syntaxError"
				}));
				if (typeof callback !== "function") return p;
				p.then((r) => callback(r));
			});
		}
		if (!dnr) return;
		for (const name of ["updateSessionRules", "updateDynamicRules"]) {
			if (typeof dnr[name] !== "function") continue;
			const original = dnr[name].bind(dnr);
			const attempt = async (opts, left) => {
				try {
					return await original(opts);
				} catch (e) {
					const index = refusedRuleIndex(e);
					if (index === null || !Array.isArray(opts.addRules) || left <= 0) throw e;
					const rule = opts.addRules[index];
					try {
						native("debug.error", ["declarativeNetRequest: rule " + (rule && rule.id) + " left out — " + e.message]).catch(() => {});
					} catch {}
					return attempt({
						...opts,
						addRules: opts.addRules.filter((_, i) => i !== index)
					}, left - 1);
				}
			};
			put(dnr, name, (options = {}, callback) => {
				if (options && Array.isArray(options.addRules)) options = {
					...options,
					addRules: options.addRules.map((rule) => mendRule(rule, base)).filter(Boolean)
				};
				const p = attempt(options, 100);
				if (typeof callback !== "function") return p;
				p.then(() => callback(), (e) => shim.withLastError(e, callback));
			});
		}
	}

//#endregion
//#region src/extension-shims/embedded.ts
/** Namespaces a content script may call itself. */
	const DIRECT_NAMESPACES = /* @__PURE__ */ new Set([
		"runtime",
		"storage",
		"i18n",
		"extension",
		"permissions",
		"dom",
		"test"
	]);
	const NO_RECEIVER = "Could not establish connection. Receiving end does not exist.";
	/** The arguments of a call carried to the worker: trailing undefineds dropped, then as JSON. */
	function carriedArguments(args) {
		while (args.length && args[args.length - 1] === void 0) args.pop();
		return JSON.parse(JSON.stringify(args));
	}
	function forwardThroughWorker(shim) {
		const { chrome, put, spaces, embedded } = shim;
		if (!embedded) return;
		const ask = (space, method, args) => {
			let payload;
			try {
				payload = carriedArguments(args);
			} catch (e) {
				return Promise.reject(e);
			}
			const call = { __moteCall: {
				space,
				method,
				args: payload
			} };
			return Promise.resolve(chrome.runtime.sendMessage(call)).then((reply) => {
				if (!reply) throw new Error("chrome." + space + "." + method + " had no answer from the extension's background");
				if (reply.error) throw new Error(reply.error);
				return reply.value;
			});
		};
		for (const space of spaces) {
			if (DIRECT_NAMESPACES.has(space)) continue;
			let ns;
			try {
				ns = chrome[space];
			} catch {
				continue;
			}
			if (!ns || typeof ns !== "object") continue;
			for (const name of memberNames(ns)) {
				if (name === "constructor" || isEventName(name)) continue;
				let f;
				try {
					f = ns[name];
				} catch {
					continue;
				}
				if (typeof f !== "function") continue;
				if (name === "connect") {
					put(ns, name, (...args) => {
						const port = {
							name: (args.find((a) => a && typeof a === "object") || {}).name || "",
							sender: void 0,
							postMessage: () => {},
							disconnect: () => {},
							onMessage: createEvent(),
							onDisconnect: createEvent()
						};
						setTimeout(() => {
							shim.withLastError({ message: NO_RECEIVER }, () => {
								for (const listener of [...port.onDisconnect.listeners]) listener(port);
							});
						});
						return port;
					});
					continue;
				}
				put(ns, name, (...args) => {
					const callback = takeCallback(args);
					const answer = ask(space, name, args);
					if (!callback) return answer;
					settleCallback(shim, answer, callback);
				});
			}
		}
	}

//#endregion
//#region src/extension-shims/environment.ts
/**
	* Whether `chrome` is an extension's. A page's own world, where an extension's
	* MAIN-world script runs with this before it, has no extension APIs. Nothing to
	* mend there, and nothing may be left there for a page to see: Safari leaves
	* nothing. (There, Mote's passkey patch holds navigator.credentials.)
	*/
	function carriesExtensionAPIs(chrome) {
		try {
			return !!(chrome && chrome.runtime && chrome.runtime.id);
		} catch {
			return false;
		}
	}
	/**
	* On a web page this is a content script: only Chrome's behaviour is
	* mended there, no API that Chrome doesn't give content scripts either.
	*/
	function isContentScript() {
		return typeof location !== "undefined" && !/^(chrome|webkit)-extension:$/.test(location.protocol);
	}
	/**
	* One of the extension's pages in a frame of a website — Vimium's bar,
	* the list iCloud Passwords opens under a field. WebKit runs it in the
	* website's process, which it trusts with no more than a content
	* script: a single call to tabs, windows, scripting… and WebKit takes
	* the process for compromised and ends it. The page reloads, and a
	* frame that makes the call as it loads reloads it for ever. Chrome
	* gives such a frame everything, so here the worker makes those calls
	* for it (see `__moteCall` in messaging.ts).
	*/
	function isEmbedded(inContent) {
		return !inContent && typeof window !== "undefined" && window.top !== window && (() => {
			try {
				const ancestors = location.ancestorOrigins;
				if (ancestors && ancestors.length) return [...ancestors].some((origin) => origin !== location.origin);
			} catch {}
			try {
				return window.top.location.origin !== location.origin;
			} catch {
				return true;
			}
		})();
	}
	/** The extension's service worker. */
	function isServiceWorker(root) {
		return typeof root.ServiceWorkerGlobalScope !== "undefined" && root instanceof root.ServiceWorkerGlobalScope;
	}
	/**
	* The extension's background, whichever WebKit runs: the worker, or a
	* page — it picks the page when a manifest names scripts as well.
	*/
	function isBackground(root, chrome, worker, inContent) {
		return worker || !inContent && typeof document !== "undefined" && (() => {
			try {
				return chrome.extension && typeof chrome.extension.getBackgroundPage === "function" && chrome.extension.getBackgroundPage() === root;
			} catch {
				return false;
			}
		})();
	}

//#endregion
//#region src/extension-shims/error-reporting.ts
/** Longest error told to the browser. */
	const MAX_LENGTH = 2e3;
	/** Console errors and warnings told in a test run, at most. */
	const MAX_CONSOLE_REPORTS = 60;
	/** Where an error happened: its file's path within the extension, and line. */
	function errorPlace(filename, line) {
		return String(filename || "").split("/").slice(3).join("/") + ":" + line;
	}
	/** A console argument as text. */
	function consoleText(value) {
		if (value instanceof Error) return value.message + " — " + (value.stack || "");
		try {
			return typeof value === "string" ? value : JSON.stringify(value);
		} catch {
			return String(value);
		}
	}
	function reportErrors({ root, native, config }) {
		if (!root.addEventListener) return;
		const tell = (text) => {
			try {
				native("debug.error", [String(text).slice(0, MAX_LENGTH)]).catch(() => {});
			} catch {}
		};
		root.addEventListener("error", (e) => tell((e.message || "error") + " @ " + errorPlace(e.filename, e.lineno)));
		root.addEventListener("unhandledrejection", (e) => tell("unhandled: " + (e.reason && (e.reason.message || "") + " — " + (e.reason.stack || "") || e.reason)));
		if (config.verbose && root.console) {
			let told = 0;
			for (const level of ["error", "warn"]) {
				const original = console[level].bind(console);
				console[level] = (...args) => {
					original(...args);
					if (told++ < MAX_CONSOLE_REPORTS) tell("console." + level + ": " + args.map(consoleText).join(" "));
				};
			}
		}
	}

//#endregion
//#region src/extension-shims/captured.ts
	const root = globalThis;
	const URL = root.URL;
	const FileReader = root.FileReader;
	const Response = root.Response;
	const Blob = root.Blob;
	const File = root.File;
	const DOMException = root.DOMException;
	const HTMLImageElement = root.HTMLImageElement;
	const HTMLAnchorElement = root.HTMLAnchorElement;
	const Element = root.Element;
	const crypto = root.crypto;

//#endregion
//#region src/extension-shims/file-system/paths.ts
/** The folders at the root of the origin private file system, by type. */
	const KINDS = ["temporary", "persistent"];
	/** Paths are kept as their segments; "/a/b" is ["a", "b"]. `path` is resolved against `base`. */
	function segments(base, path) {
		const text = String(path ?? "");
		const out = text.startsWith("/") ? [] : base.split("/").filter(Boolean);
		for (const part of text.split("/")) {
			if (!part || part === ".") continue;
			if (part === "..") out.pop();
			else out.push(part);
		}
		return out;
	}
	function joinPath(segs) {
		return "/" + segs.join("/");
	}
	/** filesystem:<this origin>/<persistent|temporary>/<path>, or null. */
	function parseFileSystemURL(url, origin) {
		const s = String(url);
		if (!s.startsWith("filesystem:")) return null;
		const m = /^filesystem:([^/]+:\/\/[^/]+)\/(temporary|persistent)(\/[^?#]*)?/i.exec(s);
		if (!m || m[1] !== origin) return null;
		let segs;
		try {
			segs = segments("/", (m[3] || "/").split("/").map(decodeURIComponent).join("/"));
		} catch {
			return null;
		}
		return {
			type: KINDS.indexOf(m[2].toLowerCase()),
			segs
		};
	}
	/** The `filesystem:` URL of a path. */
	function fileSystemURL(origin, type, fullPath) {
		return "filesystem:" + origin + "/" + KINDS[type] + (fullPath === "/" ? "/" : segments("/", fullPath).map(encodeURIComponent).map((s) => "/" + s).join(""));
	}
	/** OPFS files come without a type; a blob: URL or download wants one. */
	const TYPES = {
		png: "image/png",
		jpg: "image/jpeg",
		jpeg: "image/jpeg",
		gif: "image/gif",
		webp: "image/webp",
		svg: "image/svg+xml",
		pdf: "application/pdf",
		txt: "text/plain",
		html: "text/html",
		json: "application/json",
		mp4: "video/mp4",
		webm: "video/webm"
	};
	/** A file's type, or the one its name's extension says, or "". */
	function typeOf(file) {
		return file.type || TYPES[(file.name.split(".").pop() || "").toLowerCase()] || "";
	}

//#endregion
//#region src/extension-shims/file-system/origin-storage.ts
/**
	* Chrome answers with DOMExceptions whose name says what went wrong; the
	* legacy code comes with the name (NotFoundError is 8, and so on).
	*/
	function fail(name, message) {
		return new DOMException(message || name, name);
	}
	function asError(e) {
		return e instanceof DOMException ? e : fail(e && e.name || "InvalidStateError", e && e.message || String(e));
	}
	/**
	* Chrome calls back later, never in the same turn, success or not.
	* A callback that throws is reported as uncaught, not as a rejection.
	*/
	function invoke(f, v) {
		try {
			f(v);
		} catch (e) {
			rethrowLater(e);
		}
	}
	function settle$1(promise, success, error) {
		promise.then((v) => {
			if (typeof success === "function") invoke(success, v);
		}, (e) => {
			if (typeof error === "function") invoke(error, asError(e));
		});
	}
	/** The file with the type its name says, when it has none (see `typeOf`). */
	function typed(file) {
		const type = typeOf(file);
		return type === file.type ? file : new File([file], file.name, {
			type,
			lastModified: file.lastModified
		});
	}
	function createOriginStorage() {
		const top = [];
		const folder = (type) => top[type] || (top[type] = navigator.storage.getDirectory().then((d) => d.getDirectoryHandle(KINDS[type], { create: true })));
		const walk = async (type, segs, create = false) => {
			let dir = await folder(type);
			for (const name of segs) dir = await dir.getDirectoryHandle(name, { create });
			return dir;
		};
		const lookup = async (type, segs) => {
			if (!segs.length) return folder(type);
			const dir = await walk(type, segs.slice(0, -1));
			const name = segs[segs.length - 1];
			try {
				return await dir.getFileHandle(name);
			} catch (e) {
				if (e.name !== "TypeMismatchError") {
					if (e.name === "NotFoundError") return null;
					throw e;
				}
			}
			return dir.getDirectoryHandle(name);
		};
		const need = async (type, segs) => {
			const handle = await lookup(type, segs).catch((e) => {
				if (e.name === "NotFoundError") return null;
				throw e;
			});
			if (!handle) throw fail("NotFoundError", "A requested file or directory could not be found.");
			return handle;
		};
		return {
			folder,
			walk,
			lookup,
			need
		};
	}

//#endregion
//#region src/extension-shims/file-system/entries.ts
/** Copies a file, or a directory with everything in it, into `into` as `name`. */
	async function copy(handle, into, name) {
		if (handle.kind === "file") {
			const w = await (await into.getFileHandle(name, { create: true })).createWritable();
			await w.write(await handle.getFile());
			return w.close();
		}
		const dir = await into.getDirectoryHandle(name, { create: true });
		for await (const [child, h] of handle.entries()) await copy(h, dir, child);
	}
	/**
	* The entry classes, on `storage`. `forget` is told of every path whose file
	* changes or goes, and everything under it.
	*/
	function createEntries(storage, forget) {
		const { walk, lookup, need } = storage;
		const systems = [];
		const system = (type) => systems[type] || (systems[type] = (() => {
			const fs = { name: location.host + ":" + (type ? "Persistent" : "Temporary") };
			fs.root = new DirectoryEntry(fs, type, "/");
			return fs;
		})());
		class Entry {
			constructor(fs, type, path) {
				Object.defineProperty(this, "_type", { value: type });
				this.filesystem = fs;
				this.fullPath = path;
				this.name = path === "/" ? "" : path.split("/").pop();
			}
			get _segs() {
				return segments("/", this.fullPath);
			}
			toURL() {
				return fileSystemURL(location.origin, this._type, this.fullPath);
			}
			toInternalURL() {
				return this.toURL();
			}
			getParent(success, error) {
				settle$1(Promise.resolve(new DirectoryEntry(this.filesystem, this._type, joinPath(this._segs.slice(0, -1)))), success, error);
			}
			getMetadata(success, error) {
				settle$1((async () => {
					const handle = await need(this._type, this._segs);
					if (handle.kind === "directory") return {
						modificationTime: /* @__PURE__ */ new Date(),
						size: 0
					};
					const file = await handle.getFile();
					return {
						modificationTime: new Date(file.lastModified),
						size: file.size
					};
				})(), success, error);
			}
			remove(success, error) {
				settle$1((async () => {
					const segs = this._segs;
					if (!segs.length) throw fail("InvalidModificationError", "The root directory cannot be removed.");
					const handle = await need(this._type, segs);
					await (await walk(this._type, segs.slice(0, -1))).removeEntry(segs[segs.length - 1]).catch((e) => {
						throw handle.kind === "directory" && e.name !== "NotFoundError" ? fail("InvalidModificationError", "The directory is not empty.") : e;
					});
					forget(this._type, this.fullPath);
				})(), success, error);
			}
			moveTo(parent, name, success, error) {
				settle$1(this._transfer(parent, name, true), success, error);
			}
			copyTo(parent, name, success, error) {
				settle$1(this._transfer(parent, name, false), success, error);
			}
			async _transfer(parent, name, move) {
				if (!(parent instanceof DirectoryEntry)) throw fail("TypeMismatchError", "The parent is not a directory.");
				const newName = name == null || name === "" ? this.name : String(name);
				if (!newName || newName.includes("/") || newName === "." || newName === "..") throw fail("EncodingError", "Invalid name.");
				const from = this._segs;
				const to = [...parent._segs, newName];
				const same = parent._type === this._type;
				if (!from.length) throw fail("InvalidModificationError", "The root directory cannot be moved or copied.");
				if (same && (joinPath(to) === this.fullPath || joinPath(to).startsWith(this.fullPath + "/"))) throw fail("InvalidModificationError", "An entry cannot be moved or copied onto or into itself.");
				const handle = await need(this._type, from);
				const into = await need(parent._type, parent._segs);
				if (into.kind !== "directory") throw fail("NotFoundError");
				const there = await lookup(parent._type, to).catch(() => null);
				if (there) {
					if (there.kind !== handle.kind) throw fail("InvalidModificationError", "An entry of another kind is in the way.");
					await into.removeEntry(newName).catch(() => {
						throw fail("InvalidModificationError", "The directory in the way is not empty.");
					});
					forget(parent._type, joinPath(to));
				}
				let moved = false;
				if (move && same && typeof handle.move === "function") try {
					await handle.move(into, newName);
					moved = true;
				} catch {}
				if (!moved) {
					await copy(handle, into, newName);
					if (move) await (await walk(this._type, from.slice(0, -1))).removeEntry(from[from.length - 1], { recursive: true });
				}
				if (move) forget(this._type, this.fullPath);
				return new (this.isDirectory ? DirectoryEntry : FileEntry)(parent.filesystem, parent._type, joinPath(to));
			}
		}
		class DirectoryEntry extends Entry {
			get isFile() {
				return false;
			}
			get isDirectory() {
				return true;
			}
			createReader() {
				return new DirectoryReader(this);
			}
			getFile(path, options, success, error) {
				settle$1(this._get(path, options, "file"), success, error);
			}
			getDirectory(path, options, success, error) {
				settle$1(this._get(path, options, "directory"), success, error);
			}
			async _get(path, options, kind) {
				const create = !!(options && options.create);
				const exclusive = !!(options && options.exclusive);
				const segs = segments(this.fullPath, path);
				if (!segs.length) {
					if (kind === "file") throw fail("TypeMismatchError", "The root is a directory.");
					if (create && exclusive) throw fail("InvalidModificationError", "The directory already exists.");
					return this.filesystem.root;
				}
				const dir = await walk(this._type, segs.slice(0, -1)).catch((e) => {
					throw e.name === "TypeMismatchError" ? fail("NotFoundError") : e;
				});
				const name = segs[segs.length - 1];
				if (create && exclusive) {
					if (await lookup(this._type, segs).catch(() => null)) throw fail("InvalidModificationError", "The entry already exists.");
				}
				await (kind === "file" ? dir.getFileHandle(name, { create }) : dir.getDirectoryHandle(name, { create }));
				return new (kind === "file" ? FileEntry : DirectoryEntry)(this.filesystem, this._type, joinPath(segs));
			}
			removeRecursively(success, error) {
				settle$1((async () => {
					const segs = this._segs;
					if (!segs.length) throw fail("InvalidModificationError", "The root directory cannot be removed.");
					await need(this._type, segs);
					await (await walk(this._type, segs.slice(0, -1))).removeEntry(segs[segs.length - 1], { recursive: true });
					forget(this._type, this.fullPath);
				})(), success, error);
			}
		}
		class DirectoryReader {
			constructor(dir) {
				this._dir = dir;
				this._left = null;
			}
			readEntries(success, error) {
				settle$1((async () => {
					const dir = this._dir;
					if (!this._left) {
						const handle = await need(dir._type, dir._segs);
						this._left = [];
						for await (const [name, h] of handle.entries()) {
							const Kind = h.kind === "file" ? FileEntry : DirectoryEntry;
							this._left.push(new Kind(dir.filesystem, dir._type, joinPath([...dir._segs, name])));
						}
					}
					return this._left.splice(0, 100);
				})(), success, error);
			}
		}
		class FileEntry extends Entry {
			get isFile() {
				return true;
			}
			get isDirectory() {
				return false;
			}
			file(success, error) {
				settle$1((async () => {
					const handle = await need(this._type, this._segs);
					if (handle.kind !== "file") throw fail("TypeMismatchError");
					return typed(await handle.getFile());
				})(), success, error);
			}
			createWriter(success, error) {
				settle$1((async () => {
					const handle = await need(this._type, this._segs);
					if (handle.kind !== "file") throw fail("TypeMismatchError");
					return new FileWriter(this, handle, (await handle.getFile()).size);
				})(), success, error);
			}
		}
		class FileWriter extends EventTarget {
			constructor(entry, handle, length) {
				super();
				Object.defineProperty(this, "_entry", { value: entry });
				Object.defineProperty(this, "_handle", { value: handle });
				Object.defineProperty(this, "_token", {
					value: null,
					writable: true
				});
				this.readyState = 0;
				this.position = 0;
				this.length = length;
				this.error = null;
				this.onwritestart = this.onprogress = this.onwrite = this.onabort = this.onerror = this.onwriteend = null;
			}
			_fire(type, loaded, total) {
				const event = new ProgressEvent(type, {
					lengthComputable: true,
					loaded,
					total
				});
				this.dispatchEvent(event);
				const handler = this["on" + type];
				if (typeof handler === "function") handler.call(this, event);
			}
			_run(size, work, after) {
				if (this.readyState === 1) throw fail("InvalidStateError", "A write is already in progress.");
				this.readyState = 1;
				this.error = null;
				const run = this._token = {};
				setTimeout(async () => {
					if (this._token !== run) return;
					this._fire("writestart", 0, size);
					try {
						const w = await this._handle.createWritable({ keepExistingData: true });
						try {
							await work(w);
							await w.close();
						} catch (e) {
							await w.abort().catch(() => {});
							throw e;
						}
						if (this._token !== run) return;
						after();
						forget(this._entry._type, this._entry.fullPath);
						this.readyState = 2;
						this._fire("progress", size, size);
						this._fire("write", size, size);
					} catch (e) {
						if (this._token !== run) return;
						this.error = asError(e);
						this.readyState = 2;
						this._fire("error", 0, size);
					}
					this._fire("writeend", this.readyState === 2 ? size : 0, size);
				});
			}
			write(data) {
				if (!(data instanceof Blob)) throw new TypeError("Failed to execute 'write' on 'FileWriter': parameter 1 is not of type 'Blob'.");
				const at = this.position;
				this._run(data.size, (w) => w.write({
					type: "write",
					position: at,
					data
				}), () => {
					this.position = at + data.size;
					this.length = Math.max(this.length, this.position);
				});
			}
			truncate(size) {
				const length = Math.max(0, Number(size) || 0);
				this._run(0, (w) => w.truncate(length), () => {
					this.length = length;
					this.position = Math.min(this.position, length);
				});
			}
			seek(offset) {
				if (this.readyState === 1) throw fail("InvalidStateError", "A write is in progress.");
				let at = Number(offset) || 0;
				if (at < 0) at = Math.max(0, this.length + at);
				this.position = Math.min(at, this.length);
			}
			abort() {
				if (this.readyState !== 1) return;
				this._token = null;
				this.readyState = 2;
				this.error = fail("AbortError", "The write was aborted.");
				this._fire("abort", 0, 0);
				this._fire("writeend", 0, 0);
			}
		}
		for (const [k, v] of [
			["INIT", 0],
			["WRITING", 1],
			["DONE", 2]
		]) {
			Object.defineProperty(FileWriter, k, { value: v });
			Object.defineProperty(FileWriter.prototype, k, { value: v });
		}
		return {
			Entry,
			DirectoryEntry,
			DirectoryReader,
			FileEntry,
			FileWriter,
			system
		};
	}

//#endregion
//#region src/extension-shims/file-system/loading.ts
/** Where a `filesystem:` URL of this page's origin points, or null. */
	const parse = (url) => parseFileSystemURL(url, location.origin);
	/** The URLs a download or a new tab or window is given. */
	const urlsOf = (o) => typeof o.url === "string" ? [o.url] : Array.isArray(o.url) ? o.url : null;
	/** Whether a `made` key, "<type>:<path>", is the path or under it. */
	function isUnder(key, type, path) {
		const [t, p] = [Number(key[0]), key.slice(2)];
		return t === type && (p === path || p.startsWith(path === "/" ? "/" : path + "/"));
	}
	function createFileCache({ need }) {
		const made = /* @__PURE__ */ new Map();
		const forget = (type, path) => {
			for (const [key, url] of made) if (isUnder(key, type, path)) {
				made.delete(key);
				Promise.resolve(url).then((u) => {
					if (u) setTimeout(() => URL.revokeObjectURL(u), 6e4);
				}, () => {});
			}
		};
		const fileAt = async (url) => {
			const at = parse(url);
			if (!at) throw fail("NotFoundError");
			const handle = await need(at.type, at.segs);
			if (handle.kind !== "file") throw fail("NotFoundError");
			return typed(await handle.getFile());
		};
		const blobURL = (url) => {
			const at = parse(url);
			if (!at) return Promise.reject(fail("NotFoundError"));
			const key = at.type + ":" + joinPath(at.segs);
			if (!made.has(key)) {
				const p = fileAt(url).then((file) => {
					const u = URL.createObjectURL(file);
					made.set(key, u);
					return u;
				});
				made.set(key, p);
				p.catch(() => {
					if (made.get(key) === p) made.delete(key);
				});
			}
			return Promise.resolve(made.get(key));
		};
		const ready = (url) => {
			const at = parse(url);
			const u = at && made.get(at.type + ":" + joinPath(at.segs));
			return typeof u === "string" ? u : null;
		};
		const dataURL = (url) => fileAt(url).then((file) => new Promise((resolve, reject) => {
			const reader = new FileReader();
			reader.onload = () => resolve(reader.result);
			reader.onerror = () => reject(reader.error);
			reader.readAsDataURL(file);
		}));
		return {
			forget,
			fileAt,
			blobURL,
			ready,
			dataURL
		};
	}
	/**
	* Where a filesystem: URL is loaded. An image or link gets the blob: URL
	* once it's made — at once when it already was, so a src set again stays
	* put — and reads back the filesystem: URL, as in Chrome. A file that
	* isn't there leaves the URL as it was, so the image fails as it would.
	*/
	function loadFileSystemURLs(root, cache) {
		const shown = /* @__PURE__ */ new WeakMap();
		const hook = (proto, prop) => {
			const d = proto && Object.getOwnPropertyDescriptor(proto, prop);
			if (!d || !d.set || !d.get) return;
			const { get, set } = d;
			Object.defineProperty(proto, prop, Object.assign({}, d, {
				get() {
					const value = get.call(this);
					const was = shown.get(this);
					return was && was.blob === value ? was.url : value;
				},
				set(value) {
					const url = typeof value === "string" ? value : null;
					if (!url || !url.startsWith("filesystem:") || !parse(url)) {
						shown.delete(this);
						return set.call(this, value);
					}
					const now = cache.ready(url);
					if (now) {
						shown.set(this, {
							url,
							blob: now
						});
						return set.call(this, now);
					}
					const was = {
						url,
						blob: null
					};
					shown.set(this, was);
					cache.blobURL(url).then((blob) => {
						if (shown.get(this) !== was) return;
						was.blob = blob;
						set.call(this, blob);
					}, () => {
						if (shown.get(this) === was) {
							shown.delete(this);
							set.call(this, url);
						}
					});
				}
			}));
		};
		hook(root.HTMLImageElement && HTMLImageElement.prototype, "src");
		hook(root.HTMLAnchorElement && HTMLAnchorElement.prototype, "href");
		const setAttribute = Element.prototype.setAttribute;
		Element.prototype.setAttribute = function(name, value) {
			if (typeof value === "string" && value.startsWith("filesystem:")) {
				const n = String(name).toLowerCase();
				if (n === "src" && this instanceof HTMLImageElement || n === "href" && this instanceof HTMLAnchorElement) {
					this[n] = value;
					return;
				}
			}
			return setAttribute.call(this, name, value);
		};
		if (typeof root.fetch === "function") {
			const fetch = root.fetch;
			root.fetch = function(input, _init) {
				const url = typeof input === "string" ? input : input instanceof URL ? input.href : null;
				if (!url || !url.startsWith("filesystem:") || !parse(url)) return fetch.apply(this, arguments);
				return cache.fileAt(url).then((file) => new Response(file, {
					status: 200,
					headers: {
						"Content-Type": file.type || "application/octet-stream",
						"Content-Length": String(file.size)
					}
				}), () => {
					throw new TypeError("Load failed");
				});
			};
		}
	}
	/**
	* The browser downloads and opens tabs from outside this page, where a blob:
	* URL of this page means nothing: those get the file itself, as a data: URL.
	*/
	function handOverFileSystemURLs(root, cache, define) {
		const chrome = root.chrome || root.browser;
		const lastError = (e, callback) => {
			const runtime = chrome && chrome.runtime;
			try {
				Object.defineProperty(runtime, "lastError", {
					value: { message: String(e && e.message || e) },
					configurable: true
				});
			} catch {}
			try {
				callback();
			} finally {
				try {
					delete runtime.lastError;
				} catch {}
			}
		};
		const held = [];
		const swap = (space, method, urls) => {
			const ns = chrome && chrome[space];
			const original = ns && ns[method];
			if (typeof original !== "function") return;
			held.push(ns);
			define(ns, method, function(options, ...rest) {
				const list = options && urls(options);
				if (!list || !list.some((u) => typeof u === "string" && parse(u))) return original.call(this, options, ...rest);
				const callback = typeof rest[rest.length - 1] === "function" ? rest.pop() : null;
				const p = Promise.all(list.map((u) => typeof u === "string" && parse(u) ? cache.dataURL(u) : u)).then((done) => {
					const copy = Object.assign({}, options, { url: Array.isArray(options.url) ? done : done[0] });
					return original.call(this, copy, ...rest);
				});
				if (!callback) return p;
				p.then((v) => callback(v), (e) => lastError(e, callback));
			});
		};
		swap("downloads", "download", urlsOf);
		swap("tabs", "create", urlsOf);
		swap("windows", "create", urlsOf);
	}

//#endregion
//#region src/extension-shims/file-system.ts
	function define(target, key, value) {
		try {
			Object.defineProperty(target, key, {
				value,
				configurable: true,
				writable: true,
				enumerable: true
			});
		} catch {}
	}
	function rebuildFileSystem(root) {
		if (root.requestFileSystem || root.webkitRequestFileSystem || typeof document === "undefined" || !(root.navigator && navigator.storage && navigator.storage.getDirectory)) return;
		const storage = createOriginStorage();
		const cache = createFileCache(storage);
		const { Entry, DirectoryEntry, DirectoryReader, FileEntry, FileWriter, system } = createEntries(storage, cache.forget);
		const requestFileSystem = (type, _size, success, error) => {
			const kind = Number(type);
			settle$1(kind === 0 || kind === 1 ? storage.folder(kind).then(() => system(kind)) : Promise.reject(fail("InvalidModificationError", "Unknown file system type.")), success, error);
		};
		const resolveURL = (url, success, error) => {
			settle$1((async () => {
				const at = parseFileSystemURL(url, location.origin);
				if (!at) throw fail(String(url).startsWith("filesystem:") ? "SecurityError" : "EncodingError", "Not a filesystem: URL of this origin.");
				const handle = await storage.need(at.type, at.segs);
				const fs = system(at.type);
				if (!at.segs.length) return fs.root;
				return new (handle.kind === "file" ? FileEntry : DirectoryEntry)(fs, at.type, joinPath(at.segs));
			})(), success, error);
		};
		define(root, "TEMPORARY", 0);
		define(root, "PERSISTENT", 1);
		define(root, "requestFileSystem", requestFileSystem);
		define(root, "webkitRequestFileSystem", requestFileSystem);
		define(root, "resolveLocalFileSystemURL", resolveURL);
		define(root, "webkitResolveLocalFileSystemURL", resolveURL);
		const quota = {
			requestQuota: (size, success, error) => settle$1(Promise.resolve(size), success, error),
			queryUsageAndQuota: (success, error) => settle$1(navigator.storage.estimate().then((e) => [e.usage || 0, e.quota || 0]), (v) => typeof success === "function" && success(v[0], v[1]), error)
		};
		const nav = navigator;
		if (!nav.webkitPersistentStorage) define(navigator, "webkitPersistentStorage", quota);
		if (!nav.webkitTemporaryStorage) define(navigator, "webkitTemporaryStorage", quota);
		for (const [name, Kind] of [
			["FileSystemEntry", Entry],
			["FileSystemDirectoryEntry", DirectoryEntry],
			["FileSystemFileEntry", FileEntry],
			["FileSystemDirectoryReader", DirectoryReader]
		]) if (!root[name]) define(root, name, Kind);
		if (!root.FileWriter) define(root, "FileWriter", FileWriter);
		loadFileSystemURLs(root, cache);
		handOverFileSystemURLs(root, cache, define);
	}

//#endregion
//#region src/extension-shims/globals.ts
/**
	* WebKit reverted `requestIdleCallback` after a page-load regression
	* (bug 287681), leaving Proton Pass's form detection without it.
	*/
	function polyfillIdleCallback(root) {
		const nativeIdle = typeof root.requestIdleCallback === "function" ? root.requestIdleCallback.bind(root) : null;
		const nativeCancelIdle = typeof root.cancelIdleCallback === "function" ? root.cancelIdleCallback.bind(root) : null;
		if (nativeIdle && nativeCancelIdle) return;
		const idle = /* @__PURE__ */ new Map();
		let idleId = 0;
		root.requestIdleCallback = (callback, options) => {
			const id = ++idleId;
			if (nativeIdle) {
				const nativeId = nativeIdle((deadline) => {
					if (!idle.delete(id)) return;
					callback(deadline);
				}, options);
				idle.set(id, { nativeId });
			} else {
				const timer = setTimeout(() => {
					if (!idle.delete(id)) return;
					const start = Date.now();
					callback({
						didTimeout: false,
						timeRemaining: () => Math.max(0, 50 - (Date.now() - start))
					});
				}, 1);
				idle.set(id, { timer });
			}
			return id;
		};
		root.cancelIdleCallback = (id) => {
			const request = idle.get(id);
			if (request === void 0) {
				if (nativeCancelIdle) nativeCancelIdle(id);
				return;
			}
			idle.delete(id);
			if (request.timer !== void 0) clearTimeout(request.timer);
			else if (nativeCancelIdle) nativeCancelIdle(request.nativeId);
		};
	}
	/**
	* Keep the first credentials container alive so extension hooks
	* survive WebKit replacing an unreferenced container.
	*/
	function keepCredentials(root) {
		const credentials = root.navigator && root.navigator.credentials;
		if (credentials && !Object.prototype.hasOwnProperty.call(root, "__moteCredentials")) Object.defineProperty(root, "__moteCredentials", { value: credentials });
	}
	/** Marks the context as mended, so the shim runs once however often it is loaded. */
	function markInstalled(root) {
		Object.defineProperty(root, "__moteShim", { value: true });
	}
	/**
	* WebKit finds a page's extension APIs through the `chrome` and
	* `browser` globals when it delivers an event. A sandbox that locks
	* every global away (MetaMask's LavaMoat) cuts it off: nothing arrives
	* any more. Made fixed accessors, they can't be taken away, and code
	* that assigns its own polyfill to them still can.
	*/
	function fixChromeGlobals(root) {
		for (const key of ["browser", "chrome"]) {
			const descriptor = Object.getOwnPropertyDescriptor(root, key);
			if (!descriptor || !descriptor.configurable) continue;
			let value = root[key];
			try {
				Object.defineProperty(root, key, {
					configurable: false,
					enumerable: descriptor.enumerable,
					get: () => value,
					set: (v) => {
						if (carriesExtensionAPIs(v)) value = v;
					}
				});
			} catch {}
		}
	}

//#endregion
//#region src/extension-shims/holding.ts
/** The set of held objects, also reachable as `__moteKept`, and `put`, which adds to it. */
	function createHolder(root) {
		const kept = /* @__PURE__ */ new Set();
		try {
			Object.defineProperty(root, "__moteKept", { value: kept });
		} catch {}
		const put = (target, key, value) => {
			if (target && (typeof target === "object" || typeof target === "function")) kept.add(target);
			try {
				Object.defineProperty(target, key, {
					value,
					configurable: true,
					writable: true,
					enumerable: true
				});
			} catch {
				try {
					target[key] = value;
				} catch {}
			}
		};
		return {
			kept,
			put
		};
	}
	/**
	* Holds every namespace of `chrome`, its events and storage areas, from the
	* start, before the extension's own code runs — its polyfills set things on
	* these objects too. Returns the namespaces' names.
	*/
	function holdNamespaces(chrome, kept) {
		const spaces = new Set(Object.keys(chrome));
		for (let o = Object.getPrototypeOf(chrome); o && o !== Object.prototype; o = Object.getPrototypeOf(o)) for (const key of Object.getOwnPropertyNames(o)) spaces.add(key);
		for (const space of spaces) {
			let ns;
			try {
				ns = chrome[space];
			} catch {
				continue;
			}
			if (!ns || typeof ns !== "object") continue;
			kept.add(ns);
			if (!Object.prototype.hasOwnProperty.call(chrome, space) || Object.getOwnPropertyDescriptor(chrome, space).get) try {
				Object.defineProperty(chrome, space, {
					value: ns,
					configurable: true,
					writable: true,
					enumerable: true
				});
			} catch {}
			for (const key of memberNames(ns)) {
				if (!isEventName(key)) continue;
				try {
					const event = ns[key];
					if (event && typeof event === "object") kept.add(event);
				} catch {}
			}
			for (const sub of [
				"local",
				"sync",
				"session",
				"managed"
			]) try {
				if (ns[sub] && typeof ns[sub] === "object") kept.add(ns[sub]);
			} catch {}
		}
		return spaces;
	}
	/** Calls `callback` with `runtime.lastError` set, then takes it away again, as Chrome does. */
	function lastErrorReporter(runtime, put) {
		return (error, callback) => {
			put(runtime, "lastError", { message: errorMessage(error) });
			try {
				callback();
			} finally {
				try {
					delete runtime.lastError;
				} catch {}
			}
		};
	}
	/** Own copies of runtime's methods, bound to it. */
	function bindRuntimeMethods(runtime, put) {
		if (!runtime) return;
		for (const name of memberNames(runtime)) {
			if (name === "constructor" || isEventName(name)) continue;
			let f;
			try {
				f = runtime[name];
			} catch {
				continue;
			}
			if (typeof f === "function") put(runtime, name, f.bind(runtime));
		}
	}

//#endregion
//#region src/extension-shims/web-request.ts
	function fillWebRequest(shim, resourceTypes) {
		fill(shim, "webRequest", {
			OnBeforeRequestOptions: {
				BLOCKING: "blocking",
				REQUEST_BODY: "requestBody",
				EXTRA_HEADERS: "extraHeaders"
			},
			OnBeforeSendHeadersOptions: {
				REQUEST_HEADERS: "requestHeaders",
				BLOCKING: "blocking",
				EXTRA_HEADERS: "extraHeaders"
			},
			OnSendHeadersOptions: {
				REQUEST_HEADERS: "requestHeaders",
				EXTRA_HEADERS: "extraHeaders"
			},
			OnHeadersReceivedOptions: {
				BLOCKING: "blocking",
				RESPONSE_HEADERS: "responseHeaders",
				EXTRA_HEADERS: "extraHeaders"
			},
			OnAuthRequiredOptions: {
				RESPONSE_HEADERS: "responseHeaders",
				BLOCKING: "blocking",
				ASYNC_BLOCKING: "asyncBlocking",
				EXTRA_HEADERS: "extraHeaders"
			},
			OnResponseStartedOptions: {
				RESPONSE_HEADERS: "responseHeaders",
				EXTRA_HEADERS: "extraHeaders"
			},
			OnBeforeRedirectOptions: {
				RESPONSE_HEADERS: "responseHeaders",
				EXTRA_HEADERS: "extraHeaders"
			},
			OnCompletedOptions: {
				RESPONSE_HEADERS: "responseHeaders",
				EXTRA_HEADERS: "extraHeaders"
			},
			OnErrorOccurredOptions: { EXTRA_HEADERS: "extraHeaders" },
			ResourceType: resourceTypes,
			MAX_HANDLER_BEHAVIOR_CHANGED_CALLS_PER_10_MINUTES: 20,
			handlerBehaviorChanged: resolved(void 0),
			onActionIgnored: createEvent()
		});
	}
	/**
	* WebKit can't read ws:// and wss:// patterns, and refuses the
	* whole listener over one; Chrome watches sockets too. The
	* listener is kept for everything else: the filter without them, or
	* null when nothing is left.
	*/
	function withoutSocketPatterns(filter) {
		if (!filter || !Array.isArray(filter.urls)) return filter;
		const urls = filter.urls.filter((u) => !/^wss?:/i.test(u));
		if (!urls.length) return null;
		return {
			...filter,
			urls
		};
	}
	/** The extra info WebKit takes: headers and bodies, reported anyway, and no blocking. */
	function supportedExtraInfo(spec) {
		return spec.filter((s) => s === "requestHeaders" || s === "responseHeaders" || s === "requestBody");
	}
	/** Whether WebKit refused a listener for being added after the worker's startup. */
	function isLateListenerError(error) {
		return /startup/i.test(String(error && error.message));
	}
	/**
	* webRequest listeners with options WebKit doesn't take — blocking
	* needs a policy-installed extension in Chrome's MV3 too; extra headers
	* WebKit reports anyway — are added with the options it does take.
	*/
	function mendRequestListeners({ chrome, put }) {
		if (!chrome.webRequest) return;
		for (const key of Object.keys(chrome.webRequest)) {
			const target = chrome.webRequest[key];
			if (!isEventName(key) || !target || typeof target.addListener !== "function") continue;
			const add = target.addListener.bind(target);
			put(target, "addListener", (listener, filter, spec) => {
				const kept = withoutSocketPatterns(filter);
				if (kept === null) return void 0;
				filter = kept;
				try {
					if (!Array.isArray(spec)) return add(listener, filter);
					try {
						return add(listener, filter, supportedExtraInfo(spec));
					} catch (e) {
						if (isLateListenerError(e)) throw e;
						return add(listener, filter);
					}
				} catch (e) {
					if (!isLateListenerError(e)) throw e;
				}
			});
		}
	}

//#endregion
//#region src/extension-shims/lifecycle.ts
/** An `onInstalled` reason told as the update it is, for an extension taken up again in the session. */
	function asUpdate(details, version) {
		return {
			...details,
			reason: "update",
			previousVersion: version
		};
	}
	/**
	* WebKit says "install" again when an extension is taken up afresh in
	* the same session — after a Reload, or a worker brought back — where
	* Chrome says "update"; extensions open their welcome page on
	* "install". The first one of a session is marked, and any later one
	* told as the update it is.
	*/
	function mendInstalledReason({ runtime, put, native, background }) {
		if (!background || !runtime.onInstalled || typeof runtime.onInstalled.addListener !== "function") return;
		let decided = null;
		const seenBefore = () => decided || (decided = native("background.loadedBefore", []).then((v) => !!v, () => false));
		const add = runtime.onInstalled.addListener.bind(runtime.onInstalled);
		const remove = runtime.onInstalled.removeListener.bind(runtime.onInstalled);
		const wrapped = /* @__PURE__ */ new Map();
		put(runtime.onInstalled, "addListener", (listener) => {
			const w = (details) => {
				if (!details || details.reason !== "install") return listener(details);
				seenBefore().then((seen) => listener(seen ? asUpdate(details, runtime.getManifest().version) : details));
			};
			wrapped.set(listener, w);
			return add(w);
		});
		put(runtime.onInstalled, "removeListener", (listener) => {
			const w = wrapped.get(listener);
			wrapped.delete(listener);
			return remove(w || listener);
		});
		put(runtime.onInstalled, "hasListener", (listener) => wrapped.has(listener));
	}
	/**
	* A worker may add listeners only while it starts; WebKit throws for
	* one added later, where Chrome takes it. So for every event this
	* extension's code mentions (`ShimConfig.events`), the worker has one
	* listener of WebKit's from the start, and a late one joins the list
	* behind it. Events it never mentions still take late listeners without
	* throwing — they just aren't heard. (Request events are left alone: a
	* listener for all of them would wake the worker for every request.)
	*/
	function acceptLateListeners({ chrome, put, background, config }) {
		if (!background) return;
		const mentioned = new Set(config.events);
		for (const space of Object.keys(chrome)) {
			if (space === "webRequest") continue;
			let ns;
			try {
				ns = chrome[space];
			} catch {
				continue;
			}
			if (!ns || typeof ns !== "object") continue;
			for (const key of memberNames(ns)) {
				if (!isEventName(key) || space === "runtime" && key.startsWith("onMessage")) continue;
				let target;
				try {
					target = ns[key];
				} catch {
					continue;
				}
				if (!target || typeof target.addListener !== "function" || target.listeners) continue;
				const add = target.addListener.bind(target);
				const remove = target.removeListener.bind(target);
				const late = /* @__PURE__ */ new Set();
				if (mentioned.has(space + "." + key)) try {
					add(function(...args) {
						let answer;
						for (const f of [...late]) try {
							const r = f(...args);
							if (r !== void 0) answer = r;
						} catch (e) {
							rethrowLater(e);
						}
						return answer;
					});
				} catch {}
				put(target, "addListener", (listener, ...rest) => {
					try {
						return add(listener, ...rest);
					} catch (e) {
						if (isLateListenerError(e)) late.add(listener);
						else throw e;
					}
				});
				put(target, "removeListener", (listener) => {
					late.delete(listener);
					try {
						remove(listener);
					} catch {}
				});
			}
		}
	}

//#endregion
//#region src/extension-shims/menus.ts
	function fillMenus(shim) {
		const contextTypes = enumOf("all", "page", "frame", "selection", "link", "editable", "image", "video", "audio", "launcher", "browser_action", "page_action", "action");
		fill(shim, "contextMenus", {
			ContextType: contextTypes,
			ItemType: enumOf("normal", "checkbox", "radio", "separator")
		});
		fill(shim, "menus", {
			ContextType: contextTypes,
			ItemType: enumOf("normal", "checkbox", "radio", "separator")
		});
	}
	/**
	* Context menu entries for places Mote has no menu for — the old
	* toolbar button contexts are the button's menu now, and there is no
	* app launcher at all.
	*/
	function mendMenuProperties(props) {
		if (!props || !Array.isArray(props.contexts)) return props;
		const contexts = [...new Set(props.contexts.map((c) => c === "browser_action" || c === "page_action" ? "action" : c).filter((c) => c !== "launcher"))];
		return {
			...props,
			contexts: contexts.length ? contexts : ["page"]
		};
	}
	function mendMenus({ chrome, put }) {
		for (const name of ["contextMenus", "menus"]) {
			const menus = chrome[name];
			if (!menus || typeof menus.create !== "function") continue;
			const create = menus.create.bind(menus);
			put(menus, "create", (props, callback) => create(mendMenuProperties(props), callback));
			if (typeof menus.update !== "function") continue;
			const update = menus.update.bind(menus);
			put(menus, "update", (id, props, callback) => update(id, mendMenuProperties(props), callback));
		}
	}

//#endregion
//#region src/extension-shims/ids.ts
/**
	* A new id: 128 random bits, as 32 hex digits. From `getRandomValues`,
	* which every context has; `randomUUID` needs a secure one, and a
	* content script can run on a plain http page.
	*/
	function randomId() {
		const bytes = crypto.getRandomValues(/* @__PURE__ */ new Uint8Array(16));
		return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
	}

//#endregion
//#region src/extension-shims/message-verdicts.ts
	const CHANNEL_NAME = "mote-messages";
	/** Longest message, as JSON, that is told about; a longer one is simply waited for. */
	const MAX_KEY_LENGTH = 4e3;
	/** How long what was said about a message is remembered. */
	const REMEMBERED_MS = 3e4;
	/** The message as a key to what is said about it, or null when it is too long or not JSON. */
	function messageKey(message) {
		try {
			const key = JSON.stringify(message);
			return key && key.length < MAX_KEY_LENGTH ? key : null;
		} catch {
			return null;
		}
	}
	/** Takes in a verdict, forgetting old ones; the entry for a key goes last, as the newest. */
	function recordVerdict(verdicts, news, now) {
		for (const [key, entry] of verdicts) if (now - entry.at > REMEMBERED_MS) verdicts.delete(key);
		else break;
		const entry = verdicts.get(news.key) || {
			at: now,
			worker: null,
			pages: /* @__PURE__ */ new Map()
		};
		verdicts.delete(news.key);
		verdicts.set(news.key, entry);
		entry.at = now;
		if (news.from === "worker") entry.worker = news;
		else entry.pages.set(news.from, news);
		return entry;
	}
	function createVerdicts({ root, inContent, embedded, background }) {
		const channel = !inContent && !embedded && typeof BroadcastChannel === "function" ? new BroadcastChannel(CHANNEL_NAME) : null;
		const me = randomId();
		const peers = /* @__PURE__ */ new Set();
		const verdicts = /* @__PURE__ */ new Map();
		const waiting = /* @__PURE__ */ new Set();
		const present = /* @__PURE__ */ new Set();
		const deaf = /* @__PURE__ */ new Set();
		let listening = false;
		const post = (news) => channel.postMessage(news);
		const tell = (message, verdict, heard) => {
			const key = channel && messageKey(message);
			if (key) post({
				key,
				from: background ? "worker" : me,
				verdict,
				heard,
				at: Date.now()
			});
		};
		const join = () => {
			if (channel && !background && !listening) {
				listening = true;
				post({
					hello: true,
					from: me,
					where: location.pathname
				});
			}
		};
		const leave = () => {
			if (channel && !background && listening) {
				listening = false;
				post({
					bye: true,
					from: me
				});
			}
		};
		if (channel) {
			channel.onmessage = ({ data }) => {
				if (!data || data.from === me) return;
				if (!background && data.hello) {
					const known = peers.has(data.from);
					peers.add(data.from);
					if (!known && listening) post({
						hello: true,
						from: me,
						where: location.pathname
					});
					return;
				}
				if (data.bye) {
					peers.delete(data.from);
					waiting.forEach((check) => check());
					return;
				}
				if (data.roll) {
					if (listening && !background) post({
						here: true,
						from: me,
						to: data.from
					});
					return;
				}
				if (data.here) {
					if (data.to === me) present.forEach((hear) => hear(data.from));
					return;
				}
				if (typeof data.key !== "string") return;
				if (data.from !== "worker") {
					peers.add(data.from);
					if (data.heard) deaf.delete(data.from);
				}
				recordVerdict(verdicts, data, Date.now());
				waiting.forEach((check) => check());
			};
			if (!background) try {
				root.addEventListener("pagehide", () => leave());
			} catch {}
		}
		return {
			channel,
			me,
			peers,
			verdicts,
			waiting,
			present,
			deaf,
			tell,
			join,
			leave
		};
	}

//#endregion
//#region src/extension-shims/messaging.ts
/** How long a page that has nothing to say waits before saying so. */
	const SILENCE_MS = 1e4;
	function nothing$1() {}
	/** Calls the listeners Chrome's way: whichever returns true or a promise keeps the answer open. */
	function callListeners(listeners, message, sender, sendResponse) {
		let keep = false;
		for (const listener of [...listeners]) {
			let result;
			try {
				result = listener(message, sender, sendResponse);
			} catch (e) {
				rethrowLater(e);
				continue;
			}
			if (result === true) keep = true;
			else if (result && typeof result.then === "function") {
				keep = true;
				result.then(sendResponse, () => sendResponse(void 0));
			}
		}
		return keep;
	}
	function createGather(shim, verdicts) {
		const { root, chrome, runtime, put, inContent, embedded, background } = shim;
		const { channel, me, peers, waiting, present, deaf, tell, join, leave } = verdicts;
		let ownTab = null;
		/** A tab's message for a page framed in it: taken by the frame it names, in the tab it names. */
		const toFrame = (to, listeners, sender, sendResponse) => {
			if (!embedded || !(to.urls || []).includes(location.href)) {
				if (!background) setTimeout(() => sendResponse(void 0), SILENCE_MS);
				return background ? void 0 : true;
			}
			if (!ownTab) ownTab = Promise.resolve(runtime.sendMessage({ __moteCall: {
				space: "tabs",
				method: "getCurrent",
				args: []
			} })).then((reply) => reply && reply.value ? reply.value.id : null, () => null);
			ownTab.then((id) => {
				if (id !== to.tabId) return setTimeout(() => sendResponse(void 0), SILENCE_MS);
				if (!callListeners(listeners, to.message, sender, sendResponse)) sendResponse(void 0);
			});
			return true;
		};
		/**
		* A call one of the extension's pages in a website's frame can't
		* make itself (see `embedded`), made here for it — and only for
		* one of its pages: a content script gets no more than Chrome
		* gives it.
		*/
		const callFor = (call, sender, sendResponse) => {
			if (!background) return true;
			const { space, method, args } = call;
			if (!(() => {
				try {
					return new URL(sender.url).origin === location.origin;
				} catch {
					return false;
				}
			})()) {
				sendResponse({ error: "chrome." + space + " isn't available to content scripts" });
				return;
			}
			if (space === "tabs" && method === "getCurrent") {
				sendResponse({ value: sender.tab });
				return;
			}
			let ns;
			try {
				ns = chrome[space];
			} catch {}
			if (!ns || typeof ns[method] !== "function") {
				sendResponse({ error: "chrome." + space + "." + method + " isn't available" });
				return;
			}
			Promise.resolve().then(() => ns[method](...args || [])).then((value) => sendResponse({ value }), (e) => sendResponse({ error: String(e && e.message || e) }));
			return true;
		};
		/**
		* Nothing here answers it. In Chrome that leaves the question to
		* the extension's other pages and its worker; WebKit takes the
		* first reply from any of them, and an empty one from a page that
		* only listens for something else — an offscreen document, an
		* options page — would arrive before the worker's real answer. So
		* a page that has nothing to say steps aside, and says nothing
		* only once everyone else has had ample time — or as soon as the
		* worker and every other open page have said they let it pass too,
		* or the worker sent it itself. Bitwarden's offscreen document
		* keeps its storage and answers a save with nothing: ten seconds
		* on each one got in the way of signing in.
		*/
		const stepAside = (message, isSettled, sendResponse) => {
			const received = Date.now();
			const key = channel && messageKey(message);
			let check = nothing$1;
			let roll;
			const done = () => {
				waiting.delete(check);
				clearTimeout(late);
				clearTimeout(roll);
			};
			const late = setTimeout(() => {
				done();
				sendResponse(void 0);
			}, SILENCE_MS);
			if (!key) return;
			const fresh = (said) => !!said && said.at >= received - 2e3;
			check = () => {
				const entry = verdicts.verdicts.get(key);
				if (isSettled() || !entry) return;
				const worker = entry.worker;
				if (fresh(worker) && worker.verdict === "answers") {
					done();
					return;
				}
				const said = [...peers].filter((id) => !deaf.has(id) || entry.pages.has(id)).map((id) => entry.pages.get(id));
				if (said.some((p) => fresh(p) && p.verdict === "answers")) {
					done();
					return;
				}
				if (!fresh(worker) || said.some((p) => !fresh(p))) return;
				done();
				sendResponse(void 0);
			};
			waiting.add(check);
			check();
			roll = setTimeout(() => {
				if (isSettled()) return;
				const heard = /* @__PURE__ */ new Set();
				const hear = (id) => {
					heard.add(id);
				};
				present.add(hear);
				channel.postMessage({
					roll: true,
					from: me
				});
				setTimeout(() => {
					present.delete(hear);
					for (const id of [...peers]) if (!heard.has(id)) peers.delete(id);
					const entry = verdicts.verdicts.get(key);
					for (const id of peers) {
						const p = entry && entry.pages.get(id);
						if (!p || p.at < received - 2e3) deaf.add(id);
					}
					check();
				}, 1e3);
			}, 200);
		};
		/**
		* Gathers the listeners of `event` (runtime.onMessage or onMessageExternal)
		* behind one of WebKit's. `told`: this page takes part in the verdicts.
		*/
		return (event, told) => {
			if (!event || typeof event.addListener !== "function") return;
			const add = event.addListener.bind(event);
			const remove = event.removeListener.bind(event);
			const listeners = /* @__PURE__ */ new Set();
			let attached = false;
			const dispatch = function(message, sender, respond) {
				let settled = false;
				const sendResponse = (value) => {
					if (!settled) {
						settled = true;
						respond(value);
					}
				};
				if (message && message.__motePing === true) {
					if (background) {
						sendResponse("pong");
						return;
					}
					return true;
				}
				if (message && message.__moteUserScript === true) {
					const route = root.__moteUserScriptMessage;
					return route && route(message.message, sender, sendResponse) && !settled ? true : void 0;
				}
				if (message && message.__moteToFrame) return toFrame(message.__moteToFrame, listeners, sender, sendResponse);
				if (message && message.__moteCall) return callFor(message.__moteCall, sender, sendResponse);
				const keep = callListeners(listeners, message, sender, sendResponse);
				if (!inContent) tell(message, keep || settled ? "answers" : "passes", true);
				if (keep || settled) return keep && !settled ? true : void 0;
				if (!background && !inContent) {
					stepAside(message, () => settled, sendResponse);
					return true;
				}
			};
			put(event, "addListener", (listener) => {
				listeners.add(listener);
				if (told) join();
				if (!attached) {
					attached = true;
					add(dispatch);
				}
			});
			put(event, "removeListener", (listener) => {
				listeners.delete(listener);
				if (told && listeners.size === 0) leave();
				if (attached && listeners.size === 0) {
					attached = false;
					remove(dispatch);
				}
			});
			put(event, "hasListener", (listener) => listeners.has(listener));
			put(event, "hasListeners", () => listeners.size > 0);
			if (background) {
				attached = true;
				add(dispatch);
			}
		};
	}

//#endregion
//#region src/extension-shims/namespaces.ts
/** The namespaces answered by the browser, in the order they are defined. */
	function browserNamespaces(runtime) {
		return [
			{
				name: "bookmarks",
				methods: [
					"get",
					"getChildren",
					"getRecent",
					"getSubTree",
					"getTree",
					"search",
					"create",
					"move",
					"update",
					"remove",
					"removeTree"
				],
				events: [
					"onCreated",
					"onRemoved",
					"onChanged",
					"onMoved",
					"onChildrenReordered",
					"onImportBegan",
					"onImportEnded"
				]
			},
			{
				name: "history",
				methods: [
					"search",
					"getVisits",
					"addUrl",
					"deleteUrl",
					"deleteRange",
					"deleteAll"
				],
				events: ["onVisited", "onVisitRemoved"]
			},
			{
				name: "downloads",
				methods: [
					"download",
					"search",
					"pause",
					"resume",
					"cancel",
					"open",
					"show",
					"showDefaultFolder",
					"erase",
					"removeFile",
					"getFileIcon"
				],
				events: [
					"onCreated",
					"onChanged",
					"onErased",
					"onDeterminingFilename"
				]
			},
			{
				name: "sidePanel",
				methods: [
					"open",
					"setOptions",
					"getOptions",
					"setPanelBehavior",
					"getPanelBehavior"
				]
			},
			{
				name: "offscreen",
				methods: [
					"createDocument",
					"closeDocument",
					"hasDocument"
				],
				extra: { Reason: new Proxy({}, { get: (_, key) => String(key) }) }
			},
			{
				name: "tabGroups",
				methods: [
					"get",
					"query",
					"update",
					"move"
				],
				events: [
					"onCreated",
					"onRemoved",
					"onUpdated",
					"onMoved"
				],
				extra: { TAB_GROUP_ID_NONE: -1 }
			},
			{
				name: "fontSettings",
				methods: [
					"getFontList",
					"getFont",
					"setFont",
					"clearFont",
					"getDefaultFontSize",
					"setDefaultFontSize",
					"clearDefaultFontSize",
					"getDefaultFixedFontSize",
					"setDefaultFixedFontSize",
					"clearDefaultFixedFontSize",
					"getMinimumFontSize",
					"setMinimumFontSize",
					"clearMinimumFontSize"
				],
				events: [
					"onFontChanged",
					"onDefaultFontSizeChanged",
					"onDefaultFixedFontSizeChanged",
					"onMinimumFontSizeChanged"
				]
			},
			{
				name: "management",
				methods: [
					"getSelf",
					"getAll",
					"get",
					"setEnabled",
					"uninstallSelf"
				],
				events: [
					"onInstalled",
					"onUninstalled",
					"onEnabled",
					"onDisabled"
				]
			},
			{
				name: "notifications",
				methods: [
					"create",
					"update",
					"clear",
					"getAll",
					"getPermissionLevel"
				],
				events: [
					"onClicked",
					"onClosed",
					"onButtonClicked",
					"onPermissionLevelChanged",
					"onShowSettings"
				]
			},
			{
				name: "tts",
				methods: [
					"speak",
					"stop",
					"pause",
					"resume",
					"isSpeaking",
					"getVoices"
				],
				events: ["onVoicesChanged"]
			},
			{
				name: "identity",
				methods: [
					"launchWebAuthFlow",
					"getAuthToken",
					"getProfileUserInfo",
					"removeCachedAuthToken",
					"clearAllCachedAuthTokens"
				],
				events: ["onSignInChanged"],
				extra: { getRedirectURL: (path = "") => "https://" + runtime.id + ".chromiumapp.org/" + String(path).replace(/^\//, "") }
			},
			{
				name: "search",
				methods: ["query"]
			},
			{
				name: "idle",
				methods: ["queryState", "getAutoLockDelay"],
				extra: { IdleState: {
					ACTIVE: "active",
					IDLE: "idle",
					LOCKED: "locked"
				} }
			},
			{
				name: "power",
				methods: [
					"requestKeepAwake",
					"releaseKeepAwake",
					"reportActivity"
				]
			},
			{
				name: "browsingData",
				methods: [
					"remove",
					"removeAppcache",
					"removeCache",
					"removeCacheStorage",
					"removeCookies",
					"removeDownloads",
					"removeFileSystems",
					"removeFormData",
					"removeHistory",
					"removeIndexedDB",
					"removeLocalStorage",
					"removePasswords",
					"removeServiceWorkers",
					"removeWebSQL",
					"settings"
				]
			},
			{
				name: "sessions",
				methods: [
					"getRecentlyClosed",
					"getDevices",
					"restore"
				],
				events: ["onChanged"],
				extra: { MAX_SESSION_RESULTS: 25 }
			},
			{
				name: "topSites",
				methods: ["get"]
			},
			{
				name: "readingList",
				methods: [
					"query",
					"addEntry",
					"removeEntry",
					"updateEntry"
				],
				events: [
					"onEntryAdded",
					"onEntryRemoved",
					"onEntryUpdated"
				]
			}
		];
	}
	/** Sets a whole namespace on `chrome`, and on `browser` when that is another object, unless it is there. */
	function putNamespace({ root, chrome, put }, name, api) {
		if (chrome[name]) return;
		put(chrome, name, api);
		if (root.browser && root.browser !== chrome && !root.browser[name]) put(root.browser, name, api);
	}
	function defineNamespace(shim, { name, methods, events = [], extra = {} }) {
		if (shim.chrome[name]) return;
		const api = Object.assign({}, extra);
		for (const method of methods) api[method] = nativeCall(shim, name + "." + method);
		for (const event of events) api[event] = createEvent();
		putNamespace(shim, name, api);
	}
	function defineBrowserNamespaces(shim) {
		for (const spec of browserNamespaces(shim.runtime)) defineNamespace(shim, spec);
	}
	/**
	* idle.onStateChanged, asked every so often while anyone listens, the way
	* Chrome notices on its own.
	*/
	function addIdleStateEvent({ chrome, put, native }) {
		if (!chrome.idle || chrome.idle.onStateChanged) return;
		const changed = createEvent();
		const add = changed.addListener;
		let every = 60;
		let state = "active";
		let timer = null;
		changed.addListener = (f) => {
			add(f);
			if (timer) return;
			timer = setInterval(() => native("idle.queryState", [every]).then((now) => {
				if (now === state) return;
				state = now;
				for (const g of changed.listeners) try {
					g(now);
				} catch (e) {
					rethrowLater(e);
				}
			}).catch(() => {}), 15e3);
		};
		put(chrome.idle, "onStateChanged", changed);
		put(chrome.idle, "setDetectionInterval", (seconds) => {
			every = Math.max(15, Number(seconds) || 60);
		});
	}
	function defineSystem(shim) {
		const call = (api) => nativeCall(shim, api);
		putNamespace(shim, "system", {
			cpu: { getInfo: call("system.cpu.getInfo") },
			memory: { getInfo: call("system.memory.getInfo") },
			storage: {
				getInfo: call("system.storage.getInfo"),
				ejectDevice: refuse(shim, "system.storage.ejectDevice"),
				getAvailableCapacity: refuse(shim, "system.storage.getAvailableCapacity"),
				onAttached: createEvent(),
				onDetached: createEvent()
			},
			display: {
				getInfo: call("system.display.getInfo"),
				onDisplayChanged: createEvent()
			}
		});
	}
	/** Members of namespaces WebKit has, answered by the browser. */
	function addBrowserMembers(shim) {
		const { chrome, runtime, put } = shim;
		if (chrome.i18n && !chrome.i18n.detectLanguage) put(chrome.i18n, "detectLanguage", nativeCall(shim, "i18n.detectLanguage"));
		if (runtime && !runtime.getContexts) put(runtime, "getContexts", nativeCall(shim, "runtime.getContexts"));
	}

//#endregion
//#region src/extension-shims/native-ports.ts
	function isPortProbe(message) {
		return !!message && typeof message === "object" && "__moteNative" in message;
	}
	/**
	* Whether a port is to an app: not one to the extension's own pages or tabs,
	* nor one WebKit opened towards this end (it has a sender), nor a search port.
	*/
	function goesToApp(port, toPages) {
		return !toPages.has(port) && port.sender == null && typeof port.name === "string" && !/^search(\.|$)/.test(port.name);
	}
	function holdEarlyNativeMessages({ worker, runtime, chrome, put, kept }) {
		if (!worker || !runtime || typeof runtime.connectNative !== "function") return;
		let found = null;
		try {
			found = runtime.connectNative(APPLICATION);
			found.disconnect();
		} catch {}
		const portProto = found && Object.getPrototypeOf(found);
		const eventProto = found && found.onMessage && Object.getPrototypeOf(found.onMessage);
		if (!portProto || !eventProto || typeof portProto.postMessage !== "function" || typeof eventProto.addListener !== "function") return;
		const toPages = /* @__PURE__ */ new WeakSet();
		for (const [space, name] of [[runtime, "connect"], [chrome.tabs, "connect"]]) {
			const connect = space && space[name];
			if (typeof connect !== "function") continue;
			put(space, name, (...args) => {
				const port = connect.apply(space, args);
				try {
					toPages.add(port);
				} catch {}
				return port;
			});
		}
		const post = portProto.postMessage;
		const add = eventProto.addListener;
		const remove = eventProto.removeListener;
		const has = eventProto.hasListener;
		const ports = /* @__PURE__ */ new WeakMap();
		const start = (port) => {
			const state = { held: [] };
			let tries = 0;
			const flush = () => {
				const list = state.held;
				state.held = null;
				for (const m of list || []) post.call(port, m);
			};
			const again = () => {
				if (!state.held) return;
				if (tries++ >= 20) {
					flush();
					return;
				}
				try {
					post.call(port, { __moteNative: "here?" });
				} catch {}
				setTimeout(again, 100 * Math.min(tries, 5));
			};
			add.call(port.onMessage, (m) => {
				if (m && m.__moteNative === "here" && state.held) flush();
				if (m && m.__moteNative === "alive") try {
					post.call(port, { __moteNative: "beat" });
				} catch {}
			});
			add.call(port.onDisconnect, () => {
				state.held = null;
			});
			again();
			return state;
		};
		put(portProto, "postMessage", function(message) {
			let state = ports.get(this);
			if (!state) {
				state = goesToApp(this, toPages) ? start(this) : { held: null };
				ports.set(this, state);
			}
			if (state.held) {
				state.held.push(message);
				return;
			}
			return post.call(this, message);
		});
		const wrapped = /* @__PURE__ */ new WeakMap();
		const wrapper = (event, f, make) => {
			let byEvent = wrapped.get(event);
			if (!byEvent) {
				byEvent = /* @__PURE__ */ new Map();
				if (make) wrapped.set(event, byEvent);
			}
			let w = byEvent.get(f);
			if (!w && make) {
				w = function(m, ...rest) {
					if (isPortProbe(m)) return void 0;
					return f.call(this, m, ...rest);
				};
				byEvent.set(f, w);
			}
			return w;
		};
		put(eventProto, "addListener", function(f) {
			if (kept.has(this) || typeof f !== "function") return add.call(this, f);
			return add.call(this, wrapper(this, f, true));
		});
		put(eventProto, "removeListener", function(f) {
			const w = !kept.has(this) && typeof f === "function" && wrapper(this, f, false);
			if (!w) return remove.call(this, f);
			wrapped.get(this).delete(f);
			return remove.call(this, w);
		});
		put(eventProto, "hasListener", function(f) {
			const w = !kept.has(this) && typeof f === "function" && wrapper(this, f, false);
			return has.call(this, w || f);
		});
	}

//#endregion
//#region src/extension-shims/permissions.ts
/** Permissions WebKit knows. */
	const WEBKIT_PERMISSIONS = /* @__PURE__ */ new Set([
		"activeTab",
		"alarms",
		"clipboardWrite",
		"contextMenus",
		"cookies",
		"declarativeNetRequest",
		"declarativeNetRequestFeedback",
		"declarativeNetRequestWithHostAccess",
		"menus",
		"nativeMessaging",
		"scripting",
		"storage",
		"tabs",
		"unlimitedStorage",
		"webNavigation",
		"webRequest"
	]);
	/** Permissions Mote grants itself, for the APIs the shim adds. */
	const MOTE_PERMISSIONS = /* @__PURE__ */ new Set([
		"bookmarks",
		"history",
		"downloads",
		"downloads.open",
		"downloads.shelf",
		"downloads.ui",
		"tabGroups",
		"sidePanel",
		"offscreen",
		"notifications",
		"tts",
		"fontSettings",
		"management",
		"identity",
		"identity.email",
		"idle",
		"power",
		"privacy",
		"browsingData",
		"sessions",
		"topSites",
		"search",
		"system.cpu",
		"system.memory",
		"system.storage",
		"system.display",
		"readingList",
		"contentSettings",
		"proxy",
		"favicon",
		"clipboardRead",
		"geolocation",
		"userScripts"
	]);
	/** Permissions by who answers for them: WebKit, Mote, or no one. */
	function splitPermissions(list = []) {
		return {
			theirs: list.filter((p) => WEBKIT_PERMISSIONS.has(p)),
			mine: list.filter((p) => MOTE_PERMISSIONS.has(p)),
			unknown: list.filter((p) => !WEBKIT_PERMISSIONS.has(p) && !MOTE_PERMISSIONS.has(p))
		};
	}
	function mendPermissions(shim) {
		const { chrome, runtime, put, native } = shim;
		if (!chrome.permissions) return;
		const manifest = (() => {
			try {
				return runtime.getManifest() || {};
			} catch {
				return {};
			}
		})();
		const declared = new Set(manifest.permissions || []);
		const p = chrome.permissions;
		const contains = p.contains.bind(p);
		const request = p.request.bind(p);
		const getAll = p.getAll.bind(p);
		const remove = p.remove.bind(p);
		const granted = () => native("permissions.granted", []).then((list) => /* @__PURE__ */ new Set([...declared, ...list || []]));
		const withCb = (f) => (arg, callback) => {
			const pr = f(arg || {});
			if (typeof callback !== "function") return pr;
			pr.then((v) => callback(v), (e) => shim.withLastError(e, callback));
		};
		put(p, "contains", withCb(async ({ permissions = [], origins = [] }) => {
			const { theirs, mine, unknown } = splitPermissions(permissions);
			if (unknown.length) return false;
			if (mine.length) {
				const have = await granted();
				if (!mine.every((m) => have.has(m))) return false;
			}
			return theirs.length || origins.length ? contains({
				permissions: theirs,
				origins
			}) : true;
		}));
		put(p, "request", withCb(async ({ permissions = [], origins = [] }) => {
			const { theirs, mine, unknown } = splitPermissions(permissions);
			if (unknown.length) return false;
			if (mine.length) {
				const have = await granted();
				const missing = mine.filter((m) => !have.has(m));
				if (missing.length && !await native("permissions.request", [missing])) return false;
			}
			return theirs.length || origins.length ? request({
				permissions: theirs,
				origins
			}) : true;
		}));
		put(p, "getAll", (callback) => {
			const pr = (async () => {
				const all = await getAll();
				const have = await granted();
				return {
					...all,
					permissions: [.../* @__PURE__ */ new Set([...all.permissions || [], ...[...have].filter((m) => MOTE_PERMISSIONS.has(m))])]
				};
			})();
			if (typeof callback !== "function") return pr;
			pr.then((v) => callback(v), (e) => shim.withLastError(e, callback));
		});
		put(p, "remove", withCb(async ({ permissions = [], origins = [] }) => {
			const { theirs, mine } = splitPermissions(permissions);
			if (mine.length) await native("permissions.remove", [mine]);
			return theirs.length || origins.length ? remove({
				permissions: theirs,
				origins
			}) : true;
		}));
	}

//#endregion
//#region src/extension-shims/popup.ts
/** Whether `path` is the page the manifest names as the action's popup. */
	function isManifestPopup(manifest, origin, path) {
		const action = manifest.action || manifest.browser_action || {};
		return !!action.default_popup && new URL(action.default_popup, origin + "/").pathname === path;
	}
	/** Whether a tab WebKit describes is the popup: it has no place in the row. */
	function isPopupTab(tab) {
		return !!tab && !(tab.index >= 0 && tab.index < 1e6);
	}
	function mendPopup(shim) {
		const { root, chrome, runtime, put, embedded } = shim;
		if (typeof document === "undefined") return;
		let popup = (() => {
			try {
				return isManifestPopup(runtime.getManifest(), location.origin, location.pathname);
			} catch {
				return false;
			}
		})();
		if (!embedded && chrome.tabs && typeof chrome.tabs.getCurrent === "function") {
			const getCurrent = chrome.tabs.getCurrent.bind(chrome.tabs);
			const current = () => Promise.resolve(getCurrent()).then((t) => {
				if (isPopupTab(t)) {
					popup = true;
					return;
				}
				if (t) popup = false;
				return t;
			});
			current().catch(() => {});
			put(chrome.tabs, "getCurrent", (callback) => {
				const p = current();
				if (typeof callback !== "function") return p;
				p.then((t) => callback(t), (e) => shim.withLastError(e, callback));
			});
		}
		if (chrome.extension && typeof chrome.extension.getViews === "function") {
			const extension = chrome.extension;
			const getViews = extension.getViews.bind(extension);
			const views = (properties = {}) => {
				let list = [...getViews(properties) || []];
				if (popup && properties.type === "tab") list = list.filter((v) => v !== root);
				if (popup && (!properties.type || properties.type === "popup") && !list.includes(root)) list.push(root);
				return list;
			};
			put(extension, "getViews", views);
			if (popup && extension.getViews !== views) {
				const bound = /* @__PURE__ */ new Map();
				const ownExtension = Object.create(extension);
				for (const key of Object.getOwnPropertyNames(extension)) {
					if (key === "getViews") continue;
					Object.defineProperty(ownExtension, key, {
						configurable: true,
						enumerable: true,
						get: () => {
							const v = extension[key];
							if (typeof v !== "function") return v;
							if (!bound.has(key)) bound.set(key, v.bind(extension));
							return bound.get(key);
						}
					});
				}
				Object.defineProperty(ownExtension, "getViews", {
					value: views,
					configurable: true,
					writable: true,
					enumerable: true
				});
				const ownChrome = Object.create(chrome);
				Object.defineProperty(ownChrome, "extension", {
					value: ownExtension,
					configurable: true,
					writable: true,
					enumerable: true
				});
				for (const key of ["chrome", "browser"]) try {
					if (root[key] === chrome) root[key] = ownChrome;
				} catch {}
			}
		}
	}

//#endregion
//#region src/extension-shims/port-numbering.ts
/**
	* Takes in a message, as numbered or not: what the listeners are to hear,
	* or `skip` for a number already heard. `heard` holds each end's last number.
	*/
	function unnumber(message, heard) {
		const tag = message && typeof message === "object" ? message.__motePort : null;
		if (!Array.isArray(tag)) return { message };
		if (tag[1] <= (heard.get(tag[0]) || 0)) return "skip";
		heard.set(tag[0], tag[1]);
		return { message: message.message };
	}
	/**
	* Set on the port itself, not with `put`, which holds what it touches
	* for good: a port is the extension's to let go.
	*/
	function set(target, key, value) {
		try {
			Object.defineProperty(target, key, {
				value,
				configurable: true,
				writable: true
			});
		} catch {}
	}
	function numberOwnPorts({ runtime, put }) {
		if (!runtime || typeof runtime.connect !== "function" || !runtime.onConnect) return;
		const own = runtime.getURL("");
		const numbered = /* @__PURE__ */ new WeakSet();
		const number = (port) => {
			const event = port && port.onMessage;
			const post = port && port.postMessage;
			if (!event || typeof event.addListener !== "function" || typeof post !== "function" || numbered.has(port)) return port;
			numbered.add(port);
			const me = randomId();
			let sent = 0;
			const heard = /* @__PURE__ */ new Map();
			const listeners = /* @__PURE__ */ new Set();
			event.addListener((message, ...rest) => {
				const taken = unnumber(message, heard);
				if (taken === "skip") return;
				for (const f of [...listeners]) try {
					f(taken.message, ...rest);
				} catch (e) {
					rethrowLater(e);
				}
			});
			set(port, "onMessage", event);
			set(port, "postMessage", (message) => post.call(port, {
				__motePort: [me, ++sent],
				message
			}));
			set(event, "addListener", (f) => {
				listeners.add(f);
			});
			set(event, "removeListener", (f) => {
				listeners.delete(f);
			});
			set(event, "hasListener", (f) => listeners.has(f));
			set(event, "hasListeners", () => listeners.size > 0);
			return port;
		};
		const connect = runtime.connect;
		put(runtime, "connect", (...args) => {
			const port = connect.apply(runtime, args);
			return typeof args[0] === "string" && args[0] !== runtime.id ? port : number(port);
		});
		const onConnect = runtime.onConnect;
		const add = onConnect.addListener;
		const remove = onConnect.removeListener;
		const has = onConnect.hasListener;
		const wrapped = /* @__PURE__ */ new WeakMap();
		const fromOwn = (port) => !!port && !!port.sender && (String(port.sender.url) + "/").startsWith(own);
		put(onConnect, "addListener", (listener, ...rest) => {
			if (typeof listener !== "function") return add.call(onConnect, listener, ...rest);
			let w = wrapped.get(listener);
			if (!w) {
				w = (port) => listener(fromOwn(port) ? number(port) : port);
				wrapped.set(listener, w);
			}
			return add.call(onConnect, w, ...rest);
		});
		put(onConnect, "removeListener", (listener) => remove.call(onConnect, wrapped.get(listener) || listener));
		put(onConnect, "hasListener", (listener) => has.call(onConnect, wrapped.get(listener) || listener));
	}

//#endregion
//#region src/extension-shims/replies.ts
	const PORT_CLOSED = "The message port closed before a response was received.";
	/** Settles a callback with the reply, or with lastError set to `gone` when there was none. */
	function replied(shim, promise, callback, gone) {
		if (typeof callback !== "function") return promise;
		promise.then((r) => r === void 0 ? shim.withLastError(new Error(gone), callback) : callback(r), (e) => shim.withLastError(e, callback));
	}
	/** The message `runtime.sendMessage(...args)` sends: the first argument, or the second after an extension id. */
	function sentMessage(args) {
		return typeof args[0] === "string" && args.length > 1 && typeof args[1] !== "function" ? args[1] : args[0];
	}
	function pause(ms) {
		return new Promise((w) => setTimeout(w, ms));
	}
	function nothing() {}
	function mendReplies(shim, verdicts) {
		const { chrome, runtime, put, inContent, background, native, config } = shim;
		let checkWorker = nothing;
		let heard = 0;
		if (runtime && typeof runtime.sendMessage === "function") {
			const page = typeof document !== "undefined";
			const original = Object.getPrototypeOf(runtime).sendMessage;
			const send = (...args) => original.apply(chrome.runtime, args);
			const hasWorker = (() => {
				try {
					const b = runtime.getManifest().background || {};
					return !!(b.service_worker || b.scripts || b.page);
				} catch {
					return false;
				}
			})();
			let asking = false;
			const check = () => {
				if (!hasWorker || asking || Date.now() - heard < 5e3) return;
				asking = true;
				const ping = Object.getPrototypeOf(runtime).sendMessage;
				const ask = () => Promise.race([ping.call(runtime, { __motePing: true }), new Promise((r) => setTimeout(() => r("late"), 15e3))]).catch(() => void 0);
				const tries = [
					() => ask(),
					() => pause(1e3).then(ask),
					() => pause(1e3).then(ask),
					() => native("background.wake", []).catch(() => {}).then(() => pause(1e3)).then(ask)
				];
				const attempt = (i, last) => i >= tries.length || last === "pong" ? Promise.resolve(last) : tries[i]().then((r) => attempt(i + 1, r));
				const started = Date.now();
				attempt(0).then((r) => {
					if (r === "pong" || heard >= started) heard = Math.max(heard, Date.now());
					else {
						if (config.verbose) native("debug.error", ["worker check: " + String(r) + " from " + location.pathname]).catch(() => {});
						native("background.revive", []).catch(() => {});
					}
				}).finally(() => {
					asking = false;
				});
			};
			checkWorker = page ? check : nothing;
			put(runtime, "sendMessage", (...args) => {
				const callback = typeof args[args.length - 1] === "function" ? args.pop() : null;
				if (!inContent) verdicts.tell(sentMessage(args), "passes");
				checkWorker();
				return replied(shim, send(...args).then((r) => {
					if (r !== void 0) heard = Date.now();
					return r;
				}), callback, PORT_CLOSED);
			});
		}
		const alsoFramed = (answer, tabId, message, options) => {
			const nav = chrome.webNavigation;
			if (!nav || typeof nav.getAllFrames !== "function" || typeof tabId !== "number") return answer;
			const own = runtime.getURL("");
			const wanted = options && typeof options.frameId === "number" ? options.frameId : null;
			const framed = Promise.resolve(nav.getAllFrames({ tabId })).then((frames) => {
				const urls = (frames || []).filter((f) => f.url && f.url.startsWith(own) && f.frameId !== 0 && (wanted === null || f.frameId === wanted)).map((f) => f.url);
				if (!urls.length) return void 0;
				const handed = { __moteToFrame: {
					tabId,
					urls,
					message
				} };
				return Object.getPrototypeOf(runtime).sendMessage.call(runtime, handed);
			}, () => void 0);
			return new Promise((resolve, reject) => {
				let left = 2;
				let failure = null;
				const none = () => {
					if (--left === 0) {
						if (failure) reject(failure);
						else resolve(void 0);
					}
				};
				answer.then((v) => v !== void 0 ? resolve(v) : none(), (e) => {
					failure = e;
					none();
				});
				framed.then((v) => v !== void 0 ? resolve(v) : none(), () => none());
			});
		};
		if (chrome.tabs && typeof chrome.tabs.sendMessage === "function") {
			const send = chrome.tabs.sendMessage.bind(chrome.tabs);
			put(chrome.tabs, "sendMessage", (tabId, message, options, callback) => {
				if (typeof options === "function") {
					callback = options;
					options = void 0;
				}
				const p = options === void 0 ? send(tabId, message) : send(tabId, message, options);
				return replied(shim, background ? alsoFramed(p, tabId, message, options) : p, callback, NO_RECEIVER);
			});
		}
		if (typeof document !== "undefined" && runtime && typeof runtime.connect === "function") {
			const connect = runtime.connect.bind(runtime);
			put(runtime, "connect", (...args) => {
				checkWorker();
				const port = connect(...args);
				try {
					port.onMessage.addListener(() => {
						heard = Date.now();
					});
				} catch {}
				return port;
			});
		}
	}

//#endregion
//#region src/extension-shims/settings.ts
	function setting(shim, name) {
		return {
			get: nativeCall(shim, "setting.get:" + name),
			set: nativeCall(shim, "setting.set:" + name),
			clear: nativeCall(shim, "setting.clear:" + name),
			onChange: createEvent()
		};
	}
	function settings(shim, prefix, names) {
		return Object.fromEntries(names.map((n) => [n, setting(shim, prefix + "." + n)]));
	}
	const PRIVACY_SETTINGS = {
		services: [
			"alternateErrorPagesEnabled",
			"autofillAddressEnabled",
			"autofillCreditCardEnabled",
			"autofillEnabled",
			"passwordSavingEnabled",
			"safeBrowsingEnabled",
			"safeBrowsingExtendedReportingEnabled",
			"searchSuggestEnabled",
			"spellingServiceEnabled",
			"translationServiceEnabled"
		],
		network: ["networkPredictionEnabled", "webRTCIPHandlingPolicy"],
		websites: [
			"adMeasurementEnabled",
			"doNotTrackEnabled",
			"fledgeEnabled",
			"hyperlinkAuditingEnabled",
			"protectedContentEnabled",
			"referrersEnabled",
			"relatedWebsiteSetsEnabled",
			"thirdPartyCookiesAllowed",
			"topicsEnabled"
		]
	};
	function definePrivacy(shim) {
		putNamespace(shim, "privacy", {
			services: settings(shim, "privacy.services", PRIVACY_SETTINGS.services),
			network: settings(shim, "privacy.network", PRIVACY_SETTINGS.network),
			websites: settings(shim, "privacy.websites", PRIVACY_SETTINGS.websites),
			IPHandlingPolicy: {
				DEFAULT: "default",
				DEFAULT_PUBLIC_AND_PRIVATE_INTERFACES: "default_public_and_private_interfaces",
				DEFAULT_PUBLIC_INTERFACE_ONLY: "default_public_interface_only",
				DISABLE_NON_PROXIED_UDP: "disable_non_proxied_udp"
			}
		});
	}
	const CONTENT_SETTINGS = [
		"automaticDownloads",
		"autoVerify",
		"camera",
		"clipboard",
		"cookies",
		"images",
		"javascript",
		"location",
		"microphone",
		"notifications",
		"plugins",
		"popups",
		"sound"
	];
	function contentSetting() {
		return {
			get: (_details, cb) => {
				const v = { setting: "allow" };
				if (cb) cb(v);
				else return Promise.resolve(v);
			},
			set: (_details, cb) => {
				if (cb) cb();
				else return Promise.resolve();
			},
			clear: (_details, cb) => {
				if (cb) cb();
				else return Promise.resolve();
			},
			getResourceIdentifiers: (cb) => {
				if (cb) cb([]);
				else return Promise.resolve([]);
			}
		};
	}
	function defineContentSettings(shim) {
		putNamespace(shim, "contentSettings", Object.fromEntries(CONTENT_SETTINGS.map((n) => [n, contentSetting()])));
	}
	function defineProxy(shim) {
		putNamespace(shim, "proxy", {
			settings: setting(shim, "proxy.settings"),
			onProxyError: createEvent()
		});
	}

//#endregion
//#region src/extension-shims/storage.ts
	function fillStorage(shim) {
		fill(shim, "storage", {
			managed: {
				get: resolved({}),
				getBytesInUse: resolved(0),
				onChanged: createEvent()
			},
			AccessLevel: {
				TRUSTED_CONTEXTS: "TRUSTED_CONTEXTS",
				TRUSTED_AND_UNTRUSTED_CONTEXTS: "TRUSTED_AND_UNTRUSTED_CONTEXTS"
			}
		});
	}
	/** Items as WebKit stores them: a plain object copy of one with another prototype. */
	function plainItems(items) {
		return items && typeof items === "object" && Object.getPrototypeOf(items) !== Object.prototype ? Object.assign({}, items) : items;
	}
	/**
	* Items built with Object.create(null) — Chrome stores them, WebKit
	* throws that an object is expected.
	*/
	function storePlainItems({ chrome, put }) {
		for (const area of [
			"local",
			"sync",
			"session"
		]) {
			const store = chrome.storage && chrome.storage[area];
			if (!store || typeof store.set !== "function") continue;
			const set = store.set.bind(store);
			put(store, "set", (items, ...rest) => set(plainItems(items), ...rest));
		}
	}

//#endregion
//#region src/extension-shims/tabs.ts
	function fillTabs(shim) {
		const { chrome } = shim;
		fill(shim, "tabs", {
			TabStatus: enumOf("unloaded", "loading", "complete"),
			MutedInfoReason: enumOf("user", "capture", "extension"),
			WindowType: enumOf("normal", "popup", "panel", "app", "devtools"),
			ZoomSettingsMode: enumOf("automatic", "manual", "disabled"),
			ZoomSettingsScope: {
				PER_ORIGIN: "per-origin",
				PER_TAB: "per-tab"
			},
			MAX_CAPTURE_VISIBLE_TAB_CALLS_PER_SECOND: 2,
			TAB_INDEX_NONE: -1,
			getZoomSettings: resolved({
				mode: "automatic",
				scope: "per-origin",
				defaultZoomFactor: 1
			}),
			setZoomSettings: resolved(void 0),
			onZoomChange: createEvent(),
			onSelectionChanged: createEvent(),
			onActiveChanged: createEvent(),
			onHighlightChanged: createEvent(),
			group: refuse(shim, "tabs.group"),
			ungroup: resolved(void 0),
			getSelected: (windowId, callback) => {
				const f = typeof windowId === "function" ? windowId : callback;
				chrome.tabs.query({
					active: true,
					currentWindow: true
				}).then((t) => f && f(t[0]));
			},
			getAllInWindow: (windowId, callback) => {
				const f = typeof windowId === "function" ? windowId : callback;
				chrome.tabs.query({ currentWindow: true }).then((t) => f && f(t));
			}
		});
	}
	/** A moment for the browser to settle a tab it moved. */
	function settle() {
		return new Promise((r) => setTimeout(r, 60));
	}
	/**
	* Moving, sleeping and bringing forward tabs, by where they are in
	* the row — the one thing both sides agree on.
	*/
	function fillTabsByIndex(shim) {
		const { chrome, native } = shim;
		if (!chrome.tabs) return;
		const byIndex = (api) => async (ids, extra) => {
			const out = [];
			for (const id of Array.isArray(ids) ? ids : [ids]) {
				const tab = await chrome.tabs.get(id);
				await native(api, [tab.index, extra]);
				await settle();
				out.push(await chrome.tabs.get(id).catch(() => tab));
			}
			return Array.isArray(ids) ? out : out[0];
		};
		fill(shim, "tabs", {
			move: withCallback(shim, async (ids, props = {}) => {
				const list = Array.isArray(ids) ? ids : [ids];
				const out = [];
				let at = props.index ?? -1;
				for (const id of list) {
					out.push(await byIndex("tabs.move")(id, at));
					if (at !== -1) at++;
				}
				return Array.isArray(ids) ? out : out[0];
			}),
			discard: withCallback(shim, (id) => id === void 0 ? chrome.tabs.query({
				active: false,
				currentWindow: true
			}).then((t) => t[0] && byIndex("tabs.discard")(t[0].id)) : byIndex("tabs.discard")(id)),
			highlight: withCallback(shim, async (info = {}) => {
				const first = Array.isArray(info.tabs) ? info.tabs[0] : info.tabs;
				await native("tabs.activate", [first]);
				await settle();
				return chrome.windows ? chrome.windows.getCurrent({ populate: true }) : void 0;
			})
		});
	}
	/**
	* Every tab in what a method of `from` answers: a tab or tabs from
	* tabs, a window or windows — each with its tabs, when populated —
	* from windows. A window is never taken for a tab.
	*/
	function tabsIn(value, from) {
		if (Array.isArray(value)) return value.flatMap((v) => tabsIn(v, from));
		if (from === "tabs") return isTab(value) ? [value] : [];
		const tabs = value && typeof value === "object" ? value.tabs : void 0;
		return Array.isArray(tabs) ? tabs.filter(isTab) : [];
	}
	/**
	* A tab, by its shape: an id, and where it is — its index and its
	* window, which a window has neither of.
	*/
	function isTab(t) {
		if (!t || typeof t !== "object") return false;
		const { id, index, windowId } = t;
		return typeof id === "number" && (typeof index === "number" || typeof windowId === "number");
	}
	/**
	* Tabs as Chrome describes them. Every tab has a groupId (-1 when in
	* no group — Mote has none), which code tests before anything else;
	* and with the "tabs" permission an extension sees every tab's address
	* and title, where WebKit shows them only for sites it has host
	* access to.
	*/
	function describeTabs(shim) {
		const { chrome, runtime, put, native } = shim;
		if (!chrome.tabs) return;
		const seesTabs = (() => {
			try {
				return (runtime.getManifest().permissions || []).includes("tabs");
			} catch {
				return false;
			}
		})();
		const mend = (list) => {
			const tabs = list.filter(isTab);
			for (const t of tabs) if (t.groupId === void 0) try {
				t.groupId = -1;
			} catch {}
			const blind = seesTabs ? tabs.filter((t) => !t.url && t.index >= 0) : [];
			if (!blind.length) return null;
			return native("tabs.describe", [blind.map((t) => t.index)]).then((info) => {
				blind.forEach((t, i) => {
					const d = info && info[i];
					if (!d) return;
					try {
						if (d.url) t.url = d.url;
						if (d.title && !t.title) t.title = d.title;
					} catch {}
				});
			}, () => {});
		};
		const mendResult = (from, name) => {
			const target = chrome[from];
			if (!target || typeof target[name] !== "function") return;
			const original = target[name].bind(target);
			put(target, name, (...args) => {
				const callback = takeCallback(args);
				const p = Promise.resolve(original(...args)).then(async (r) => {
					await mend(tabsIn(r, from));
					return r;
				});
				if (!callback) return p;
				p.then((r) => callback(r), (e) => shim.withLastError(e, callback));
			});
		};
		for (const name of [
			"query",
			"get",
			"getCurrent",
			"create",
			"update",
			"duplicate",
			"move",
			"reload"
		]) mendResult("tabs", name);
		for (const name of [
			"get",
			"getAll",
			"getCurrent",
			"getLastFocused",
			"create"
		]) mendResult("windows", name);
		const mendArgs = (target, positions) => {
			if (!target || typeof target.addListener !== "function") return;
			const add = target.addListener.bind(target);
			const remove = target.removeListener.bind(target);
			const wrapped = /* @__PURE__ */ new Map();
			put(target, "addListener", (listener, ...rest) => {
				const w = function(...args) {
					const pending = mend(positions.map((i) => args[i]));
					if (!pending) return listener.apply(this, args);
					pending.then(() => listener.apply(this, args));
				};
				wrapped.set(listener, w);
				return add(w, ...rest);
			});
			put(target, "removeListener", (listener) => {
				const w = wrapped.get(listener);
				wrapped.delete(listener);
				return remove(w || listener);
			});
			put(target, "hasListener", (listener) => wrapped.has(listener));
		};
		mendArgs(chrome.tabs.onCreated, [0]);
		mendArgs(chrome.tabs.onUpdated, [2]);
		mendArgs(chrome.action && chrome.action.onClicked, [0]);
		mendArgs(chrome.contextMenus && chrome.contextMenus.onClicked, [1]);
		mendArgs(chrome.menus && chrome.menus.onClicked, [1]);
		mendArgs(chrome.commands && chrome.commands.onCommand, [1]);
	}

//#endregion
//#region src/extension-shims/unavailable.ts
	function events(...names) {
		return Object.fromEntries(names.map((n) => [n, createEvent()]));
	}
	/**
	* Rules that show a button on matching pages: every button is always
	* shown in Mote, so there is nothing for them to do.
	*/
	function rules() {
		return {
			addRules: (r, cb) => {
				if (cb) cb(r || []);
			},
			removeRules: (_ids, cb) => {
				if (cb) cb();
			},
			getRules: (ids, cb) => {
				const f = typeof ids === "function" ? ids : cb;
				if (f) f([]);
			}
		};
	}
	function defineUnavailable(shim) {
		putNamespace(shim, "omnibox", {
			setDefaultSuggestion: () => {},
			...events("onInputStarted", "onInputChanged", "onInputEntered", "onInputCancelled", "onDeleteSuggestion")
		});
		putNamespace(shim, "tabCapture", {
			capture: refuse(shim, "tabCapture.capture"),
			getMediaStreamId: refuse(shim, "tabCapture.getMediaStreamId"),
			getCapturedTabs: (cb) => {
				if (cb) cb([]);
				else return Promise.resolve([]);
			},
			onStatusChanged: createEvent()
		});
		putNamespace(shim, "desktopCapture", {
			chooseDesktopMedia: (_sources, tab, cb) => {
				const f = typeof tab === "function" ? tab : cb;
				if (f) setTimeout(() => f("", {}));
				return 1;
			},
			cancelChooseDesktopMedia: () => {},
			DesktopCaptureSourceType: {
				SCREEN: "screen",
				WINDOW: "window",
				TAB: "tab",
				AUDIO: "audio"
			}
		});
		putNamespace(shim, "pageCapture", { saveAsMHTML: refuse(shim, "pageCapture.saveAsMHTML") });
		putNamespace(shim, "debugger", {
			attach: refuse(shim, "debugger.attach"),
			detach: refuse(shim, "debugger.detach"),
			sendCommand: refuse(shim, "debugger.sendCommand"),
			getTargets: (cb) => {
				if (cb) cb([]);
				else return Promise.resolve([]);
			},
			...events("onEvent", "onDetach")
		});
		putNamespace(shim, "gcm", {
			register: refuse(shim, "gcm.register"),
			unregister: refuse(shim, "gcm.unregister"),
			send: refuse(shim, "gcm.send"),
			...events("onMessage", "onMessagesDeleted", "onSendError")
		});
		putNamespace(shim, "instanceID", {
			getID: refuse(shim, "instanceID.getID"),
			getToken: refuse(shim, "instanceID.getToken"),
			deleteID: refuse(shim, "instanceID.deleteID"),
			deleteToken: refuse(shim, "instanceID.deleteToken"),
			getCreationTime: refuse(shim, "instanceID.getCreationTime"),
			onTokenRefresh: createEvent()
		});
		putNamespace(shim, "declarativeContent", {
			onPageChanged: rules(),
			PageStateMatcher: function(o) {
				Object.assign(this, o);
			},
			ShowAction: function() {},
			ShowPageAction: function() {},
			SetIcon: function(o) {
				Object.assign(this, o);
			},
			RequestContentScript: function(o) {
				Object.assign(this, o);
			}
		});
	}

//#endregion
//#region src/extension-shims/user-agent.ts
/** Safari's user agent made Chrome's `version`. */
	function chromeUserAgent(userAgent, version) {
		return userAgent.replace(/ Version\/[\d.]+.*$/, "").replace(/ Safari\/[\d.]+$/, "") + " Chrome/" + version + " Safari/537.36";
	}
	/** Chrome's `navigator.userAgentData` for a Chrome user agent. */
	function userAgentData(chromeUA, version) {
		const major = version.split(".")[0];
		const brands = [
			{
				brand: "Chromium",
				version: major
			},
			{
				brand: "Google Chrome",
				version: major
			},
			{
				brand: "Not.A/Brand",
				version: "99"
			}
		];
		const low = {
			brands,
			mobile: false,
			platform: "macOS"
		};
		const high = {
			architecture: "arm",
			bitness: "64",
			model: "",
			platformVersion: (chromeUA.match(/Mac OS X (\d+)[_.](\d+)(?:[_.](\d+))?/) || []).slice(1).map((n) => n || "0").join(".") || "10.15.7",
			wow64: false,
			fullVersionList: brands.map((b) => ({
				brand: b.brand,
				version: b.version === major ? version : b.version + ".0.0.0"
			})),
			uaFullVersion: version
		};
		const pick = (hints) => Object.assign({}, low, ...(Array.isArray(hints) ? hints : []).filter((h) => h in high).map((h) => ({ [h]: high[h] })));
		return Object.assign({}, low, {
			getHighEntropyValues: (hints) => Promise.resolve(pick(hints)),
			toJSON: () => low
		});
	}
	function presentAsChrome({ root, inContent, worker, config }) {
		if (inContent || typeof navigator === "undefined" || / Chrome\//.test(navigator.userAgent)) return;
		const chromeUA = chromeUserAgent(navigator.userAgent, config.chromeVersion);
		const proto = typeof root.WorkerNavigator !== "undefined" && worker ? root.WorkerNavigator.prototype : typeof Navigator !== "undefined" ? Navigator.prototype : null;
		try {
			if (proto) {
				Object.defineProperty(proto, "userAgent", {
					get: () => chromeUA,
					configurable: true
				});
				Object.defineProperty(proto, "appVersion", {
					get: () => chromeUA.replace(/^Mozilla\//, ""),
					configurable: true
				});
				Object.defineProperty(proto, "vendor", {
					get: () => "Google Inc.",
					configurable: true
				});
				if (!("userAgentData" in navigator)) {
					const data = userAgentData(chromeUA, config.chromeVersion);
					Object.defineProperty(proto, "userAgentData", {
						get: () => data,
						configurable: true
					});
				}
			}
		} catch {}
	}

//#endregion
//#region src/lib/user-scripts.ts
/** The prefix of a port's name opened from the USER_SCRIPT world. */
	const USER_SCRIPT_PORT_PREFIX = "mote-us:";

//#endregion
//#region src/extension-shims/user-scripts.ts
/** Mote's passkey patch (Passkeys.swift), written into every extension by `ExtensionShims.prepare`. */
	const PASSKEYS_FILE = "mote-passkeys.js";
	/** The ids under which user scripts are registered as content scripts. */
	const USER_SCRIPT_ID_PREFIX = "mote-us-";
	/**
	* What an extension registers for a page's own world has Mote's
	* passkey patch before it, as its manifest's do (see prepare): a
	* password manager keeps a reference to navigator.credentials as it
	* finds it, and falls back to that. An update that names no world gets
	* it too; in any other world the patch does nothing.
	*/
	function withPasskeys(scripts, updating) {
		if (!Array.isArray(scripts)) return scripts;
		return scripts.map((s) => {
			if (!s || !Array.isArray(s.js) || s.js.includes("mote-passkeys.js")) return s;
			const world = String(s.world || "").toUpperCase();
			return world === "MAIN" || updating && !world ? {
				...s,
				js: [PASSKEYS_FILE, ...s.js]
			} : s;
		});
	}
	function patchPasskeysFirst({ chrome, put }) {
		const scripting = chrome.scripting;
		if (!scripting) return;
		for (const name of ["registerContentScripts", "updateContentScripts"]) {
			const original = scripting[name];
			if (typeof original === "function") put(scripting, name, function(scripts, ...rest) {
				return original.call(scripting, withPasskeys(scripts, name === "updateContentScripts"), ...rest);
			});
		}
	}
	/** Scripts named by the filter, or all of them. */
	function pickScripts(filter, list) {
		return filter && Array.isArray(filter.ids) ? list.filter((s) => filter.ids.includes(s.id)) : list;
	}
	function defineUserScripts(shim) {
		const { root, chrome, runtime, put, native, background } = shim;
		const scripting = chrome.scripting;
		const wantsUserScripts = (() => {
			try {
				return (runtime.getManifest().permissions || []).includes("userScripts");
			} catch {
				return false;
			}
		})();
		if (chrome.userScripts || !wantsUserScripts || !scripting || typeof scripting.registerContentScripts !== "function") return;
		const tag = USER_SCRIPT_ID_PREFIX;
		const content = async (script) => ({
			id: tag + script.id,
			matches: script.matches && script.matches.length ? script.matches : ["*://*/*"],
			excludeMatches: script.excludeMatches || [],
			js: [await native("userScripts.file", [script])],
			runAt: script.runAt || "document_idle",
			allFrames: !!script.allFrames,
			world: script.world === "MAIN" ? "MAIN" : "ISOLATED",
			persistAcrossSessions: false
		});
		const registered = async () => (await scripting.getRegisteredContentScripts()).filter((s) => s.id.startsWith(tag));
		const list = () => native("userScripts.list", []).then((l) => l || []);
		const save = (l) => native("userScripts.save", [l]);
		const sync = async () => {
			const want = await list();
			const have = new Set((await registered()).map((s) => s.id));
			const missing = want.filter((s) => !have.has(tag + s.id));
			if (!missing.length) return;
			const scripts = await Promise.all(missing.map(content));
			await scripting.registerContentScripts(scripts).catch(async (e) => {
				if (!/duplicate/i.test(String(e && e.message))) throw e;
				await scripting.unregisterContentScripts({ ids: scripts.map((s) => s.id) }).catch(() => {});
				await scripting.registerContentScripts(scripts);
			});
		};
		const callbacks = Object.fromEntries(Object.entries({
			register: async (scripts) => {
				const l = await list();
				for (const s of scripts) if (l.some((o) => o.id === s.id)) throw new Error("Duplicate script id '" + s.id + "'");
				await scripting.registerContentScripts(await Promise.all(scripts.map(content)));
				await save([...l, ...scripts]);
			},
			update: async (scripts) => {
				const l = await list();
				const merged = scripts.map((s) => {
					const old = l.find((o) => o.id === s.id);
					if (!old) throw new Error("Script with id '" + s.id + "' does not exist");
					return {
						...old,
						...s
					};
				});
				await scripting.unregisterContentScripts({ ids: merged.map((s) => tag + s.id) }).catch(() => {});
				await scripting.registerContentScripts(await Promise.all(merged.map(content)));
				await save(l.map((o) => merged.find((m) => m.id === o.id) || o));
			},
			unregister: async (filter) => {
				const l = await list();
				const gone = pickScripts(filter, l);
				const ids = (await registered()).map((s) => s.id).filter((id) => gone.some((g) => tag + g.id === id));
				if (ids.length) await scripting.unregisterContentScripts({ ids });
				await save(l.filter((o) => !gone.includes(o)));
			},
			getScripts: async (filter) => pickScripts(filter, await list()),
			configureWorld: (properties) => native("userScripts.world", [properties || {}]),
			getWorldConfigurations: () => native("userScripts.worlds", []),
			resetWorldConfiguration: (worldId) => native("userScripts.world", [{
				worldId,
				reset: true
			}]),
			execute: async (injection) => {
				const file = await native("userScripts.file", [{
					id: "execute-" + Date.now(),
					js: injection.js || [],
					world: injection.world
				}]);
				return scripting.executeScript({
					target: injection.target,
					files: [file],
					world: injection.world === "MAIN" ? "MAIN" : "ISOLATED",
					injectImmediately: !!injection.injectImmediately
				});
			}
		}).map(([k, f]) => [k, (...args) => {
			const callback = takeCallback(args);
			const p = f(...args);
			if (!callback) return p;
			p.then((v) => callback(v), (e) => shim.withLastError(e, callback));
		}]));
		putNamespace(shim, "userScripts", {
			...callbacks,
			ExecutionWorld: {
				MAIN: "MAIN",
				USER_SCRIPT: "USER_SCRIPT"
			}
		});
		if (background) sync().catch((e) => {
			try {
				native("debug.error", ["userScripts: " + e.message]).catch(() => {});
			} catch {}
		});
		const onMessage = runtime.onUserScriptMessage;
		const onConnect = runtime.onUserScriptConnect;
		root.__moteUserScriptMessage = (message, sender, respond) => {
			let keep = false;
			for (const f of [...onMessage.listeners]) {
				const r = f(message, sender, respond);
				if (r === true) keep = true;
				else if (r && typeof r.then === "function") {
					keep = true;
					r.then(respond);
				}
			}
			return keep;
		};
		if (runtime.onConnect && typeof runtime.onConnect.addListener === "function") {
			const marker = USER_SCRIPT_PORT_PREFIX;
			const add = runtime.onConnect.addListener.bind(runtime.onConnect);
			const remove = runtime.onConnect.removeListener.bind(runtime.onConnect);
			const wrapped = /* @__PURE__ */ new Map();
			try {
				add((port) => {
					if (!String(port.name).startsWith(marker)) return;
					const view = Object.create(port, { name: { value: port.name.slice(marker.length) } });
					for (const f of [...onConnect.listeners]) f(view);
				});
			} catch {}
			put(runtime.onConnect, "addListener", (listener) => {
				const w = (port) => {
					if (!String(port.name).startsWith(marker)) return listener(port);
				};
				wrapped.set(listener, w);
				return add(w);
			});
			put(runtime.onConnect, "removeListener", (listener) => {
				const w = wrapped.get(listener);
				if (w) {
					wrapped.delete(listener);
					remove(w);
				}
			});
		}
	}

//#endregion
//#region src/extension-shims/wasm.ts
/** A response for one of the extension's own files. */
	function isExtensionResponse(response) {
		const r = response;
		return !!r && typeof r.url === "string" && /^(chrome|webkit)-extension:/.test(r.url);
	}
	function compileWasmWhole(root) {
		if (!root.WebAssembly || typeof WebAssembly.instantiateStreaming !== "function") return;
		const instantiate = WebAssembly.instantiateStreaming.bind(WebAssembly);
		WebAssembly.instantiateStreaming = async (source, imports) => {
			const response = await source;
			return isExtensionResponse(response) ? WebAssembly.instantiate(await response.arrayBuffer(), imports) : instantiate(response, imports);
		};
		if (typeof WebAssembly.compileStreaming === "function") {
			const compile = WebAssembly.compileStreaming.bind(WebAssembly);
			WebAssembly.compileStreaming = async (source) => {
				const response = await source;
				return isExtensionResponse(response) ? WebAssembly.compile(await response.arrayBuffer()) : compile(response);
			};
		}
	}

//#endregion
//#region src/extension-shims/web-socket.ts
/** The native application whose ports carry sockets (ExtensionSocket.swift). */
	const SOCKET_APPLICATION = "mote.socket";
	/** Bytes as base64, in chunks small enough for `String.fromCharCode`. */
	function encodeBytes(bytes) {
		let s = "";
		for (let i = 0; i < bytes.length; i += 32768) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 32768));
		return btoa(s);
	}
	function decodeBytes(text) {
		const s = atob(text);
		const bytes = new Uint8Array(s.length);
		for (let i = 0; i < s.length; i++) bytes[i] = s.charCodeAt(i);
		return bytes.buffer;
	}
	/** A socket's address made absolute, with http(s) taken for ws(s); throws as WebSocket does for any other. */
	function socketURL(url, base) {
		let parsed;
		try {
			parsed = new URL(url, base);
		} catch {
			throw new DOMException("The URL '" + url + "' is invalid.", "SyntaxError");
		}
		if (parsed.protocol === "http:") parsed.protocol = "ws:";
		if (parsed.protocol === "https:") parsed.protocol = "wss:";
		if (!/^wss?:$/.test(parsed.protocol) || parsed.hash) throw new DOMException("The URL '" + url + "' is invalid.", "SyntaxError");
		return parsed;
	}
	const STATES = {
		CONNECTING: 0,
		OPEN: 1,
		CLOSING: 2,
		CLOSED: 3
	};
	function replaceWorkerWebSocket({ root, worker, runtime }) {
		if (!worker || typeof root.WebSocket !== "function" || !runtime || typeof runtime.connectNative !== "function") return;
		const connectNative = runtime.connectNative.bind(runtime);
		class WebSocket extends EventTarget {
			#port;
			#state = 0;
			#queue = Promise.resolve();
			#origin;
			#hello;
			constructor(url, protocols) {
				super();
				const parsed = socketURL(url, location.href);
				const list = protocols === void 0 ? [] : (Array.isArray(protocols) ? protocols : [protocols]).map(String);
				Object.defineProperty(this, "url", {
					value: parsed.href,
					enumerable: true
				});
				this.#origin = parsed.origin;
				this.protocol = "";
				this.extensions = "";
				this.binaryType = "blob";
				this.bufferedAmount = 0;
				this.onopen = null;
				this.onmessage = null;
				this.onerror = null;
				this.onclose = null;
				this.#hello = {
					open: this.url,
					protocols: list,
					userAgent: navigator.userAgent
				};
				this.#connect();
			}
			#connect() {
				const port = connectNative(SOCKET_APPLICATION);
				let ready = false;
				let tries = 0;
				this.#port = port;
				const again = () => {
					if (ready || this.#state === 3) return;
					if (tries++ >= 20) {
						this.#fire("error");
						this.#closed(1006, "", false);
						return;
					}
					try {
						port.postMessage(this.#hello);
					} catch {}
					setTimeout(again, 100 * Math.min(tries, 5));
				};
				port.onMessage.addListener((m) => {
					if (!ready) ready = true;
					if (m && m.ready === true) return;
					this.#take(m);
				});
				port.onDisconnect.addListener(() => {
					if (this.#state === 3) return;
					this.#fire("error");
					this.#closed(1006, "", false);
				});
				again();
			}
			get readyState() {
				return this.#state;
			}
			#fire(type, init) {
				let event;
				if (type === "message") event = new MessageEvent("message", init);
				else if (type === "close" && typeof CloseEvent === "function") event = new CloseEvent("close", init);
				else {
					event = new Event(type);
					if (init) for (const k in init) Object.defineProperty(event, k, { value: init[k] });
				}
				const handler = this["on" + type];
				if (typeof handler === "function") try {
					handler.call(this, event);
				} catch (e) {
					rethrowLater(e);
				}
				this.dispatchEvent(event);
			}
			#closed(code, reason, wasClean) {
				this.#state = 3;
				try {
					this.#port.disconnect();
				} catch {}
				this.#fire("close", {
					code,
					reason,
					wasClean
				});
			}
			#take(m) {
				if (!m || this.#state === 3) return;
				if ("opened" in m) {
					this.protocol = m.opened;
					this.#state = 1;
					this.#fire("open");
				} else if ("text" in m) this.#fire("message", {
					data: m.text,
					origin: this.#origin
				});
				else if ("binary" in m) {
					const buffer = decodeBytes(m.binary);
					this.#fire("message", {
						data: this.binaryType === "arraybuffer" ? buffer : new Blob([buffer]),
						origin: this.#origin
					});
				} else if ("failed" in m) this.#fire("error");
				else if ("closed" in m) this.#closed(m.closed, m.reason || "", !!m.clean);
			}
			send(data) {
				if (this.#state === 0) throw new DOMException("WebSocket is still in CONNECTING state.", "InvalidStateError");
				if (this.#state !== 1) return;
				const post = (message) => {
					try {
						this.#port.postMessage(message);
					} catch {}
				};
				if (typeof data === "string") {
					this.#queue = this.#queue.then(() => post({ send: data }));
					return;
				}
				const bytes = data instanceof ArrayBuffer ? Promise.resolve(new Uint8Array(data)) : ArrayBuffer.isView(data) ? Promise.resolve(new Uint8Array(data.buffer, data.byteOffset, data.byteLength)) : data instanceof Blob ? data.arrayBuffer().then((b) => new Uint8Array(b)) : Promise.resolve(null);
				this.#queue = this.#queue.then(() => bytes).then((b) => b ? post({ sendBinary: encodeBytes(b) }) : post({ send: String(data) }));
			}
			close(code, reason) {
				if (code !== void 0 && code !== 1e3 && !(code >= 3e3 && code <= 4999)) throw new DOMException("The close code must be either 1000, or between 3000 and 4999. " + code + " is neither.", "InvalidAccessError");
				if (this.#state >= 2) return;
				this.#state = 2;
				const message = {
					close: code === void 0 ? 1e3 : code,
					reason: reason === void 0 ? "" : String(reason)
				};
				this.#queue = this.#queue.then(() => {
					try {
						this.#port.postMessage(message);
					} catch {}
				});
			}
		}
		for (const [k, v] of Object.entries(STATES)) {
			Object.defineProperty(WebSocket, k, { value: v });
			Object.defineProperty(WebSocket.prototype, k, { value: v });
		}
		Object.defineProperty(root, "WebSocket", {
			value: WebSocket,
			configurable: true,
			writable: true
		});
	}

//#endregion
//#region src/extension-shims/worker-fixes.ts
/**
	* The static routing API of Chrome's service workers (install
	* event.addRoutes) — a speed-up, so nothing is lost without it.
	*/
	function addInstallRoutes({ root, worker }) {
		if (worker && typeof root.InstallEvent === "function" && !root.InstallEvent.prototype.addRoutes) root.InstallEvent.prototype.addRoutes = () => Promise.resolve();
	}
	function shippedScripts(scripts) {
		const shipped = /* @__PURE__ */ new Set();
		const empty = /* @__PURE__ */ new Set();
		for (const path of scripts) if (path.startsWith("-")) empty.add(path.slice(1));
		else shipped.add(path);
		return {
			shipped,
			empty
		};
	}
	function importVerdict(url, origin, files) {
		const path = decodeURIComponent(url.pathname);
		if (url.origin === origin && files.empty.has(path)) return "skip";
		if (url.origin === origin && !files.shipped.has(path)) return "missing";
		return "load";
	}
	/**
	* A script a worker imports that isn't there: Chrome throws at once.
	* WebKit goes looking for it first, and while it does, runs the
	* promises already waiting — code that notes "still starting" until
	* its first promise settles (Tampermonkey) then thinks startup is
	* over, and refuses its own listeners. The extension's files are
	* known, so a missing one is refused the way Chrome refuses it, and
	* an empty one — Tampermonkey's test.js — isn't fetched at all.
	*/
	function checkImportedScripts({ root, worker, config }) {
		if (!worker || typeof root.importScripts !== "function") return;
		const files = shippedScripts(config.scripts);
		const load = root.importScripts.bind(root);
		root.importScripts = (...urls) => {
			const wanted = [];
			for (const u of urls) {
				let url;
				try {
					url = new URL(u, location.href);
				} catch {
					wanted.push(u);
					continue;
				}
				const verdict = importVerdict(url, location.origin, files);
				if (verdict === "skip") continue;
				if (verdict === "missing") throw new DOMException("Failed to execute 'importScripts' on 'WorkerGlobalScope': The script at '" + url.href + "' failed to load.", "NetworkError");
				wanted.push(u);
			}
			if (wanted.length) return load(...wanted);
		};
	}

//#endregion
//#region src/extension-shims/install.ts
	function install(root, config) {
		const chrome = root.chrome || root.browser;
		if (!carriesExtensionAPIs(chrome) || root.__moteShim) return;
		polyfillIdleCallback(root);
		keepCredentials(root);
		markInstalled(root);
		fixChromeGlobals(root);
		const inContent = isContentScript();
		const embedded = isEmbedded(inContent);
		const runtime = chrome.runtime;
		const { kept, put } = createHolder(root);
		const spaces = holdNamespaces(chrome, kept);
		const worker = isServiceWorker(root);
		const shim = {
			root,
			config,
			chrome,
			runtime,
			inContent,
			embedded,
			worker,
			background: isBackground(root, chrome, worker, inContent),
			spaces,
			kept,
			put,
			native: (api, args) => runtime.sendNativeMessage(APPLICATION, nativeRequest(api, args)).then(replyValue),
			withLastError: lastErrorReporter(runtime, put)
		};
		addInstallRoutes(shim);
		replaceWorkerWebSocket(shim);
		holdEarlyNativeMessages(shim);
		presentAsChrome(shim);
		checkImportedScripts(shim);
		const verdicts = createVerdicts(shim);
		const gather = createGather(shim, verdicts);
		bindRuntimeMethods(runtime, put);
		if (inContent) return;
		forwardThroughWorker(shim);
		mendReplies(shim, verdicts);
		gather(runtime && runtime.onMessage, true);
		gather(runtime && runtime.onMessageExternal);
		defineBrowserNamespaces(shim);
		addIdleStateEvent(shim);
		defineSystem(shim);
		definePrivacy(shim);
		defineContentSettings(shim);
		defineProxy(shim);
		defineUnavailable(shim);
		compileWasmWhole(root);
		const types = resourceTypes();
		fillRuntime(shim);
		mendPopup(shim);
		fillExtension(shim);
		fillTabs(shim);
		fillTabsByIndex(shim);
		fillWindows(shim);
		fillStorage(shim);
		storePlainItems(shim);
		fillScripting(shim);
		tellPopups(shim);
		fillAction(shim);
		fillWebNavigation(shim);
		fillWebRequest(shim, types);
		fillDeclarativeNetRequest(shim, types);
		fillMenus(shim);
		mendRules(shim);
		mendMenus(shim);
		mendRequestListeners(shim);
		describeTabs(shim);
		mendPermissions(shim);
		patchPasskeysFirst(shim);
		defineUserScripts(shim);
		mendInstalledReason(shim);
		acceptLateListeners(shim);
		numberOwnPorts(shim);
		addBrowserMembers(shim);
		rebuildFileSystem(root);
		reportErrors(shim);
	}

//#endregion
//#region src/extension-shims.ts
	install(globalThis, moteConfig);

//#endregion
})();