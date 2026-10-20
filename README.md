# WezWordn

**WezWordn** — تطبيق iOS لإدارة كلمات المرور، مشروع **مشتق غير رسمي** من الشيفرة المصدرية المفتوحة لتطبيق Bitwarden (‏`bitwarden/ios`)، يضيف فوق وظائف upstream طبقة ميزات محلية مستقلة تعمل دون خوادم إضافية ودون اشتراكات مدفوعة.

- **المطوّر:** Wesam Majed — WezCrypt
- **Bundle Identifier:** `com.wezcrypt.wezwordn`
- **App Group الرئيسي:** `group.com.wezcrypt.wezwordn`
- **المنصة:** iOS — ‏deployment target ‏`15.0` (موروث من upstream)، يُبنى بـ Xcode `26.6`
- **الترخيص:** GNU GPLv3 — انظر ملف `LICENSE` في جذر هذا المستودع

> **عدم انتساب:** WezWordn ليس منتجًا من Bitwarden, Inc. ولا إصدارًا رسميًا منها، ولا يستخدم علاماتها التجارية كاسم أو هوية. الاسم والـ bundle identifier والـ App Group كلها مستقلة: التثبيت بجانب تطبيق Bitwarden الأصلي لا يستبدله ولا يشاركه بياناته.

---

## البنية في سطرين

```
wezwordn/
├── WezWordnCore/        حزمة Swift مستقلة (7 وحدات) — تُختبر بـ swift test على أي منصة
├── AppIntegration/      ملفات SwiftUI/Security تُدمج داخل تطبيق upstream عند البناء على macOS
├── identity/            قالب Local-bwpm.xcconfig لفرض هوية WezWordn بالآلية الرسمية في upstream
├── scripts/bootstrap.sh تجهيز بيئة macOS: جلب upstream + الهوية + XcodeGen
├── .github/workflows/   بناء واختبار وإنتاج IPA غير موقّع على macOS runners
└── upstream-ios/        شجرة bitwarden/ios (تُجلب محليًا، غير ملتزمة بهذا المستودع)
```

قلب التشفير والمزامنة والحسابات يبقى كما هو في upstream: مفوّضًا إلى `BitwardenSdk` (نواة Rust عبر FFI، ‏KDF: ‏PBKDF2-SHA256 / Argon2id). ميزات WezWordn الجديدة لا تلمس تنسيق المزامنة الرسمي ولا مفاتيح الخزنة — كل وحدة محلية لها مفاتيحها المستقلة في Keychain. التفاصيل في `ARCHITECTURE.md`.

## الميزات وحالتها الصادقة

مستويات الحالة: **مكتملة ومختبرة** (كود + اختبارات آلية ناجحة فعليًا) / **مدمجة غير مترجمة** (كود واجهة مكتوب واجتاز فحص syntax، بانتظار أول ترجمة على macOS) / **موثّقة فقط**.

| الميزة | الوحدة | الحالة |
|---|---|---|
| Username + Email كحقلين مستقلين + بحث وترحيل آمن من النموذج القديم | `ExtendedLoginFields` | منطق مكتمل ومختبر في الـ Core؛ شاشة التحرير مدمجة غير مترجمة |
| تخزين ملفات مشفر محلي (AES-256-GCM مجزّأ، streaming، بلا تحميل كامل في الذاكرة) | `LocalEncryptedStorage` | مكتمل ومختبر في الـ Core؛ واجهة Files file-backed مدمجة غير مترجمة؛ مفتاح الإنتاج في Keychain (`KeychainKeyProvider`) |
| TOTP/HOTP (‏RFC 4226 / RFC 6238: ‏SHA-1/256/512، ‏6–8 أرقام، فترات قابلة للضبط، ‏`otpauth://` URI، ‏Base32) | `LocalTOTP` | مكتمل ومختبر في الـ Core؛ شاشة Authenticator مدمجة غير مترجمة |
| تقارير صحة الخزنة (ضعيف/مكرر/قديم/مكرر حسابيًا/بلا TOTP + درجة أمان بصيغة موثّقة) | `VaultHealth` | مكتمل ومختبر في الـ Core؛ لوحة Security Reports مدمجة غير مترجمة |
| فحص التسريب عبر Have I Been Pwned بـ k-anonymity (أول 5 hex chars من SHA-1 فقط) | `HIBPClient` | مكتمل ومختبر في الـ Core بوسيط نقل قابل للحقن (اختبارات offline) |
| Emergency Recovery محلي (حزمة X25519 + HKDF-SHA256 + AES-256-GCM) | `EmergencyRecovery` | مكتمل ومختبر في الـ Core؛ حدوده (لا فترة انتظار ملزمة دون خادم) موثّقة في `SECURITY.md` |
| Secure Sharing (حزم `.wezshare` مشفرة بمفتاح عام + بصمة SHA-256 للتحقق خارج النطاق) | `SecureSharing` | مكتمل ومختبر في الـ Core؛ غير قابلة للسحب بعد فك التشفير عند المستلم — موثّق صراحة |
| وظائف Bitwarden الأصلية (خزنة، مزامنة، AutoFill، Face ID، امتدادات) | upstream كما هو | محفوظة بعدم التعديل؛ إعادة اختبارها تتم على macOS عبر مخطط upstream — انظر `FEATURE_MAPPING.md` |

