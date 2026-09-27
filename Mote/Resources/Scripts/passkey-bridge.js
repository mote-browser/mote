// Generated from Scripts/src/passkey-bridge.ts by `pnpm build`. Do not edit.
(function() {

//#region src/lib/passkey-messages.ts
	const parseJSON = JSON.parse;
	/** JSON of an object, or null for anything else. */
	function parseObject(detail) {
		let message;
		try {
			message = parseJSON(detail);
		} catch {
			return null;
		}
		return message && typeof message === "object" ? message : null;
	}
	/** A request read from an event's detail, or null when it isn't one with a token. */
	function parseRequest(detail) {
		const message = parseObject(detail);
		if (!message || typeof message.token !== "string") return null;
		return message;
	}

//#endregion
//#region src/lib/passkeys.ts
/**
	* The errors a page may hear from a WebAuthn request, each with the one
	* message it always carries, whatever the reason, as the spec leaves messages
	* to the browser: a site can't tell passkeys turned off from a sheet the user
	* closed. `Passkeys.messages` in Passkeys.swift is the same table.
	*/
	const PAGE_ERRORS = Object.assign(Object.create(null), {
		NotAllowedError: "The operation either timed out or was not allowed.",
		SecurityError: "The operation is insecure.",
		TypeError: "Type error",
		NotSupportedError: "The operation is not supported.",
		InvalidStateError: "The object is in an invalid state.",
		AbortError: "The operation was aborted."
	});
	const fillRandom = crypto.getRandomValues.bind(crypto);
	const addListener = EventTarget.prototype.addEventListener;
	/** The message of every refusal a page hears, whatever the reason. */
	const NOT_ALLOWED_MESSAGE = PAGE_ERRORS.NotAllowedError;
	/** `bytes` random bytes from the cryptographic generator, as hex. */
	function randomHex(bytes, fill = fillRandom) {
		const values = new Uint8Array(bytes);
		fill(values);
		let hex = "";
		for (let i = 0; i < values.length; i++) hex += values[i].toString(16).padStart(2, "0");
		return hex;
	}

//#endregion
//#region src/passkey-bridge.ts
	const handler = window.webkit?.messageHandlers?.[moteConfig.handler];
	if (handler && !window.__motePasskeyBridge) {
		window.__motePasskeyBridge = true;
		const documentName = randomHex(16);
		window.addEventListener(moteConfig.askEvent, (event) => {
			const message = parseRequest(event.detail);
			if (!message) return;
			message.document = documentName;
			const answer = (reply) => {
				const detail = {
					token: message.token,
					reply
				};
				window.dispatchEvent(new CustomEvent(moteConfig.answerEvent, { detail: JSON.stringify(detail) }));
			};
			const cancelling = message.kind === "cancel";
			handler.postMessage(message).then((reply) => {
				if (!cancelling) answer(reply);
			}, () => {
				if (!cancelling) answer(null);
			});
		});
	}

//#endregion
})();