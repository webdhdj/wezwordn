# DEPENDENCY_REPORT — WezWordn 0.1.0

## تبعيات WezWordn الجديدة
| التبعية | الإصدار | الترخيص | الاستخدام |
|---|---|---|---|
| apple/swift-crypto | 3.0.0 (Package.resolved) | Apache-2.0 | AES-256-GCM، Curve25519، HKDF، HMAC، SHA — تنفيذ مفتوح المصدر من Apple بواجهة CryptoKit-compatible، يعمل على iOS وLinux |

لا تبعيات جديدة أخرى. لا مفاتيح أو أسرار مدمجة في أي تبعية أو شيفرة.

## تبعيات upstream الرئيسية (من Package.resolved الفعلي — 21 pin)
- BitwardenSdk — bitwarden/sdk-swift @ e98eb301 (تعليق 4.0.0-8629-3b2c8fc) — نواة التشفير والمزامنة (Rust FFI). **نقطة مفتوحة**: ترخيص مكونات الـ SDK الثنائية من مستودع منفصل ويجب حسمه قبل أي توزيع تجاري؛ مشروع WezWordn نفسه يلتزم GPLv3 تبعًا لتطبيق iOS.
- Firebase 12.14.0 (Crashlytics وغيرها عبر تبعيات عابرة) — **ملاحظة خصوصية**: WezWordn لا يضيف أي analytics؛ بقاء Firebase من upstream كما هو، وإزالته قرار لاحق يتطلب تعديل upstream.
- SnapshotTesting 1.19.4، ViewInspector 0.10.3 (اختبارات فقط)، SwiftProtobuf 1.38.1 (Authenticator)، SwiftUIIntrospect 26.0.1.

## فحص أمن التبعيات
- WezWordnCore: تبعية واحدة مدققة المصدر (Apple) مثبتة برقم إصدار وresolved file ملتزم.
- لم يُشغَّل فحص ثغرات آلي (لا أداة macOS هنا)؛ يُنصح بتشغيل `swift package audit`/GitHub Dependabot عند رفع المستودع.
