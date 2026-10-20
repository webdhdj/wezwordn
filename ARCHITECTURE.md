# ARCHITECTURE — بنية WezWordn

> مصدر الحقائق عن upstream: فحص فعلي للقطة `bitwarden/ios` (فرع `main`، commit ‏`901bd4de8dbd9f5f7ba11b69499dd618feb0933c` وقت الفحص) — التقرير الكامل في `~/workspace/wezwordn-analysis/UPSTREAM_FINDINGS.md`. كل قيمة أدناه من ملفات اللقطة نفسها، لا من ذاكرة أو توثيق خارجي.

---

## 1) خريطة مكونات upstream

المستودع ليس تطبيقًا واحدًا: تطبيقان (Password Manager + Authenticator مستقل) فوق طبقات مشتركة، تُولّد مشاريعها بـ **XcodeGen 2.44.1** من ملفات `project-*.yml` — **لا يوجد أي `project.pbxproj` ملتزم** (العدد 0). ‏`.xcode-version` = ‏`26.6`، و deployment target: ‏iOS `15.0` / watchOS `8.0` (‏`project-common.yml`).

### 1.1 الوحدات

| المكوّن | الدور الفعلي في اللقطة |
|---|---|
| `Bitwarden/` | تطبيق Password Manager (الهدف `Bitwarden` في `project-pm.yml`) |
| `BitwardenShared/` | منطق PM المشترك: ‏`Core` مقسم ‏Auth / Autofill / Billing / Platform / Tools / Vault، وكل قسم ‏Models / Repositories / Services / Extensions / Utilities؛ والواجهة في `BitwardenShared/UI` |
| `BitwardenKit/` | طبقة المنصة المشتركة: أهداف `BitwardenKit` و`AuthenticatorBridgeKit` و`BitwardenResources` و`Networking` و`BitwardenSdkMocks`. فيها خدمات Keychain (‏`KeychainService`، `BiometricsKeychainRepository`) والبيومترية (‏`BiometricsService` في `Core/Auth/Services/Biometrics`) — Face ID/LocalAuthentication تعيش هنا مركزيًا |
| `Authenticator/` + `AuthenticatorShared/` | تطبيق Authenticator مستقل كامل (`project-bwa.yml`)، وTOTP الخاص به يُحسب عبر SDK (انظر §1.4) |
| `AuthenticatorBridgeKit/` | جسر PM↔Authenticator: ‏`SharedKeychain` ونموذج Core Data خاص ومجموعة مشاركة عبر `SHARED_APP_GROUP_IDENTIFIER` |
| `Networking/` | مجلد Sources/Tests داخل مشروع BitwardenKit المولّد — ليس Swift Package مستقلًا (لا يوجد أي `Package.swift` في المستودع كله) |
| `BitwardenWatchApp/` + `BitwardenWatchShared/` + `BitwardenWatchWidgetExtension` | تطبيق وودجت watchOS |
| `TestHarness/` + `TestHarnessShared/` | تطبيق حامل للاختبارات (`project-bwth.yml`) |

### 1.2 الامتدادات (App Extensions)

| الامتداد | لاحقة الـ bundle | الدور |
|---|---|---|
| `BitwardenAutoFillExtension` | `.autofill` | ‏AutoFill Credential Provider فعلي (‏`CredentialProviderViewController.swift`) — كلمات مرور + Passkeys + رموز OTP وفق قدرات الامتداد |
| `BitwardenActionExtension` | `.find-login-action-extension` | ‏Action extension للبحث/الملء من متصفحات وتطبيقات |
| `BitwardenShareExtension` | `.share-extension` | حفظ محتوى مشترك إلى الخزنة |
| `BitwardenNotificationExtension` | `.notification` | ‏Notification service extension |
| `BitwardenWatchWidgetExtension` | `.watchkitapp.widget-extension` | ودجت watchOS (داخل تطبيق الساعة، deployment ‏watchOS 9.0 خاص) |

كل امتداد له ملف `.entitlements` خاص، وجميعها تشترك في `group.$(BASE_BUNDLE_ID)` عبر `com.apple.security.application-groups` — هذه الصيغة هي ما يجعل فرض `BASE_BUNDLE_ID = com.wezcrypt.wezwordn` كافيًا لاشتقاق App Group جديد `group.com.wezcrypt.wezwordn` دون لمس أي ملف entitlements.

### 1.3 الهوية والتوقيع في upstream

من `Configs/Common-bwpm.xcconfig`:

```
CODE_SIGN_STYLE = Automatic
DEVELOPMENT_TEAM = LTZ2PFU5D6
ORGANIZATION_IDENTIFIER = com.8bit
BASE_BUNDLE_ID = $(ORGANIZATION_IDENTIFIER).bitwarden
SHARED_APP_GROUP_IDENTIFIER = group.com.bitwarden.bitwarden-authenticator
```

