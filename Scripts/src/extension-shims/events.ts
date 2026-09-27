export type Listener = (...args: any[]) => any;

/** An event of a namespace or member the shim defines itself, fired by the shim. */
export interface ShimEvent {
  addListener(listener: Listener): unknown;
  removeListener(listener: Listener): unknown;
  hasListener(listener: Listener): boolean;
  hasListeners(): boolean;
  /** Read by the shim to fire the event, and to tell its events from WebKit's. */
  listeners: Set<Listener>;
}

export function createEvent(): ShimEvent {
  const listeners = new Set<Listener>();
  return {
    addListener: (listener) => listeners.add(listener),
    removeListener: (listener) => listeners.delete(listener),
    hasListener: (listener) => listeners.has(listener),
    hasListeners: () => listeners.size > 0,
    listeners,
  };
}

/** Whether `key` names an event (`onMessage`, `onClicked`). */
export function isEventName(key: string): boolean {
  return /^on[A-Z]/.test(key);
}

/** Every property name of `target` and its prototypes, up to `Object.prototype`. */
export function memberNames(target: object): Set<string> {
  const names = new Set<string>();
  for (let o: object | null = target; o && o !== Object.prototype; o = Object.getPrototypeOf(o)) {
    for (const key of Object.getOwnPropertyNames(o)) names.add(key);
  }
  return names;
}

/** Throws `error` outside the current call, so a failing listener is reported but stops nothing. */
export function rethrowLater(error: unknown): void {
  setTimeout(() => {
    throw error;
  });
}
