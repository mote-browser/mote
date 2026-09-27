// Generated from Scripts/src/passkeys-hidden.ts by `pnpm build`. Do not edit.
(function() {

//#region src/lib/native.ts
	const apply$2 = Reflect.apply;
	const mapGet = Map.prototype.get;
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
		const text = (f) => apply$2(original, f, []);
		const texts = /* @__PURE__ */ new Map();
		const replaced = { toString() {
			const source = apply$2(original, this, []);
			const native = apply$2(mapGet, texts, [source]);
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
	const addListener = EventTarget.prototype.addEventListener;
	const apply$1 = Reflect.apply;
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
			apply$1(addListener, signal, [
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
//#region src/passkeys-hidden.ts
	const apply = Reflect.apply;
	const PagePromise = Promise;
	hidePasskeys();
	function hidePasskeys() {
		let real = window.PublicKeyCredential;
		if (!real) return;
		const extensionAnswers = extensionWatcher();
		try {
			Object.defineProperty(window, "PublicKeyCredential", {
				configurable: true,
				get: function() {
					return extensionAnswers() ? real : void 0;
				},
				set: function(value) {
					real = value;
				}
			});
		} catch {
			try {
				delete window.PublicKeyCredential;
			} catch {}
			return;
		}
		const proto = CredentialsContainer.prototype;
		const nativeGet = proto.get;
		const nativeCreate = proto.create;
		const replacements = {
			get(...args) {
				const options = args[0];
				if (!options || !options.publicKey) return apply(nativeGet, this, args);
				if (options.mediation === "conditional") return pendingUntilAborted(options.signal, (signal) => signal.reason || abortError());
				return PagePromise.reject(pageError("NotAllowedError"));
			},
			create(...args) {
				const options = args[0];
				if (!options || !options.publicKey) return apply(nativeCreate, this, args);
				return PagePromise.reject(pageError("NotAllowedError"));
			}
		};
		for (const name of ["get", "create"]) try {
			Object.defineProperty(proto, name, { value: replacements[name] });
		} catch {}
		presentAsNative([[replacements.get, nativeGet], [replacements.create, nativeCreate]]);
	}

//#endregion
})();