الآلية الرسمية الموثّقة في الملف نفسه: تجاوز القيم من `Configs/Local-bwpm.xcconfig` غير الملتزم. WezWordn يستخدمها كما هي عبر `identity/Local-WezWordn.xcconfig.example` — **صفر تعديلات على ملفات upstream المولّدة أو إعداداته الملتزمة**.

### 1.4 التشفير والمزامنة — أهم حقيقة هندسية

**التشفير لا يُنفّذ في Swift داخل هذا المستودع.** الأدلة من اللقطة: 602 موضع `import BitwardenSdk`؛ أنواع الخزنة (`CipherView`، `EncString`) من الـ SDK؛ توليد TOTP في Authenticator يتم عبر `clientService.vault().generateTOTPCode(...)` داخل الـ SDK. الحزمة `bitwarden/sdk-swift` (مثبتة عند revision ‏`e98eb30158d3d2239d8bb6e35daf0a3e65db77ec`) هي غلاف Swift + هدف ثنائي `BitwardenFFI` بصيغة XCFramework (نواة Rust). ما تعرضه طبقة Swift من بروتوكول الحساب: ‏KDF بنوعين فقط — `PBKDF2-SHA256` (‏`0`) و`Argon2id` (‏`1`) في `KdfType.swift`.

التخزين المحلي: 5 نماذج Core Data (‏`Bitwarden.xcdatamodeld`، `Authenticator.xcdatamodeld`، نموذج الجسر، نموذج الساعة، إضافة إلى نموذج Authenticator داخل تطبيقه).

**تبعة معمارية ملزمة لـ WezWordn:** أي ميزة محلية جديدة لا تستطيع إعادة استخدام تشفير الخزنة الأصلي إلا عبر واجهات SDK العامة؛ وما لا يعرّضه الـ SDK يُنفّذ بمكتبة موثوقة مستقلة (swift-crypto) ومفاتيح منفصلة في Keychain — مع عدم لمس تنسيق المزامنة.

### 1.5 حزم Swift المعلنة في upstream

`BitwardenSdk` (sdk-swift @ revision أعلاه)، `Firebase 12.14.0` (يُستخدم `FirebaseCrashlytics` فقط)، وتبعيات اختبار: `SnapshotTesting 1.19.4`، `ViewInspector 0.10.3`، وإضافات خاصة: `SwiftProtobuf 1.38.1` (Authenticator)، `SwiftUIIntrospect 26.0.1` (BitwardenKit). لا توجد أي مكتبة تشفير Swift مستقلة في `Package.resolved` — متسق مع §1.4.

---

## 2) طبقات WezWordn الجديدة

ثلاث طبقات مضافة، بحدود صارمة: الإضافات **وحدات مستقلة + ملفات تكامل**، والتعديل الوحيد على شجرة upstream عند البناء هو (أ) ملف `Local-bwpm.xcconfig` بالآلية الرسمية، (ب) نسخ ملفات التكامل إلى مجلد داخل هدف التطبيق، (ج) مقتطف ربط الحزمة في `project-pm.yml` (موثّق في `AppIntegration/README.md`).

```
┌─────────────────────────────────────────────────────────────┐
│ UI Integration (AppIntegration/, SwiftUI — iOS only)        │
│ WezWordnFeaturesRootView + KeychainKeyProvider              │
├─────────────────────────────────────────────────────────────┤
│ WezWordnCore (Swift Package — بلا أي اعتماد على upstream)   │
│ ExtendedLoginFields · LocalEncryptedStorage · LocalTOTP     │
│ VaultHealth · HIBPClient · EmergencyRecovery · SecureSharing│
│ التبعية الوحيدة: apple/swift-crypto (وحدة Crypto)          │
├─────────────────────────────────────────────────────────────┤
│ Upstream Bitwarden (دون تعديل)                              │
│ BitwardenShared · BitwardenKit · Extensions · BitwardenSdk  │
│ (Rust FFI: تشفير الخزنة، KDF، المزامنة، TOTP الخادمي)        │
└─────────────────────────────────────────────────────────────┘
```

