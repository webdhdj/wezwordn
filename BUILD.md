# BUILD — بناء WezWordn على macOS خطوة بخطوة

> كل خطوة هنا مبنية على حقائق upstream المفحوصة: لا `xcodeproj` ملتزم، التوليد بـ XcodeGen من `project-*.yml`، ‏Xcode مطلوب `26.6` (‏`.xcode-version`)، محاكي اختبار iOS `26.5` على `iPhone 17 Pro`، deployment target ‏iOS `15.0`. **لم يُنفّذ أي بناء في بيئة إنشاء هذا الهيكل (Linux بلا Xcode)** — أول تنفيذ فعلي يكون على جهازك أو عبر GitHub Actions، ونتائجه تُسجّل في سجل البناء لا تُفترض هنا.

## 0) المتطلبات

| المتطلب | القيمة | ملاحظة |
|---|---|---|
| نظام | macOS حديث يدعم Xcode 26.6 | البناء مستحيل على Linux/Windows |
| Xcode | `26.6` بالتحديد وفق `upstream/.xcode-version` | إصدار مختلف قد يبني لكنه انحراف موثّق عن متطلب upstream |
| أدوات | Homebrew + ‏mint (أو XcodeGen مباشرة) | ‏`Mintfile` في upstream يثبّت `xcodegen@2.44.1` وSwiftGen وSwiftLint وSwiftFormat وSourcery وLicensePlist |
| حساب | Apple ID على الأقل (فريق شخصي) للتوقيع على جهاز؛ Apple Developer Program للـ provisioning الكامل | البناء غير الموقّع لا يحتاج أي حساب |
| مساحة/شبكة | عدة GB لـ DerivedData وحزم SwiftPM (Firebase، SDK) | أول توليد يجلب كل التبعيات |

## 1) تجهيز الشجرة (مرة واحدة)

```bash
cd wezwordn
./scripts/bootstrap.sh
```

السكربت: يتحقق من Xcode → يجلب upstream إلى `upstream-ios/` (‏git clone أو tarball رسمي من codeload عند فشل git) → ينسخ `identity/Local-WezWordn.xcconfig.example` إلى `upstream-ios/Configs/Local-bwpm.xcconfig` → ينسخ ملفات `AppIntegration/*.swift` إلى `upstream-ios/Bitwarden/Application/WezWordnFeatures/` → يولّد المشاريع الأربعة بـ XcodeGen بنفس ترتيب سكربت upstream الرسمي. فحصه المنفّذ في بيئة الإنشاء: `bash -n` فقط (syntax) — موثّق في `SCAFFOLD_LOG.md`.

## 2) ضبط الهوية والتوقيع

افتح `upstream-ios/Configs/Local-bwpm.xcconfig` (الآلية الرسمية الموثّقة في `Configs/Common-bwpm.xcconfig` نفسه) وتأكد من:

```
BASE_BUNDLE_ID = com.wezcrypt.wezwordn
ORGANIZATION_IDENTIFIER = com.wezcrypt
SHARED_APP_GROUP_IDENTIFIER = group.com.wezcrypt.wezwordn.shared
DEVELOPMENT_TEAM = <معرّف فريقك من 10 أحرف>   ← أزل التعليق وضع قيمتك
```

المشتقات التلقائية: الـ App Group الرئيسي `group.$(BASE_BUNDLE_ID)` = ‏`group.com.wezcrypt.wezwordn`، ومعرّفات الامتدادات `com.wezcrypt.wezwordn.autofill` و`.find-login-action-extension` و`.share-extension` و`.notification` إضافة إلى تطبيق الساعة وودجته — كلها من صيغ upstream دون تعديل ملفات.

للبناء غير الموقّع فقط (CI/تحقق ترجمة): تجاوز بـ `CODE_SIGNING_ALLOWED=NO` على سطر الأوامر ولا حاجة لفريق حقيقي.

## 3) ربط WezWordnCore

قبل أول بناء يتضمن ملفات التكامل: ألصق مقتطف الحزمة المحلية وتبعيات الهدف من `AppIntegration/README.md` في `project-pm.yml`، ثم أعد التوليد:

```bash
cd upstream-ios
mint run xcodegen --spec project-pm.yml
```

