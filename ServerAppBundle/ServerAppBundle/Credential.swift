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
        self.createdAt = createdAt
    }

    func matchesFingerprint(of other: Credential) -> Bool {
        // Same username on same form = duplicate
        guard self.username == other.username else { return false }

        if let lhs = usernameFieldId, let rhs = other.usernameFieldId, lhs == rhs { return true }
        if let lhs = passwordFieldId, let rhs = other.passwordFieldId, lhs == rhs { return true }
        if let lhs = usernameFieldName, let rhs = other.usernameFieldName, lhs == rhs { return true }
        if let lhs = passwordFieldName, let rhs = other.passwordFieldName, lhs == rhs { return true }
        if let lhs = formActionPath, let rhs = other.formActionPath, lhs == rhs { return true }
        if let lhs = pagePath, let rhs = other.pagePath, lhs == rhs { return true }
        return false
    }
}
