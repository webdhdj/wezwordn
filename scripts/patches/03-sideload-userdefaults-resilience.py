#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
03-sideload-userdefaults-resilience.py — WezWordn patch: صلابة UserDefaults عند غياب App Group
================================================================================================

الغرض
-----
الـ IPA الذي يحمل الرقعة 02 (حراسة `containerURL` في `DataStore`
و`AuthenticatorBridgeDataStore`) ما زال ينهار عند شاشة البداية على iPhone
حقيقي بعد تحميل جانبي بفريق Apple ID مجاني — نتيجة جهاز مُثبتة أبلغها
المستخدم في 2026-10-21. إذن فخّ الإقلاع الأول زمنيًا ليس مخزنَي SQLite:
يوجد ختمان قسريان على `UserDefaults(suiteName:)` داخل
`ServiceContainer` convenience init، أولهما يُنفَّذ قبل إنشاء `DataStore`
أصلًا. عند غياب تخويل الـ App Group يعيد
`UserDefaults(suiteName:)` القيمة nil (سلوك موثّق من Apple: الـ suite
الخاصة بمجموعة لا يملك التطبيق تخويلها تعيد nil)، فيقتل الختم القسري
التطبيق أثناء الإقلاع قبل أي واجهة.

هذه الرقعة تحوّل الختمين إلى سقوط موثّق إلى `UserDefaults.standard` عند
عودة الـ suite بـ nil، مع تسجيل الحدث عبر `errorReporter` المتاح أصلًا في
نطاق الـ init نفسه (الآلية نفسها التي استخدمتها الرقعة 02:
`errorReporter.log(error: BitwardenError.dataError(...))` — لا API مخترع).
عند توفّر الـ suite (بناء مخوّل فعليًا) لا يتغيّر أي سلوك إطلاقًا: نفس
المثيل، نفس قيم الإعدادات، نفس الترتيب.

موضعا الرقعة (قراءة فعلية من لقطة upstream الحالية)
---------------------------------------------------
الملف: BitwardenShared/Core/Platform/Services/ServiceContainer.swift

الهدف الأول — سطر 495 (أول فخّ في ترتيب التنفيذ، قبل `DataStore` سطر 512):
    let appSettingsStore = DefaultAppSettingsStore(
        userDefaults: UserDefaults(suiteName: Bundle.main.groupIdentifier)!,
    )
`DefaultAppSettingsStore.init` نفسه بريء (يخزّن المثيل فقط — AppSettingsStore.swift:807).