بدون هذه الخطوة ستفشل ترجمة ملفات `WezWordnFeatures/` لغياب الوحدات — فشل صريح مقصود بدل بناء ناقص صامت.

## 4) اختبارات WezWordnCore (لا تحتاج محاكيًا)

```bash
cd WezWordnCore
swift test
```

تعمل على macOS وLinux على حد سواء (الحزمة بلا أي اعتماد على أطر Apple الخاصة بالواجهة؛ تبعيتها الوحيدة `apple/swift-crypto`).

## 5) اختبارات upstream + التكامل على المحاكي

```bash
cd upstream-ios
xcodebuild test \
  -workspace Bitwarden.xcworkspace \
  -scheme Bitwarden \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5" \
  CODE_SIGNING_ALLOWED=NO
```

اسم المخطط الحرفي في `project-pm.yml` هو `Bitwarden` (لا يوجد مخطط باسم `BitwardenPM`). خطط الاختبار: `TestPlans/Bitwarden-Default.xctestplan` (افتراضية) وUnit/Snapshot/ViewInspector.

## 6) أرشفة وبناء IPA غير موقّع

```bash
cd upstream-ios
xcodebuild archive \
  -workspace Bitwarden.xcworkspace \
  -scheme Bitwarden \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath ../build/WezWordn.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

cd ..
mkdir -p Payload
cp -R build/WezWordn.xcarchive/Products/Applications/*.app Payload/
zip -qry WezWordn.ipa Payload
shasum -a 256 WezWordn.ipa | tee SHA256SUMS.txt
```

الناتج `WezWordn.ipa` **غير موقّع**: بنية IPA سليمة لكن iOS سيرفض تثبيته حتى يُعاد توقيعه (AltStore/SideStore أو شهادتك). هذا هو بالضبط مسار `.github/workflows/build-ipa.yml`.

## 7) بناء موقّع بفريقك (اختياري)

أزل تجاوزات `CODE_SIGNING_ALLOWED=NO`، وتأكد أن `DEVELOPMENT_TEAM` مضبوط وأن Xcode أنشأ/حمّل provisioning profiles لكل هدف (التطبيق + 4 امتدادات + الساعة وودجتها) من `project-pm.yml`، ثم أرشف من Xcode (Product → Archive) أو بـ `xcodebuild archive` + `-exportArchive` مع `ExportOptions.plist` يطابق فريقك. لا تُودع أي شهادة أو profile أو كلمة مرور في المستودع — في CI تكون في GitHub Secrets فقط، وهذا المستودع لا يتضمن مسار توقيع CI جاهزًا (الـ workflow مقصود غير موقّع).

## 8) التحقق من ناتج البناء

```bash
unzip -l WezWordn.ipa | head          # بنية Payload/*.app
codesign -dvvv Payload/*.app 2>&1 | head   # حالة التوقيع الفعلية — لا تفترضها
```

سجّل نتيجة كل خطوة (نجاح/فشل + رسالة الخطأ الحرفية) في تقرير بناء الإصدار. قاعدة المشروع: لا يُوصف بناء بأنه ناجح ولا IPA بأنه موجود دون ناتج فعلي على القرص.

## أعطال معروفة ومتوقعة

| العرض | السبب المرجح | المعالجة |
|---|---|---|
| لا يوجد أي `.xcodeproj` بعد الجلب | طبيعي — المشاريع مولّدة | شغّل خطوة XcodeGen (bootstrap أو يدويًا) |
| فشل توقيع App Group | فريق شخصي/مجاني لا يدعم كل الـ capabilities أو تعارض group | راجع `INSTALL.md` قيود إعادة التوقيع؛ تحقق أن `SHARED_APP_GROUP_IDENTIFIER` بقيمة WezWordn لا قيمة upstream |
| `No such module 'LocalTOTP'` | مقتطف ربط الحزمة غير ملصوق أو التوليد لم يُعد | خطوة §3 |
| فشل جلب SwiftPM لـ Firebase/SDK | شبكة/بروكسي يقطع التنزيلات الكبيرة (لوحظ مع git clone في بيئة التحليل) | أعد المحاولة على شبكة مباشرة؛ الـ tarball fallback موثّق في سكربت bootstrap لمصدر upstream فقط |
