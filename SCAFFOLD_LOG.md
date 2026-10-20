# SCAFFOLD_LOG — سجل إنشاء هيكل مشروع WezWordn

- **التاريخ:** 2026-10-20 (Asia/Riyadh)
- **النطاق:** إنشاء هيكل المشروع في `~/workspace/wezwordn/` حصرًا. لم يُلمس مجلد `WezWordnCore/` (قيد بناء عامل موازٍ) ولا `~/workspace/wezwordn-upstream-ios/`.
- **الأساس الواقعي:** تقرير الفحص الفعلي `~/workspace/wezwordn-analysis/UPSTREAM_FINDINGS.md` + قراءة مباشرة لملفات upstream والـ IPA المرفق أثناء هذه الجلسة (انظر الأدلة أدناه).

## الملفات المنشأة (16 ملفًا)

| # | المسار | الحجم (bytes) | المحتوى باختصار |
|---|---|---|---|
| 1 | `LICENSE` | 35,140 | نسخة حرفية بأمر `cp` من `wezwordn-upstream-ios/LICENSE.txt` (GPLv3) — تحقق `cmp`: متطابق |
| 2 | `identity/Local-WezWordn.xcconfig.example` | 4,105 | فرض `BASE_BUNDLE_ID = com.wezcrypt.wezwordn` + ‏`ORGANIZATION_IDENTIFIER` + ‏`SHARED_APP_GROUP_IDENTIFIER`؛ ‏`DEVELOPMENT_TEAM` معلّق بلا قيمة مختلقة؛ توثيق اشتقاق `group.com.wezcrypt.wezwordn` من صيغة `group.$(BASE_BUNDLE_ID)` |
| 3 | `scripts/bootstrap.sh` | 8,726 | سكربت macOS كامل (`set -euo pipefail`): فحص Xcode/إصداره مقابل `.xcode-version`، جلب upstream (git clone ثم tarball codeload احتياطيًا مع `gzip -t`)، نسخ الـ xcconfig دون طمس، نسخ ملفات التكامل، كشف XcodeGen (مباشر/mint/brew)، توليد المشاريع الأربعة |
| 4 | `.github/workflows/build-ipa.yml` | 8,946 | ‏workflow ‏macos-latest: ‏checkout + جلب upstream tarball + فرض الهوية + XcodeGen + ‏`swift test` للحزمة + ‏`xcodebuild test` لمخطط `Bitwarden` + archive بـ `CODE_SIGNING_ALLOWED=NO` + تجميع `WezWordn.ipa` (Payload zip) + ‏`shasum -a 256` + ‏upload-artifact؛ تعليقات صريحة: الناتج unsigned |
| 5 | `AppIntegration/WezWordnFeaturesRootView.swift` | 31,418 | ‏`NavigationStack` بخمسة أقسام + محرر Login، كلها تستدعي واجهات WezWordnCore الحقيقية؛ Encrypted Files ‏file-backed فعلي؛ TODOs موثّقة بدل واجهات كاذبة للحفظ الدائم المشفر |
| 6 | `AppIntegration/KeychainKeyProvider.swift` | 4,154 | ‏`KeyProvider` إنتاجي: ‏Security framework، ‏`kSecClassGenericPassword`، `SecRandomCopyBytes`، ‏`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`، غير متزامن؛ ملف iOS-only |
| 7 | `AppIntegration/README.md` | 7,905 | طريقة الدمج (نسخ + مقتطف `project-pm.yml` جاهز للإلصاق لربط الحزمة المحلية والمنتجات السبعة + ‏`Crypto`) + حقيقة غياب منتج مظلّي باسم `WezWordnCore` + حدود TODO + نتائج التحقق الحقيقية |
| 8 | `README.md` | 8,263 | هوية المشروع وعدم الانتساب، جدول ميزات بحالات صادقة، التزامات GPLv3، ما لا يدّعيه المشروع |
| 9 | `ARCHITECTURE.md` | 13,657 | خريطة upstream الفعلية (وحدات/امتدادات/تشفير SDK/KDF) + طبقات WezWordn + جدول فصل البيانات الخمس + مبدأ عدم لمس تنسيق المزامنة |
| 10 | `REA_ANALYSIS.md` | 10,050 | نتائج تحليل IPA الفعلية (انظر الأدلة) + قسم REA: الأداة حقيقية وموثّقة ولم تُثبّت/تُشغّل هنا |
| 11 | `FEATURE_MAPPING.md` | 11,129 | ربط كل وظيفة أصلية بمكوّنها upstream وكل ميزة جديدة بوحدتها + قائمة فجوات معلنة (5 بنود) |
| 12 | `SECURITY.md` | 10,695 | Threat Model بأربعة مهاجمين + النسخ الاحتياطية، وحدود صريحة (flash/سحب/طوارئ محلي/HIBP ‏5 hex chars) |
| 13 | `BUILD.md` | 7,579 | بناء macOS خطوة بخطوة: تجهيز، هوية، ربط الحزمة، اختبارات، أرشفة، IPA غير موقّع، أعطال متوقعة |
| 14 | `INSTALL.md` | 6,429 | تثبيت Xcode وAltStore/SideStore + جدول قيود إعادة التوقيع على App Groups وAutoFill وKeychain groups وAssociated Domains والإشعارات |
| 15 | `CHANGELOG.md` | 4,467 | إدخال `0.1.0` بتاريخ 2026-10-20 بما أُنجز فعليًا فقط + قسم «لم يُنجز بعد» |
| 16 | `SCAFFOLD_LOG.md` | (هذا الملف) | سجل الإنشاء ونتائج التحقق |

