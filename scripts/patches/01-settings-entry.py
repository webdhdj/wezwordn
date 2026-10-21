#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
01-settings-entry.py — WezWordn Phase B patch: صف "WezWordn Features" في إعدادات upstream
========================================================================================

الغرض
-----
الـ CI يجلب upstream Bitwarden iOS طازجًا في كل تشغيل، فلا يمكن تعديل ملفاته
يدويًا. هذا السكربت يُطبَّق على شجرة upstream بعد الجلب (وقبل توليد مشاريع
XcodeGen) ويحقن سلسلة التنقّل الكاملة بأسلوب upstream نفسه:

    SettingsView row ──store.send(.wezWordnFeaturesPressed)──▶ SettingsAction
    SettingsProcessor.receive ──coordinator.navigate(to: .wezWordnFeatures)──▶ SettingsRoute
    SettingsCoordinator.navigate ──▶ showWezWordnFeatures() ──▶ push(UIViewController)

ما وُجد في لقطة upstream الحالية (كل مرساة أدناه من قراءة فعلية للملفات)
------------------------------------------------------------------------
- شاشة الإعدادات: BitwardenShared/UI/Platform/Settings/Settings/SettingsView.swift
  الصفوف مكوّنات `SettingsListItem(Localizations.x, icon: SharedAsset.Icons.y) {
  store.send(.zPressed) } trailingContent: { chevron }` داخل `settingsItems`
  (ContentBlock)؛ فرع ما بعد تسجيل الدخول: accountSecurityRow, autofillRow,
  vaultRow, [planRow], appearanceRow, otherRow, aboutRow.
- الإجراءات: Settings/SettingsAction.swift — `enum SettingsAction: Equatable`.
- المعالج: Settings/SettingsProcessor.swift — `receive(_:)` يربط كل إجراء بـ
  `coordinator.navigate(to:)`؛ خدماته تشمل HasVaultRepository وHasStateService.
- المسارات: BitwardenShared/UI/Platform/Settings/SettingsRoute.swift —
  `public enum SettingsRoute: Equatable, Hashable`.
- المنسّق: BitwardenShared/UI/Platform/Settings/SettingsCoordinator.swift —
  `navigate(to:)` switch شامل، ودوال `showX()` تبني Processor+View وتلفّها في
  `UIHostingController` ثم `stackNavigator?.push(viewController,
  navigationTitle:)`؛ خدمات المنسّق تشمل HasVaultRepository وHasErrorReporter.
- التجميع: `DefaultAppModule` معرّف داخل BitwardenShared نفسه
  (UI/Platform/Application/AppModule.swift) ويُبنى في هدف التطبيق:
  Bitwarden/Application/AppDelegate.swift سطر 46:
  `let appModule = DefaultAppModule(services: services)`.

الفجوة المعمارية وخط التماس (seam) — اقرأ قبل الحكم على التصميم
----------------------------------------------------------------
`WezWordnFeaturesRootView` يعيش في هدف التطبيق (Bitwarden) عبر ملفات
AppIntegration، بينما كل سلسلة الإعدادات أعلاه داخل إطار BitwardenShared.
اتجاه التبعية أحادي (التطبيق ← BitwardenShared)؛ لا يستطيع المنسّق تسمية
نوع من هدف التطبيق. الحلول الممكنة:
  (أ) نقل ملفات التكامل إلى هدف BitwardenShared وربط منتجات WezWordnCore به
      (تغيير في bootstrap/project-*.yml — خارج نطاق هذا الـ patch).
  (ب) خط تماس مصنعي داخل BitwardenShared — وهو المنفَّذ هنا:
      يضيف هذا الـ patch ملفًا جديدًا إلى BitwardenShared:
        BitwardenShared/UI/Platform/Settings/WezWordnFeatures/WezWordnFeaturesPresenter.swift
      يعرّف `WezWordnFeaturesPresenter` العلني: مصنع اختياري
      `(@MainActor (any VaultRepository) -> UIViewController)?` يسجّله هدف
      التطبيق عند الإقلاع (عبر `WezWordnAppGlue.registerWezWordnFeatures()`
      من AppIntegration، ويستدعيه الـ patch نفسه من AppDelegate بعد بناء
      DefaultAppModule). المنسّق يمرّر `services.vaultRepository` الحقيقي
      للمصنع، فيحصل الـ View على VaultRepository الأصلي عبر
      UpstreamVaultHealthDataSource دون أي singleton أو بحث runtime بالاسم.
      إن لم يُسجَّل مصنع (سياق امتداد مثلًا) يُسجَّل خطأ عبر
      `services.errorReporter` ولا يُدفع أي View — لا واجهة بديلة وهمية.
