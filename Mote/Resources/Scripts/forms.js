// Generated from Scripts/src/forms.ts by `pnpm build`. Do not edit.
(function() {

//#region src/forms/sign-in.ts
/** Input types that can hold the account name next to a password. */
	const USERNAME_TYPES = /* @__PURE__ */ new Set([
		"text",
		"email",
		"tel"
	]);
	/** The lowercase type of an input, `text` when it has none. */
	function inputType(input) {
		return (input.type || "text").toLowerCase();
	}
	/** Whether an element takes up any room on the page (hidden ones don't). */
	function hasSize(element) {
		const rect = element.getBoundingClientRect();
		return rect.width > 0 && rect.height > 0;
	}
	/**
	* The page's sign-in, or null when it has none: the first password field that
	* is shown, and the last field before it (in its form, or the document) that
	* could hold a name.
	*/
	function signInFields(document) {
		let password = null;
		for (const field of document.querySelectorAll("input[type=\"password\"]")) if (hasSize(field)) {
			password = field;
			break;
		}
		if (!password) return null;
		const scope = password.form || password.closest("form") || document;
		let user = null;
		for (const input of scope.querySelectorAll("input")) {
			if (input === password) break;
			if (USERNAME_TYPES.has(inputType(input))) user = input;
		}
		return {
			user,
			password
		};
	}
	/**
	* Sets a field's value as typing would. The native setter and the input and
	* change events are what frameworks such as React notice; assigning `.value`
	* alone is not.
	*/
	function setFieldValue(field, value) {
		const descriptor = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value");
		if (descriptor && descriptor.set) descriptor.set.call(field, value);
		else field.value = value;
		field.dispatchEvent(new Event("input", { bubbles: true }));
		field.dispatchEvent(new Event("change", { bubbles: true }));
	}
	/**
	* Fills a saved account the user picked: the name only into an empty name
	* field, the password always. False when the page has no sign-in anymore.
	*/
	function fillSignIn(fields, user, password) {
		if (!fields) return false;
		if (fields.user && !fields.user.value) setFieldValue(fields.user, user);
		setFieldValue(fields.password, password);
		return true;
	}
	/** What a sign-in is about to send, or null while its password is empty. */
	function submittedCredentials(fields) {
		if (!fields || !fields.password.value) return null;
		return {
			user: fields.user ? fields.user.value : "",
			password: fields.password.value
		};
	}

//#endregion
//#region src/forms/typing.ts
/** How many fields typed into are remembered, the oldest forgotten first. */
	const MAX_TYPED_FIELDS = 40;
	/** Input types whose text is worth keeping a page awake for. */
	const TEXT_TYPES = /* @__PURE__ */ new Set([
		"text",
		"email",
		"url",
		"tel",
		"number"
	]);
	/** Input types that take typing at the caret, so Tab stays with the page. */
	const TYPING_TYPES = /* @__PURE__ */ new Set([
		"text",
		"search",
		"email",
		"url",
		"tel",
		"password",
		"number",
		"date",
		"datetime-local",
		"month",
		"week",
		"time"
	]);
	function tagName(element) {
		return (element.tagName || "").toLowerCase();
	}
	function changedText(element) {
		return !!(element.value || "").trim() && element.value !== element.defaultValue;
	}
	/**
	* Whether a field typed into by hand still holds text that wasn't sent. A
	* field emptied by sending (a chat's composer) no longer does, and neither
	* does a search field.
	*/
	function holdsUnsentText(element) {
		if (!element.isConnected) return false;
		const tag = tagName(element);
		if (tag === "textarea") return changedText(element);
		if (tag === "input") {
			if (!TEXT_TYPES.has((element.type || "text").toLowerCase())) return false;
			return changedText(element);
		}
		if (element.isContentEditable) return !!(element.textContent || "").trim();
		return false;
	}
	/**
	* The fields typed into by hand. A page whose fields still hold what was typed
	* is not put to sleep: waking it couldn't bring that back.
	*/
	var TypedFields = class {
		fields = [];
		/** Remembers the field an input event came from. */
		record(event) {
			if (!event.isTrusted) return;
			const field = event.target;
			if (!field || this.fields.includes(field)) return;
			this.fields.push(field);
			if (this.fields.length > 40) this.fields.shift();
		}
		/** Whether any of them holds text that wasn't sent. */
		unsaved() {
			return this.fields.some((field) => holdsUnsentText(field));
		}
	};
	/**
	* Whether the caret is somewhere on the page that takes typing.
	*
	* The browser gives Tab to its own row of tabs, which is right until you are
	* filling something in: plenty of fields offer a completion you take with Tab,
	* and stealing the key there would make them unusable.
	*/
	function acceptsTyping(element) {
		if (!element) return false;
		const tag = tagName(element);
		if (tag === "textarea") return true;
		if (element.isContentEditable === true) return true;
		if (element.getAttribute && element.getAttribute("role") === "textbox") return true;
		if (tag === "iframe") try {
			const inner = element.contentDocument;
			return acceptsTyping(inner && inner.activeElement);
		} catch {
			return false;
		}
		if (tag !== "input") return false;
		return TYPING_TYPES.has((element.type || "text").toLowerCase());
	}
	/** A field's frame in the viewport, in CSS pixels, or null while it takes no room. */
	function fieldFrame(element) {
		const rect = element.getBoundingClientRect();
		if (rect.width > 0 && rect.height > 0) return {
			x: rect.left,
			y: rect.top,
			w: rect.width,
			h: rect.height
		};
		return null;
	}

//#endregion
//#region src/forms.ts
/** Once the sign-in fields are gone, how long they must stay gone for a sign-in done in place. */
	const SETTLE_MS = 400;
	/** When to look again for a sign-in the page builds itself, or the password step after the name. */
	const LATE_FORM_CHECKS_MS = [700, 2200];
	function post(message) {
		window.webkit.messageHandlers.moteForms?.postMessage(message);
	}
	function findSignIn() {
		return signInFields(document);
	}
	/**
	* What is in the fields when they are sent. Said every time (a click on "show
	* password" says it too) because Swift only listens once the page has moved
	* on, and keeps the last thing it heard.
	*/
	function offer() {
		const sent = submittedCredentials(findSignIn());
		if (sent) post({
			kind: "submit",
			user: sent.user,
			password: sent.password
		});
	}
	/** The last caret report, so the same one isn't sent twice. */
	let reported = "";
	/** Whether the caret is in a sign-in field, whose frame moves with the page. */
	let hanging = false;
	/** Where the caret is, and the frame of the sign-in field it's in, which the account list hangs from. */
	function caret() {
		const focused = document.activeElement;
		const fields = findSignIn();
		const rect = fields && focused && (focused === fields.user || focused === fields.password) && focused ? fieldFrame(focused) : null;
		hanging = rect !== null;
		const message = {
			kind: "focus",
			typing: acceptsTyping(focused),
			rect
		};
		const said = JSON.stringify(message);
		if (said === reported) return;
		reported = said;
		post(message);
	}
	/**
	* Full screen, on or off, as the page hears it. Swift learns of going full
	* screen earlier from the web view itself (FormRelay.watchFullscreen): the
	* page's own requestFullscreen can't be seen from this world, and nothing
	* patched here could be without the page seeing it too.
	*/
	function immersed() {
		const webkitElement = document.webkitFullscreenElement;
		post({
			kind: "fullscreen",
			on: !!(document.fullscreenElement || webkitElement)
		});
	}
	if (!window.__moteForms) installForms();
	function installForms() {
		const typed = new TypedFields();
		document.addEventListener("input", (event) => typed.record(event), true);
		window.__moteForms = {
			unsaved: () => typed.unsaved(),
			fill: (user, password) => fillSignIn(findSignIn(), user, password),
			hasPassword: () => !!findSignIn()
		};
		document.addEventListener("submit", offer, true);
		document.addEventListener("keydown", (event) => {
			if (event.key !== "Enter") return;
			const fields = findSignIn();
			const focused = document.activeElement;
			if (fields && (focused === fields.password || focused === fields.user)) offer();
		}, true);
		document.addEventListener("click", (event) => {
			const target = event.target;
			if (!target || !target.closest) return;
			if (target.closest("button, input[type=\"submit\"], [role=\"button\"]")) setTimeout(offer, 0);
		}, true);
		let told = false;
		const tell = () => {
			if (told || !findSignIn()) return;
			told = true;
			post({ kind: "form" });
		};
		if (document.readyState === "complete") tell();
		else window.addEventListener("load", tell);
		for (const delay of LATE_FORM_CHECKS_MS) setTimeout(tell, delay);
		let settling;
		new MutationObserver(() => {
			if (!told) {
				tell();
				return;
			}
			if (findSignIn()) return;
			told = false;
			clearTimeout(settling);
			settling = setTimeout(() => {
				if (!findSignIn()) post({ kind: "settled" });
			}, SETTLE_MS);
		}).observe(document.documentElement, {
			childList: true,
			subtree: true
		});
		let moving = false;
		const moved = () => {
			if (moving || !hanging) return;
			moving = true;
			requestAnimationFrame(() => {
				moving = false;
				caret();
			});
		};
		window.addEventListener("scroll", moved, true);
		window.addEventListener("resize", moved);
		document.addEventListener("fullscreenchange", immersed, true);
		document.addEventListener("webkitfullscreenchange", immersed, true);
		document.addEventListener("focusin", caret, true);
		document.addEventListener("focusout", () => setTimeout(caret, 0), true);
		document.addEventListener("mouseup", () => setTimeout(caret, 0), true);
		caret();
	}

//#endregion
})();