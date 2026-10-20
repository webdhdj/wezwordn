import Foundation

/// A login item whose username, email and password are fully independent fields.
/// Rationale: Bitwarden's legacy `Login.username` is routinely (ab)used to store
/// an email address. Keeping a separate, encrypted-at-rest `email` field avoids
/// overloading `username`, keeps AutoFill semantics intact, and lets search /
/// copy act on each value individually.
public struct ExtendedLogin: Codable, Equatable {
    public var username: String?
    public var email: String?
    public var password: String?

    public init(username: String? = nil, email: String? = nil, password: String? = nil) {
        self.username = username
        self.email = email
        self.password = password
    }

    /// Case-insensitive substring search over BOTH username and email.
    /// An empty / whitespace-only query matches everything (caller is listing).
    public func matches(search query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        if let u = username, u.lowercased().contains(q) { return true }
        if let e = email, e.lowercased().contains(q) { return true }
        return false
    }

    /// Deliberately simple, documented email format check (not full RFC 5322):
    /// exactly one '@', non-empty local part, domain containing at least one
    /// dot with non-empty labels, and no whitespace anywhere.
    public static func isValidEmail(_ value: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
            && !value.contains(" ")
    }

    public var emailIsValid: Bool {
        guard let email, !email.isEmpty else { return false }
        return Self.isValidEmail(email)
    }
}

/// The legacy (pre-extension) login shape: a single username field only.
public struct LegacyLogin: Codable, Equatable {
    public var username: String?
    public var password: String?
    public init(username: String? = nil, password: String? = nil) {
        self.username = username
        self.password = password
    }
}

extension ExtendedLogin {
    /// Migration from the legacy model.
    ///
    /// Decision (documented): if the legacy `username` is email-shaped and no
    /// email exists yet, we COPY it into `email` and KEEP `username` unchanged.
    /// We do not clear/move it out of `username`, because existing AutoFill
    /// rules, URI matching and synced Bitwarden data key off `username`;
    /// clearing it would silently break AutoFill for migrated items and would
    /// diverge from the server-side record. Duplication is harmless: the user
    /// can clear `username` explicitly in the editor if it was only an email.
    /// No data is ever dropped by this migration.
    public static func migrate(legacy: LegacyLogin) -> ExtendedLogin {
        var email: String? = nil
        if let u = legacy.username, isValidEmail(u) {
            email = u
        }
        return ExtendedLogin(username: legacy.username, email: email, password: legacy.password)
    }

    /// Convenience initialiser performing the same migration.
    public init(legacy: LegacyLogin) {
        self = Self.migrate(legacy: legacy)
    }
}
