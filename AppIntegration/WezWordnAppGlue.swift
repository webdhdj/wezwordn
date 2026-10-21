// WezWordnAppGlue.swift — WezWordn AppIntegration (iOS only)
//
// Launch-time glue between the app target and BitwardenShared's settings
// flow. Called once from `AppDelegate` by patch 01-settings-entry (right
// after `DefaultAppModule` is built); the patch fails loudly at CI time if
// that call site ever disappears from upstream.
//
// What it registers: the `WezWordnFeaturesPresenter.viewControllerFactory`
// that `SettingsCoordinator.showWezWordnFeatures()` invokes. The factory
// receives the settings flow's real `VaultRepository` and builds the
// features UI with a production VaultHealth data source bound to it:
//
//   SettingsCoordinator (BitwardenShared)
//     └─ WezWordnFeaturesPresenter.makeViewController(vaultRepository:)
//          └─ this factory (app target)
//               └─ UIHostingController(WezWordnFeaturesRootView(
//                      healthDataSource: UpstreamVaultHealthDataSource(
//                          vaultRepository: <the forwarded instance>)))
//
// Without this registration the settings row still exists but the
// coordinator logs an error and pushes nothing — by design (see the
// presenter file added by patch 01), so a missing registration can never
// surface as a dead or fake screen.

#if os(iOS)

import BitwardenShared
import SwiftUI
import UIKit

/// App-target registration points for WezWordn's upstream seams.
public enum WezWordnAppGlue {
    /// Registers the WezWordn features view factory with
    /// `WezWordnFeaturesPresenter`. Call once at app launch, on the main
    /// actor (AppDelegate satisfies this).
    @MainActor
    public static func registerWezWordnFeatures() {
        WezWordnFeaturesPresenter.viewControllerFactory = { vaultRepository in
            UIHostingController(
                rootView: WezWordnFeaturesRootView(
                    healthDataSource: UpstreamVaultHealthDataSource(
                        vaultRepository: vaultRepository
                    )
                )
            )
        }
    }
}

#endif
