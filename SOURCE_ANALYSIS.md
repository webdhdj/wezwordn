# SOURCE_ANALYSIS — تحليل المصدر الرسمي bitwarden/ios

التقرير البحثي الكامل: `~/workspace/wezwordn-analysis/UPSTREAM_FINDINGS.md` (ناتج فحص فعلي للقطة المصدر).

## الأساس
- اللقطة: فرع `main`، commit `901bd4de8dbd9f5f7ba11b69499dd618feb0933c`، جُلبت كـ tarball رسمي من codeload.github.com بعد فشل `git clone` مرتين (انقطاع TLS لنقل pack كبير عبر البروكسي — موثّق برسائل الخطأ).
- `MARKETING_VERSION` في اللقطة 2026.4.0؛ أحدث إصدار منشور 2026.10.0 وهو ما يطابق الـ IPA المرفق.
- الترخيص: **GPLv3** (`LICENSE.txt`).

## البنية الفعلية
- لا xcodeproj ملتزم: التوليد بـ **XcodeGen 2.44.1** من `project-pm/bwa/bwk/bwth.yml` و`project-common.yml`. ‏`.xcode-version` = 26.6، deployment target **iOS 15.0** / watchOS 8.0.
- الوحدات: `BitwardenShared` (Auth/Autofill/Vault/Platform/Tools)، `BitwardenKit` (يحوي Networking وAuthenticatorBridgeKit وBitwardenResources كأهداف)، تطبيق ثانٍ `Authenticator` + `AuthenticatorShared`.
- الامتدادات: AutoFill (CredentialProvider)، Action، Share، Notification، WatchWidget.
- التخزين: 5 نماذج Core Data؛ Keychain وLocalAuthentication مركّزة في BitwardenKit.
- التشفير: **ليس في Swift** — ‏602 موضع `import BitwardenSdk`؛ النواة Rust (BitwardenFFI binary target من مستودع bitwarden/sdk-swift)، والـ KDF المعروض للواجهة: PBKDF2-SHA256 أو Argon2id. الخوارزمية المتماثلة داخل النواة غير مُتحقق منها من هذا الفحص ولا تُدّعى هنا.
- توليد TOTP الأصلي يتم داخل الـ SDK (`clientService.vault().generateTOTPCode`) — وحدة LocalTOTP في WezWordn مستقلة عنه وتخدم الأسرار المحلية فقط، ولا تستبدله.

## قرارات WezWordn المبنية على هذا التحليل
1. فرض الهوية عبر `Local-bwpm.xcconfig` (آلية upstream الرسمية الموثقة في ملفات المشروع نفسها) بدل تعديل ملفات التوليد — تحديثات upstream تبقى قابلة للدمج.
2. كل الميزات الجديدة في حزمة Swift مستقلة (WezWordnCore) ببيانات محلية منفصلة؛ لا تعديل على تنسيق المزامنة ولا على نماذج Core Data الأصلية.
3. لا ادعاء دعم iOS 27: لا ذكر له في المشروع، وأحدث SDK مُتحقق هو 26.5 في الـ IPA و26.6 في `.xcode-version`.
