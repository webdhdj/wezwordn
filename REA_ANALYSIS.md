# REA_ANALYSIS — تحليل IPA المرفق وأداة REA

> نطاق هذا التحليل: فحص ثابت (static) مصرح به لملف IPA قدّمه مالك المشروع، بأدوات قياسية (فك ZIP، قراءة `Info.plist` بـ plist parsing، قراءة Mach-O header). لم يُكسر أي تشفير، ولم تُستخرج مفاتيح مستخدم، ولم يُتجاوز أي آلية حماية. قيم هذا الملف إما منسوبة لتحليل فعلي مذكور أدناه أو موثّقة في تقرير الفحص المرجعي `~/workspace/wezwordn-analysis/UPSTREAM_FINDINGS.md`.

---

## 1) الملف المفحوص — الهوية والسلامة

| البند | القيمة |
|---|---|
| اسم الملف كما رُفع | `Bitwarden.ipa` (مرفق مع طلب المشروع) |
| الحجم | ‏59 MB (كما ظهر في بيئة الفحص) |
| SHA-256 | `943e06916964a73791ca1fbedfb21eea501785e9e16843f2322be420397994fe` — مُتحقق منه في جلسة إنشاء هذا الهيكل بأمر `sha256sum` على الملف المرفق نفسه |
| البنية | ‏IPA = ZIP يحتوي `Payload/Bitwarden.app` (+ مجلد `Signatures/` لتوقيعات XCFramework) |

## 2) Bundle Metadata — من `Info.plist` الفعلي داخل الـ IPA

قُرئت القيم التالية مباشرة من `Payload/Bitwarden.app/Info.plist` (binary plist) في جلسة إنشاء هذا الهيكل:

| المفتاح | القيمة |
|---|---|
| `CFBundleIdentifier` | `com.8bit.bitwarden` |
| `CFBundleShortVersionString` | `2026.10.0` |
| `CFBundleVersion` (build) | `3551` |
| `CFBundleDisplayName` / `CFBundleName` | `Bitwarden` |
| `MinimumOSVersion` | `15.0` |
| `DTSDKName` | `iphoneos26.5` |
| `DTPlatformVersion` | `26.5` |
| `CFBundleSupportedPlatforms` | `iPhoneOS` |

ملاحظات:

- الإصدار `2026.10.0` يطابق أحدث Release منشور على GitHub وقت الفحص (‏`v2026.10.0-bwpm` بتاريخ 2026-10-16)، بينما لقطة `main` تحمل `MARKETING_VERSION: 2026.4.0` — القيمتان موثّقتان كما وُجدتا دون تفسير مختلق.
- **لا دعم iOS 27**: أعلى SDK في الـ IPA هو 26.5، و `MinimumOSVersion` هو 15.0. لا يوجد في الـ IPA ولا في المصدر أي ذكر لـ iOS 27 كهدف بناء أو اختبار.

## 3) Mach-O والبنية

- التنفيذي الرئيسي `Payload/Bitwarden.app/Bitwarden`: ‏magic ‏`cffaedfe` = ‏Mach-O 64-bit، بنية **ARM64 thin** (ملف واحد غير fat) — متسق مع توزيع App Store الحديث لأجهزة ARM64.
- الحزمة تتضمن `BitwardenFFI.xcframework` (تظهر توقيعاته في `Signatures/BitwardenFFI.xcframework-ios.signature`) — تأكيد ثنائي مستقل لحقيقة المصدر: نواة التشفير تأتي من `BitwardenSdk` كـ binary FFI، لا من كود Swift داخل التطبيق.

## 4) الامتدادات داخل الـ IPA

أربعة امتدادات في `Payload/Bitwarden.app/PlugIns/`، وخامس (ودجت) متداخل داخل تطبيق الساعة في `Watch/BitwardenWatchApp.app/PlugIns/`:

| الامتداد | Bundle ID داخل الـ IPA | نقطة التمديد (`NSExtensionPointIdentifier`) / ملاحظة |
|---|---|---|
| `BitwardenAutoFillExtension.appex` | `com.8bit.bitwarden.autofill` | ‏`com.apple.authentication-services-credential-provider-ui` — قدراته المعلنة في `Info.plist`: ‏Passwords + Passkeys + OneTimeCodes + TextToInsert + توليد/حفظ كلمات مرور + Credential Exchange 1.0 |
| `BitwardenActionExtension.appex` | `com.8bit.bitwarden.find-login-action-extension` | ‏`com.apple.ui-services` — قاعدة تفعيل تغطي `find-login` / `save-login` / `change-password` / `fill-*` actions |
| `BitwardenShareExtension.appex` | `com.8bit.bitwarden.share-extension` | ‏`com.apple.share-services` — يدعم نصًا وملفًا واحدًا وصورة واحدة كحد أقصى لكل مشاركة |
| `BitwardenNotificationExtension.appex` | `com.8bit.bitwarden.notification` | ‏`com.apple.usernotifications.service` — الفئة الرئيسية `NotificationServiceExtension` |
| `BitwardenWatchWidgetExtension.appex` | `com.8bit.bitwarden.watchkitapp.widget-extension` | ‏`com.apple.widgetkit-extension` (داخل تطبيق الساعة) |

كل امتداد يحمل `embedded.mobileprovision` خاصًا به، والتطبيق الرئيسي كذلك — أي أن إعادة التوقيع (sideloading) يجب أن تعيد توقيع كل مكوّن على حدة وتصحّح الـ bundle IDs والـ groups معًا، كما هو موثّق في `INSTALL.md`.

## 5) الـ Entitlements الرئيسية (من مصدر upstream المقابل لهذه البنية)