أهداف XcodeGen تستخدم `sourcesPath: BitwardenShared` (project-pm.yml) أي
التقاطًا بالمجلد، فالملف الجديد يدخل هدف BitwardenShared تلقائيًا عند إعادة
التوليد التي يجريها الـ CI أصلًا.

قراران موثّقان:
- عنوان الصف حرفي "WezWordn Features" لا مفتاح Localizations: مفاتيح
  BitwardenResources مولّدة بـ SwiftGen من ملفات .strings، وإضافة مفتاح
  تتطلب تعديل موارد upstream وإعادة توليد — خارج نطاق patch نصّي آمن.
- الأيقونة SharedAsset.Icons.locked24 (موجودة مولّدة ومستعملة في صف
  accountSecurity): إضافة أصل جديد تتطلب تعديل Asset Catalog.

عمليات الـ patch (anchor → إدراج) — كل مرساة يجب أن توجد مرة واحدة بالضبط
----------------------------------------------------------------------------
1) SettingsRoute.swift        : بعد case vaultUnlockSetup ← case wezWordnFeatures
2) SettingsAction.swift       : بعد case vaultPressed ← case wezWordnFeaturesPressed
3) SettingsProcessor.swift    : بعد case .vaultPressed ← ربط .wezWordnFeaturesPressed
4) SettingsView.swift         : بعد vaultRow في settingsItems ← wezWordnFeaturesRow
                                + خاصية الصف قبل خاصية vaultRow
5) SettingsCoordinator.swift  : بعد case .vault في navigate ← case .wezWordnFeatures
                                + دالة showWezWordnFeatures() بعد showVault()
6) Bitwarden/Application/AppDelegate.swift
                              : بعد سطر DefaultAppModule ← استدعاء تسجيل الـ Glue
7) ملف جديد: WezWordnFeaturesPresenter.swift (الوصف أعلاه)

سلوك الفشل: مرحلتان — التحقق من كل المراسي أولًا، ولا يُكتب أي ملف قبل نجاح
التحقق كاملًا. غياب مرساة أو تكرارها أو وجود علامة الـ patch مسبقًا = خروج
غير صفري دون أي تعديل.

الاستعمال:
    python3 01-settings-entry.py <upstream_root>           # تطبيق
    python3 01-settings-entry.py --verify <upstream_root>  # تحقق فقط (dry-run)

