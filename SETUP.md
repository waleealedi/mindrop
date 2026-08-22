# Mindrop — دليل الإعداد الأول

هذا أول كود بمشروع Mindrop: **المرحلة 1** من خطة الـ MVP — "التسجيل والتخزين".
الكود يسوّي: صلاحية المايك، تسجيل صوتي، حفظ محلي، إدارة حالات، والتعامل مع
المقاطعات (مكالمة، قفل شاشة) — كل هذا **بدون أي اعتماد على الإنترنت**.
الرفع لـ Firebase مجهّز كهيكلية (`upload_queue_service.dart`) بس غير مفعّل
لين تسوّي إعداد Firebase بالقسم 6.

جهازك: **macOS (Apple Silicon)**. الخطوات التالية مخصوصة لهذا.

---

## 0) الملفات اللي معك الحين

```
mindrop/
├── pubspec.yaml              الحزم المطلوبة
├── SETUP.md                  هذا الملف
└── lib/
    ├── main.dart              نقطة البداية + الثيم
    ├── models/
    │   └── recording_draft.dart      نموذج التسجيل وحالاته
    ├── services/
    │   ├── audio_recorder_service.dart   التسجيل الفعلي (حزمة record)
    │   ├── draft_store.dart              الحفظ المحلي + فهرس JSON
    │   └── upload_queue_service.dart     هيكلية طابور الرفع (Firebase لاحقًا)
    ├── screens/
    │   └── record_screen.dart    الشاشة الرئيسية (زر التسجيل)
    └── widgets/
        └── record_button.dart    الزر نفسه
```

لا يوجد لسا مجلدي `android/` و `ios/` — بيصيرو بالخطوة 4.

---

## 1) أدوات macOS الأساسية

```bash
xcode-select --install
```

---

## 2) ثبّت Flutter SDK

الطريقة الرسمية (الأضمن):

