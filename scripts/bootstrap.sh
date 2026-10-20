#!/usr/bin/env bash
# bootstrap.sh — تجهيز بيئة بناء WezWordn على macOS
# ============================================================
# ما يفعله هذا السكربت فعليًا (بالترتيب):
#   1) يتحقق أن النظام macOS وأن Xcode مثبّت (xcodebuild موجود ومقبول الترخيص).
#   2) يجلب شجرة upstream (bitwarden/ios) إلى upstream-ios/ إن لم توجد:
#      يحاول git clone أولًا، وعند فشله يستخدم tarball رسمي من
#      codeload.github.com (بديل موثّق: لوحظ فشل نقل git pack الكبير عبر
#      بعض البروكسيات بخطأ TLS بينما ينجح تنزيل tarball من نفس المصدر).
#   3) ينسخ identity/Local-WezWordn.xcconfig.example إلى
#      upstream-ios/Configs/Local-bwpm.xcconfig (لا يطمس نسخة موجودة).
#   4) ينسخ ملفات AppIntegration/*.swift إلى
#      upstream-ios/Bitwarden/Application/WezWordnFeatures/
#      (مجلد داخل sourcesPath الخاص بهدف التطبيق، فيلتقطه XcodeGen تلقائيًا).
#      ملاحظة: ربط حزمة WezWordnCore نفسها كـ Swift Package محلي يتطلب
#      المقتطف الموثّق في AppIntegration/README.md داخل project-pm.yml —
#      السكربت لا يعدّل ملفات yml الخاصة بـ upstream تلقائيًا.
#   5) يتحقق من XcodeGen (أداة مباشرة، أو عبر mint كما في Mintfile الخاص
#      بـ upstream: yonaskolb/xcodegen@2.44.1) ويثبّته بـ brew إن غابا معًا.
#   6) يولّد مشاريع Xcode الأربعة من project-bwk/bwa/pm/bwth.yml بنفس
#      ترتيب سكربت upstream الرسمي Scripts/bootstrap.sh.
#   7) يقارن إصدار Xcode الحالي بملف upstream/.xcode-version ويحذّر عند
#      الاختلاف (لا يفشل: قد ترغب بالبناء بإصدار أحدث على مسؤوليتك).
#
# متغيرات بيئة اختيارية:
#   WEZWORDN_UPSTREAM_DIR  مسار شجرة upstream (الافتراضي: <repo>/upstream-ios)
#   WEZWORDN_UPSTREAM_REF  فرع/tag upstream   (الافتراضي: main)
#   SKIP_XCODEGEN=1         تخطّي خطوة توليد المشاريع
#
# حدود صريحة: هذا السكربت لا يوقّع ولا يبني ولا ينتج IPA. البناء والتوقيع
# موثّقان في BUILD.md، والبناء غير الموقّع آليًا في .github/workflows/build-ipa.yml.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(dirname -- "$SCRIPT_DIR")"
UPSTREAM_DIR="${WEZWORDN_UPSTREAM_DIR:-$REPO_ROOT/upstream-ios}"
UPSTREAM_REF="${WEZWORDN_UPSTREAM_REF:-main}"
UPSTREAM_REPO="https://github.com/bitwarden/ios"
UPSTREAM_TARBALL="https://codeload.github.com/bitwarden/ios/tar.gz/refs/heads/${UPSTREAM_REF}"

log()  { printf '[wezwordn] %s\n' "$*"; }
warn() { printf '[wezwordn] تحذير: %s\n' "$*" >&2; }
die()  { printf '[wezwordn] خطأ: %s\n' "$*" >&2; exit 1; }

# --- 1) macOS + Xcode --------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || die "هذا السكربت يعمل على macOS فقط (بناء iOS يتطلب Xcode)."
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild غير موجود. ثبّت Xcode من App Store ثم شغّل: sudo xcodebuild -license accept"
log "Xcode: $(xcodebuild -version | head -n 1)"

# --- 2) جلب upstream ----------------------------------------------------------
if [ -f "$UPSTREAM_DIR/project-pm.yml" ]; then
    log "شجرة upstream موجودة مسبقًا في: $UPSTREAM_DIR (لن يُعاد جلبها)"
