// The relay goes in once per page world, whichever copy comes first: Mote's
// own or the one an extension carries before its page-world scripts.
//
// The copies find each other with an event named at random for this launch
// (`PasskeyRelay.installed`): the first listens for it and cancels it; a later
// one dispatches it, and finds it cancelled. Nothing is left on any object and
// nothing goes in the global symbol registry, so a page reading properties or
// `Symbol.for` finds nothing.
//
// Limits: it holds while the name stays secret, and it does from pages as long
// as both copies run before any page script (at document start), taking the
// event functions they use as they start. An extension whose page-world
// scripts run later carries its copy late too: a page that replaced
// `dispatchEvent` by then sees that copy's one probe, and could learn the name
// and dispatch it to find Mote's relay. It works only between copies built in
// the same launch, which is all there are (ExtensionShims writes Mote's copy
// into extensions at each launch).

const apply = Reflect.apply;
const addListener = EventTarget.prototype.addEventListener;
const dispatch = EventTarget.prototype.dispatchEvent;
const PageEvent = Event;

/**
 * Whether this copy is the first on `target` to claim `name`; if so, it keeps
 * the claim, and `held` alive with it.
 */
export function claim(target: EventTarget, name: string, held?: unknown): boolean {
  const probe = new PageEvent(name, { cancelable: true });
  // Cancelled: another copy is in.
  if (!apply(dispatch, target, [probe])) return false;
  apply(addListener, target, [
    name,
    (event: Event): unknown => {
      event.preventDefault();
      return held;
    },
  ]);
  return true;
}
