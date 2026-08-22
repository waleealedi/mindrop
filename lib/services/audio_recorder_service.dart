import 'dart:async';
import 'dart:math' as math;

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// حالة المسجّل من منظور واجهة المستخدم.
enum RecorderState { idle, recording, paused }

/// نتيجة إيقاف التسجيل: مسار الملف الفعلي (null لو فشل) ومدته الصافية
/// (بدون احتساب فترات الإيقاف المؤقت).
class RecordingResult {
  const RecordingResult({required this.path, required this.duration});
  final String? path;
  final Duration duration;
}

/// يغلّف حزمة `record` ويدير صلاحية المايك وحساب مدة التسجيل.
///
/// كل شيء هنا محلي بالكامل ولا يعتمد على الإنترنت إطلاقًا — بما يتوافق
/// مع خطة الـ MVP: "التسجيل لا يجب أن يعتمد على وجود الإنترنت".
class AudioRecorderService {
  AudioRecorderService() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;

  final _stateController = StreamController<RecorderState>.broadcast();
  Stream<RecorderState> get stateStream => _stateController.stream;

  RecorderState _state = RecorderState.idle;
  RecorderState get state => _state;

  DateTime? _startedAt;
  DateTime? _pausedAt;
  Duration _pausedDuration = Duration.zero;

  /// يفحص حالة صلاحية المايك الحالية بدون إظهار أي نافذة للمستخدم.
  Future<PermissionStatus> checkPermission() => Permission.microphone.status;

  /// يطلب صلاحية المايك (يظهر نافذة النظام إذا لزم).
  Future<PermissionStatus> requestPermission() => Permission.microphone.request();