## نتائج التحقق المنفّذة فعليًا في هذه الجلسة

| الفحص | الأمر | النتيجة الحقيقية |
|---|---|---|
| سلامة سكربت الباش نحويًا | `bash -n ~/workspace/wezwordn/scripts/bootstrap.sh` | **exit 0** — فحص syntax فقط؛ السكربت لم يُشغّل (يتطلب macOS/Xcode غير المتاحين هنا) |
| فحص Swift نحوي 1 | `~/workspace/toolchains/swift/usr/bin/swiftc -parse AppIntegration/KeychainKeyProvider.swift` | **exit 0**، بلا أي مخرجات تشخيصية |
| فحص Swift نحوي 2 | `~/workspace/toolchains/swift/usr/bin/swiftc -parse AppIntegration/WezWordnFeaturesRootView.swift` | **exit 0**، بلا أي مخرجات تشخيصية |
| سلامة YAML للـ workflow | `python3 -c yaml.safe_load(...)` على `build-ipa.yml` | **valid** (فحص بنية YAML فقط — لا يثبت نجاح تشغيل GitHub Actions) |
| تطابق الترخيص | `cmp upstream/LICENSE.txt wezwordn/LICENSE` | **متطابق بايتًا ببايت** |
| SHA-256 للـ IPA المرفق | `sha256sum` على ملف الـ IPA المرفق | `943e06916964a73791ca1fbedfb21eea501785e9e16843f2322be420397994fe` — يطابق القيمة المطلوب توثيقها |

بيئة الفحص: ‏Swift 6.1.2 (‏`swift-6.1.2-RELEASE`، ‏`x86_64-unknown-linux-gnu`). ‏`swiftc -parse` يتحقق من البنية النحوية فقط — لا أنواع، لا وحدات، لا ترجمة. ملفا التكامل **لا يمكن تجميعهما على Linux** (‏SwiftUI/Security/UniformTypeIdentifiers خارج Apple SDKs)، وأول ترجمة حقيقية لهما تكون على macOS عبر `BUILD.md` أو الـ workflow.

## أدلة قراءة مباشرة استُخدمت لتوثيق الحقائق (هذه الجلسة)

- `Configs/Common-bwpm.xcconfig` في upstream: قيم الهوية الأصلية وآلية `Local-bwpm.xcconfig` الموثّقة فيه حرفيًا.
- `Bitwarden.entitlements` و`BitwardenAutoFill.entitlements`: صيغة `group.$(BASE_BUNDLE_ID)` وبقية المفاتيح الموثّقة في `REA_ANALYSIS.md`.
- `project-pm.yml`: اسم المخطط الفعلي `Bitwarden` وأهدافه وخطط اختباره.
- `project-common.yml` و`.xcode-version` و`Mintfile`: ‏deployment ‏iOS 15.0، ‏Xcode 26.6، ‏XcodeGen 2.44.1.
- `Info.plist` داخل الـ IPA (قراءة plist فعلية): ‏bundle `com.8bit.bitwarden`، ‏version ‏`2026.10.0`، ‏build `3551`، ‏`MinimumOSVersion 15.0`، ‏`DTSDKName iphoneos26.5`؛ وقائمة الـ `.appex` الخمسة مع `NSExtensionPointIdentifier` لكل منها؛ وmagic التنفيذي `cffaedfe` (Mach-O 64-bit ARM64 thin).
- مصادر وحدات `WezWordnCore` السبع (قراءة كاملة): أسماء الأنواع والواجهات العامة كما استُخدمت في ملفات التكامل والوثائق.

## انحرافات موثّقة عن صياغة التكليف (قرارات هندسية معلنة)

1. **اسم المخطط في الـ workflow هو `Bitwarden` لا `BitwardenPM`**: لا يوجد مخطط باسم `BitwardenPM` في upstream؛ الاسم الحرفي في `project-pm.yml` هو `Bitwarden`. استخدام الاسم المطلوب حرفيًا كان سينتج workflow مكسورًا بيقين. موثّق داخل ملف الـ workflow نفسه.
2. **ملفات التكامل تستورد أسماء وحدات الـ Core الحقيقية لا `import WezWordnCore`**: ‏`Package.swift` الحالي للحزمة يعرّف 7 منتجات منفصلة ولا منتج مظلّيًا بهذا الاسم؛ الاستيراد المطلوب كان سيفشل في أول ترجمة macOS. موثّق في `AppIntegration/README.md` — إصلاحه الجذري (إن رُغب) إضافة منتج مظلّي داخل `WezWordnCore/`، وهو خارج نطاق لمس هذا المجلد في مهمتي.
3. **الامتدادات خمسة لا أربعة في العد الكامل**: أربعة في `PlugIns/` الرئيسي + ودجت الساعة متداخل داخل تطبيق الساعة. `REA_ANALYSIS.md` يوثّق الخمسة بمواقعها بدل إخفاء الخامس.

## ما لم يُنفّذ في هذه المهمة (بتصميم التكليف أو بحدود البيئة)

- لا بناء، لا اختبارات تشغيلية، لا IPA: لا macOS/Xcode في هذه البيئة، ومسارا التنفيذ (محلي + CI) جاهزان وموثّقان فقط.
- لم تُشغّل أداة REA ولم تُثبّت (انظر `REA_ANALYSIS.md` §7 للأسباب الموثّقة).
- لم يُعدَّل أي ملف داخل `WezWordnCore/` أو شجرة upstream.
