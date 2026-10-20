# TEST_REPORT — WezWordn 0.1.0 (2026-10-20)

## ما اختُبر فعليًا

### WezWordnCore — Swift Package (Linux, Swift 6.1.2)
الأمر: `cd WezWordnCore && swift test` — أُعيد تشغيله وتحقق منه مرتين مستقلتين.
النتيجة: **39 اختبارًا منفذًا، 0 إخفاقات** (exit 0).

| Suite | العدد | النتيجة |
|---|---|---|
| ExtendedLoginFieldsTests | 5 | ناجحة |
| LocalTOTPTests | 9 | ناجحة — تشمل متجهات RFC 6238 Appendix B الرسمية الـ18 (SHA1/SHA256/SHA512 × 6 timestamps، 8 أرقام) |
| LocalEncryptedStorageTests | 6 | ناجحة — roundtrip مجزّأ، tamper ببايت واحد يفشل ويحذف الإخراج الجزئي، مفتاح خاطئ يفشل، اختلاف baseNonce بين تشفيرين |
| VaultHealthTests | 7 | ناجحة — كشف weak/reused/old/duplicate/missingTOTP/missingIdentity ببيانات synthetic |
| HIBPClientTests | 4 | ناجحة — k-anonymity بمتجه SHA1("password") المعروف، transport مُحقَن offline، لا شبكة فعلية |
| EmergencyRecoveryTests | 4 | ناجحة — roundtrip X25519+HKDF+AES-GCM، مفتاح خاص خاطئ يفشل |
| SecureSharingTests | 4 | ناجحة — roundtrip حزمة .wezshare، tamper يفشل |

### فحوص ثابتة
- `bash -n scripts/bootstrap.sh`: exit 0 (فحص syntax فقط — السكربت لم يُشغَّل، لا macOS هنا).
- `swiftc -parse` لملفي AppIntegration (SwiftUI/Keychain): exit 0 لكليهما (parse فقط — لا type-check ولا ترجمة كاملة ممكنة على Linux).
- YAML الـ GitHub Actions workflow: صالح عبر yaml.safe_load.
- `cmp` لملف LICENSE مقابل upstream/LICENSE.txt: متطابق بايتًا ببايت.

## ما لم يُختبر (صريح)
- **بناء تطبيق iOS الكامل و IPA**: مستحيل في بيئة Linux بلا Xcode. المسار الجاهز: `.github/workflows/build-ipa.yml` على macOS runner أو جهاز Mac محلي عبر `scripts/bootstrap.sh` ثم BUILD.md.
- **وظائف Bitwarden الأصلية (تسجيل الدخول، المزامنة، AutoFill، Face ID)**: لم تُشغَّل — تتطلب بناء التطبيق وحساب اختبار على خادم. لم تُعدَّل أي من شيفرات upstream الوظيفية؛ الدمج الوحيد هو طبقة إضافية (xcconfig هوية + حزمة محلية + ملفات تكامل)، لذا خطر الـ regression محصور في التكامل لا في منطق upstream، لكن هذا استدلال لا اختبار.
- **HIBP الحي**: `URLSessionHIBPTransport` مُصرَّف لكنه غير مختبر ضد API الحقيقي.
- **Keychain/Face ID على جهاز**: غير مختبرة.
- **REA**: لم تُثبّت ولم تُشغَّل (انظر REA_ANALYSIS.md).
