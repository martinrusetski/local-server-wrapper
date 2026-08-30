//
//  Credential.swift
//  ServerAppBundle
//

import Foundation

struct Credential: Codable, Identifiable, Equatable {
    let id: UUID
    var username: String
    var password: String

    var usernameFieldId: String?
    var usernameFieldName: String?
    var passwordFieldId: String?
    var passwordFieldName: String?
    var formActionPath: String?
    var pagePath: String?
    /// The origin (scheme + host + port) the credential was captured on, e.g. "http://localhost:3000".
    /// Optional so older stored credentials (which lack it) still decode (TASK-8). Autofill requires
    /// an origin match, so legacy credentials without an origin are treated as no-match.
    var origin: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        username: String,
        password: String,
        usernameFieldId: String? = nil,
        usernameFieldName: String? = nil,
        passwordFieldId: String? = nil,
        passwordFieldName: String? = nil,
        formActionPath: String? = nil,
        pagePath: String? = nil,
        origin: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.username = username
        self.password = password
        self.usernameFieldId = usernameFieldId
        self.usernameFieldName = usernameFieldName
        self.passwordFieldId = passwordFieldId
        self.passwordFieldName = passwordFieldName
        self.formActionPath = formActionPath
        self.pagePath = pagePath
        self.origin = origin
        self.createdAt = createdAt
    }

    func matchesFingerprint(of other: Credential) -> Bool {
        // Same username on same form = duplicate
        guard self.username == other.username else { return false }

        // Must be the same origin, too. This also gives the TASK-8 migration path: a legacy
        // credential (origin == nil) is NOT a duplicate of a freshly-detected one (origin set),
        // so the save prompt re-appears and the user can re-save with an origin. Without this,
        // legacy credentials would block re-saving AND never autofill — a silent dead end.
        guard self.origin == other.origin else { return false }

        if let lhs = usernameFieldId, let rhs = other.usernameFieldId, lhs == rhs { return true }
        if let lhs = passwordFieldId, let rhs = other.passwordFieldId, lhs == rhs { return true }
        if let lhs = usernameFieldName, let rhs = other.usernameFieldName, lhs == rhs { return true }
        if let lhs = passwordFieldName, let rhs = other.passwordFieldName, lhs == rhs { return true }
        if let lhs = formActionPath, let rhs = other.formActionPath, lhs == rhs { return true }
        if let lhs = pagePath, let rhs = other.pagePath, lhs == rhs { return true }
        return false
    }

    /// Return a canonical HTTP(S) origin matching `window.location.origin`.
    /// Default ports are omitted because WebKit serializes them that way.
    static func normalizedOrigin(from url: URL?) -> String? {
        guard let url,
              let rawScheme = url.scheme,
              let rawHost = url.host else { return nil }

        let scheme = rawScheme.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = rawHost.lowercased()
        if let port = url.port,
           !((scheme == "http" && port == 80) || (scheme == "https" && port == 443)) {
            components.port = port
        }
        return components.string
    }

    static func normalizedOrigin(fromURLString urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        return normalizedOrigin(from: url)
    }
}
