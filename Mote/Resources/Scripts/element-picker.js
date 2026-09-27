// Generated from Scripts/src/element-picker.ts by `pnpm build`. Do not edit.
(function() {

//#region src/element-picker/describe.ts
/**
	* Names for elements whose tag says what they are. A Map, not an object: a page
	* can name an element `constructor` or `__proto__`.
	*/
	const KINDS = /* @__PURE__ */ new Map([
		["nav", "Navigation"],
		["header", "Header"],
		["footer", "Footer"],
		["aside", "Sidebar"],
		["form", "Form"],
		["dialog", "Dialog"],
		["video", "Video"],
		["img", "Image"],
		["button", "Button"],
		["iframe", "Embed"],
		["figure", "Figure"],
		["table", "Table"]
	]);
	/** Longest name shown, in characters. */
	const MAX_NAME_LENGTH = 40;
	/** Cuts `text` to `length` characters, marking the cut with an ellipsis. */
	function clip(text, length) {
		return text.length > length ? `${text.slice(0, length)}…` : text;
	}
	/**
	* What an element is, in the order a person would answer the question: what it
	* calls itself, then what kind of thing it is, then what it says.
	*/
	function elementName(element) {
		const said = element.getAttribute("aria-label") || element.getAttribute("title");
		if (said && said.trim()) return clip(said.trim(), MAX_NAME_LENGTH);
		const tag = element.localName;
		const kind = KINDS.get(tag);
		if (kind) return kind;
		const role = element.getAttribute("role");
		if (role) return role.charAt(0).toUpperCase() + role.slice(1);
		const text = (element.innerText || "").trim().replace(/\s+/g, " ");
		return text ? clip(text, MAX_NAME_LENGTH) : tag;
	}
	/**
	* How big, and which part of the window: two sidebars read alike, but they are
	* rarely the same shape in the same place.
	*/
	function elementShape(box, viewport) {
		const centerX = box.left + box.width / 2;
		const centerY = box.top + box.height / 2;
		const side = centerX < viewport.width / 3 ? "left" : centerX > viewport.width * 2 / 3 ? "right" : "centre";
		const band = centerY < viewport.height / 3 ? "top" : centerY > viewport.height * 2 / 3 ? "bottom" : "middle";
		return `${Math.round(box.width)}×${Math.round(box.height)} · ${band} ${side}`;
	}

//#endregion
//#region src/element-picker/overlay.ts
	const FRAME_STYLE = "position:fixed;z-index:2147483646;pointer-events:none;border:2px solid rgba(23,23,23,.9);background:rgba(23,23,23,.07);border-radius:4px;transition:all .07s ease-out;display:none";
	const TAG_STYLE = "position:absolute;font:500 11px -apple-system,BlinkMacSystemFont,sans-serif;color:#fff;background:#171717;padding:2px 7px;border-radius:5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis";
	/** Builds the overlay, hidden, at the end of the document. */
	function createOverlay(document) {
		const frame = document.createElement("div");
		frame.style.cssText = FRAME_STYLE;
		const tag = document.createElement("div");
		tag.style.cssText = TAG_STYLE;
		frame.appendChild(tag);
		document.documentElement.appendChild(frame);
		return {
			frame,
			tag
		};
	}
	/** Shows the overlay over `box`, labelled `name`, within a window `viewportWidth` wide. */
	function placeOverlay({ frame, tag }, box, name, viewportWidth) {
		frame.style.display = "block";
		frame.style.left = `${box.left}px`;
		frame.style.top = `${box.top}px`;
		frame.style.width = `${box.width}px`;
		frame.style.height = `${box.height}px`;
		tag.textContent = name;
		tag.style.top = box.top >= 26 ? "-21px" : "3px";
		tag.style.left = `${Math.max(2, -box.left + 4)}px`;
		tag.style.maxWidth = `${Math.max(80, viewportWidth - Math.max(0, box.left) - 16)}px`;
	}

//#endregion
//#region src/element-picker/selector.ts
/** Attributes sites put on elements for tests and accessibility, which rarely change between builds. */
	const HOOK_ATTRIBUTES = [
		"data-testid",
		"data-test",
		"data-qa",
		"data-cy",
		"aria-label",
		"name",
		"role"
	];
	/**
	* A class worth hanging a rule on: a word, not a build artefact — no long runs
	* of digits, and none of the prefixes CSS-in-JS libraries generate.
	*/
	function isStableClass(name) {
		return /^[a-zA-Z][\w-]{2,29}$/.test(name) && !/\d{3,}/.test(name) && !/^(css|sc|jsx|emotion|svelte|styles?)-/.test(name);
	}
	/** Whether `selector` matches exactly one element; false when it isn't valid. */
	function isUnique(document, selector) {
		try {
			return document.querySelectorAll(selector).length === 1;
		} catch {
			return false;
		}
	}
	/**
	* A CSS selector that matches `element` alone, preferring what survives a
	* redesign: its id, a test or accessibility hook, its stable classes, and only
	* as a last resort its position in the tree.
	*/
	function selectorFor(element) {
		const document = element.ownerDocument;
		const byId = element.id && `#${CSS.escape(element.id)}`;
		if (byId && isUnique(document, byId)) return byId;
		const tag = CSS.escape(element.localName);
		for (const hook of HOOK_ATTRIBUTES) {
			const value = element.getAttribute(hook);
			if (!value) continue;
			const byHook = `${tag}[${hook}="${CSS.escape(value)}"]`;
			if (isUnique(document, byHook)) return byHook;
		}
		const classes = element.className && typeof element.className === "string" ? element.className.trim().split(/\s+/).filter(isStableClass) : [];
		if (classes.length) {
			const byClass = `${tag}.${classes.map((name) => CSS.escape(name)).join(".")}`;
			if (isUnique(document, byClass)) return byClass;
		}
		return pathTo(element);
	}
	/** A child-by-child path to `element`, anchored on the nearest ancestor with a unique id. */
	function pathTo(element) {
		const document = element.ownerDocument;
		const parts = [];
		let node = element;
		while (node && node.nodeType === Node.ELEMENT_NODE && node !== document.documentElement) {
			const byId = node.id && `#${CSS.escape(node.id)}`;
			if (byId && isUnique(document, byId)) {
				parts.unshift(byId);
				break;
			}
			const tag = CSS.escape(node.localName);
			const parent = node.parentElement;
			if (!parent) {
				parts.unshift(tag);
				break;
			}
			const current = node;
			const kin = [...parent.children].filter((sibling) => sibling.localName === current.localName && sibling.namespaceURI === current.namespaceURI);
			parts.unshift(kin.length > 1 ? `${tag}:nth-of-type(${kin.indexOf(current) + 1})` : tag);
			node = parent;
		}
		return parts.join(" > ");
	}

//#endregion
//#region src/lib/element-hiding.ts
/** The <style> element hiding the elements someone chose to hide on a site. */
	const HIDDEN_ELEMENTS_STYLE_ID = "mote-hidden-elements";
	/** What each hiding rule declares. */
	const HIDDEN = { display: "none" };
	/**
	* Hides the elements `selectors` select, replacing what was hidden before: one
	* rule per selector, so one the browser can't parse leaves the others working.
	*/
	function hideElements(document, selectors) {
		return writeRules(document, HIDDEN_ELEMENTS_STYLE_ID, selectors, HIDDEN);
	}
	/**
	* Replaces the rules of the <style> element `id` — created at the end of <head>
	* when missing — with one rule per selector, declaring each of `declarations` as
	* `!important`. Returns how many selectors made a rule.
	*
	* Selectors are stored, and could say anything: never CSS text. Each is built
	* into a rule through the CSSOM, which takes exactly one rule or throws, and a
	* selector is skipped unless it parses as a selector on its own and makes a
	* style rule that declares nothing of its own — so no selector can add rules,
	* declarations or imports to the page.
	*/
	function writeRules(document, id, selectors, declarations) {
		const sheet = emptySheet(document, id);
		if (!sheet) return 0;
		let written = 0;
		for (const selector of selectors) {
			const rule = emptyRule(document, sheet, selector);
			if (!rule) continue;
			for (const [name, value] of Object.entries(declarations)) rule.style.setProperty(name, value, "important");
			written++;
		}
		return written;
	}
	/** The sheet of the <style> element `id`, emptied. */
	function emptySheet(document, id) {
		let style = document.getElementById(id);
		if (!style) {
			style = document.createElement("style");
			style.id = id;
			(document.head || document.documentElement).appendChild(style);
		}
		style.textContent = "";
		const sheet = style.sheet;
		while (sheet?.cssRules.length) sheet.deleteRule(sheet.cssRules.length - 1);
		return sheet;
	}
	/** An empty style rule for `selector` at the end of `sheet`, or null when `selector` is anything else. */
	function emptyRule(document, sheet, selector) {
		if (typeof selector !== "string" || !isSelector(document, selector)) return null;
		let index;
		try {
			index = sheet.insertRule(`${selector} {}`, sheet.cssRules.length);
		} catch {
			return null;
		}
		const rule = sheet.cssRules[index];
		const nested = rule?.cssRules?.length ?? 0;
		if (!rule || !("selectorText" in rule) || !rule.style || rule.style.length > 0 || nested > 0) {
			sheet.deleteRule(index);
			return null;
		}
		return rule;
	}
	/** Whether `selector` parses as a selector: a brace, semicolon or at-rule outside a string doesn't. */
	function isSelector(document, selector) {
		if (!selector.trim()) return false;
		try {
			document.createDocumentFragment().querySelector(selector);
			return true;
		} catch {
			return false;
		}
	}

//#endregion
//#region src/element-picker.ts
	const PEEK_STYLE_ID = "mote-peek";
	/** How `peek` outlines the element it shows. */
	const PEEK_OUTLINE = {
		outline: "2px solid rgba(23,23,23,.9)",
		"outline-offset": "2px"
	};
	/**
	* Everything a press can be, swallowed. Real pages act on pointerdown or
	* mousedown and are gone before a click ever completes — which looked
	* exactly like nothing happening. The pick itself happens on pointerdown.
	*/
	const PRESSES = [
		"pointerdown",
		"mousedown",
		"pointerup",
		"mouseup",
		"click",
		"dblclick",
		"contextmenu",
		"touchstart"
	];
	if (!window.__moteVeil) {
		let overlay = null;
		let target = null;
		let live = false;
		const post = (message) => window.webkit.messageHandlers.moteVeil?.postMessage(message);
		const showOverlay = () => overlay ??= createOverlay(document);
		const hideOverlay = () => {
			if (overlay) overlay.frame.style.display = "none";
		};
		/** Whether the picker may pick `element`: not its own outline, nor the whole page. */
		const pickable = (element) => !!element && element !== overlay?.frame && element !== document.documentElement && element !== document.body;
		const onMove = (event) => {
			if (!live) return;
			const element = document.elementFromPoint(event.clientX, event.clientY);
			if (!pickable(element)) return;
			target = element;
			placeOverlay(showOverlay(), element.getBoundingClientRect(), elementName(element), window.innerWidth);
		};
		const swallow = (event) => {
			if (!live) return;
			event.preventDefault();
			event.stopPropagation();
			event.stopImmediatePropagation();
		};
		const onPress = (event) => {
			if (!live) return;
			swallow(event);
			const { clientX, clientY } = event;
			const element = target || document.elementFromPoint(clientX, clientY);
			if (!pickable(element)) return;
			try {
				post({
					selector: selectorFor(element),
					label: elementName(element),
					note: elementShape(element.getBoundingClientRect(), {
						width: window.innerWidth,
						height: window.innerHeight
					})
				});
			} catch (error) {
				post({ trouble: String(error) });
			}
			target = null;
			hideOverlay();
		};
		const handlerFor = (kind) => kind === "pointerdown" ? onPress : swallow;
		window.__moteVeil = {
			on() {
				if (live) return;
				live = true;
				showOverlay();
				document.documentElement.style.cursor = "crosshair";
				document.addEventListener("mousemove", onMove, true);
				document.addEventListener("pointermove", onMove, true);
				for (const kind of PRESSES) document.addEventListener(kind, handlerFor(kind), true);
			},
			off() {
				if (!live) return;
				live = false;
				target = null;
				hideOverlay();
				document.documentElement.style.cursor = "";
				document.removeEventListener("mousemove", onMove, true);
				document.removeEventListener("pointermove", onMove, true);
				for (const kind of PRESSES) document.removeEventListener(kind, handlerFor(kind), true);
				post({ off: true });
			},
			peek(selectors, selector) {
				hideElements(document, selectors);
				writeRules(document, PEEK_STYLE_ID, [selector], PEEK_OUTLINE);
				try {
					document.querySelector(selector)?.scrollIntoView({
						block: "center",
						behavior: "smooth"
					});
				} catch {}
			},
			unpeek(selectors) {
				hideElements(document, selectors);
				writeRules(document, PEEK_STYLE_ID, [], PEEK_OUTLINE);
			}
		};
	}

//#endregion
})();