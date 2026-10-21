#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
02-sideload-datastore-resilience.py — WezWordn patch: صلابة DataStore عند غياب App Group
========================================================================================

الغرض
-----
الـ IPA الذي يبنيه الـ CI غير موقّع، ويثبّته المستخدم على iPhone حقيقي عبر
تحميل جانبي (SideStore/AltStore أو مثيلاتهما) حيث تُعاد كتابة التوقيع بفريق
Apple ID شخصي مجاني. معرّفات الـ App Group المبنية في الـ entitlements
(`group.com.wezcrypt.wezwordn` والمجموعة المشتركة مع Authenticator) غير
مسجّلة لذلك الفريق، فليست مخوّلة له. في هذه الحالة تعيد
`containerURL(forSecurityApplicationGroupIdentifier:)` القيمة nil على جهاز
حقيقي، وكود upstream يختم النتيجة قسريًا (`!`) أثناء الإقلاع — فيموت
التطبيق عند شاشة البداية قبل ظهور أي واجهة.

هذه الرقعة تزيل الختمين القسريين الواقعين على مسار إقلاع التطبيق الرئيسي
وتستبدل بهما سقوطًا متدهورًا موثّقًا إلى مخزن محلي داخل حاوية التطبيق
الخاصة، مع تسجيل الحدث عبر `errorReporter` الموجود أصلًا في الكلاسين.
عند توفّر الحاوية (بناء مخوّل فعليًا) لا يتغيّر أي سلوك إطلاقًا: نفس
الملف، نفس المسار، نفس الترتيب.

مسار الإقلاع كما وُجد في لقطة upstream الحالية (قراءة فعلية، بأسطر دقيقة)
----------------------------------------------------------------------------
Bitwarden/Application/AppDelegate.swift:41-46 — عند
`didFinishLaunchingWithOptions` يُبنى `ServiceContainer.shared(...)` ثم
`DefaultAppModule(services:)`. وداخل
BitwardenShared/Core/Platform/Services/ServiceContainer.swift
(convenience init، بترتيب التنفيذ):
  1. سطر 495: `userDefaults: UserDefaults(suiteName: Bundle.main.groupIdentifier)!,`
     (لبناء DefaultAppSettingsStore) — ختم قسري. **غير مشمول بهذه الرقعة**
     (انظر "ما لا تفعله الرقعة").
  2. سطر 512: `let dataStore = DataStore(errorReporter: errorReporter)`
     ← الهدف الأول أدناه.
  3. سطر 899: `appGroupUserDefaults: UserDefaults(suiteName: Bundle.main.groupIdentifier)!,`
     (لبناء DefaultMigrationService) — ختم قسري ثانٍ. **غير مشمول أيضًا**.
  4. أسطر 1139-1143: `AuthenticatorBridgeDataStore(errorReporter:,
     groupIdentifier: Bundle.main.sharedAppGroupIdentifier, storeType: .persisted)`
     ← الهدف الثاني أدناه.

الهدف الأول — BitwardenShared/Core/Platform/Services/Stores/DataStore.swift:70-72
    let storeURL = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: Bundle.main.groupIdentifier)!
        .appendingPathComponent("Bitwarden.sqlite")

الهدف الثاني — AuthenticatorBridgeKit/AuthenticatorBridgeDataStore.swift:102-104
    let storeURL = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)!
        .appendingPathComponent("\\(authenticatorBridgeModelName).sqlite")
وُثّق الثاني كهدف لأنه يُبنى في نفس الـ init وبنفس نمط `.persisted` على
مجموعة أخرى (`sharedAppGroupIdentifier` = Info.plist
`BitwardenAuthenticatorSharedAppGroup` وإلا `groupIdentifier` —
Bundle+Extensions.swift:71-73)، والمجموعتان معًا غير مخوّلتين في سيناريو
التحميل الجانبي؛ إصلاح الأول وحده يترك الانهيار نفسه بعد ~600 سطر في نفس
الدالة. المعرّف نفسه: `Bundle.main.groupIdentifier` =
`"group." + appIdentifier` (Bundle+Extensions.swift:63-65).

مواضع موثّقة أخرى بنفس العيب (خارج بناء WezWordn الحالي، لا تُلمس):
- AuthenticatorShared/Core/Platform/Services/Stores/DataStore.swift:66-68 —
  تطبيق Authenticator المستقل، النمط نفسه حرفيًا.
