# CHANGELOG — WezWordn

كل ما يلي يصف ما أُنجز فعليًا في التاريخ المذكور فقط. لا إدخالات استباقية لميزات لم تُسلّم.

## [0.1.0] — 2026-10-20

أول هيكل مشروع متكامل (scaffold) فوق لقطة upstream `bitwarden/ios` عند commit ‏`901bd4de8dbd9f5f7ba11b69499dd618feb0933c` (فرع `main`).

### أُضيف

- **هوية التطبيق** عبر الآلية الرسمية في upstream: قالب `identity/Local-WezWordn.xcconfig.example` يفرض `BASE_BUNDLE_ID = com.wezcrypt.wezwordn` و`ORGANIZATION_IDENTIFIER = com.wezcrypt` و`SHARED_APP_GROUP_IDENTIFIER = group.com.wezcrypt.wezwordn.shared` (الـ App Group الرئيسي `group.com.wezcrypt.wezwordn` مشتق من صيغة `group.$(BASE_BUNDLE_ID)` في entitlements الخاصة بـ upstream) — وقيمة `DEVELOPMENT_TEAM` متروكة للمستخدم دون أي قيمة مختلقة.
- **حزمة `WezWordnCore`** (من عامل موازٍ ضمن نفس الإصدار): سبع وحدات Swift مستقلة بتبعية وحيدة `apple/swift-crypto` — ‏`ExtendedLoginFields` (حقول Username/Email مستقلة + ترحيل بلا فقدان)، `LocalEncryptedStorage` (‏AES-256-GCM مجزّأ بتنسيق `WZEN v1`)، `LocalTOTP` (‏RFC 4226/6238 + ‏`otpauth://`)، `VaultHealth` (تقارير صحة بصيغة درجة موثّقة)، `HIBPClient` (‏k-anonymity، ‏prefix من 5 hex chars)، `EmergencyRecovery` و`SecureSharing` (تغليف X25519 + HKDF-SHA256 + AES-256-GCM).
- **طبقة تكامل iOS** في `AppIntegration/`: ‏`WezWordnFeaturesRootView.swift` (‏NavigationStack بخمسة أقسام وظيفية تستدعي واجهات الـ Core الحقيقية + محرر Login) و`KeychainKeyProvider.swift` (‏`KeyProvider` إنتاجي بـ Security framework و`WhenUnlockedThisDeviceOnly`)، مع `README.md` يوثّق الدمج في XcodeGen ومقتطف `project-pm.yml` جاهزًا، ويصرّح بحدود TODO المتبقية (الحفظ المشفر الدائم لأسرار TOTP والمفاتيح الخاصة في طبقة التطبيق المضيف).
- **سكربت `scripts/bootstrap.sh`**: تجهيز macOS كامل (فحص Xcode، جلب upstream بـ git أو tarball رسمي بديل موثّق السبب، نسخ الهوية وملفات التكامل، توليد المشاريع بـ XcodeGen بنفس ترتيب upstream الرسمي).
- **GitHub Actions** في `.github/workflows/build-ipa.yml`: ‏swift test للحزمة + ‏xcodebuild test لمخطط `Bitwarden` على محاكي upstream + أرشفة `CODE_SIGNING_ALLOWED=NO` + تجميع `WezWordn.ipa` غير موقّع من الـ `.app` + ‏SHA-256 ورفع artifacts، مع تعليقات صريحة بأن الناتج يحتاج إعادة توقيع.
- **وثائق المشروع**: ‏`README.md`، `ARCHITECTURE.md` (خريطة upstream + فصل البيانات الخمس)، `REA_ANALYSIS.md` (تحليل ثابت فعلي للـ IPA المرفق: ‏`2026.10.0` build `3551`، ‏ARM64 thin، ‏SDK 26.5، الامتدادات والـ entitlements، وتوثيق حالة أداة REA دون ادعاء استخدامها)، `FEATURE_MAPPING.md` (بما فيه قائمة فجوات معلنة)، `SECURITY.md` (نموذج تهديد وحدود صريحة)، `BUILD.md`، `INSTALL.md`، و`LICENSE` منسوخ حرفيًا من `LICENSE.txt` الخاص بـ upstream (GPLv3).

### تحقق منفّذ في هذا الإصدار

- `bash -n` على `scripts/bootstrap.sh`: ناجح (فحص syntax فقط — السكربت لم يُشغّل فعليًا لعدم وجود macOS).
- `swiftc -parse` (‏Swift 6.1.2 على Linux) على ملفي `AppIntegration`: ناجح بلا تشخيصات (فحص بنية نحوية فقط — لا ترجمة ولا فحص أنواع؛ SwiftUI/Security غير متاحين خارج Apple SDKs).

### لم يُنجز بعد (حالة صريحة)

- أي بناء Xcode أو IPA فعلي: لا يوجد macOS/Xcode في بيئة الإنشاء؛ المساران (محلي وCI) موثّقان ومجهّزان ولم يُشغّلا.
- ترجمة/اختبار طبقة `AppIntegration` على محاكي أو جهاز.
- حسم فحص ترخيص مكوّنات `BitwardenSdk` الثنائية قبل أي توزيع خارجي.
- دعم iOS 27: غير موجود في upstream وغير مُدّعى هنا.
