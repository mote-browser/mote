import Foundation
import Testing

@testable import Mote

/// WebKit's delegate methods are optional, so a Swift signature that stops
/// matching the SDK (after an SDK or language-mode change) compiles with only a
/// warning, and WebKit silently stops calling it. These tests fail instead.
@Suite("WebKit delegates")
@MainActor
struct DelegateConformanceTests {
    @Test(
        "The browser implements the navigation, UI and download delegate methods it relies on",
        arguments: [
            "webView:decidePolicyForNavigationAction:decisionHandler:",
            "webView:decidePolicyForNavigationResponse:decisionHandler:",
            "webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:",
            "webView:navigationAction:didBecomeDownload:",
            "webView:navigationResponse:didBecomeDownload:",
            "webView:requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:",
            "webView:didFailNavigation:withError:",
            "webView:didFailProvisionalNavigation:withError:",
            "webView:didCommitNavigation:",
            "webView:didFinishNavigation:",
            "webView:didReceiveAuthenticationChallenge:completionHandler:",
            "webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:",
            "webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:",
            "webView:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:completionHandler:",
            "webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:",
            "webViewWebContentProcessDidTerminate:",
            "download:decideDestinationUsingResponse:suggestedFilename:completionHandler:",
            "download:didFailWithError:resumeData:",
        ])
    func browser(selector: String) {
        #expect(Browser.instancesRespond(to: NSSelectorFromString(selector)))
    }

    @Test(
        "Extensions implement the extension controller delegate methods",
        arguments: [
            "webExtensionController:openWindowsForExtensionContext:",
            "webExtensionController:focusedWindowForExtensionContext:",
            "webExtensionController:openNewWindowUsingConfiguration:forExtensionContext:completionHandler:",
            "webExtensionController:openNewTabUsingConfiguration:forExtensionContext:completionHandler:",
            "webExtensionController:openOptionsPageForExtensionContext:completionHandler:",
            "webExtensionController:promptForPermissions:inTab:forExtensionContext:completionHandler:",
            "webExtensionController:promptForPermissionToAccessURLs:inTab:forExtensionContext:completionHandler:",
            "webExtensionController:promptForPermissionMatchPatterns:inTab:forExtensionContext:completionHandler:",
            "webExtensionController:didUpdateAction:forExtensionContext:",
            "webExtensionController:presentPopupForAction:forExtensionContext:completionHandler:",
            "webExtensionController:sendMessage:toApplicationWithIdentifier:forExtensionContext:replyHandler:",
            "webExtensionController:connectUsingMessagePort:forExtensionContext:completionHandler:",
        ])
    @available(macOS 15.4, *)
    func extensions(selector: String) {
        #expect(Extensions.instancesRespond(to: NSSelectorFromString(selector)))
    }
}
