//
//  CredentialAutoFill.swift
//  ServerAppBundle
//

import Foundation
import WebKit
import os.log

private let logger = OSLog(subsystem: "com.localserverwrapper.serverappbundle", category: "credential-autofill")

struct CredentialAutoFill {

    static func injectCredentials(_ credentials: [Credential], into webView: WKWebView) {
        // Enforce the origin boundary in native code before any secret crosses into WebKit.
        // The JavaScript origin check below remains as defense in depth for navigation races.
        let matchingCredentials = credentialsForInjection(credentials, pageURL: webView.url)
        guard !matchingCredentials.isEmpty else { return }

        guard let jsonData = try? JSONEncoder().encode(matchingCredentials) else {
            os_log(.error, log: logger, "Failed to encode credentials for auto-fill")
            return
        }
        // Base64 keeps user-controlled credential text out of the generated JavaScript syntax.
        let encodedJSON = jsonData.base64EncodedString()

        let js = """
        (function() {
            const credentialBytes = Uint8Array.from(atob('\(encodedJSON)'), function(c) { return c.charCodeAt(0); });
            const credentials = JSON.parse(new TextDecoder().decode(credentialBytes));

            function showDropdowns() {
                var existing = document.querySelector('.__credentialDropdown');
                if (existing) existing.parentNode.removeChild(existing);

                if (!credentials.length) return;

                var currentPath = window.location.pathname;
                var currentOrigin = window.location.origin;
                var matches = [];

                credentials.forEach(function(cred) {
                    // Require an origin match (scheme + host + port), not just a path match (TASK-8).
                    // Legacy credentials without an origin never match here.
                    if (!cred.origin || cred.origin !== currentOrigin) return;
                    if (cred.pagePath && cred.pagePath !== currentPath) return;

                    var pwField = findField(cred, 'password');
                    var userField = findField(cred, 'username') || (pwField ? findAdjacentUserField(pwField) : null);

                    if (!pwField || !userField) return;
                    if (pwField.value && userField.value) return;

                    matches.push({ cred: cred, userEl: userField, pwEl: pwField });
                });

                if (!matches.length) return;

                var anchor = matches[0].userEl;
                var rect = anchor.getBoundingClientRect();
                if (rect.width === 0 && rect.height === 0) return;

                var dropdown = document.createElement('div');
                dropdown.className = '__credentialDropdown';
                dropdown.style.cssText = 'position:fixed;left:' + rect.left + 'px;top:' + (rect.bottom + 4) + 'px;min-width:220px;z-index:2147483647;background:white;border:0.5px solid rgba(0,0,0,0.12);border-radius:8px;box-shadow:0 4px 16px rgba(0,0,0,0.12);font-family:-apple-system,BlinkMacSystemFont,sans-serif;font-size:13px;color:#1d1d1f;overflow:hidden;transition:opacity 0.15s';

                var header = document.createElement('div');
                header.innerHTML = '<svg width="14" height="14" viewBox="0 0 14 14" style="flex-shrink:0;margin-right:6px"><circle cx="7" cy="7" r="6" fill="none" stroke="#007AFF" stroke-width="1.5"/><rect x="4.5" y="6.5" width="5" height="4" rx="1" fill="#007AFF"/></svg><span style="color:#6e6e73;font-size:11px">PASSWORDS</span>';
                header.style.cssText = 'display:flex;align-items:center;padding:8px 12px 4px;border-bottom:1px solid rgba(0,0,0,0.06)';
                dropdown.appendChild(header);

                matches.forEach(function(match, i) {
                    var row = document.createElement('div');
                    row.innerHTML = '<svg width="14" height="14" viewBox="0 0 14 14" style="flex-shrink:0;margin-right:8px;opacity:0.4"><circle cx="7" cy="5" r="2.5" fill="none" stroke="currentColor" stroke-width="1.2"/><path d="M3 12c0-2.2 1.8-4 4-4s4 1.8 4 4" fill="none" stroke="currentColor" stroke-width="1.2"/></svg><span style="flex:1">' + escHtml(match.cred.username) + '</span><span style="font-size:11px;color:#007AFF">Fill</span>';
                    row.style.cssText = 'display:flex;align-items:center;padding:8px 12px;cursor:default;user-select:none;-webkit-user-select:none';
                    row.setAttribute('data-row', '1');

                    row.addEventListener('mouseenter', function() {
                        Array.from(dropdown.querySelectorAll('[data-row]')).forEach(function(r) { r.style.background = ''; });
                        row.style.background = 'rgba(0,122,255,0.08)';
                    });
                    row.addEventListener('mousedown', function(e) { e.preventDefault(); });
                    row.addEventListener('click', function(event) {
                        // Shared DOM nodes are visible to page scripts. Require a real user gesture
                        // so page-world code cannot call row.click() to extract the password field.
                        if (!event.isTrusted) return;
                        var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
                        setter.call(match.userEl, match.cred.username);
                        match.userEl.dispatchEvent(new Event('input', {bubbles: true}));
                        match.userEl.dispatchEvent(new Event('change', {bubbles: true}));
                        setter.call(match.pwEl, match.cred.password);
                        match.pwEl.dispatchEvent(new Event('input', {bubbles: true}));
                        match.pwEl.dispatchEvent(new Event('change', {bubbles: true}));
                        dropDismiss();
                    });

                    dropdown.appendChild(row);
                });

                document.body.appendChild(dropdown);

                function dropDismiss() {
                    if (!dropdown.parentNode) return;
                    dropdown.style.opacity = '0';
                    setTimeout(function() { if (dropdown.parentNode) dropdown.parentNode.removeChild(dropdown); }, 200);
                    document.removeEventListener('mousedown', onOutsideClick, true);
                    clearTimeout(dismissTimer);
                }

                function onOutsideClick(e) {
                    if (!dropdown.contains(e.target)) dropDismiss();
                }

                var dismissTimer = setTimeout(dropDismiss, 15000);
                setTimeout(function() {
                    document.addEventListener('mousedown', onOutsideClick, true);
                }, 100);
            }

            function findField(cred, type) {
                var fieldId = type === 'password' ? cred.passwordFieldId : cred.usernameFieldId;
                var fieldName = type === 'password' ? cred.passwordFieldName : cred.usernameFieldName;
                var pwCheck = type === 'password';

                if (fieldId) {
                    var f = document.getElementById(fieldId);
                    if (f && (!pwCheck || f.type === 'password') && f.offsetParent !== null) return f;
                }
                if (fieldName) {
                    var sel = 'input[name="' + fieldName.replace(/"/g, '\\\\"') + '"]';
                    var f = document.querySelector(sel);
                    if (f && f.offsetParent !== null) return f;
                }
                return null;
            }

            function findAdjacentUserField(pwField) {
                var form = pwField.closest('form');
                var container = form || document;
                var inputs = container.querySelectorAll('input[type="text"], input[type="email"], input:not([type])');
                for (var i = 0; i < inputs.length; i++) {
                    if (inputs[i].offsetParent !== null && inputs[i] !== pwField) return inputs[i];
                }
                return null;
            }

            function escHtml(s) {
                return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
            }

            // Show dropdown when focusing any credential field
            document.addEventListener('focusin', function(e) {
                var el = e.target;
                if (!el || !el.tagName || el.tagName !== 'INPUT') return;
                var isPw = el.type === 'password';
                var isUser = el.type === 'text' || el.type === 'email' || !el.type;
                if (!isPw && !isUser) return;
                showDropdowns();
            }, true);

            // Show immediately, then retry for slow SPAs that haven't rendered the form yet.
            // Bounded retries replace the old fixed Swift-side delay (TASK-12).
            var autofillAttempts = 0;
            function attemptShow() {
                showDropdowns();
                if (document.querySelector('.__credentialDropdown')) return; // dropdown shown, done
                if (autofillAttempts++ >= 20) return;                        // ~6s of retries, then stop
                setTimeout(attemptShow, 300);
            }
            attemptShow();
        })();
        """

        // Run in WebKit's isolated client world. Page scripts cannot access the credential array
        // or the listener closures; only the explicit user-selected field values cross to the DOM.
        webView.evaluateJavaScript(js, in: nil, in: .defaultClient) { result in
            if case .failure(let error) = result {
                os_log(.error, log: logger, "Auto-fill JS evaluation failed: %{public}@", error.localizedDescription)
            } else {
                os_log(.info, log: logger, "Credential auto-fill configured")
            }
        }
    }

    static func credentialsForInjection(_ credentials: [Credential], pageURL: URL?) -> [Credential] {
        guard let pageOrigin = Credential.normalizedOrigin(from: pageURL) else { return [] }
        return credentials.compactMap { credential in
            guard let origin = credential.origin,
                  let normalized = Credential.normalizedOrigin(fromURLString: origin) else { return nil }
            guard normalized == pageOrigin else { return nil }

            // Encode the canonical authorized origin so the isolated-world navigation-race check
            // uses the same representation as WebKit's window.location.origin.
            var authorizedCredential = credential
            authorizedCredential.origin = pageOrigin
            return authorizedCredential
        }
    }
}
