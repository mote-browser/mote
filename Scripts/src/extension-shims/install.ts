// Installs the shim, in this order: each step may build on what the ones
// before it set (a wrapper wraps what an earlier step defined).
// Defines only APIs that are missing, so native WebKit implementations take precedence.

import { fillAction, tellPopups } from './action';
import { nativeRequest, replyValue, APPLICATION } from './callbacks';
import { fillDeclarativeNetRequest, mendRules } from './declarative-net-request';
import { forwardThroughWorker } from './embedded';
import {
  carriesExtensionAPIs,
  isBackground,
  isContentScript,
  isEmbedded,
  isServiceWorker,
} from './environment';
import { reportErrors } from './error-reporting';
import { rebuildFileSystem } from './file-system';
import { fixChromeGlobals, keepCredentials, markInstalled, polyfillIdleCallback } from './globals';
import { bindRuntimeMethods, createHolder, holdNamespaces, lastErrorReporter } from './holding';
import { acceptLateListeners, mendInstalledReason } from './lifecycle';
import {
  fillExtension,
  fillRuntime,
  fillScripting,
  fillWebNavigation,
  fillWindows,
  resourceTypes,
} from './members';
import { fillMenus, mendMenus } from './menus';
import { createVerdicts } from './message-verdicts';
import { createGather } from './messaging';
import { addBrowserMembers, addIdleStateEvent, defineBrowserNamespaces, defineSystem } from './namespaces';
import { holdEarlyNativeMessages } from './native-ports';
import { mendPermissions } from './permissions';
import { mendPopup } from './popup';
import { numberOwnPorts } from './port-numbering';
import { mendReplies } from './replies';
import { defineContentSettings, definePrivacy, defineProxy } from './settings';
import { fillStorage, storePlainItems } from './storage';
import { describeTabs, fillTabs, fillTabsByIndex } from './tabs';
import type { Root, Shim, ShimConfig } from './types';
import { defineUnavailable } from './unavailable';
import { presentAsChrome } from './user-agent';
import { defineUserScripts, patchPasskeysFirst } from './user-scripts';
import { compileWasmWhole } from './wasm';
import { fillWebRequest, mendRequestListeners } from './web-request';
import { replaceWorkerWebSocket } from './web-socket';
import { addInstallRoutes, checkImportedScripts } from './worker-fixes';

export function install(root: Root, config: ShimConfig): void {
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
  const shim: Shim = {
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
    withLastError: lastErrorReporter(runtime, put),
  };

  // Where WebKit's worker behaves unlike Chrome's, and what every context shares.
  addInstallRoutes(shim);
  replaceWorkerWebSocket(shim);
  holdEarlyNativeMessages(shim);
  presentAsChrome(shim);
  checkImportedScripts(shim);
  const verdicts = createVerdicts(shim);
  const gather = createGather(shim, verdicts);
  bindRuntimeMethods(runtime, put);
  if (inContent) return;

  // Messages between the extension's own pages and its worker.
  forwardThroughWorker(shim);
  mendReplies(shim, verdicts);
  gather(runtime && runtime.onMessage, true);
  gather(runtime && runtime.onMessageExternal);

  // Namespaces WebKit lacks.
  defineBrowserNamespaces(shim);
  addIdleStateEvent(shim);
  defineSystem(shim);
  definePrivacy(shim);
  defineContentSettings(shim);
  defineProxy(shim);
  defineUnavailable(shim);
  compileWasmWhole(root);

  // Members of the namespaces WebKit has.
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