else
    log "جلب upstream ($UPSTREAM_REF) إلى: $UPSTREAM_DIR"
    mkdir -p "$UPSTREAM_DIR"
    fetched=0
    if command -v git >/dev/null 2>&1; then
        tmp_clone="$(mktemp -d)"
        if git clone --depth 1 --branch "$UPSTREAM_REF" "$UPSTREAM_REPO" "$tmp_clone/ios" 2>/dev/null; then
            cp -a "$tmp_clone/ios/." "$UPSTREAM_DIR/"
            fetched=1
            log "تم الجلب عبر git clone."
        else
            warn "فشل git clone — التحوّل إلى بديل tarball الرسمي من codeload.github.com."
        fi
        rm -rf "$tmp_clone"
    fi
    if [ "$fetched" -eq 0 ]; then
        command -v curl >/dev/null 2>&1 || die "لا git ناجح ولا curl متاح — لا توجد قناة جلب."
        tmp_tar="$(mktemp -d)"
        curl -fL -o "$tmp_tar/bw-ios.tar.gz" "$UPSTREAM_TARBALL" \
            || die "فشل تنزيل tarball من $UPSTREAM_TARBALL"
        gzip -t "$tmp_tar/bw-ios.tar.gz" || die "ملف tarball تالف (فشل gzip -t)."
        tar -xzf "$tmp_tar/bw-ios.tar.gz" -C "$tmp_tar"
        src_dir="$(find "$tmp_tar" -maxdepth 1 -type d -name 'ios-*' | head -n 1)"
        [ -n "$src_dir" ] || die "بنية tarball غير متوقعة: لم يُعثر على مجلد ios-*."
        cp -a "$src_dir/." "$UPSTREAM_DIR/"
        rm -rf "$tmp_tar"
        log "تم الجلب عبر tarball (لقطة مصدر بلا .git — أعد git clone على شبكة سليمة إن احتجت سجل commits)."
    fi
    [ -f "$UPSTREAM_DIR/project-pm.yml" ] || die "اكتمل الجلب لكن project-pm.yml مفقود — الشجرة غير سليمة."
fi

# مقارنة إصدار Xcode بمتطلب upstream (.xcode-version)
if [ -f "$UPSTREAM_DIR/.xcode-version" ]; then
    required_xcode="$(tr -d '[:space:]' < "$UPSTREAM_DIR/.xcode-version")"
    current_xcode="$(xcodebuild -version | head -n 1 | awk '{print $2}')"
    if [ "$current_xcode" != "$required_xcode" ]; then
        warn "إصدار Xcode الحالي ($current_xcode) يختلف عن المطلوب في upstream ($required_xcode). قد يفشل البناء أو تختلف نتائجه."
    else
        log "إصدار Xcode مطابق لمتطلب upstream: $required_xcode"
    fi
fi

# --- 3) فرض هوية WezWordn عبر Local-bwpm.xcconfig ------------------------------
LOCAL_CFG="$UPSTREAM_DIR/Configs/Local-bwpm.xcconfig"
if [ -f "$LOCAL_CFG" ]; then
    log "Local-bwpm.xcconfig موجود مسبقًا — لن يُطمس. راجع قيمه يدويًا عند الحاجة."
else
    cp "$REPO_ROOT/identity/Local-WezWordn.xcconfig.example" "$LOCAL_CFG"
    log "نُسخت هوية WezWordn إلى: Configs/Local-bwpm.xcconfig"
    warn "افتح الملف وضع DEVELOPMENT_TEAM الخاص بك (السطر معلّق افتراضيًا) قبل أي بناء موقّع."
fi

# --- 4) نسخ ملفات التكامل -------------------------------------------------------
INTEGRATION_DST="$UPSTREAM_DIR/Bitwarden/Application/WezWordnFeatures"
mkdir -p "$INTEGRATION_DST"
cp "$REPO_ROOT"/AppIntegration/*.swift "$INTEGRATION_DST/"
log "نُسخت ملفات AppIntegration إلى: Bitwarden/Application/WezWordnFeatures/"
warn "اربط حزمة WezWordnCore في project-pm.yml بالمقتطف الموثّق في AppIntegration/README.md قبل البناء، وإلا ستفشل ترجمة ملفات التكامل (import للوحدات المحلية)."

# --- 5) XcodeGen ------------------------------------------------------------------
XCODEGEN_CMD=()
if command -v xcodegen >/dev/null 2>&1; then
    XCODEGEN_CMD=(xcodegen)
    log "XcodeGen متاح مباشرة: $(xcodegen --version)"
elif command -v mint >/dev/null 2>&1; then
    XCODEGEN_CMD=(mint run xcodegen)
    log "XcodeGen سيعمل عبر mint (الإصدار مثبّت في Mintfile الخاص بـ upstream: 2.44.1)."
elif command -v brew >/dev/null 2>&1; then
    log "XcodeGen و mint غائبان — التثبيت عبر Homebrew..."
    brew install xcodegen
    XCODEGEN_CMD=(xcodegen)
else
    die "لا XcodeGen ولا mint ولا brew. ثبّت Homebrew ثم: brew install mint xcodegen — أو شغّل mint bootstrap داخل upstream."
fi

# --- 6) توليد المشاريع -------------------------------------------------------------
if [ "${SKIP_XCODEGEN:-0}" = "1" ]; then
    log "تخطّي توليد المشاريع بناءً على SKIP_XCODEGEN=1."
else
    # نفس ترتيب سكربت upstream الرسمي Scripts/bootstrap.sh
    for spec in project-bwk.yml project-pm.yml project-bwa.yml project-bwth.yml; do
        log "XcodeGen: $spec"
        (cd "$UPSTREAM_DIR" && "${XCODEGEN_CMD[@]}" --spec "$spec")
    done
    log "وُلّدت المشاريع. افتح: $UPSTREAM_DIR/Bitwarden.xcworkspace"
fi

log "اكتمل bootstrap. الخطوات التالية (BUILD.md): ضبط DEVELOPMENT_TEAM، ربط WezWordnCore، ثم البناء من Xcode أو xcodebuild."
