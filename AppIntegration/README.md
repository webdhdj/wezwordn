# AppIntegration — ملفات دمج WezWordn داخل تطبيق iOS

ملفات SwiftUI/Security تُنسخ إلى شجرة upstream عند البناء على macOS وتربط واجهة التطبيق بوحدات `WezWordnCore` الحقيقية. لا تُبنى هذه الملفات مستقلة، ولا توجد فيها خدمات وهمية: كل شاشة تستدعي واجهات الـ Core الفعلية.

## الملفات

| الملف | المحتوى |
|---|---|
| `WezWordnFeaturesRootView.swift` | `WezWordnFeaturesRootView` (‏`NavigationView` — توافق iOS 15) بخمسة أقسام + محرر Login: ‏Encrypted Files (file-backed فعلي على القرص عبر `LocalEncryptedStorage`)، Authenticator (‏`OTPAuthParser`/`OTPGenerator`/`Base32`)، Security Reports (‏`VaultHealth.analyze` + فحص `HIBPClient` اختياري)، Emergency Recovery (‏`EmergencyRecovery.createPackage`/`recoverVaultKey`)، Secure Sharing (‏`SecureSharing.createPackage`/`openPackage`)، ومحرر `ExtendedLogin` بحقول Username/Email مستقلة وبحث ونسخ فردي وترحيل `LegacyLogin`. حالات فارغ/خطأ/مشغول حقيقية في كل شاشة. |
| `KeychainKeyProvider.swift` | تنفيذ production لبروتوكول `KeyProvider` من وحدة `LocalEncryptedStorage` باستخدام Security framework: ‏`kSecClassGenericPassword`، توليد 32 bytes بـ `SecRandomCopyBytes` عند أول استخدام، ‏`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`، ‏`kSecAttrSynchronizable = false`. ملف iOS-only (‏`#if os(iOS)`). |
| `WezWordnHealthMapping.swift` | تحويل نقي (Foundation + ‏`VaultHealth` فقط، بلا SDK ولا SwiftUI) من `WezWordnCipherSnapshot` إلى `VaultHealthItem` بقواعد موثّقة في رأس الملف (تخطّي العناصر بلا كلمة مرور، domain من host أول URI، نسخ الـ username الشبيه ببريد إلى email مع إبقائه، ‏updatedAt = revisionDate). بلا `#if os(iOS)` عمدًا حتى يُختبر على Linux — وله اختبار وظيفي فعلي (15 assertion ضد وحدة VaultHealth الحقيقية، ناجح 2026-10-21). |
| `WezWordnVaultHealthAdapter.swift` | بروتوكول خط التماس `WezWordnVaultHealthDataSource` + التنفيذ الحقيقي `UpstreamVaultHealthDataSource` فوق `VaultRepository` الأصلي: ‏`cipherPublisher()` (أول إصدار) ← تصفية logins غير المحذوفة ← ‏`fetchCipher(withId:)` لكل عنصر ← snapshots ← الـ mapper. رأس الملف يوثّق الفجوة بدقة: ‏`ServiceContainer.vaultRepository` ليست public، فلا سبيل لبناء الـ adapter إلا بتسليمه الـ repository من كود BitwardenShared (مصنع patch 01). |
| `WezWordnAppGlue.swift` | تسجيل مصنع `WezWordnFeaturesPresenter.viewControllerFactory` عند إقلاع التطبيق: يستقبل الـ `VaultRepository` الحقيقي من منسّق الإعدادات ويبني `WezWordnFeaturesRootView` بمصدر بيانات مربوط به. يستدعيه `AppDelegate` عبر patch 01. |

## حقيقة الوحدات (Module Reality)

حزمة `WezWordnCore` في حالتها الحالية تعرّف **سبعة منتجات مكتبية منفصلة** في `Package.swift` — ‏`ExtendedLoginFields`، `LocalTOTP`، `LocalEncryptedStorage`، `VaultHealth`، `HIBPClient`، `EmergencyRecovery`، `SecureSharing` — ولا يوجد منتج مظلّي (umbrella) باسم `WezWordnCore`. لذلك تستورد ملفات التكامل أسماء الوحدات الحقيقية مباشرة. لا تستخدم `import WezWordnCore` — ستفشل الترجمة حتى يُضاف منتج مظلّي فعلي إلى الحزمة.