  /// يبدأ تسجيلًا جديدًا ويحفظه في [filePath].
  /// يرمي [StateError] إذا رُفضت صلاحية المايك.
  Future<void> start(String filePath) async {
    final status = await requestPermission();
    if (!status.isGranted) {
      throw StateError('Microphone permission not granted: $status');
    }

    await _recorder.start(
      const RecordConfig(
        // AAC/m4a بدل WAV الخام: نفس الجودة الكافية للكلام بحجم أصغر
        // بكثير — مهم لطابور الرفع لاحقًا فوق بيانات الجوال.
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
        // معالجة صوتية أساسية أثناء الالتقاط (يخفف مشكلة "رداءة الصوت"
        // المذكورة كحالة استثنائية في خطة الـ MVP).
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: filePath,
    );

    _startedAt = DateTime.now();
    _pausedAt = null;
    _pausedDuration = Duration.zero;
    _setState(RecorderState.recording);
  }

  Future<void> pause() async {
    if (_state != RecorderState.recording) return;
    await _recorder.pause();
    _pausedAt = DateTime.now();
    _setState(RecorderState.paused);
  }

  Future<void> resume() async {
    if (_state != RecorderState.paused) return;
    if (_pausedAt != null) {
      _pausedDuration += DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
    }
    await _recorder.resume();
    _setState(RecorderState.recording);
  }

  /// يوقف التسجيل نهائيًا ويرجّع مسار الملف ومدته.
  Future<RecordingResult> stop() async {
    final path = await _recorder.stop();
    final duration = _currentDuration();
    _reset();
    _setState(RecorderState.idle);
    return RecordingResult(path: path, duration: duration);
  }

  /// يلغي التسجيل الحالي ويحذف الملف الجزئي (مثلاً لو المستخدم رجع
  /// عن الشاشة بدون ما يبي يحفظ).
  Future<void> cancel() async {
    if (_state == RecorderState.idle) return;
    await _recorder.cancel();
    _reset();
    _setState(RecorderState.idle);
  }

  /// المدة الحالية للتسجيل، بدون احتساب فترات الإيقاف المؤقت.
  Duration elapsed() => _currentDuration();

  /// دفق مستوى الصوت (dBFS) — جاهز لاستخدامه لاحقًا برسم موجة صوتية
  /// حيّة أثناء التسجيل.
  Stream<Amplitude> amplitudeStream({
    Duration interval = const Duration(milliseconds: 200),
  }) {
    return _recorder.onAmplitudeChanged(interval);
  }

  /// نفس الدفق السابق لكن مطبَّعًا بين 0 و1 وجاهزًا مباشرة للرسم.
  ///
  /// السبب: `Amplitude.current` يجي بوحدة dBFS (سالبة، لوغاريتمية،
  /// و«الصفر» فيها يعني أقصى صوت مو الصمت). لو مرّرناها للواجهة كما هي
  /// بتحتاج كل ويدجت يعرف تفاصيل الصوت. هنا نحوّلها مرة وحدة، فتبقى
  /// الواجهة جاهلة تمامًا بحزمة `record` — وأسهل بالاستبدال لاحقًا.
  ///
  /// **ليش تطبيع تكيّفي (adaptive) ومو نطاق ثابت؟**
  /// المشكلة إن كل جهاز/مايك يعطي مدى dBFS مختلف، وفوق هذا فيه AGC
  /// (autoGain) شغّال بالتسجيل وظيفته الأساسية إنه *يقلّل* الفروق بين
  /// الهمس والصوت العالي. نتيجتها: نطاق ثابت يعطي أعمدة كلها بنفس
  /// الطول تقريبًا — موجة تتحرك لكنها ما تعكس الكلام فعليًا.
  /// الحل: نتتبّع أعلى صوت شفناه مؤخرًا ونطبّع عليه، فتصير الموجة
  /// نسبية لصوت المستخدم نفسه مهما كان جهازه أو بُعده عن المايك.
  Stream<double> levelStream({
    Duration interval = const Duration(milliseconds: 50),
  }) {
    // أرضية الصمت العملية لتسجيل كلام بالجوال.
    const floorDb = -55.0;

    // أضيق نافذة ديناميكية مسموحة — تمنع تضخيم ضجيج الغرفة لموجة
    // ضخمة أول ثانيتين قبل ما يبدأ المستخدم يتكلم.
    const minSpanDb = 14.0;

    // السقف المتتبَّع: يبدأ بتقدير معقول ويتكيّف مع صوت المستخدم.
    var peakDb = -32.0;

    return amplitudeStream(interval: interval).map((a) {
      var db = a.current;
      if (!db.isFinite) db = floorDb;
      db = db.clamp(floorDb, 0.0);

      // يقفز فورًا مع أي صوت أعلى (عشان ما نقصّ قمم الكلام)، وينزل
      // ببطء (0.4 dB لكل عيّنة) عشان ما يتأثر بلحظة صمت قصيرة.
      peakDb = db > peakDb ? db : math.max(peakDb - 0.4, floorDb + minSpanDb);

      final span = math.max(peakDb - floorDb, minSpanDb);
      final raw = ((db - floorDb) / span).clamp(0.0, 1.0);

      // منحنى أُسّي > 1: يوسّع التباين. الصمت يصير صامتًا فعلاً بدل ما
      // يطلع نص عمود، والكلام يبرز. (المنحنى السابق كان 0.6 — أي عكس
      // المطلوب: كان يضغط كل شي لأعلى فيطلع الرسم مسطّحًا.)
      final shaped = math.pow(raw, 1.7).toDouble();

      // نبقي حدًا أدنى بسيط عشان الموجة تبقى موجودة بصريًا بالصمت.
      return (shaped * 0.97 + 0.03).clamp(0.0, 1.0);
    });
  }

  Duration _currentDuration() {
    if (_startedAt == null) return Duration.zero;
    final end = _pausedAt ?? DateTime.now();
    return end.difference(_startedAt!) - _pausedDuration;
  }

  void _reset() {
    _startedAt = null;
    _pausedAt = null;
    _pausedDuration = Duration.zero;
  }

  void _setState(RecorderState s) {
    _state = s;
    _stateController.add(s);
  }

  Future<void> dispose() async {
    await _recorder.dispose();
    await _stateController.close();
  }
}
