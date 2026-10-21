// WezWordnHealthMapping.swift — WezWordn AppIntegration
//
// Pure mapping from decrypted-vault snapshots to VaultHealth inputs.
//
// This file deliberately imports only Foundation + the VaultHealth core
// module — no BitwardenSdk, no BitwardenShared, no SwiftUI — so the mapping
// rules stay unit-testable anywhere (including the Linux CI job that runs
// WezWordnCore's tests) and reviewable without the upstream SDK. The
// SDK-facing half lives in WezWordnVaultHealthAdapter.swift, which builds
// these snapshots from real `CipherView`s and delegates the conversion here.
//
// Mapping rules (documented, no hidden behaviour):
//   * Items with a nil or empty password are SKIPPED: VaultHealthItem's
//     password is non-optional and a password-health analysis has nothing
//     to say about an item that has no password.
//   * `domain` is the host of the first login URI when it parses as a URL;
//     otherwise the raw first URI; otherwise the cipher's display name.
//   * `email` mirrors the documented ExtendedLoginFields legacy migration:
//     a username that is email-shaped (contains "@") is ALSO copied into
//     `email`, but kept in `username` (Bitwarden's single login field is
//     what AutoFill uses). Non-email usernames leave `email` nil.
//   * `updatedAt` is the cipher's revisionDate (last modification), which
//     is what the "old password" heuristic must measure.
//   * `hasTOTP` is true iff the login carries a non-empty TOTP secret.

import Foundation
import VaultHealth

/// A decrypted login cipher reduced to exactly the fields VaultHealth
/// needs. Produced by `UpstreamVaultHealthDataSource` from upstream's
/// `CipherView`/`LoginView`; consumed by `WezWordnHealthMapper`.
public struct WezWordnCipherSnapshot: Equatable {
    public var id: String
    public var name: String
    public var username: String?
    public var password: String?
    public var firstURI: String?
    public var revisionDate: Date
    public var hasTOTP: Bool

    public init(
        id: String,
        name: String,
        username: String?,
        password: String?,
        firstURI: String?,
        revisionDate: Date,
        hasTOTP: Bool
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.password = password
        self.firstURI = firstURI
        self.revisionDate = revisionDate
        self.hasTOTP = hasTOTP
    }
}

/// Converts `WezWordnCipherSnapshot`s into `VaultHealthItem`s.
public enum WezWordnHealthMapper {
    /// Converts one snapshot, or returns `nil` when the item has no
    /// password to analyse (see the mapping rules at the top of this file).
    public static func healthItem(from snapshot: WezWordnCipherSnapshot) -> VaultHealthItem? {
        guard let password = snapshot.password, !password.isEmpty else { return nil }
        let domain = domainName(firstURI: snapshot.firstURI, fallbackName: snapshot.name)
        let username = snapshot.username
        let email = (username?.contains("@") == true) ? username : nil
        return VaultHealthItem(
            id: snapshot.id,
            domain: domain,
            username: username,
            email: email,
            password: password,
            updatedAt: snapshot.revisionDate,
            hasTOTP: snapshot.hasTOTP
        )
    }

    /// Converts a batch of snapshots, skipping password-less items and
    /// preserving order.
    public static func healthItems(from snapshots: [WezWordnCipherSnapshot]) -> [VaultHealthItem] {
        snapshots.compactMap(healthItem(from:))
    }

    /// Host of the first URI when parseable, else the raw URI, else the
    /// cipher's display name.
    static func domainName(firstURI: String?, fallbackName: String) -> String {
        guard let firstURI, !firstURI.isEmpty else { return fallbackName }
        if let host = URL(string: firstURI)?.host, !host.isEmpty {
            return host
        }
        return firstURI
    }
}
