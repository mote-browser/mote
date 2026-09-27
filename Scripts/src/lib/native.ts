// Functions Mote puts in place of the page's own (`navigator.credentials.get`
// and the like), made to read as the browser's: `Function.prototype.toString`
// would otherwise show their source where WebKit's show `[native code]`.
//
// Used by the page-world passkey scripts. What it can't hide: a stack trace
// taken inside a call (a getter on the options the page passes, say) still
// lists Mote's frames, and a realm the scripts don't run in keeps the plain
// `toString`.

type AnyFunction = (...args: never[]) => unknown;

const apply = Reflect.apply;
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
export function presentAsNative(
  pairs: ReadonlyArray<readonly [ours: AnyFunction, native: AnyFunction]>,
): void {
  const proto = Function.prototype;
  const original = proto.toString;
  const text = (f: unknown): string => apply(original, f, []) as string;
  const texts = new Map<string, string>();
  const replaced = {
    toString(this: unknown): string {
      const source = apply(original, this, []) as string;
      const native = apply(mapGet, texts, [source]) as string | undefined;
      return native === undefined ? source : native;
    },
  }.toString;
  for (const [ours, native] of pairs) texts.set(text(ours), text(native));
  texts.set(text(replaced), text(original));
  try {
    Object.defineProperty(proto, 'toString', { value: replaced });
  } catch {
    // Left as it is when it can't be redefined.
  }
}
