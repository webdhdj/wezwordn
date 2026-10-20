# FEATURE_MAPPING — ربط الوظائف بمكوناتها الحقيقية

> القاعدة: «محفوظة» تعني أن المكوّن upstream المسؤول موجود في اللقطة المفحوصة وأن WezWordn لا يعدّله — لا تعني أن اختبارًا آليًا لـ WezWordn أثبت عمله على جهاز؛ حالة التحقق لكل صف مذكورة صراحة. مصدر أسماء المكونات: `~/workspace/wezwordn-analysis/UPSTREAM_FINDINGS.md` وملفات اللقطة نفسها.

## 1) وظائف Bitwarden الأصلية المطلوب الحفاظ عليها

| الوظيفة المطلوبة | مكوّن upstream الحقيقي | آلية الحفاظ في WezWordn | حالة التحقق |
|---|---|---|---|
| إضافة/تعديل/حذف عناصر الخزنة، بحث، تصنيف، مفضلة، مجلدات | `BitwardenShared/Core/Vault` (Models/Repositories/Services) + `BitwardenShared/UI` | لا تعديل؛ تُبنى كما هي من `project-pm.yml` | محفوظة بالبناء — إعادة اختبارها على macOS ضمن مخطط `Bitwarden` |
| ملاحظات آمنة، بطاقات، هويات، حقول مخصصة | نماذج `CipherView` وأنواعها داخل `BitwardenSdk` + طبقة Vault في `BitwardenShared` | لا تعديل في النماذج أو تنسيق التشفير | محفوظة بالبناء |
| مولّد كلمات المرور | ‏`BitwardenShared/Core/Tools` + دوال SDK | لا تعديل | محفوظة بالبناء |
| قفل الخزنة وإعدادات الحماية | ‏`BitwardenKit` (خدمات المنصة) + `BitwardenShared/Core/Auth` | لا تعديل | محفوظة بالبناء |
| تسجيل الدخول/الخروج، إدارة حسابات، استعادة الحالة | `BitwardenShared/Core/Auth` (Repositories/Services) عبر `ClientService` إلى SDK | لا تعديل؛ التوافق مع حساب قائم يخضع لبروتوكول الخادم كما هو | محفوظة بالبناء — **لم** يُختبر تسجيل دخول حقيقي في هذه البيئة (لا حسابات حقيقية في الاختبارات أصلًا) |
| المزامنة وتحديث بيانات الخزنة | طبقة `Networking` (داخل مشروع BitwardenKit) + مزامنة SDK | لا تعديل في أي تنسيق أو endpoint | محفوظة بالبناء |
| التحقق الثنائي الخادمي (2FA عند الدخول، FIDO2/WebAuthn/Passkeys من جهة الخادم) | ‏`BitwardenShared/Core/Auth` + SDK + قدرات AutoFill extension المعلنة (Passkeys) | لا تعديل؛ ما يدعمه الخادم وApple APIs فقط هو ما يعمل — لا خيارات مضافة تدّعي دعمًا خادميًا غير موجود | محفوظة بالبناء |
| Face ID / البيومترية | `BitwardenKit/Core/Auth/Services/Biometrics` (‏`BiometricsService`/`BiometricsRepository`) + `BiometricsKeychainRepository` | لا تعديل | محفوظة بالبناء |
| Keychain (حماية مفاتيح الجلسة/الخزنة) | `BitwardenKit/Core/Platform/Services` (‏`KeychainService`/`KeychainServiceFacade`) | لا تعديل؛ مفاتيح WezWordn المحلية في عناصر Keychain منفصلة بخدمة خاصة (`KeychainKeyProvider`) ولا تصطدم بعناصر upstream | محفوظة + فصل موثّق |
| AutoFill | `BitwardenAutoFillExtension` (‏`CredentialProviderViewController.swift`) + entitlement ‏`autofill-credential-provider` | الهوية الجديدة فقط عبر `BASE_BUNDLE_ID`؛ قيود إعادة التوقيع في `INSTALL.md` | محفوظة بالبناء — تعمل كاملة بالتوقيع الأصلي/فريق المطوّر؛ بـ sideloading تخضع لقيود الفريق الشخصي |
| المرفقات (Attachments الخادمية الأصلية) | طبقة Vault/Tools في `BitwardenShared` + SDK | لا تعديل؛ ملاحظة: حدودها الخادمية (بما فيها اشتراطات الحساب) كما هي — بديل WezWordn المحلي منفصل ولا يدّعي أنه هي | محفوظة بالبناء |
| استيراد/تصدير بيانات الخزنة | أدوات Vault في `BitwardenShared/Core/Tools` | لا تعديل | محفوظة بالبناء |
| التشفير الأصلي وسلامة البيانات | `BitwardenSdk` (‏`BitwardenFFI`، Rust) — ‏KDF: ‏PBKDF2-SHA256 / Argon2id (`KdfType` في طبقة Swift) | ممنوع الإضعاف: لا كود WezWordn يلمس هذه المسارات | محفوظة بالبناء |
| الامتدادات (Action/Share/Notification/Watch) | المجلدات الأربعة + ودجت الساعة (انظر `ARCHITECTURE.md` §1.2) | تنتقل هوياتها تلقائيًا مع `BASE_BUNDLE_ID` الجديد | محفوظة بالبناء |
| العربية وRTL | حزم توطين upstream (`ar.lproj` موجودة في الـ IPA والمصدر) + اتجاه واجهة iOS | لا تعديل؛ أقسام WezWordn الجديدة تستخدم عناوين إنجليزية تقنية مع واجهة تتبع اتجاه النظام | محفوظة بالبناء |