حالة الاختبارات والبناء الفعلية لكل إصدار تُسجَّل في `SCAFFOLD_LOG.md` وتقارير البناء — لا تُستنتج من هذا الجدول وحده.

## ما لا يدّعيه هذا المشروع

- **لا يوجد ادعاء بدعم iOS 27**: لا ذكر له في upstream (أعلى SDK موثّق: iOS 26.5 / Xcode 26.6). التطبيق يستهدف iOS 15.0 فأعلى؛ التشغيل على إصدارات أحدث مسألة توافق نظام تشغيل، لا خاصية مختبرة هنا.
- **لا يوجد IPA موقّع جاهز** ما لم يُنتج فعليًا عبر مسار موثّق: الـ workflow ينتج IPA **غير موقّع** يحتاج إعادة توقيع (AltStore/SideStore أو شهادة المطوّر) — انظر `BUILD.md` و`INSTALL.md`.
- **لا تجاوز لصلاحيات الخادم**: ميزات Bitwarden التي تتطلب Premium على خوادمه ليست مستهدفة ولا مُعاد تنفيذها من جهة الخادم؛ بدائل WezWordn محلية بالكامل وتعمل على بيانات محلية فقط.
- **لا ضمان حذف فيزيائي** من ذاكرة flash، ولا سحب لمحتوى فُكّ تشفيره عند مستلم — انظر `SECURITY.md`.

## البدء السريع (macOS)

```bash
# 1) تجهيز: Xcode 26.6 + جلب upstream + فرض الهوية + توليد المشاريع
./scripts/bootstrap.sh

# 2) ضع DEVELOPMENT_TEAM الخاص بك في:
#    upstream-ios/Configs/Local-bwpm.xcconfig

# 3) اربط حزمة WezWordnCore في project-pm.yml بالمقتطف في AppIntegration/README.md
#    ثم أعد التوليد وافتح الـ workspace:
cd upstream-ios && mint run xcodegen --spec project-pm.yml
open Bitwarden.xcworkspace
```

التفاصيل الكاملة: `BUILD.md` (بناء واختبار وأرشفة) و`INSTALL.md` (تثبيت وسideloading وقيوده).

## الترخيص والتزامات التوزيع

هذا العمل مشتق من `bitwarden/ios` المرخّص بـ **GPLv3** (الملف الأصلي `LICENSE.txt` منسوخ حرفيًا إلى `LICENSE` هنا). أي توزيع لنسخة مبنية (بما فيها أي IPA) يلزمك بـ:

1. توفير الشيفرة المصدرية المقابلة كاملة (upstream + تعديلات WezWordn) بنفس الترخيص.
2. الاحتفاظ بإشعارات حقوق المؤلف والترخيص في المصدر والمنتج.
3. عدم تقديم العمل على أنه صادر عن Bitwarden, Inc.

تنبيه مفتوح موثّق في تحليل upstream: ترخيص نواة `BitwardenSdk` الثنائية (مستودع `bitwarden/sdk-swift` ومن خلفه `sdk`) لم يُفحص فحصًا كاملًا مستقلًا في هذه المرحلة؛ حسمه واجب قبل أي توزيع خارجي واسع.

## الوثائق

`ARCHITECTURE.md` — خريطة المكونات وفصل البيانات · `FEATURE_MAPPING.md` — ربط كل وظيفة بمكوّنها · `REA_ANALYSIS.md` — تحليل الـ IPA المرفق وأداة REA · `SECURITY.md` — نموذج التهديد وحدود الحماية · `BUILD.md` / `INSTALL.md` — البناء والتثبيت · `CHANGELOG.md` — سجل التغييرات
