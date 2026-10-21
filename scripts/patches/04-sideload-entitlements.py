#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
04-sideload-entitlements.py — WezWordn patch: تجريد الـ entitlements المقيدة لفريق مجاني
============================================================================================

الغرض
-----
ثلاث رقع كود سابقة لم تُشفِ انهيار الإقلاع على iPhone حقيقي بعد تحميل
جانبي بفريق Apple ID مجاني: الرقعة 02 حرست حاويات الـ App Group في
`DataStore` و`AuthenticatorBridgeDataStore`، والرقعة 03 حرست ختمي
`UserDefaults(suiteName:)` في `ServiceContainer` — والبناء الذي يحمل
الرقع الثلاث (Run #32) ما زال يموت عند شاشة البداية على الجهاز
(نتيجة جهاز أبلغها المستخدم في 2026-10-21). هذه الرقعة تعالج فرضية
مختلفة الطبقة: ليست كودًا ينهار، بل **entitlements لا يستطيع provisioning
المجاني منحها أصلًا**.

الفرضية (مصرَّح بأنها فرضية — الدليل الحاسم سجل .ips لم يصل بعد)
------------------------------------------------------------------
الـ provisioning profile الذي تصنعه أدوات التحميل الجانبي (SideStore /
AltStore) بفريق شخصي مجاني لا يمكنه تضمين قدرات مقيدة ببرنامج مطوّر
مدفوع أو بتحقق خارجي: iCloud containers، وAssociated Domains، وقراءة
NFC بصيغة TAG. إعادة التوقيع تُبقي عادةً كل مفاتيح الـ entitlements
الأصلية في الثنائية الموقّعة، فيجد iOS عند الإقلاع ثنائية تطالب بقدرات
لا يغطّيها الـ profile — والرفض عندها يكون في طبقة الإقلاع/التحقق لا في
كود التطبيق، فيموت التطبيق قبل أي سجل انهيار من كوده. الأدوات تختلف في
مدى تجريدها لهذه المفاتيح تلقائيًا (بعضها يجرّد وبعضها لا)، لذا تضمن
هذه الرقعة التجريد من جهة المصدر بدل تركه لرحمة الأداة.

هذه الرقعة تحرّر ملفات `*.entitlements` في شجرة upstream قبل توليد
المشاريع في الـ CI: تزيل المفاتيح المقيدة وتُبقي كل ما يعتمد عليه
التشغيل الفعلي للخزنة. هي تغيير توزيع (distribution variant): البناء
الناتج مخصص لقناة التحميل الجانبي حصرًا — البناء المخوّل بفريق مدفوع لا
يحتاجها ولا يجب أن تُطبّق عليه.

المفاتيح المزالة (حيثما وُجدت في أي ملف)
-----------------------------------------
صريحة:
  - com.apple.developer.icloud-container-identifiers
  - com.apple.developer.icloud-services
  - com.apple.developer.ubiquity-kvstore-identifier
  - com.apple.developer.associated-domains
  - com.apple.developer.nfc.readersession.formats
وبقواعد:
  - أي مفتاح يبدأ بـ com.apple.developer.icloud
  - أي مفتاح يحتوي associated-domains
  - أي مفتاح يبدأ بـ com.apple.developer.ubiquity- — توسعة موثّقة لقاعدة
    kvstore الصريحة: لقطة upstream الحالية تحمل فعليًا
    `com.apple.developer.ubiquity-container-identifiers` في ملف التطبيق
    الرئيسي (حاوية iCloud باسم iCloud.$(CFBundleIdentifier))، وهو مفتاح
    iCloud/ubiquity بالمعنى نفسه؛ إبقاؤه يُبقي قدرة لا يمنحها الفريق
    المجاني ويهزم غرض الرقعة.

المفاتيح المُبقاة دون مساس (حماية صريحة في الكود قبل أي قاعدة إزالة)
----------------------------------------------------------------------
  - com.apple.security.application-groups — مشاركة قاعدة البيانات
    والإعدادات بين التطبيق والامتدادات؛ إزالتها تكسر AutoFill نفسه.
    (تخويل المجموعة فعليًا يبقى شأن أداة التثبيت/الفريق — الرقعتان
    02 و03 تعالجان غيابه برمجيًا.)
  - keychain-access-groups — وصول الخزنة لمفاتيح التشفير.
  - com.apple.developer.default-data-protection — غير موجود في اللقطة
    الحالية، ويُحمى احترازيًا إن ظهر.
  - com.apple.developer.authentication-services.autofill-credential-provider
    — قدرة AutoFill الأساسية؛ الفريق المجاني يمنحها، وإزالتها تعني فقدان
    الميزة كليًا.
  - aps-environment — ليس ضمن قائمة الإزالة؛ يبقى كما هو.

أثر التجريد المتوقَّع (مصرَّح به — تدهور مقصود ومحدود)
---------------------------------------------------------
يتوقف في هذا التوزيع فقط:
  - مزامنة/تخزين iCloud (CloudKit وكوينات ubiquity) إن استخدمها أي
    مكوّن — بيانات الخزنة نفسها لا تعيش في iCloud في Bitwarden.
  - Associated Domains: روابط applinks وwebcredentials إلى
    *.bitwarden.com/.eu/.pw/-gov.com — أي فتح روابط الويب مباشرة داخل
    التطبيق وربط الاعتماد بمواقع Bitwarden عبر النظام.
  - قراءة NFC بصيغة TAG.
لا يعتمد على المفاتيح المزالة: الخزنة المحلية وتشفيرها، المزامنة عبر
خادم Bitwarden (شبكة عادية)، AutoFill الأساسي (credential provider)،
Face ID، والإشعارات المحلية. قدرات الامتدادات الأربع لا تحمل أصلًا أي
مفتاح مستهدف في اللقطة الحالية (مجموعات + keychain فقط).

جدول اللقطة الحالية (قراءة فعلية لكل ملف)
-------------------------------------------
  الملف (مسار نسبي من جذر upstream)                                     المفاتيح الحالية → الإجراء
  ------------------------------------------------------------------- ---------------------------------
  Bitwarden/Application/Support/Bitwarden.entitlements                aps-environment (يبقى)،
                                                                       associated-domains ✂،
                                                                       autofill-credential-provider (يبقى)،
                                                                       nfc.readersession.formats ✂،
                                                                       ubiquity-container-identifiers ✂،
                                                                       application-groups (يبقى)،
                                                                       keychain-access-groups (يبقى)
  BitwardenAutoFillExtension/.../BitwardenAutoFill.entitlements       autofill + groups + keychain → no-op
  BitwardenActionExtension/.../BitwardenActionExtension.entitlements  groups + keychain → no-op
  BitwardenShareExtension/.../BitwardenShareExtension.entitlements    groups + keychain → no-op
  BitwardenNotificationExtension/.../....entitlements                 groups فقط → no-op
  Authenticator/Application/Support/Entitlements/Authenticator.ent…   groups + keychain → no-op
  TestHarness/Application/Support/Entitlements/TestHarness.ent…       groups + keychain → no-op

إذن في اللقطة الحالية لا يتغيّر فعليًا إلا ملف التطبيق الرئيسي (3 مفاتيح
تُزال). إدراج الملفات الستة الأخرى في مجموعة «المتوقّعة» مقصود: الرقعة
تفحصها وتُبلغ عنها no-op، وأي مفتاح مقيد يضيفه upstream إليها مستقبلًا
يُزال تلقائيًا، وغياب أيٍّ منها خطأ صاخب (شجرة مختلفة عن المتوقّع).

تصميم إعادة التطبيق: exit 3 (قرار موثّق)
------------------------------------------
سائر الرقَع (01–03) تكتشف التطبيق المسبق من علامة نصّية داخل الملف
المعدّل. ملفات الـ entitlements لا تحمل قناة تعليق آمنة: plistlib لا
يكتب تعليقات XML، وحقن مفتاح وهمي في entitlements مرفوض (قد يغيّر سلوك
التحقق عند التوقيع). لذا الكشف هنا حالتيّ (state-based): إن لم يحتوِ أي
ملف متوقّع أي مفتاح مستهدف، فالشجرة في الحالة «المجرّدة» أصلًا —
سواء لأن الرقعة طُبّقت أو لأن upstream جرّد بنفسه — فالخروج 3
(مطبّقة/مُحقَّقة مسبقًا) دون كتابة، اتساقًا مع دلالة الرمز في العائلة.
وغياب مفتاح مستهدف من ملف بعينه ليس خطأ: ذلك الملف no-op ناجح كما في
جدول اللقطة.

سلوك الفشل: مرحلتان كالرقَع 01–03 — قراءة كل الملفات وتحليلها بـ
plistlib وحساب الإزالات أولًا، ولا يُكتب أي ملف قبل نجاح التحقق كاملًا.
غياب ملف متوقّع أو plist فاسد = خروج صاخب دون أي تعديل في أي ملف.
رموز الخروج: 64 استعمال خاطئ، 4 جذر غير موجود، 3 مطبّقة مسبقًا
(لا مفاتيح مستهدفة في أي ملف)، 2 مشكلة ملف (غائب/فاسد).

الاستعمال:
    python3 04-sideload-entitlements.py <upstream_root>           # تطبيق
    python3 04-sideload-entitlements.py --verify <upstream_root>  # تحقق فقط (يعرض ما سيُزال)

حدود التحقق هنا: تحرير plist عبر plistlib مع إعادة تحليل كل ناتج
للتحقق من غياب المُزال وحضور المُبقى بقيمه الأصلية. لا swiftc -parse
(لا ينطبق) ولا اختبار جهاز: حسم الفرضية يكون ببناء CI ثم تثبيت على
iPhone حقيقي، أو بسجل .ips.
"""

import plistlib
import sys
from pathlib import Path

NAME = "04-sideload-entitlements"

# Expected entitlements files, relative to the upstream root. A missing
# file is a loud error (the tree differs from the audited snapshot).
FILES = [
    "Authenticator/Application/Support/Entitlements/Authenticator.entitlements",
    "Bitwarden/Application/Support/Bitwarden.entitlements",
    "BitwardenActionExtension/Application/Support/BitwardenActionExtension.entitlements",
    "BitwardenAutoFillExtension/Application/Support/BitwardenAutoFill.entitlements",
    "BitwardenNotificationExtension/Application/Support/BitwardenNotificationExtension.entitlements",
    "BitwardenShareExtension/Application/Support/BitwardenShareExtension.entitlements",
    "TestHarness/Application/Support/Entitlements/TestHarness.entitlements",
]

EXPLICIT_REMOVE = {
    "com.apple.developer.icloud-container-identifiers",
    "com.apple.developer.icloud-services",
    "com.apple.developer.ubiquity-kvstore-identifier",
    "com.apple.developer.associated-domains",
    "com.apple.developer.nfc.readersession.formats",
}

# Never removed — checked before every removal rule. Losing any of these
# breaks the vault or AutoFill itself, which is the opposite of this
# patch's intent (strip only what a free team cannot grant).
NEVER_REMOVE = {
    "com.apple.security.application-groups",
    "keychain-access-groups",
    "com.apple.developer.default-data-protection",
    "com.apple.developer.authentication-services.autofill-credential-provider",
}


def is_restricted(key):
    if key in NEVER_REMOVE:
        return False
    return (
        key in EXPLICIT_REMOVE
        or key.startswith("com.apple.developer.icloud")
        or "associated-domains" in key
        or key.startswith("com.apple.developer.ubiquity-")
    )


def fail(code, message):
    print(f"{NAME}: ERROR: {message}", file=sys.stderr)
    sys.exit(code)


def main(argv):
    args = [a for a in argv[1:] if a != "--verify"]
    verify_only = "--verify" in argv[1:]
    if len(args) != 1:
        fail(64, f"usage: {NAME}.py [--verify] <upstream_root>")
    root = Path(args[0])
    if not root.is_dir():
        fail(4, f"upstream root not found: {root}")

    # Phase 1: read, parse, and plan every file before writing anything.
    parsed = {}
    plans = {}
    total_removals = 0
    for relpath in FILES:
        path = root / relpath
        if not path.is_file():
            fail(2, f"expected entitlements file missing: {relpath}")
        try:
            with path.open("rb") as handle:
                data = plistlib.load(handle)
        except Exception as exc:  # corrupt or non-plist content
            fail(2, f"entitlements file is not a valid plist: {relpath}: {exc}")
        if not isinstance(data, dict):
            fail(2, f"entitlements plist root is not a dict: {relpath}")
        parsed[relpath] = data
        plans[relpath] = [key for key in data if is_restricted(key)]
        total_removals += len(plans[relpath])

    if total_removals == 0:
        fail(3, "already applied: no restricted entitlement keys in any expected file")

    for relpath in FILES:
        removed = plans[relpath]
        if removed:
            print(f"{NAME}: {relpath}: would remove {removed}" if verify_only
                  else f"{NAME}: {relpath}: removing {removed}")
        else:
            print(f"{NAME}: {relpath}: no restricted keys (no-op)")

    if verify_only:
        print(f"{NAME}: verify OK — {total_removals} restricted key(s) present and removable; patch not applied.")
        return 0

    # Phase 2: write only the files that change, each via a temp sibling
    # + atomic replace (same discipline as patches 01–03).
    for relpath in FILES:
        if not plans[relpath]:
            continue
        stripped = {k: v for k, v in parsed[relpath].items() if not is_restricted(k)}
        path = root / relpath
        tmp = path.with_suffix(path.suffix + ".weztmp")
        with tmp.open("wb") as handle:
            plistlib.dump(stripped, handle, fmt=plistlib.FMT_XML, sort_keys=False)
        tmp.replace(path)
        print(f"{NAME}: patched {relpath}")

    print(f"{NAME}: done.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