## 2) ميزات WezWordn الجديدة

| الميزة المطلوبة | الوحدة المنفّذة | التكامل في الواجهة | حالة التنفيذ |
|---|---|---|---|
| Username + Email مستقلان (بحث، نسخ فردي، تعديل، بيانات قديمة، تشفير الحقول) | `ExtendedLoginFields` (`ExtendedLogin` + `migrate(legacy:)`) | `ExtendedLoginEditorView` في `AppIntegration` | Core: مكتمل ومختبر. التشفير عند الحفظ: عبر طبقة التخزين المحلية عند الدمج الكامل (النموذج نفسه `Codable` محايد التخزين — موثّق في `ARCHITECTURE.md` §3). التعبئة التلقائية: تبقى على `username` الأصلي عمدًا |
| Encrypted File Storage (استيراد Files/صور/PDF/مستندات/مفاتيح، مجلدات منطقية، إعادة تسمية، بحث، معاينة آمنة، حذف، مساحة مستخدمة، ربط بعناصر، تصدير بعد فك التشفير) | `LocalEncryptedStorage` (تنسيق `WZEN v1` مجزّأ) + `KeychainKeyProvider` | `EncryptedFilesView` file-backed (استيراد/تشفير/معاينة/حذف/حجم) | Core: مكتمل ومختبر (منها ملفات كبيرة مجزّأة وكشف corruption). الواجهة: استيراد ومعاينة نصية وحذف ومساحة منفّذة؛ الربط بعناصر الخزنة والمجلدات المنطقية وإعادة التسمية **غير منفّذة في شاشة التكامل** — حالة صريحة لا واجهة وهمية |
| TOTP متقدم داخل عناصر الخزنة (SHA-1/256/512، 6–8 أرقام، فترات، QR، ‏`otpauth://`، إدخال يدوي، نسخ، عدّاد متبقٍّ، حسابات متعددة، أسرار مشفرة) | `LocalTOTP` (`OTPGenerator`/`OTPAuthParser`/`Base32`) | `AuthenticatorView` (URI + يدوي + قائمة حية + نسخ) | Core: مكتمل ومختبر مقابل متجهات RFC. QR: التحليل عبر نفس `OTPAuthParser`، ومسح الكاميرا مسؤولية التطبيق المضيف (لا ماسح مدمج في ملفات التكامل). حفظ الأسرار مشفرًا دائمًا: TODO موثّق في الكود — الجلسة الحالية في الذاكرة فقط |
| FIDO2 / WebAuthn / YubiKey / Passkeys / Duo كمصادقة | — (لا وحدة جديدة) | — | **لم تُنفّذ كميزة WezWordn**: ما يعمل منها هو ما يدعمه upstream + خوادم Bitwarden + Apple APIs أصلًا (Passkeys عبر AutoFill، NFC ‏`TAG` في الـ entitlements). أي طبقة إضافية تتطلب دعم خادم غير متوفر لم تُبنَ ولم تُعرض في الواجهة — التزامًا بقاعدة عدم عرض خيار لا يعمل |
| Vault Health Reports + Security Dashboard | `VaultHealth` (+ `HIBPClient` اختياريًا) | `SecurityReportsView` (لوحة أعداد + درجة + قائمة مشكلات وتوصيات في تفاصيل كل مشكلة) | Core: مكتمل ومختبر؛ الدرجة بصيغة موثّقة داخل الكود. التقارير الأساسية offline بالكامل؛ HIBP وحده online واختياري |
| Emergency Access (جهات موثوقة، مفتاح عام، حزمة مشفرة، تحقق سلامة، استيراد/تصدير) | `EmergencyRecovery` (حزمة JSON ‏version 1) | `EmergencyRecoveryView` (توليد زوج مفاتيح، إنشاء حزمة، استرداد) | Core: مكتمل ومختبر (مفتاح خاطئ يفشل GCM). البديل المحلي فقط: **لا** فترة انتظار ملزمة ولا إشعارات طلب ولا إلغاء موزّع — تحتاج خادمًا/طرفًا موثوقًا، موثّق في `SECURITY.md` |
| Secure Sharing (كلمات مرور/ملاحظات/ملفات، حزم مشفرة، AirDrop/Share Sheet، تحقق سلامة) | `SecureSharing` (`.wezshare`، بصمة SHA-256) | `SecureSharingView` (إنشاء/فتح/بصمة) | Core: مكتمل ومختبر للنصوص/العناصر (`ShareableItem`). مشاركة **الملفات** كحزم: غير منفّذة (الملفات الكبيرة تذهب عبر `LocalEncryptedStorage` + نقل الملف المشفر نفسه، لا عبر حزمة JSON). AirDrop/Share Sheet ينقلان بايتات الحزمة الجاهزة — طبقة نظام لا كود مخصص. لا سحب بعد فك التشفير — موثّق |
| فصل البيانات الخمس + Migration آمنة قابلة للاختبار | تصميم `ARCHITECTURE.md` §3 + `version` في كل تنسيقات WezWordn | — | التنسيقات مرقّمة والترحيل الوحيد المطلوب حاليًا (`LegacyLogin`→`ExtendedLogin`) منفّذ ومختبر وبلا فقدان |

## 3) ملخص فجوات معلن (لا فجوات مخفية)

1. حفظ TOTP secrets والمفاتيح الخاصة (Emergency/Sharing) بشكل دائم مشفر: طبقة repositories في التطبيق المضيف — TODO موثّق في `AppIntegration`، ليس منفّذًا بعد.
2. ربط الملفات المشفرة بعناصر الخزنة + مجلدات منطقية + إعادة تسمية داخل شاشة Files: غير منفّذة.
3. حزم مشاركة للملفات الثنائية الكبيرة: غير منفّذة (البديل الموثّق: نقل ملف `WZEN` المشفر نفسه).
4. ماسح QR للكاميرا داخل ملفات التكامل: غير منفّذ (الـ parsing الحقيقي موجود ومختبر).
5. أول ترجمة/اختبار على macOS لطبقة `AppIntegration` كاملة: لم تحدث بعد في بيئة إنشاء هذا الهيكل (لا Xcode هنا) — مسارها `.github/workflows/build-ipa.yml`.