ملفات الـ entitlements في الشجرة المصدرية المطابقة (الـ IPA الإنتاجي قد يضيف قيود متجر لا تظهر في المصدر):

| المفتاح | القيمة/الصيغة | الأثر |
|---|---|---|
| `com.apple.security.application-groups` | ‏`group.$(BASE_BUNDLE_ID)` + `$(SHARED_APP_GROUP_IDENTIFIER)` | عند فرض هوية WezWordn يصبح الأول `group.com.wezcrypt.wezwordn` تلقائيًا |
| `com.apple.developer.authentication-services.autofill-credential-provider` | `true` (التطبيق الرئيسي + امتداد AutoFill) | شرط عمل AutoFill Credential Provider |
| `keychain-access-groups` | `$(AppIdentifierPrefix)$(BASE_BUNDLE_ID)` | تُعاد كتابته بمعرّف فريق من يعيد التوقيع |
| `com.apple.developer.associated-domains` | ‏`webcredentials:` / `applinks:` لنطاقات `*.bitwarden.com` و `.eu` و `.pw` و `-gov.com` | **تنبيه مشتق:** هذه النطاقات تخص Bitwarden؛ بقاؤها في مشتق موقّع بفريق آخر غير فعّال عمليًا (يتطلب ملف `apple-app-site-association` على تلك النطاقات) ويجب تقييم إزالتها قبل أي توزيع — موثّق هنا كقرار مفتوح، لا كتعديل منفّذ |
| `com.apple.developer.nfc.readersession.formats` | `TAG` | قراءة NFC (مفاتيح أمان/عوامل أجهزة) |
| `com.apple.developer.ubiquity-container-identifiers` | ‏`iCloud.$(CFBundleIdentifier)` | حاوية iCloud مرتبطة بالـ bundle id |
| `aps-environment` | `development` في ملف مصدر التطبيق الرئيسي | بيئة إشعارات التطوير في البنية المصدرية |

## 6) URL Schemes والموارد

- لم تُستخرج قائمة URL schemes مخصصة موثّقة من الـ IPA في هذه الجلسة، ولا يُدّعى أي scheme بعينه هنا. مخططات `otpauth://` ذات الصلة بميزة Authenticator هي مدخلات بيانات لوحدة `LocalTOTP` (parsing في `OTPAuthParser`) وليست schemes مسجلة باسم التطبيق بالضرورة.
- الموارد داخل الحزمة تشمل حزم Firebase (`Firebase_FirebaseCore.bundle` وغيرها) وملفات توطين واسعة (منها `ar.lproj` و `he.lproj` و `fa.lproj` — دعم RTL موجود في upstream أصلًا) — تعداد شامل للموارد خارج نطاق هذا التحليل الثابت.

## 7) أداة REA (‏`morluto/rea`) — الحالة الحقيقية

**الأداة موجودة فعلًا، ولم تُثبّت ولم تُشغّل في هذه البيئة. هذا القسم توثيق تحقق، لا ادعاء استخدام.**

| البند | القيمة المُتحقق منها (GitHub API + README + ‏`package.json` خام) |
|---|---|
| المستودع | `morluto/rea` — «Reverse engineer anything with agents, from app behavior down to native binaries» |
| الترخيص | MIT (‏`Copyright (c) 2026 morluto`) |
| الطبيعة | ‏MCP server + CLI يصل وكيل برمجة بأدوات هندسة عكسية قائمة (Ghidra / Hopper / IDA عند توفرها محليًا) |
| أمر الإعداد الموثّق | `npx rea-agents setup` (README: ‏Quick start + قسم Set up your agent؛ صيغة التحديث `npx rea-agents@latest setup`) |
| الحزمة | `rea-agents` إصدار `6.7.0`، ‏`bin`: ‏`rea` / `rea-agents` ← `scripts/rea.mjs` |
| متطلب Node | ‏`^22.19.0 \|\| ^24.11.0 \|\| >=26.0.0` (حقل `engines` في `package.json`) |
| الموقع الرسمي | `https://rea.tools` — وتحذير README نفسه: المصادر الرسمية هي `morluto/rea` و `rea.tools` وحزمة npm `rea-agents` فقط؛ تشابه اسم مستودع آخر لا يثبت رسميته |

**لماذا لم تُستخدم هنا:** (1) بيئة التنفيذ Linux بلا Xcode ولا Ghidra/IDA/Hopper — نصف قيمة REA (ربط أدوات التحليل الثنائية بسطح مكتب macOS) غير متاح أصلًا؛ (2) محاولة `git clone` للمستودع لم تكتمل عبر بروكسي هذه البيئة (timeout موثّق في تقرير الفحص)؛ (3) كل ما احتاجه التحليل الثابت للـ IPA (plist/Mach-O/entitlements/extensions) أُنجز بأدوات قياسية ونتائجه أعلاه. أي استخدام لاحق لـ REA على macOS يجب أن يبدأ بمراجعة تغييرات `setup` المقترحة على إعدادات الوكيل قبل الموافقة عليها، كما ينص README نفسه.

## 8) حدود هذا التحليل

- تحليل ثابت فقط: لا تشغيل للتطبيق، لا اعتراض شبكة، لا فحص runtime، لا تحليل Ghidra للتنفيذيات في هذه الجلسة.
- الـ IPA بنية إنتاج موقّعة من Bitwarden؛ استُخدم مرجعًا للمقارنة البنيوية فقط. تطوير WezWordn يعتمد على **المصدر الرسمي** وحده، ولا يُعاد توزيع أي جزء من هذا الـ IPA.
