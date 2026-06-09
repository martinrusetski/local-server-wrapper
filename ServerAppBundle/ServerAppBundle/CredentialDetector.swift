//
//  CredentialDetector.swift
//  ServerAppBundle
//

import Foundation
import WebKit
import os.log

private let logger = OSLog(subsystem: "com.localserverwrapper.serverappbundle", category: "credential-detector")

@MainActor
class CredentialDetector: NSObject, WKScriptMessageHandler {
    var onCredentialsSubmitted: ((Credential) -> Void)?

    private let detectionScript: String = {
        """
        (function() {
            if (window.__credentialDetectorInstalled) return;
            window.__credentialDetectorInstalled = true;
            console.log('[Credentials] Detector installed on', window.location.href);

            function detectCredentials(container) {
                var pw = container.querySelector('input[type="password"]');
                if (!pw) { console.log('[Credentials] No password field found'); return false; }
                if (!pw.value) { console.log('[Credentials] Password field is empty'); return false; }

                var form = pw.closest('form') || container;
                var inputs = form.querySelectorAll('input[type="text"], input[type="email"], input:not([type])');
                var user = null;
                for (var i = 0; i < inputs.length; i++) {
                    var inp = inputs[i];
                    if (inp !== pw && inp.offsetParent !== null && inp.type !== 'hidden' && inp.type !== 'submit' && inp.type !== 'button') {
                        user = inp;
                        break;
                    }
                }
                if (!user) { console.log('[Credentials] No username field found'); return false; }
                if (!user.value) { console.log('[Credentials] Username field is empty'); return false; }

                console.log('[Credentials] Detected: user=' + user.value + ' pw=' + (pw.value ? '***' : 'empty'));

                function fieldId(el) { return el.id || null; }
                function fieldName(el) { return el.name || null; }

                var actionPath = '/';
                try { actionPath = new URL(form.action || window.location.href).pathname; } catch(_) {}

                window.webkit.messageHandlers.credentialDetector.postMessage({
                    username: user.value,
                    password: pw.value,
                    usernameFieldId: fieldId(user),
                    usernameFieldName: fieldName(user),
                    passwordFieldId: fieldId(pw),
                    passwordFieldName: fieldName(pw),
                    formActionPath: actionPath,
                    pagePath: window.location.pathname
                });
                console.log('[Credentials] Message posted to Swift');
                return true;
            }

            function isSubmitElement(el) {
                if (el.type === 'submit') return true;
                if (el.tagName === 'BUTTON') {
                    var t = (el.type || '').toLowerCase();
                    if (t === '' || t === 'submit') return true;
                }
                var text = (el.textContent || el.value || '').toLowerCase();
                var classes = (el.className || '').toLowerCase();
                if (/\\blogin\\b|\\bsign\\s*in\\b|\\bsubmit\\b|\\blog\\s*in\\b/.test(text)) return true;
                if (/\\blogin\\b|\\bsignin\\b|\\bsubmit\\b/.test(classes)) return true;
                return false;
            }

            document.addEventListener('submit', function(e) {
                console.log('[Credentials] Form submit detected');
                try { detectCredentials(e.target); } catch(_) {}
            }, true);

            document.addEventListener('click', function(e) {
                try {
                    var el = e.target;
                    while (el && el !== document.body) {
                        if (el.tagName === 'BUTTON' || el.tagName === 'INPUT') break;
                        el = el.parentElement;
                    }
                    if (el && isSubmitElement(el)) {
                        console.log('[Credentials] Submit button clicked, will retry detection');
                        tryDetect(4);
                    }
                } catch(_) {}
            }, true);

            document.addEventListener('keydown', function(e) {
                try {
                    if (e.key === 'Enter' && e.target && e.target.type === 'password') {
                        console.log('[Credentials] Enter key in password field, will retry detection');
                        tryDetect(4);
                    }
                } catch(_) {}
            }, true);

            function tryDetect(retries) {
                if (retries <= 0) { console.log('[Credentials] Detection retries exhausted'); return; }
                if (detectCredentials(document)) return;
                setTimeout(function() { tryDetect(retries - 1); }, 300);
            }
        })();
        """
    }()

    func configure(_ userContentController: WKUserContentController) {
        userContentController.add(self, name: "credentialDetector")

        let userScript = WKUserScript(
            source: detectionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(userScript)
        os_log(.info, log: logger, "Credential detector configured")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "credentialDetector",
              let body = message.body as? [String: String] else { return }

        let credential = Credential(
            id: UUID(),
            username: body["username"] ?? "",
            password: body["password"] ?? "",
            usernameFieldId: nilIfEmpty(body["usernameFieldId"]),
            usernameFieldName: nilIfEmpty(body["usernameFieldName"]),
            passwordFieldId: nilIfEmpty(body["passwordFieldId"]),
            passwordFieldName: nilIfEmpty(body["passwordFieldName"]),
            formActionPath: nilIfEmpty(body["formActionPath"]),
            pagePath: nilIfEmpty(body["pagePath"]),
            createdAt: Date()
        )

        os_log(.info, log: logger, "Credential detected for user: %{public}@", credential.username)
        onCredentialsSubmitted?(credential)
    }

    private func nilIfEmpty(_ string: String?) -> String? {
        guard let string = string, !string.isEmpty else { return nil }
        return string
    }
}
