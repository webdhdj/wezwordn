// WezWordnVaultHealthAdapter.swift — WezWordn AppIntegration (iOS only)
//
// The adapter between upstream Bitwarden's vault layer and WezWordn's
// VaultHealth reports.
//
// THE GAP THIS FILE EXISTS BECAUSE OF (verified against the upstream
// snapshot, not assumed):
//   * The decrypted-vault API for the UI layer is the public protocol
//     `VaultRepository` (BitwardenShared/Core/Vault/Repositories/
//     VaultRepository.swift).
//   * A live instance is reachable only through BitwardenShared's service
//     composition (`HasVaultRepository`), consumed by processors and
//     coordinators inside that framework. `ServiceContainer` is public,
//     but its `vaultRepository` / `stateService` properties are internal
//     to BitwardenShared — code in the app target (where these integration
//     files live) cannot read them, and there is no public accessor.
//   * Therefore nothing in the app target can conjure a VaultRepository on
//     its own. It must be HANDED one by BitwardenShared-side code — which
//     is exactly what patch 01's `WezWordnFeaturesPresenter` factory does:
//     `SettingsCoordinator` passes its real `services.vaultRepository`
//     into the factory registered by `WezWordnAppGlue`, and the glue builds
//     the concrete data source below.
//
// Data flow (all in-memory; decrypted items are never written to disk,
// UserDefaults, or the network by this layer):
//   VaultRepository.cipherPublisher()  -> first emission [CipherListView]
//   filter: login type, not deleted   -> ids
//   VaultRepository.fetchCipher(withId:) per id -> CipherView (decrypted)
//   CipherView/LoginView -> WezWordnCipherSnapshot -> WezWordnHealthMapper
//   -> [VaultHealthItem] -> VaultHealth.analyze(items:)
//
// API facts used below, each read from the snapshot (no invented names):
//   * `cipherPublisher() async throws -> AsyncThrowingPublisher<
//     AnyPublisher<[CipherListView], Error>>` (VaultRepository.swift).
//   * `fetchCipher(withId:) async throws -> CipherView?` (same file), and
//     the repository's own `fetchCipher(from cipherListView:)` extension
//     uses `cipherListView.id` the same way.
//   * `CipherListView.type.isLogin` and `CipherListView.deletedDate`
//     (BitwardenShared/Core/Vault/Extensions/CipherListView+Extensions.swift).
//   * `CipherView`: `id: String?`, `name: String`, `type` (compared with
//     `.login` in Core/Autofill/Services/AutofillCredentialService.swift),
//     `login: LoginView?`, `revisionDate: Date`, `deletedDate: Date?`
//     (memberwise use verified in UI/Vault/VaultItem/CipherItemState.swift
//     `newCipherView`).
//   * `LoginView`: `username: String?`, `password: String?`,
//     `totp: String?`, `uris: [LoginUriView]?` with `LoginUriView.uri:
//     String?` (UI/Vault/VaultItem/LoginItemState.swift `loginView`,
//     Core/Vault/Extensions/CipherView+Extensions.swift).

#if os(iOS)

import BitwardenSdk
import BitwardenShared
import Foundation
import VaultHealth

/// Source of decrypted vault items for the VaultHealth reports screen.
///
/// The protocol is the seam: `SecurityReportsView` depends only on this,
/// so its states (not connected / loading / loaded / failed) are honest —
/// when no source is installed the screen says so instead of pretending
/// the vault is empty.
public protocol WezWordnVaultHealthDataSource {
    /// Fetches the active account's decrypted login items as health
    /// inputs. Implementations must keep the decrypted data in memory
    /// only.
    func fetchHealthItems() async throws -> [VaultHealthItem]
}

/// The production data source, backed by upstream's real `VaultRepository`.
///
/// Constructed by `WezWordnAppGlue` with the repository instance forwarded
/// by `SettingsCoordinator` through the patch-01 presenter factory — see
/// the file header for why it cannot be constructed any other way.
public final class UpstreamVaultHealthDataSource: WezWordnVaultHealthDataSource {
    private let vaultRepository: any VaultRepository

    public init(vaultRepository: any VaultRepository) {
        self.vaultRepository = vaultRepository
    }

    public func fetchHealthItems() async throws -> [VaultHealthItem] {
        // First emission of the cipher list publisher: the current
        // decrypted list projection for the active account.
        let publisher = try await vaultRepository.cipherPublisher()
        var listViews: [CipherListView] = []
        for try await emission in publisher {
            listViews = emission
            break
        }

        // Login test by public pattern matching: the SDK's
        // `CipherListViewType.isLogin` helper lives in an internal
        // BitwardenShared extension and is not visible from the app
        // target (CI Run #24/#27 compile errors).
        let loginIDs = listViews
            .filter { $0.deletedDate == nil }
            .compactMap { listView -> String? in
                guard case .login = listView.type else { return nil }
                return listView.id
            }

        var snapshots: [WezWordnCipherSnapshot] = []
        snapshots.reserveCapacity(loginIDs.count)
        for id in loginIDs {
            // fetchCipher returns the fully decrypted CipherView. Items
            // that vanished mid-sync, are not logins, are in the trash, or
            // carry no login payload are skipped, never fabricated.
            // The operative login test here is the presence of the
            // decrypted login payload itself (`cipher.login`), which
            // the health mapper consumes; a bare `cipher.type`
            // comparison failed to type-check from the app target
            // (CI Run #24/#27) and adds nothing once the payload is
            // required anyway.
            guard let cipher = try await vaultRepository.fetchCipher(withId: id),
                  cipher.deletedDate == nil,
                  let login = cipher.login
            else { continue }
            snapshots.append(WezWordnCipherSnapshot(
                id: cipher.id ?? id,
                name: cipher.name,
                username: login.username,
                password: login.password,
                firstURI: login.uris?.first?.uri,
                revisionDate: cipher.revisionDate,
                hasTOTP: !(login.totp ?? "").isEmpty
            ))
        }
        return WezWordnHealthMapper.healthItems(from: snapshots)
    }
}

#endif