حدود التحقق هنا: هذا السكربت يعدّل نصوصًا فقط. سلامة الأنواع (أنواع
SettingsListItem، شمولية switch في اختبارات upstream، إعادة تسجيل
snapshot tests لشاشة الإعدادات) لا تُحسم إلا ببناء macOS في الـ CI.
"""

import sys
from pathlib import Path

PRESENTER_PATH = "BitwardenShared/UI/Platform/Settings/WezWordnFeatures/WezWordnFeaturesPresenter.swift"

PRESENTER_CONTENT = '''import UIKit

// MARK: - WezWordnFeaturesPresenter

/// The presentation seam for the WezWordn features screen. (WezWordn patch 01)
///
/// Why this exists: the settings navigation stack (`SettingsView`,
/// `SettingsProcessor`, `SettingsCoordinator`) lives in the `BitwardenShared`
/// framework, while the WezWordn features UI (`WezWordnFeaturesRootView`)
/// lives in the app target. The dependency direction is one-way (app target
/// depends on `BitwardenShared`), so the coordinator cannot name the app
/// target's view type.
///
/// The host app therefore registers a factory at launch (from
/// `AppDelegate`, via the app target's `WezWordnAppGlue`). When the user
/// opens the WezWordn Features settings row, `SettingsCoordinator` passes
/// its real `VaultRepository` to the factory, so the features UI receives
/// the genuine upstream repository — no singletons, no runtime name lookup,
/// no mock data path.
///
/// If no factory is registered (for example in an app-extension process
/// that never ran the registration), `makeViewController` returns `nil` and
/// the coordinator logs an error instead of pushing anything.
@MainActor
public enum WezWordnFeaturesPresenter {
    /// Builds the WezWordn features view controller from the settings
    /// flow's `VaultRepository`.
    public typealias ViewControllerFactory = @MainActor (any VaultRepository) -> UIViewController

    /// The factory registered by the host app at launch, if any.
    public static var viewControllerFactory: ViewControllerFactory?

    /// Builds the features view controller using the registered factory.
    ///
    /// - Parameter vaultRepository: The settings flow's vault repository,
    ///     forwarded to the features UI so it can read the decrypted vault.
    /// - Returns: The view controller to push, or `nil` if the host app did
    ///     not register a factory.
    ///
    static func makeViewController(vaultRepository: any VaultRepository) -> UIViewController? {
        viewControllerFactory?(vaultRepository)
    }
}
'''

# Each op: (relative path, mode, anchor, insertion)
#   mode "after":  result = anchor + "\n" + insertion
#   mode "before": result = insertion + "\n" + anchor
OPS = [
    (
        "BitwardenShared/UI/Platform/Settings/SettingsRoute.swift",
        "after",
        """    /// A route to the vault unlock setup screen.
    case vaultUnlockSetup""",
        """
    /// A route to the WezWordn features screen. (WezWordn patch 01)
    case wezWordnFeatures""",
    ),
    (
        "BitwardenShared/UI/Platform/Settings/Settings/SettingsAction.swift",
        "after",
        """    /// The vault button was pressed.
    case vaultPressed""",
        """
    /// The WezWordn features button was pressed. (WezWordn patch 01)
    case wezWordnFeaturesPressed""",
    ),
    (
        "BitwardenShared/UI/Platform/Settings/Settings/SettingsProcessor.swift",
        "after",
        """        case .vaultPressed:
            coordinator.navigate(to: .vault)""",
        """        case .wezWordnFeaturesPressed:
            coordinator.navigate(to: .wezWordnFeatures)""",
    ),
    (
        "BitwardenShared/UI/Platform/Settings/Settings/SettingsView.swift",
        "after",
        """                accountSecurityRow
                autofillRow
                vaultRow""",
        """                wezWordnFeaturesRow""",
    ),
    (
        "BitwardenShared/UI/Platform/Settings/Settings/SettingsView.swift",
        "before",
        """    /// The vault settings row.
    private var vaultRow: some View {""",
        """    /// The WezWordn features settings row. (WezWordn patch 01)
    ///
    /// The title is a literal brand string rather than a `Localizations`
    /// key: resource keys are SwiftGen-generated from upstream's .strings
    /// files, which this patch deliberately does not modify. The icon is
    /// the existing generated `locked24` asset.
    private var wezWordnFeaturesRow: some View {
        SettingsListItem(
            "WezWordn Features",
            icon: SharedAsset.Icons.locked24,
        ) {
            store.send(.wezWordnFeaturesPressed)
        } trailingContent: {
            chevron
        }
        .accessibilityIdentifier("WezWordnFeaturesSettingsButton")
    }
""",
    ),
    (
        "BitwardenShared/UI/Platform/Settings/SettingsCoordinator.swift",
        "after",
        """        case .vault:
            showVault()""",
        """        case .wezWordnFeatures:
            showWezWordnFeatures()""",
    ),
    (
        "BitwardenShared/UI/Platform/Settings/SettingsCoordinator.swift",
        "after",
        """    /// Shows the vault screen.
    ///
    private func showVault() {
        let processor = VaultSettingsProcessor(
            coordinator: asAnyCoordinator(),
            services: services,
            state: VaultSettingsState(),
        )
        let view = VaultSettingsView(store: Store(processor: processor))
        let viewController = UIHostingController(rootView: view)
        viewController.navigationItem.largeTitleDisplayMode = .never
        stackNavigator?.push(viewController, navigationTitle: Localizations.vault)
    }""",
        """
    /// Shows the WezWordn features screen. (WezWordn patch 01)
    ///
    /// The features UI lives in the app target, so this pushes the view
    /// controller produced by the factory the host app registered in
    /// `WezWordnFeaturesPresenter`, handing it this flow's real
    /// `VaultRepository`. If no factory is registered the error is logged
    /// and nothing is pushed — there is deliberately no fallback UI.
    ///
    private func showWezWordnFeatures() {
        guard let viewController = WezWordnFeaturesPresenter.makeViewController(
            vaultRepository: services.vaultRepository,
        ) else {
            services.errorReporter.log(
                error: BitwardenError.dataError(
                    "WezWordn features factory was not registered by the host app.",
                ),
            )
            return
        }
        viewController.navigationItem.largeTitleDisplayMode = .never
        stackNavigator?.push(viewController, navigationTitle: "WezWordn Features")
    }""",
    ),
    (
        "Bitwarden/Application/AppDelegate.swift",
        "after",
        """        let appModule = DefaultAppModule(services: services)""",
        """        // WezWordn patch 01: register the features view factory so the
        // settings flow (BitwardenShared) can present the app target's
        // WezWordn features UI. The glue type lives in the app target.
        WezWordnAppGlue.registerWezWordnFeatures()""",
    ),
]


def fail(code, message):
    print(f"01-settings-entry: ERROR: {message}", file=sys.stderr)
    sys.exit(code)


def main(argv):
    args = [a for a in argv[1:] if a != "--verify"]
    verify_only = "--verify" in argv[1:]
    if len(args) != 1:
        fail(64, "usage: 01-settings-entry.py [--verify] <upstream_root>")
    root = Path(args[0])
    if not root.is_dir():
        fail(4, f"upstream root not found: {root}")

    presenter_file = root / PRESENTER_PATH
    if presenter_file.exists():
        fail(3, f"already applied: {PRESENTER_PATH} already exists")

    # Phase 1: read and validate every anchor before writing anything.
    contents = {}
    for relpath, _mode, anchor, _insertion in OPS:
        path = root / relpath
        if relpath not in contents:
            if not path.is_file():
                fail(2, f"target file missing: {relpath}")
            contents[relpath] = path.read_text(encoding="utf-8")
        text = contents[relpath]
        # Pristine upstream contains no "wezWordnFeatures" symbol anywhere in
        # these files (verified against the current snapshot), so its
        # presence means this patch (or a conflicting change) already landed.
        if "wezWordnFeatures" in text:
            fail(3, f"already applied or conflicting: {relpath} contains WezWordn symbols")
        count = text.count(anchor)
        if count != 1:
            fail(2, f"anchor found {count} times (expected exactly 1) in {relpath}: {anchor[:80]!r}...")

    if verify_only:
        print("01-settings-entry: verify OK — all anchors present exactly once; patch not applied.")
        return 0

    # Phase 2: apply in memory, then write each file once.
    for relpath, mode, anchor, insertion in OPS:
        text = contents[relpath]
        if mode == "after":
            contents[relpath] = text.replace(anchor, anchor + "\n" + insertion, 1)
        else:
            contents[relpath] = text.replace(anchor, insertion + "\n" + anchor, 1)

    for relpath, text in contents.items():
        path = root / relpath
        tmp = path.with_suffix(path.suffix + ".weztmp")
        tmp.write_text(text, encoding="utf-8")
        tmp.replace(path)
        print(f"01-settings-entry: patched {relpath}")

    presenter_file.parent.mkdir(parents=True, exist_ok=True)
    presenter_file.write_text(PRESENTER_CONTENT, encoding="utf-8")
    print(f"01-settings-entry: created {PRESENTER_PATH}")
    print("01-settings-entry: done.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