الهدف الثاني — سطر 899 (داخل بناء `DefaultMigrationService`):
    let migrationService = DefaultMigrationService(
        appGroupUserDefaults: UserDefaults(suiteName: Bundle.main.groupIdentifier)!,
`DefaultMigrationService.init` له أصلًا قيمة افتراضية `= .standard`
لهذا الوسيط بالذات (MigrationService.swift:62) — أي أن السقوط إلى
`.standard` سلوك يعرفه upstream نفسه كوضع صالح لهذا المكوّن.

تدقيق مسار الإقلاع الكامل (AppDelegate → ServiceContainer، بترتيب التنفيذ)
----------------------------------------------------------------------------
AppDelegate.swift:41-46: `ServiceContainer.shared(...)` ثم
`DefaultAppModule(services:)` ثم `AppProcessor`. وداخل `shared`
(ServiceContainer.swift:1270) تُستدعى الـ convenience init. ما فُحص
بقراءة فعلية لجسم كل init يُبنى أثناء السلسلة:

  #  الموضع                                   البناء/الاستخدام                                    الحكم
  -  ---------------------------------------- ------------------------------------------------- ------------------------------------------
  0  AppDelegate (closure)                   ErrorReporterFactory.makeDefaultErrorReporter   ليس مشتقًا من entitlements — خارج النطاق
  1  ServiceContainer.swift:495              UserDefaults(suiteName: group)! ← الهدف الأول   **فخّ: nil بلا تخويل ← انهيار فوري**
  2  ServiceContainer.swift:512              DataStore ← containerURL! (داخله :71)           عولج بالرقعة 02
  3  ServiceContainer.swift:~525             DefaultKeychainService() init فارغ؛             لا فخّ: الـ init يخزّن السلاسل فقط، وعمليات
                                             DefaultKeychainServiceFacade يأخذ سلاسل         الـ keychain كسولة وتُلقى أخطاءً مُعرّفة
                                             keychainAccessGroup / sharedAppGroupIdentifier  (errSecMissingEntitlement خطأ لا انهيار)
                                             من Info.plist — قيم نصّية لا تعيد nil أبدًا
  4  ServiceContainer.swift:533             DefaultStateService.init                        لا فخّ: يخزّن التبعيات ويقرأ appTheme و
                                                                                             disableWebIcons قراءة آمنة على أي
                                                                                             UserDefaults (تُحسم بقرار الهدف الأول)
  5  ServiceContainer.swift:~548            DefaultFlightRecorder.init +                   لا فخّ: flightRecorderLogURL يستخدم
                                             FileManager+Extensions.swift:9                containerURL(...)؟ اختياريًا أصلًا
  6  ServiceContainer.swift:899              UserDefaults(suiteName: group)! ← الهدف الثاني **فخّ: nil بلا تخويل ← انهيار فوري**
  7  ServiceContainer.swift:1139-1143        AuthenticatorBridgeDataStore containerURL!      عولج بالرقعة 02

  فُحص أيضًا: DefaultAppContextHelper (struct بلا init فعّال)،
  AppIDService.init (يخزّن مخزن الإعدادات فقط)،
  CipherIconImageLoader.shared/configure (يخزّن خدمات ويبني URLSession)،
  Bundle+Extensions: groupIdentifier/sharedAppGroupIdentifier/
  keychainAccessGroup كلها سلاسل محسوبة من Info.plist/المعرّف — لا nil
  ولا ختم في أيٍّ منها.

مواضع بنفس العيب موثّقة ولا تُلمس (قرار مُعلَّل)
-------------------------------------------------
- BitwardenShared/Core/Platform/Services/NotificationExtensionHelper.swift:55 —
  convenience init فيه الختم نفسه حرفيًا، لكنه يُبنى فقط داخل عملية
  Notification Service Extension (وعند الاختبارات)، وليس على مسار إقلاع
  التطبيق الرئيسي الذي ينهار عند المستخدم؛ إصلاحه يغيّر سلوك عملية
  الامتداد وهو قرار منفصل. يُوثّق هنا مرشّحًا لرقعة لاحقة مستقلة.
- AuthenticatorShared/.../DataStore.swift — تطبيق Authenticator المستقل،
  خارج بناء WezWordn الحالي (وُثّق في الرقعة 02 أيضًا).

ما لا تفعله الرقعة (حدود صريحة)
--------------------------------
- التدهور المُصرَّح به داخل الكود: في وضع السقوط، إعدادات التطبيق تعيش
  في نطاق `UserDefaults.standard` الخاص بالتطبيق ولن تُشارك مع
  الامتدادات (AutoFill/Share/Action/Notification) — لأن مشاركتها هي
  وظيفة الـ suite المخوّلة أصلًا. وقراءات MigrationService من الـ suite
  تصير قراءات من نطاق فارغ عمليًا (لا شيء يُرحَّل منه).
- لا هجرة بين الوضعين: ما كُتب في `.standard` أثناء الوضع المتدهور لا
  ينتقل إلى الـ suite إن صار البناء مخوّلًا لاحقًا، والعكس.
- لا تدّعي هذه الرقعة أنها آخر فخّ إقلاع ممكن: هي تعالج الفخّين
  الموثّقين المتبقّيين على مسار الإنشاء بعد الرقعة 02. إن استمر
  الانهيار بعدها، فالدليل الحاسم سجل .ips من الجهاز (مطلوب من المستخدم
  ولم يصل بعد عند كتابة الرقعة).

سلوك الفشل: مرحلتان كالرقعتين 01 و02 — التحقق من كل المراسي أولًا، ولا
يُكتب أي ملف قبل نجاح التحقق كاملًا. غياب مرساة أو تكرارها أو وجود
علامة الرقعة مسبقًا = خروج غير صفري دون أي تعديل. رموز الخروج:
64 استعمال خاطئ، 4 جذر غير موجود، 3 مطبّقة مسبقًا، 2 مشكلة مرساة/ملف.

الاستعمال:
    python3 03-sideload-userdefaults-resilience.py <upstream_root>           # تطبيق
    python3 03-sideload-userdefaults-resilience.py --verify <upstream_root>  # تحقق فقط

حدود التحقق هنا: تعديل نصّي فقط + swiftc -parse للملف الناتج. سلامة
الأنواع داخل سياق حزم upstream والتشغيل على جهاز لا يُحسمان إلا ببناء
macOS في الـ CI وبسجل انهيار/تشغيل من iPhone حقيقي.
"""

import sys
from pathlib import Path

MARKER = "WezWordn patch 03"

# Each op: (relative path, mode, anchor, replacement)
#   mode "replace": result = text with the single anchor occurrence swapped
#   for the replacement block.
OPS = [
    (
        "BitwardenShared/Core/Platform/Services/ServiceContainer.swift",
        "replace",
        r"""        let appSettingsStore = DefaultAppSettingsStore(
            userDefaults: UserDefaults(suiteName: Bundle.main.groupIdentifier)!,
        )""",
        r"""        // WezWordn patch 03 — degraded sideload fallback.
        //
        // `UserDefaults(suiteName:)` returns nil when this process is not
        // entitled to the app group, which is the case when an unsigned
        // build is re-signed with a free personal team (e.g. SideStore or
        // AltStore): the group identifier is registered to the original
        // team, not to the re-signing team. Upstream force-unwraps the
        // result, so the app dies here during launch — before the vault
        // `DataStore` below is even constructed.
        //
        // Degraded mode: fall back to `UserDefaults.standard`. App
        // settings then persist in the app's private defaults domain and
        // are NOT shared with the app extensions (AutoFill, Share,
        // Action, Notification) until the app group is genuinely
        // entitled to the signing team. The entitled path above is
        // unchanged: the app-group suite is used exactly as upstream.
        let appSettingsUserDefaults = UserDefaults(suiteName: Bundle.main.groupIdentifier)
        if appSettingsUserDefaults == nil {
            errorReporter.log(
                error: BitwardenError.dataError(
                    "App group UserDefaults unavailable; using standard defaults for app settings (degraded sideload mode).",
                ),
            )
        }
        let appSettingsStore = DefaultAppSettingsStore(
            userDefaults: appSettingsUserDefaults ?? .standard,
        )""",
    ),
    (
        "BitwardenShared/Core/Platform/Services/ServiceContainer.swift",
        "replace",
        r"""        let migrationService = DefaultMigrationService(
            appGroupUserDefaults: UserDefaults(suiteName: Bundle.main.groupIdentifier)!,""",
        r"""        // WezWordn patch 03 — degraded sideload fallback.
        //
        // Same failure as the app-settings store at the top of this
        // initializer: the app group suite is not entitled to a free
        // re-signing team, so `UserDefaults(suiteName:)` returns nil and
        // upstream's force-unwrap kills the app during launch.
        //
        // Degraded mode: the migration service reads its app-group
        // defaults from `UserDefaults.standard` instead — the same
        // instance upstream itself uses as this parameter's default
        // value. That domain holds no legacy app-group data, so
        // migrations sourced from the suite are effectively skipped in
        // this mode; the entitled path is unchanged.
        let migrationAppGroupUserDefaults = UserDefaults(suiteName: Bundle.main.groupIdentifier)
        if migrationAppGroupUserDefaults == nil {
            errorReporter.log(
                error: BitwardenError.dataError(
                    "App group UserDefaults unavailable; using standard defaults for migration checks (degraded sideload mode).",
                ),
            )
        }
        let migrationService = DefaultMigrationService(
            appGroupUserDefaults: migrationAppGroupUserDefaults ?? .standard,""",
    ),
]


def fail(code, message):
    print(f"03-sideload-userdefaults-resilience: ERROR: {message}", file=sys.stderr)
    sys.exit(code)


def main(argv):
    args = [a for a in argv[1:] if a != "--verify"]
    verify_only = "--verify" in argv[1:]
    if len(args) != 1:
        fail(64, "usage: 03-sideload-userdefaults-resilience.py [--verify] <upstream_root>")
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
        print("03-sideload-userdefaults-resilience: verify OK — all anchors present exactly once; patch not applied.")
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
        print(f"03-sideload-userdefaults-resilience: patched {relpath}")

    print("03-sideload-userdefaults-resilience: done.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