| وحدة WezWordnCore | المسؤولية | خوارزمية/معيار |
|---|---|---|
| `ExtendedLoginFields` | ‏`ExtendedLogin` (username/email/password مستقلة) + بحث + تحقق بريد + ترحيل `LegacyLogin` بلا فقدان | نماذج `Codable` فقط — التشفير عند الحفظ مسؤولية طبقة التخزين |
| `LocalEncryptedStorage` | تشفير/فك ملفات مجزّأ streaming بتنسيق `WZEN v1` + بروتوكول `KeyProvider` | ‏AES-256-GCM، ‏nonce أساسي عشوائي 12B لكل ملف + XOR بعدّاد chunk (لا إعادة استخدام ‏(key, nonce) أبدًا)، ‏chunk افتراضي 64 KiB، علامة نهاية صريحة وكشف truncation |
| `LocalTOTP` | ‏HOTP/TOTP + ‏`otpauth://` parsing + Base32 | ‏RFC 4226 / RFC 6238 / RFC 4648؛ ‏HMAC-SHA1/256/512؛ ‏6–8 أرقام |
| `VaultHealth` | تحليل محلي: ضعيف/مكرر/قديم/حساب مكرر/بلا TOTP/بلا هوية + درجة بصيغة موثّقة في الكود | تقييم entropy تقديري موثّق كـ heuristic، قائمة كلمات شائعة صغيرة مدمجة معلنة كإشارة لا كوربوس تسريب |
| `HIBPClient` | فحص كلمات مرور عبر HIBP range API بوسيط نقل قابل للحقن (اختبارات offline) | ‏k-anonymity: ‏SHA-1 محلي، يُرسل prefix من 5 hex chars فقط |
| `EmergencyRecovery` | حزمة استرداد محلية: مفتاح خزنة مُغلّف لجهة موثوقة | ‏X25519 ephemeral + HKDF-SHA256 (‏info: `WezWordn-EmergencyRecovery-v1`) + AES-256-GCM |
| `SecureSharing` | حزم مشاركة `.wezshare` (JSON) لعنصر واحد + بصمة تحقق | نفس عائلة التغليف بـ info مستقل `WezWordn-SecureSharing-v1`؛ البصمة = SHA-256 للمكوّنات العامة |

## 3) فصل البيانات — خمس مناطق صارمة

| # | المنطقة | أين تعيش | من يملك مفاتيحها | مزامنة |
|---|---|---|---|---|
| 1 | بيانات Bitwarden المتزامنة رسميًا | Core Data + Keychain الخاصة بـ upstream | مفاتيح حساب Bitwarden عبر SDK | خوادم Bitwarden الرسمية — **تنسيقها لا يُعدَّل إطلاقًا** |
| 2 | ميزات WezWordn المحلية (حقول موسّعة، عناصر صحة، إعدادات محلية) | تخزين التطبيق المحلي (طبقة repositories عند الدمج الكامل) | مفتاح WezWordn المحلي | لا مزامنة |
| 3 | المرفقات المحلية المشفرة | `Application Support/WezWordn/EncryptedFiles/*.wzen` (مستبعدة من backup) | ‏`KeyProvider` ← Keychain (‏`WhenUnlockedThisDeviceOnly`) | لا مزامنة |
| 4 | أسرار TOTP المحلية | يجب أن تعيش مشفرة (Keychain/تخزين مشفر) عند الدمج الكامل — شاشة التكامل الحالية تبقيها في ذاكرة الجلسة فقط، مع TODO موثّق | مفتاح WezWordn المحلي | لا مزامنة |
| 5 | بيانات الاسترداد والمشاركة | حزم ملفات يصدّرها المستخدم ويحتفظ بها أين يختار (`.wezshare` / حزمة طوارئ JSON) | مفاتيح X25519 الخاصة بأصحابها | نقل يدوي (AirDrop/Share Sheet/ملفات) |

قواعد الفصل:

- لا منطقة WezWordn تكتب داخل قواعد/مفاتيح منطقة (1)، ولا العكس. فشل أو حذف أي منطقة محلية لا يمس بيانات الخزنة المتزامنة.
- امتداد الحقول (Username+Email): حقل `email` الإضافي **لا** يُحقن في تنسيق `CipherView` المتزامن. عند الدمج الكامل يُخزّن في المنطقة (2) مشفرًا ومرتبطًا بمعرّف العنصر؛ حقل `username` الأصلي يبقى كما هو لسلامة AutoFill ومطابقة URI (قرار الترحيل موثّق في كود `ExtendedLoginFields`: النسخ لا النقل).
- ترحيلات مناطق WezWordn المحلية مرقّمة الإصدار (`version` في تنسيقات الملفات والحزم) وقابلة للاختبار الآلي؛ ترحيلة فاشلة تُبقي البيانات الأصلية (فك التشفير يكتب إلى وجهة جديدة ولا يطمس المصدر عند الخطأ، والملف الجزئي يُحذف عند فشل GCM).

## 4) ما لم يتغير — ولماذا

- **بروتوكول المزامنة والمصادقة و2FA الخادمي**: كما في upstream عبر SDK. لم يُبنَ أي خادم WezWordn، ولم تُدّعَ أي قدرة تتطلب طرفًا موثوقًا (انظر حدود `SECURITY.md`).
- **AutoFill / Face ID / الامتدادات**: آليات upstream كما هي؛ دور WezWordn الوحيد هو الهوية الجديدة (bundle id + App Groups) عبر `xcconfig`، وما يترتب عليها عند إعادة التوقيع موثّق في `INSTALL.md`.
- **تطبيق Authenticator المستقل في upstream** يبقى جزءًا من الشجرة ويُبنى بمخططه الخاص؛ ميزة Authenticator في WezWordn (وحدة `LocalTOTP`) مدمجة داخل تطبيق PM ولا تستبدل تطبيق Authenticator الرسمي.
