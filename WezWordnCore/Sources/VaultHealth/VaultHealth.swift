import Foundation

public struct VaultHealthItem: Equatable {
    public var id: String
    public var domain: String
    public var username: String?
    public var email: String?
    public var password: String
    public var updatedAt: Date
    public var hasTOTP: Bool
    public init(id: String, domain: String, username: String? = nil, email: String? = nil,
                password: String, updatedAt: Date, hasTOTP: Bool) {
        self.id = id; self.domain = domain; self.username = username; self.email = email
        self.password = password; self.updatedAt = updatedAt; self.hasTOTP = hasTOTP
    }
}

public enum HealthIssueKind: String, Equatable {
    case weak, reused, old, duplicateAccount, missingTOTP, missingIdentity
}

public struct HealthIssue: Equatable {
    public var itemID: String
    public var kind: HealthIssueKind
    public var detail: String
    public init(itemID: String, kind: HealthIssueKind, detail: String) {
        self.itemID = itemID; self.kind = kind; self.detail = detail
    }
}

public struct HealthReport: Equatable {
    public var totalCount: Int
    public var weakCount: Int
    public var reusedCount: Int
    public var oldCount: Int
    public var duplicateAccountCount: Int
    public var missingTOTPCount: Int
    public var missingIdentityCount: Int
    public var highRiskCount: Int // weak AND (reused OR in a duplicate group) -- documented heuristic
    public var score: Int // 0...100, see VaultHealth.scoreFormula documentation
    public var issues: [HealthIssue]
}

public enum VaultHealth {
    /// Small built-in common-password list (offline; intentionally tiny and
    /// documented as such -- it is a heuristic signal, not a breach corpus).
    static let commonPasswords: Set<String> = [
        "password", "password1", "123456", "12345678", "123456789", "12345",
        "qwerty", "qwerty123", "letmein", "admin", "welcome", "iloveyou",
        "football", "monkey", "dragon", "master", "sunshine", "princess",
        "passw0rd", "shadow", "superman", "trustno1",
    ]

    /// Estimated entropy in bits: length * log2(poolSize), where poolSize is
    /// summed from present character classes (lower 26, upper 26, digits 10,
    /// symbols 33, other/unicode 100). Documented estimate, not a strength proof.
    public static func estimatedEntropyBits(_ password: String) -> Double {
        if password.isEmpty { return 0 }
        var pool = 0
        var hasLower = false, hasUpper = false, hasDigit = false, hasSymbol = false, hasOther = false
        for scalar in password.unicodeScalars {
            switch scalar.value {
            case 97...122: hasLower = true
            case 65...90: hasUpper = true
            case 48...57: hasDigit = true
            case 33...47, 58...64, 91...96, 123...126: hasSymbol = true
            default: hasOther = true
            }
        }
        if hasLower { pool += 26 }
        if hasUpper { pool += 26 }
        if hasDigit { pool += 10 }
        if hasSymbol { pool += 33 }
        if hasOther { pool += 100 }
        guard pool > 1 else { return 0 }
        return Double(password.count) * log2(Double(pool))
    }

    /// Weak iff: length < 12, OR lowercased password is in the common list,
    /// OR estimated entropy < 45 bits, OR it uses 3 or fewer distinct
    /// characters (e.g. "aaaaaaaaaaaaaa" -- the pool-based entropy estimate
    /// alone overrates such passwords, so this rule is explicit).
    /// (Any one condition suffices.)
    public static func isWeak(_ password: String) -> Bool {
        if password.count < 12 { return true }
        if commonPasswords.contains(password.lowercased()) { return true }
        if estimatedEntropyBits(password) < 45 { return true }
        if Set(password).count <= 3 { return true }
        return false
    }

    /// Score formula (documented): start at 100 and subtract, proportionally
    /// to the share of affected items: weak 30 * weakRatio, reused 25 *
    /// reusedRatio, missingTOTP 20 * missingTOTPRatio, old 15 * oldRatio,
    /// duplicateAccount 10 * duplicateRatio. Result is rounded and clamped
    /// to 0...100. An empty vault scores 100 (nothing at risk).
    public static func analyze(items: [VaultHealthItem], now: Date = Date()) -> HealthReport {
        var issues: [HealthIssue] = []
        let total = items.count
        guard total > 0 else {
            return HealthReport(totalCount: 0, weakCount: 0, reusedCount: 0, oldCount: 0,
                                duplicateAccountCount: 0, missingTOTPCount: 0, missingIdentityCount: 0,
                                highRiskCount: 0, score: 100, issues: [])
        }
        // Reuse: identical non-empty passwords shared by >1 item.
        var byPassword: [String: [String]] = [:]
        for item in items where !item.password.isEmpty { byPassword[item.password, default: []].append(item.id) }
        let reusedIDs = Set(byPassword.values.filter { $0.count > 1 }.flatMap { $0 })
        // Duplicates: same normalised domain+username in >1 item.
        var byAccount: [String: [String]] = [:]
        for item in items {
            let key = item.domain.lowercased() + "|" + (item.username ?? "").lowercased()
            if !(item.username ?? "").isEmpty { byAccount[key, default: []].append(item.id) }
        }
        let dupIDs = Set(byAccount.values.filter { $0.count > 1 }.flatMap { $0 })

        var weak = 0, reused = 0, old = 0, dup = 0, noTOTP = 0, noIdentity = 0, highRisk = 0
        let oldThreshold = now.addingTimeInterval(-365 * 24 * 3600)
        for item in items {
            let isW = isWeak(item.password)
            let isR = reusedIDs.contains(item.id)
            if isW { weak += 1; issues.append(HealthIssue(itemID: item.id, kind: .weak, detail: "Weak password (length/common/entropy heuristic)")) }
            if isR { reused += 1; issues.append(HealthIssue(itemID: item.id, kind: .reused, detail: "Password reused across multiple items")) }
            if item.updatedAt < oldThreshold { old += 1; issues.append(HealthIssue(itemID: item.id, kind: .old, detail: "Not updated in over 365 days")) }
            if dupIDs.contains(item.id) { dup += 1; issues.append(HealthIssue(itemID: item.id, kind: .duplicateAccount, detail: "Same domain+username as another item")) }
            if !item.hasTOTP { noTOTP += 1; issues.append(HealthIssue(itemID: item.id, kind: .missingTOTP, detail: "No TOTP configured")) }
            if (item.username ?? "").isEmpty && (item.email ?? "").isEmpty {
                noIdentity += 1; issues.append(HealthIssue(itemID: item.id, kind: .missingIdentity, detail: "Both username and email are missing"))
            }
            if isW && (isR || dupIDs.contains(item.id)) { highRisk += 1 }
        }
        let r = { (n: Int) in Double(n) / Double(total) }
        let raw = 100 - 30 * r(weak) - 25 * r(reused) - 20 * r(noTOTP) - 15 * r(old) - 10 * r(dup)
        let score = max(0, min(100, Int(raw.rounded())))
        return HealthReport(totalCount: total, weakCount: weak, reusedCount: reused, oldCount: old,
                            duplicateAccountCount: dup, missingTOTPCount: noTOTP, missingIdentityCount: noIdentity,
                            highRiskCount: highRisk, score: score, issues: issues)
    }
}