ملاحظة الأنواع: واجهات الـ Core تستخدم أنواع حزمة `swift-crypto` (الوحدة `Crypto`: ‏`SymmetricKey`، `Curve25519`، `AES.GCM`). هدف التطبيق يجب أن يرتبط بمنتج `Crypto` من نفس تبعية `swift-crypto` حتى تتطابق الأنواع مع CryptoKit — لا تخلط بينهما.

## طريقة الدمج في XcodeGen

### 1) نسخ الملفات

```bash
# يقوم به scripts/bootstrap.sh تلقائيًا:
mkdir -p upstream-ios/Bitwarden/Application/WezWordnFeatures
cp AppIntegration/*.swift upstream-ios/Bitwarden/Application/WezWordnFeatures/
```

المجلد داخل `sourcesPath` الخاص بهدف `Bitwarden` (القالب `CommonTarget` في `project-pm.yml` يلتقط كل `*.swift` تحت `Bitwarden/`)، فلا حاجة لتعديل قائمة المصادر.

### 2) إضافة WezWordnCore كـ local package وربطها بهدف التطبيق

ألصق المقتطف التالي في `project-pm.yml` (بجانب كتلة `packages:` الموروثة من `project-common.yml` — إن تعارضت بنية الملف في نسختك، ضع تعريف الحزمة في `project-common.yml` بدلًا منه، وأضف التبعيات إلى هدف `Bitwarden` فقط):

```yaml
# --- WezWordn: local core package (paste into project-pm.yml) ---
packages:
  WezWordnCore:
    path: ../WezWordnCore   # نسبة إلى جذر upstream-ios/ (الحزمة في <wezwordn>/WezWordnCore)

targets:
  Bitwarden:
    dependencies:
      # تبعيات upstream الأصلية تبقى كما هي — أضف التالي إليها ولا تستبدلها:
      - package: WezWordnCore
        product: ExtendedLoginFields
      - package: WezWordnCore
        product: LocalTOTP
      - package: WezWordnCore
        product: LocalEncryptedStorage
      - package: WezWordnCore
        product: VaultHealth
      - package: WezWordnCore
        product: HIBPClient
      - package: WezWordnCore
        product: EmergencyRecovery
      - package: WezWordnCore
        product: SecureSharing
      # منتج Crypto من swift-crypto (تبعية WezWordnCore) لتطابق أنواع المفاتيح:
      - package: WezWordnCore
        product: Crypto
```

> تحذير بنيوي: لقطة upstream الحالية لا تحتوي ملف `Package.swift` على مستوى المستودع، وتعريف الحزم فيها يتم عبر مفاتيح `packages:` في ملفات XcodeGen. صيغة `path:` للحزم المحلية مدعومة في XcodeGen 2.44.1. تحقق بعد التوليد أن `Bitwarden.xcodeproj` يحتوي مرجع الحزمة فعلًا (`xcodegen --spec project-pm.yml` ثم افتح الـ workspace).

### 3) عرض الواجهة من التطبيق

نقطة الدخول الإنتاجية هي صف الإعدادات الذي يحقنه `scripts/patches/01-settings-entry.py` في سلسلة تنقّل upstream نفسها (SettingsView ← SettingsAction ← SettingsProcessor ← SettingsRoute ← SettingsCoordinator)، ويقدّم الواجهة عبر مصنع `WezWordnFeaturesPresenter` الذي يسجّله `WezWordnAppGlue` من `AppDelegate`. للمعاينات/التطوير يمكن أيضًا تقديم:

```swift
WezWordnFeaturesRootView()   // يستخدم KeychainKeyProvider افتراضيًا وبلا مصدر بيانات خزنة
```

### 4) إعادة التوليد

```bash
cd upstream-ios && mint run xcodegen --spec project-pm.yml
```

## حدود موثّقة داخل الكود نفسه