- النمط الآمن موجود داخل upstream نفسه سابقةً: BitwardenKit
  FileManager+Extensions.swift:9 يستخدم `containerURL(...)?` اختياريًا
  لسجلات FlightRecorder دون انهيار.

ما لا تفعله الرقعة (حدود صريحة)
--------------------------------
- لا تلمس ختمي `UserDefaults(suiteName:)!` (ServiceContainer:495 و:899).
  سببان: (1) نطاق هذه المهمة هو مخزنا SQLite؛ (2) هل ينهار
  `UserDefaults(suiteName:)` فعلًا عند غياب التخويل يختلف باختلاف إصدار
  iOS وسلوك cfprefsd — غير مُتحقق منه هنا، وسقوطه البديل (تقسيم مخزن
  الإعدادات بين suite و`.standard`) قرار سلوكي منفصل. إن أظهر سجل انهيار
  جهاز (.ips) أن الفخّ يقع هناك أولًا، فالعلاج رقعة لاحقة مستقلة.
- لا تهاجر البيانات بين الوضعين: ما يُكتب في الوضع المتدهور يعيش في ملف
  SQLite داخل حاوية التطبيق، وإن صار البناء مخوّلًا لاحقًا عاد التطبيق
  إلى ملف الحاوية المشتركة وبدأ منه (تسجيل دخول/مزامنة من جديد)، وملف
  الوضع المتدهور يبقى يتيمًا في مكانه لا يُقرأ.
- الامتدادات (AutoFill/Share/Action/Notification) تعمل في عمليات منفصلة
  بمخازنها الخاصة أصلًا؛ في الوضع المتدهور لا ترى قاعدة بيانات التطبيق
  الرئيسي المشتركة — تدهور وظيفي صريح حتى يُخوّل الفريقُ المجموعة فعليًا.

سلوك الفشل: مرحلتان كرقعة 01 — التحقق من كل المراسي أولًا، ولا يُكتب أي
ملف قبل نجاح التحقق كاملًا. غياب مرساة أو تكرارها أو وجود علامة الرقعة
مسبقًا = خروج غير صفري دون أي تعديل. رموز الخروج: 64 استعمال خاطئ،
4 جذر غير موجود، 3 مطبّقة مسبقًا، 2 مشكلة مرساة/ملف مفقود.

الاستعمال:
    python3 02-sideload-datastore-resilience.py <upstream_root>           # تطبيق
    python3 02-sideload-datastore-resilience.py --verify <upstream_root>  # تحقق فقط

