// Generated from Scripts/src/passkey-relay.ts by `pnpm build`. Do not edit.
(function() {

//#region src/lib/native.ts
	const apply$4 = Reflect.apply;
	const mapGet$1 = Map.prototype.get;
	/**
	* Makes each replacement read as the native function it stands for, by
	* putting a `toString` of its own on `Function.prototype` that reads as native
	* too. Replacements should be methods (`{ get() {} }.get`), which, like
	* WebKit's, have no `prototype` and can't be called with `new`.
	*
	* Source text is matched, not the function, so every frame the script runs in
	* answers the same for the functions of every other: their text is the same.
	*/
	function presentAsNative(pairs) {
		const proto = Function.prototype;
		const original = proto.toString;
		const text = (f) => apply$4(original, f, []);
		const texts = /* @__PURE__ */ new Map();
		const replaced = { toString() {
			const source = apply$4(original, this, []);
			const native = apply$4(mapGet$1, texts, [source]);
			return native === void 0 ? source : native;
		} }.toString;
		for (const [ours, native] of pairs) texts.set(text(ours), text(native));
		texts.set(text(replaced), text(original));
		try {
			Object.defineProperty(proto, "toString", { value: replaced });
		} catch {}
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
	const PageDOMException = DOMException;
	const PageTypeError = TypeError;
	const fillRandom = crypto.getRandomValues.bind(crypto);
	const addListener$2 = EventTarget.prototype.addEventListener;
	const apply$3 = Reflect.apply;
	/** The message of every refusal a page hears, whatever the reason. */
	const NOT_ALLOWED_MESSAGE = PAGE_ERRORS.NotAllowedError;
	/**
	* The error named `name` as the page hears it, with its one message: a
	* TypeError, or a DOMException. A name that isn't one of `PAGE_ERRORS` is
	* NotAllowedError.
	*/
	function pageError(name) {
		const chosen = typeof name === "string" && name in PAGE_ERRORS ? name : "NotAllowedError";
		const message = PAGE_ERRORS[chosen];
		return chosen === "TypeError" ? new PageTypeError(message) : new PageDOMException(message, chosen);
	}
	/** The standard abort error, for a signal aborted without a reason. */
	function abortError() {
		return pageError("AbortError");
	}
	/** `bytes` random bytes from the cryptographic generator, as hex. */
	function randomHex(bytes, fill = fillRandom) {
		const values = new Uint8Array(bytes);
		fill(values);
		let hex = "";
		for (let i = 0; i < values.length; i++) hex += values[i].toString(16).padStart(2, "0");
		return hex;
	}
	/**
	* A conditional request (passkeys offered under the name field) that nothing
	* answers: it waits, as it would while nobody picks a passkey, until the page
	* aborts it. Without a signal it never settles.
	*/
	function pendingUntilAborted(signal, reason) {
		return new Promise((_resolve, reject) => {
			if (!signal) return;
			if (signal.aborted) {
				reject(reason(signal));
				return;
			}
			apply$3(addListener$2, signal, [
				"abort",
				() => reject(reason(signal)),
				{ once: true }
			]);
		});
	}
	/** Whether something installed its own `get` on the `navigator.credentials` object itself. */
	function ownsCredentialMethods(credentials) {
		return !!credentials && !!Object.getOwnPropertyDescriptor(credentials, "get");
	}
	/** Whether a stack trace passes through an extension's script. */
	function isExtensionStack(stack) {
		return (stack || "").indexOf("-extension://") >= 0;
	}
	/**
	* Whether a password manager extension that keeps passkeys (1Password,
	* Bitwarden) is on the page: it puts its own `get` and `create` on
	* `navigator.credentials`, or asks from its own script. Once seen, it stays
	* seen.
	*/
	function extensionWatcher() {
		let claimed = false;
		return () => {
			if (claimed) return true;
			try {
				if (ownsCredentialMethods(navigator.credentials)) claimed = true;
				else if (isExtensionStack((/* @__PURE__ */ new Error()).stack)) claimed = true;
			} catch {}
			return claimed;
		};
	}

//#endregion
//#region src/passkey-relay/capabilities.ts
/**
	* What this browser can and can't do, for the pages that ask first
	* (`PublicKeyCredential.getClientCapabilities()`): passkeys from the Mac, a
	* phone or a key; under the name field only when a password manager extension
	* offers them (`conditional`); none of the extensions WebKit would have
	* answered for itself except credProps.
	*/
	function clientCapabilities(native, conditional) {
		const capabilities = Object.assign({}, native);
		Object.keys(capabilities).forEach((key) => {
			if (key.indexOf("extension:") === 0 && key !== "extension:credProps") capabilities[key] = false;
		});
		return Object.assign(capabilities, {
			conditionalCreate: false,
			conditionalGet: conditional,
			conditionalMediation: conditional,
			relatedOrigins: false,
			signalAllAcceptedCredentials: false,
			signalCurrentUserDetails: false,
			signalUnknownCredential: false,
			hybridTransport: true,
			passkeyPlatformAuthenticator: true,
			userVerifyingPlatformAuthenticator: true
		});
	}

//#endregion
//#region src/passkey-relay/encoding.ts
	function bytes(source) {
		if (source instanceof ArrayBuffer) return new Uint8Array(source);
		if (ArrayBuffer.isView(source)) return new Uint8Array(source.buffer, source.byteOffset, source.byteLength);
		throw new TypeError("Expected an ArrayBuffer or a view of one.");
	}
	/** Unpadded base64url of an ArrayBuffer or view; throws a TypeError for anything else. */
	function encode(source) {
		const b = bytes(source);
		let binary = "";
		for (let i = 0; i < b.length; i++) binary += String.fromCharCode(b[i]);
		return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
	}
	/** The bytes of base64url (padded or not) text; nothing for a missing value. */
	function decode(text) {
		let base64 = (text || "").replace(/-/g, "+").replace(/_/g, "/");
		while (base64.length % 4) base64 += "=";
		const raw = atob(base64);
		const out = new Uint8Array(raw.length);
		for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
		return out.buffer;
	}

//#endregion
//#region src/passkey-relay/credential.ts
/** ES256, the algorithm of every passkey the Mac makes. */
	const DEFAULT_ALGORITHM = -7;
	/**
	* The error a reply fails with, or null for one that isn't a failure. Swift
	* names the error; the page hears it with that name's one message
	* (`pageError`), never one of Swift's. No reply, or one that is no object,
	* is NotAllowedError.
	*/
	function replyError(reply) {
		if (!reply || typeof reply !== "object") return pageError("NotAllowedError");
		const { error } = reply;
		return error ? pageError(error) : null;
	}
	function text(value) {
		return typeof value === "string";
	}
	/** Whether a reply that isn't a failure has what a credential is made of. */
	function isCredentialReply(reply) {
		if (!text(reply.id) || !text(reply.clientDataJSON)) return false;
		if (reply.kind === "get") return text(reply.authenticatorData) && text(reply.signature);
		if (reply.kind === "create") return text(reply.attestationObject);
		return false;
	}
	/**
	* What Swift's reply comes to for the page. Anything that can't be read as a
	* credential (a reply broken in any way) is NotAllowedError, so no request is
	* left pending.
	*/
	function settle(reply, extensions) {
		try {
			const error = replyError(reply);
			if (error) return { error };
			if (!isCredentialReply(reply)) return { error: pageError("NotAllowedError") };
			return { credential: credential(reply, extensions) };
		} catch {
			return { error: pageError("NotAllowedError") };
		}
	}
	/**
	* The client extension results. A passkey from the Mac is always one the site
	* can find without naming it (a resident key); the site may have asked whether
	* it is.
	*/
	function extensionResults(reply, extensions) {
		const results = {};
		if (reply.kind === "create" && extensions && extensions.credProps && reply.attachment === "platform") results.credProps = { rk: true };
		return results;
	}
	/** What the credential's `toJSON()` returns. */
	function credentialJSON(reply, results) {
		const made = reply.kind === "create";
		const response = made ? {
			clientDataJSON: reply.clientDataJSON,
			attestationObject: reply.attestationObject,
			authenticatorData: reply.authenticatorData,
			transports: (reply.transports || []).slice(),
			publicKeyAlgorithm: reply.publicKeyAlgorithm ?? DEFAULT_ALGORITHM
		} : {
			clientDataJSON: reply.clientDataJSON,
			authenticatorData: reply.authenticatorData,
			signature: reply.signature
		};
		if (made && reply.publicKey) response.publicKey = reply.publicKey;
		if (!made && reply.userHandle) response.userHandle = reply.userHandle;
		return {
			id: reply.id,
			rawId: reply.id,
			type: "public-key",
			authenticatorAttachment: reply.attachment || null,
			clientExtensionResults: results,
			response
		};
	}
	/** Defines `values` on `target` as configurable properties; `hidden` ones aren't enumerable. */
	function define(target, values, hidden) {
		Object.keys(values).forEach((key) => {
			Object.defineProperty(target, key, {
				value: values[key],
				enumerable: !hidden,
				configurable: true
			});
		});
		return target;
	}
	/**
	* The credential for a reply, built on WebKit's own prototypes so
	* `instanceof PublicKeyCredential` and the response's methods work as sites
	* expect.
	*/
	function credential(reply, extensions) {
		let response;
		if (reply.kind === "create") {
			response = Object.create(AuthenticatorAttestationResponse.prototype);
			define(response, {
				clientDataJSON: decode(reply.clientDataJSON),
				attestationObject: decode(reply.attestationObject)
			});
			define(response, {
				getTransports: function() {
					return (reply.transports || []).slice();
				},
				getAuthenticatorData: function() {
					return decode(reply.authenticatorData);
				},
				getPublicKey: function() {
					return reply.publicKey ? decode(reply.publicKey) : null;
				},
				getPublicKeyAlgorithm: function() {
					return reply.publicKeyAlgorithm ?? DEFAULT_ALGORITHM;
				}
			}, true);
		} else {
			response = Object.create(AuthenticatorAssertionResponse.prototype);
			define(response, {
				clientDataJSON: decode(reply.clientDataJSON),
				authenticatorData: decode(reply.authenticatorData),
				signature: decode(reply.signature),
				userHandle: reply.userHandle ? decode(reply.userHandle) : null
			});
		}
		const results = extensionResults(reply, extensions);
		const json = credentialJSON(reply, results);
		const result = Object.create(PublicKeyCredential.prototype);
		define(result, {
			id: reply.id,
			rawId: decode(reply.id),
			type: "public-key",
			authenticatorAttachment: reply.attachment || null,
			response
		});
		return define(result, {
			getClientExtensionResults: function() {
				return JSON.parse(JSON.stringify(results));
			},
			toJSON: function() {
				return JSON.parse(JSON.stringify(json));
			}
		}, true);
	}

//#endregion
//#region src/passkey-relay/once.ts
	const apply$2 = Reflect.apply;
	const addListener$1 = EventTarget.prototype.addEventListener;
	const dispatch = EventTarget.prototype.dispatchEvent;
	const PageEvent = Event;
	/**
	* Whether this copy is the first on `target` to claim `name`; if so, it keeps
	* the claim, and `held` alive with it.
	*/
	function claim(target, name, held) {
		const probe = new PageEvent(name, { cancelable: true });
		if (!apply$2(dispatch, target, [probe])) return false;
		apply$2(addListener$1, target, [name, (event) => {
			event.preventDefault();
			return held;
		}]);
		return true;
	}

//#endregion
//#region src/passkey-relay/requests.ts
	function descriptors(list) {
		return Array.prototype.map.call(list || [], (credential) => ({
			id: encode(credential.id),
			transports: Array.prototype.slice.call(credential.transports || [])
		}));
	}
	function assertionRequest(options) {
		return {
			kind: "get",
			challenge: encode(options.challenge),
			rpId: options.rpId || null,
			allowCredentials: descriptors(options.allowCredentials),
			userVerification: options.userVerification || "preferred"
		};
	}
	/** `selection` is the options' `authenticatorSelection`, or an empty one. */
	function registrationRequest(options, selection) {
		return {
			kind: "create",
			challenge: encode(options.challenge),
			rp: { id: options.rp && options.rp.id || null },
			user: {
				id: encode(options.user.id),
				name: String(options.user.name),
				displayName: options.user.displayName ? String(options.user.displayName) : ""
			},
			algorithms: Array.prototype.map.call(options.pubKeyCredParams || [], (parameters) => parameters.alg),
			excludeCredentials: descriptors(options.excludeCredentials),
			authenticatorAttachment: selection.authenticatorAttachment || null,
			residentKey: selection.residentKey || (selection.requireResidentKey ? "required" : "discouraged"),
			userVerification: selection.userVerification || "preferred",
			attestation: options.attestation || "none"
		};
	}

//#endregion
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
	/**
	* An answer read from an event's detail, or null when it isn't one with a
	* token. The reply is whatever came: `settle` reads it.
	*/
	function parseAnswer(detail) {
		const answer = parseObject(detail);
		if (!answer || typeof answer.token !== "string") return null;
		return {
			token: answer.token,
			reply: answer.reply
		};
	}

//#endregion
//#region src/passkey-relay/waiting.ts
	const mapGet = Map.prototype.get;
	const mapSet = Map.prototype.set;
	const mapDelete = Map.prototype.delete;
	const apply$1 = Reflect.apply;
	/**
	* Requests by token, in a Map: a token like `toString` finds nothing it
	* wasn't given. Its methods were taken as the script started, so a page that
	* replaces Map's later sees none of it.
	*/
	var Waiting = class {
		requests = /* @__PURE__ */ new Map();
		add(token, settle) {
			apply$1(mapSet, this.requests, [token, settle]);
		}
		/** Forgets a request: the page let it go. */
		drop(token) {
			apply$1(mapDelete, this.requests, [token]);
		}
		/** Settles the request an answer event's detail is for; false when it's for none. */
		answer(detail) {
			const answer = parseAnswer(detail);
			if (!answer) return false;
			const settle = apply$1(mapGet, this.requests, [answer.token]);
			if (!settle) return false;
			this.drop(answer.token);
			settle(answer.reply);
			return true;
		}
	};

//#endregion
//#region src/passkey-relay.ts
	const apply = Reflect.apply;
	const addListener = EventTarget.prototype.addEventListener;
	const dispatchEvent = EventTarget.prototype.dispatchEvent;
	const PageCustomEvent = CustomEvent;
	const PagePromise = Promise;
	const stringify = JSON.stringify;
	const then = Promise.prototype.then;
	const isPrototypeOf = Object.prototype.isPrototypeOf;
	const containerProto = CredentialsContainer.prototype;
	const typeErrorProto = TypeError.prototype;
	/** `value instanceof CredentialsContainer`, which a page can't redefine. */
	const isContainer = (value) => apply(isPrototypeOf, containerProto, [value]);
	/** Why an aborted request failed: the page's reason, or the standard AbortError. */
	function abortReason(signal) {
		return signal.reason !== void 0 ? signal.reason : abortError();
	}
	/** Puts `value` in place of `target[name]`, keeping the property's attributes. */
	function replace(target, name, value) {
		try {
			Object.defineProperty(target, name, { value });
		} catch {}
	}
	/**
	* The request the page's options make, or the error they fail with. Options
	* of the wrong kind fail as a TypeError with its one message, as WebKit's
	* checks would, never with one naming Mote's code; an error the page's own
	* getters throw goes to the page as it is.
	*/
	function build(make) {
		try {
			return { request: make() };
		} catch (error) {
			return { error: apply(isPrototypeOf, typeErrorProto, [error]) ? pageError("TypeError") : error };
		}
	}
	installPasskeyRelay();
	function installPasskeyRelay() {
		if (!window.PublicKeyCredential || !window.CredentialsContainer) return;
		if (!claim(window, moteConfig.installEvent, navigator.credentials)) return;
		const proto = CredentialsContainer.prototype;
		const nativeGet = proto.get;
		const nativeCreate = proto.create;
		const waiting = new Waiting();
		apply(addListener, window, [moteConfig.answerEvent, (event) => {
			waiting.answer(event.detail);
		}]);
		function dispatch(message) {
			apply(dispatchEvent, window, [new PageCustomEvent(moteConfig.askEvent, { detail: stringify(message) })]);
		}
		function send(request, signal, extensions) {
			if (signal && signal.aborted) return PagePromise.reject(abortReason(signal));
			const token = randomHex(16);
			request.token = token;
			return new PagePromise((resolve, reject) => {
				if (signal) apply(addListener, signal, [
					"abort",
					() => {
						waiting.drop(token);
						dispatch({
							kind: "cancel",
							token
						});
						reject(abortReason(signal));
					},
					{ once: true }
				]);
				waiting.add(token, (reply) => {
					const outcome = settle(reply, extensions);
					if ("error" in outcome) reject(outcome.error);
					else resolve(outcome.credential);
				});
				dispatch(request);
			});
		}
		const replacements = {
			get(...args) {
				const options = args[0];
				if (!isContainer(this) || !options || !options.publicKey) return apply(nativeGet, this, args);
				const signal = options.signal;
				const publicKey = options.publicKey;
				if (options.mediation === "conditional") return pendingUntilAborted(signal, abortReason);
				const built = build(() => assertionRequest(publicKey));
				if ("error" in built) return PagePromise.reject(built.error);
				return send(built.request, signal, publicKey.extensions);
			},
			create(...args) {
				const options = args[0];
				if (!isContainer(this) || !options || !options.publicKey) return apply(nativeCreate, this, args);
				const publicKey = options.publicKey;
				if (options.mediation === "conditional") return PagePromise.reject(pageError("NotAllowedError"));
				const built = build(() => registrationRequest(publicKey, publicKey.authenticatorSelection || {}));
				if ("error" in built) return PagePromise.reject(built.error);
				return send(built.request, options.signal, publicKey.extensions);
			}
		};
		replace(proto, "get", replacements.get);
		replace(proto, "create", replacements.create);
		const disguised = [[replacements.get, nativeGet], [replacements.create, nativeCreate]];
		const extensionAnswers = extensionWatcher();
		const P = PublicKeyCredential;
		const nativeCapabilities = P.getClientCapabilities;
		const statics = {
			isUserVerifyingPlatformAuthenticatorAvailable() {
				return PagePromise.resolve(true);
			},
			isConditionalMediationAvailable() {
				return PagePromise.resolve(extensionAnswers());
			},
			getClientCapabilities() {
				const conditional = extensionAnswers();
				const ours = (native) => clientCapabilities(native, conditional);
				const asked = apply(nativeCapabilities, P, []);
				return apply(then, asked, [ours, () => ours({})]);
			}
		};
		for (const name of Object.keys(statics)) {
			const native = P[name];
			if (typeof native !== "function") continue;
			replace(P, name, statics[name]);
			disguised.push([statics[name], native]);
		}
		presentAsNative(disguised);
	}

//#endregion
})();