- **Encrypted Files** هو القسم الوحيد file-backed بالكامل في ملفات التكامل: الملفات المشفرة تعيش في `Application Support/WezWordn/EncryptedFiles/*.wzen` (مستبعدة من النسخ الاحتياطي عبر `isExcludedFromBackup`) والمفتاح في Keychain. المعاينة تفك التشفير إلى ملف مؤقت يُحذف فورًا، والنص يُعرض من الذاكرة؛ الملفات الثنائية تُبلَّغ بحجمها بدل معاينة كاذبة.
- **Authenticator / Emergency / Sharing**: مفاتيح وأسرار الجلسة في الذاكرة داخل شاشات التكامل، مع `TODO` صريح في الكود لنقطة الحفظ المشفر الدائم (Keychain للأسرار والمفاتيح الخاصة، `LocalEncryptedStorage` للحمولات) الواجب تنفيذه في طبقة repositories الخاصة بالتطبيق المضيف قبل أي إصدار. لا يُكتب أي سر إلى `UserDefaults` أو ملف نصي في هذه الملفات.
- **Security Reports**: عند تثبيت مصدر بيانات (وهو ما يفعله `WezWordnAppGlue` في البناء الكامل مع patch 01) تُحمَّل عناصر تسجيل الدخول المفكوكة عند فتح الشاشة عبر `VaultRepository` الحقيقي وتُحلَّل تلقائيًا — في الذاكرة فقط، بلا أي كتابة لقرص أو شبكة. عند غياب المصدر تعرض الشاشة حالة «غير متصل» صراحةً وتعمل بالإدخال اليدوي وحده؛ لا تُخفى الحالتان خلف واجهة واحدة.

## التحقق المنفّذ فعليًا في بيئة Linux (2026-10-20)

هذه الملفات **لا يمكن تجميعها** على Linux: ‏`SwiftUI` و `Security` و `UniformTypeIdentifiers` غير متاحة خارج SDKs الخاصة بـ Apple، ولا يوجد Xcode هنا. التحقق المنفّذ هو فحص syntax فقط:

```bash
~/workspace/toolchains/swift/usr/bin/swiftc -parse AppIntegration/KeychainKeyProvider.swift
# exit 0 — بلا أي تشخيصات
~/workspace/toolchains/swift/usr/bin/swiftc -parse AppIntegration/WezWordnFeaturesRootView.swift
# exit 0 — بلا أي تشخيصات
```

(Swift 6.1.2، ‏`x86_64-unknown-linux-gnu`.)

`swiftc -parse` يتحقق من سلامة البنية النحوية فقط — **لا** يتحقق من الأنواع، ولا من توفر الوحدات، ولا من صحة استدعاءات WezWordnCore. أول تحقق تجميعي حقيقي يكون على macOS عبر خطوة `xcodebuild` في `.github/workflows/build-ipa.yml` أو بناء محلي موثّق في `BUILD.md`. أي ادعاء بأن هذه الملفات «مترجمة ومختبرة» قبل ذلك غير صحيح.

## تحقق Phase B الإضافي (2026-10-21، Linux)

- `scripts/patches/01-settings-entry.py`: طُبّق فعليًا على نسخة مؤقتة من الملفات الستة المستهدفة في `/tmp` — نجح التطبيق، وكل الملفات الناتجة (شاملة `WezWordnFeaturesPresenter.swift` الجديد) مرّت `swiftc -parse`؛ إعادة التطبيق خرجت بـ exit 3 (already applied)؛ وحذف مرساة واحدة خرج بـ exit 2 مع **صفر** ملفات معدّلة (تحقق مرحلتين قبل أي كتابة). ملفات upstream الأصلية لم تُلمس.
- `WezWordnHealthMapping.swift`: اختبار وظيفي حقيقي لا parse فقط — جُمعت وحدة `VaultHealth` الفعلية من WezWordnCore كمكتبة، ورُبط الـ mapper معها ونُفّذت 15 assertion (host URI، قاعدة email، تخطّي الفارغ، ترتيب الدفعة، واستهلاك `VaultHealth.analyze` للمخرجات): **كلها ناجحة**.
- ما لم يُتحقق بعد ويحتاج macOS CI: سلامة أنواع طبقة الـ adapter والـ glue (استدعاءات `VaultRepository`/`CipherView`)، شمولية switch على `SettingsRoute`/`SettingsAction` في اختبارات upstream، وإعادة تسجيل snapshot tests لشاشة الإعدادات بعد إضافة الصف.