حدود التحقق هنا: تعديل نصّي فقط + swiftc -parse للملفات الناتجة. سلامة
الأنواع داخل سياق حزم upstream الكاملة والتشغيل على جهاز لا يُحسمان إلا
ببناء macOS في الـ CI وبسجل انهيار/تشغيل من iPhone حقيقي.
"""

import sys
from pathlib import Path

MARKER = "WezWordn patch 02"

# Each op: (relative path, mode, anchor, replacement)
#   mode "replace": result = text with the single anchor occurrence swapped
#   for the replacement block.
OPS = [
    (
        "BitwardenShared/Core/Platform/Services/Stores/DataStore.swift",
        "replace",
        r"""        case .persisted:
            let storeURL = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: Bundle.main.groupIdentifier)!
                .appendingPathComponent("Bitwarden.sqlite")
            storeDescription = NSPersistentStoreDescription(url: storeURL)""",
        r"""        case .persisted:
            let storeURL: URL
            if let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Bundle.main.groupIdentifier,
            ) {
                // Entitled path — behavior identical to upstream.
                storeURL = containerURL.appendingPathComponent("Bitwarden.sqlite")
            } else {
                // WezWordn patch 02 — degraded sideload fallback.
                //
                // `containerURL(forSecurityApplicationGroupIdentifier:)`
                // returns nil when this process is not entitled to the app
                // group, which is the case when an unsigned build is
                // re-signed with a free personal team (e.g. SideStore or
                // AltStore): the group identifier is registered to the
                // original team, not to the re-signing team. Upstream
                // force-unwraps the result, so the app dies here during
                // launch, before any UI appears.
                //
                // Degraded mode: keep the vault store in an app-private
                // Application Support directory so the main app can still
                // launch and sync. This store is NOT the shared one — app
                // extensions (AutoFill, Share, Action, Notification) run
                // in their own processes with their own stores and will
                // not see this database until the app group is genuinely
                // entitled to the signing team. Data written in this mode
                // is not migrated if the group later becomes available;
                // the app then returns to the shared-container store.
                errorReporter.log(
                    error: BitwardenError.dataError(
                        "App group container unavailable; using app-local vault store (degraded sideload mode).",
                    ),
                )
                let fallbackDirectory = FileManager.default
                    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                try? FileManager.default.createDirectory(
                    at: fallbackDirectory,
                    withIntermediateDirectories: true,
                )
                storeURL = fallbackDirectory.appendingPathComponent("Bitwarden.sqlite")
            }
            storeDescription = NSPersistentStoreDescription(url: storeURL)""",
    ),
    (
        "AuthenticatorBridgeKit/AuthenticatorBridgeDataStore.swift",
        "replace",
        r"""        case .persisted:
            let storeURL = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)!
                .appendingPathComponent("\(authenticatorBridgeModelName).sqlite")
            storeDescription = NSPersistentStoreDescription(url: storeURL)""",
        r"""        case .persisted:
            let storeURL: URL
            if let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: groupIdentifier,
            ) {
                // Entitled path — behavior identical to upstream.
                storeURL = containerURL.appendingPathComponent("\(authenticatorBridgeModelName).sqlite")
            } else {
                // WezWordn patch 02 — degraded sideload fallback.
                //
                // Same failure as in the main vault `DataStore`: this
                // store is constructed during `ServiceContainer` launch
                // setup with the *shared* app group identifier, which is
                // not entitled to a free re-signing team, so upstream's
                // force-unwrap of `containerURL` kills the app at launch.
                //
                // Degraded mode: fall back to an app-private Application
                // Support directory. The authenticator bridge data is then
                // not shared with the Authenticator app until the shared
                // group is genuinely entitled to the signing team; the
                // entitled path above is unchanged.
                errorReporter.log(
                    error: BitwardenError.dataError(
                        "Shared app group container unavailable; using app-local bridge store (degraded sideload mode).",
                    ),
                )
                let fallbackDirectory = FileManager.default
                    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                try? FileManager.default.createDirectory(
                    at: fallbackDirectory,
                    withIntermediateDirectories: true,
                )
                storeURL = fallbackDirectory.appendingPathComponent("\(authenticatorBridgeModelName).sqlite")
            }
            storeDescription = NSPersistentStoreDescription(url: storeURL)""",
    ),
]


def fail(code, message):
    print(f"02-sideload-datastore-resilience: ERROR: {message}", file=sys.stderr)
    sys.exit(code)


def main(argv):
    args = [a for a in argv[1:] if a != "--verify"]
    verify_only = "--verify" in argv[1:]
    if len(args) != 1:
        fail(64, "usage: 02-sideload-datastore-resilience.py [--verify] <upstream_root>")
    root = Path(args[0])
    if not root.is_dir():
        fail(4, f"upstream root not found: {root}")

    # Phase 1: read and validate every anchor before writing anything.
    contents = {}
    for relpath, _mode, anchor, _replacement in OPS:
        path = root / relpath
        if relpath not in contents:
            if not path.is_file():
                fail(2, f"target file missing: {relpath}")
            contents[relpath] = path.read_text(encoding="utf-8")
        text = contents[relpath]
        if MARKER in text:
            fail(3, f"already applied: {relpath} contains '{MARKER}'")
        count = text.count(anchor)
        if count != 1:
            fail(2, f"anchor found {count} times (expected exactly 1) in {relpath}: {anchor[:80]!r}...")

    if verify_only:
        print("02-sideload-datastore-resilience: verify OK — all anchors present exactly once; patch not applied.")
        return 0

    # Phase 2: apply in memory, then write each file once.
    for relpath, mode, anchor, replacement in OPS:
        if mode != "replace":
            fail(64, f"internal error: unknown mode {mode!r}")
        contents[relpath] = contents[relpath].replace(anchor, replacement, 1)

    for relpath, text in contents.items():
        path = root / relpath
        tmp = path.with_suffix(path.suffix + ".weztmp")
        tmp.write_text(text, encoding="utf-8")
        tmp.replace(path)
        print(f"02-sideload-datastore-resilience: patched {relpath}")

    print("02-sideload-datastore-resilience: done.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