1. حمّل حزمة **Apple Silicon (ARM64)** من [صفحة تثبيت Flutter الرسمية](https://docs.flutter.dev/install/manual).
2. فك الضغط بمجلد ثابت، مثلاً:
   ```bash
   mkdir -p ~/develop
   unzip ~/Downloads/flutter_macos_*-stable.zip -d ~/develop/
   ```
3. أضف Flutter لمسار `PATH` (الشل الافتراضي بـ macOS هو zsh):
   ```bash
   echo 'export PATH="$HOME/develop/flutter/bin:$PATH"' >> ~/.zprofile
   ```
   افتح تيرمنال جديد بعدها.
4. تحقق:
   ```bash
   flutter --version
   dart --version
   ```

*بديل عبر Homebrew إذا تفضّله (تأكد إنه محدث أولًا بـ `brew search flutter`):*
```bash
brew install --cask flutter
```

---

## 3) شغّل flutter doctor

```bash
flutter doctor
```

كمّل أي نقطة ناقصة يطلبها (Android SDK / Xcode license / CocoaPods).
لأول نسخة رح نستهدف **Android** فقط (الأسهل والأسرع للتجربة)، حسب خطة
الإطلاق: "الأفضل إطلاق Android أولًا". لو تبي تجرب iOS بنفس الوقت،
راجع [دليل إعداد iOS](https://docs.flutter.dev/platform-integration/ios/setup).

---

## 4) أنشئ هيكل المشروع الأصلي (android/ و ios/)

من داخل مجلد `mindrop` نفسه (نفس المجلد اللي فيه `pubspec.yaml`):

```bash
cd ~/Documents/mindrop
flutter create --org com.mindrop --platforms=android,ios .
```

هذا الأمر يضيف مجلدات `android/` و `ios/` وملفات مساعدة (`.gitignore`،
`analysis_options.yaml`، `test/`) بدون ما يلمس `pubspec.yaml` أو
`lib/main.dart` الموجودين عندك مسبقًا (Flutter ما يكتب فوق ملف موجود
إلا إذا استخدمت `--overwrite`). لو ظهرت لك أي رسالة تعارض على ملف معيّن،
اختر عدم الكتابة فوقه.

> إذا حاب تتجنب أي احتمال تعارض نهائيًا: شغّل الأمر بمجلد فاضي منفصل
> (`flutter create --org com.mindrop --platforms=android,ios mindrop_tmp`)
> وانقل مجلدي `android/` و `ios/` الناتجين يدويًا داخل `mindrop/`.

---

## 5) صلاحية المايك (خطوة يدوية لازمة)

**Android** — افتح `android/app/src/main/AndroidManifest.xml` وأضف قبل
وسم `<application>`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

**iOS** — افتح `ios/Runner/Info.plist` وأضف قبل إغلاق `</dict>` الأخير:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Mindrop يحتاج الوصول للمايك عشان تقدر تسجّل أفكارك الصوتية.</string>
```

---

## 6) شغّل التطبيق

```bash
flutter pub get
flutter run
```

اختر جهاز/محاكي Android عند السؤال. أول تشغيل بيطلب صلاحية المايك —
اضغط سماح، وجرّب تسجّل فكرة وشوف رسالة "تم حفظ فكرتك محليًا".

> نصيحة: شغّل `flutter pub outdated` بعد أول `pub get` — أرقام الإصدارات
> بـ `pubspec.yaml` كانت أحدث نسخة وقت كتابة هذا الدليل (أغسطس 2026) وممكن
> يكون طلع إصدار أجد.

---

## 7) الخطوة الجاية: ربط Firebase (Auth + Firestore + Storage)

لسا ما سوّينا هذي الخطوة — تحتاج حساب Google ومشروع Firebase من طرفك.

1. ثبّت أدوات سطر الأوامر:
   ```bash
   npm install -g firebase-tools
   firebase login
   dart pub global activate flutterfire_cli
   ```
2. أنشئ مشروع Firebase من [console.firebase.google.com](https://console.firebase.google.com)
   (فعّل فيه Authentication و Firestore و Storage).
3. من داخل مجلد `mindrop`:
   ```bash
   flutterfire configure
   ```
   اختر مشروعك ومنصّتي Android/iOS — بينشئ لك ملف `lib/firebase_options.dart`
   تلقائيًا.
4. فعّل حزم Firebase الأربع الموجودة (معلّقة بتعليق `#`) داخل `pubspec.yaml`،
   ثم `flutter pub get`.
5. بـ `lib/main.dart` أضف قبل `runApp`:
   ```dart
   WidgetsFlutterBinding.ensureInitialized();
   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
   ```
   (مع `import 'firebase_options.dart';` و `import 'package:firebase_core/firebase_core.dart';`،
   وتحويل `main()` إلى `Future<void> main() async { ... }`).
6. نفّذ الرفع الحقيقي داخل `lib/services/upload_queue_service.dart` (التفاصيل
   بتعليقات `TODO` داخل الملف نفسه).

بعد هذي الخطوة تكون خلّصت المرحلة 1 كاملة من الخطة، وجاهز تبدأ
**المرحلة 2: Backend وProcessing Pipeline** (Node.js API).

---

## مراجع رسمية استخدمتها بهذا الدليل

- [تثبيت Flutter يدويًا](https://docs.flutter.dev/install/manual)
- [أرشيف إصدارات Flutter SDK](https://docs.flutter.dev/install/archive)
- [إعداد منصة iOS](https://docs.flutter.dev/platform-integration/ios/setup)
- [حزمة record على pub.dev](https://pub.dev/packages/record)
- [وصفة تسجيل الصوت — Flutter Cookbook](https://docs.flutter.dev/cookbook/audio/record)
- [FlutterFire CLI](https://firebase.flutter.dev/docs/cli/)
- [البدء مع Firebase في Flutter](https://firebase.google.com/docs/flutter/setup)
