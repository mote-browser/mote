// The bridge WebKit gives scripts in the content world a message handler was
// added to. Handlers are optional: a script must not assume Swift listens.

interface WebKitMessageHandler {
  postMessage(message: unknown): void;
}

interface Window {
  webkit: { messageHandlers: Record<string, WebKitMessageHandler | undefined> };
}
