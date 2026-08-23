// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get hintIdle => 'Tap and start talking';

  @override
  String get hintRecording => 'Recording — tap to stop';

  @override
  String get hintPaused => 'Paused — tap to resume';

  @override
  String get savedLocally => 'Your idea is saved on this device';

  @override
  String get recordStartFailed => 'Couldn\'t start recording. Try again.';

  @override
  String get recordNotSaved => 'The recording wasn\'t saved';

  @override
  String get micPermissionTitle => 'Microphone access needed';

  @override
  String get micPermissionRationale =>
      'Mindrop needs your microphone so you can capture ideas by voice.';

  @override
  String get micPermissionBlocked =>
      'Microphone access is permanently denied. Open app settings to enable it.';

  @override
  String get cancel => 'Cancel';

  @override
  String get allow => 'Allow';

  @override
  String get openSettings => 'Open settings';

  @override
  String get uploadRetrying => 'Retrying upload…';

  @override
  String pendingUploads(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count waiting to upload',
      one: '1 waiting to upload',
    );
    return '$_temp0';
  }

  @override
  String get historyTitle => 'Your Ideas';

  @override
  String get historyEmpty => 'No ideas recorded yet';

  @override
  String get historyOpenTooltip => 'View recorded ideas';

  @override
  String get statusRecorded => 'Waiting to upload';

  @override
  String get statusUploading => 'Uploading';

  @override
  String get statusUploaded => 'Uploaded';

  @override
  String get statusTranscribing => 'Transcribing';

  @override
  String get statusAnalyzing => 'Analyzing';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get statusFailed => 'Upload failed';

  @override
  String get delete => 'Delete';

  @override
  String get deleteConfirmTitle => 'Delete this idea?';

  @override
  String get deleteConfirmBody =>
      'This recording and its transcript will be permanently deleted from your device and from the cloud.';

  @override
  String get deleteAll => 'Delete all';

  @override
  String get deleteAllConfirmTitle => 'Delete all ideas?';

  @override
  String get deleteAllConfirmBody =>
      'All recordings and their transcripts will be permanently deleted from your device and from the cloud. This can\'t be undone.';

  @override
  String get playbackLoadError => 'Couldn\'t load this recording';

  @override
  String get transcriptPending =>
      'No transcript yet — it appears here once processing finishes';

  @override
  String get analysisTasks => 'Tasks';

  @override
  String get analysisGoals => 'Goals';

  @override
  String get analysisIdeas => 'Ideas';

  @override
  String get analysisTopics => 'Topics';

  @override
  String get analysisEmpty => 'Nothing to extract from this one';

  @override
  String get mindMapTitle => 'Mind map';

  @override
  String get mindMapOpen => 'View mind map';

  @override
  String get mindMapEmpty =>
      'Nothing to map yet — the mind map appears once this recording has been organised';

  @override
  String get mindMapRecordingNode => 'Recording';

  @override
  String get mindMapResetView => 'Recentre the map';

  @override
  String get analysisPending => 'Organising this idea…';

  @override
  String get a11yStartRecording => 'Start recording';

  @override
  String get a11yStopRecording => 'Stop recording';

  @override
  String get a11yPlayRecording => 'Play recording';

  @override
  String get a11yPauseRecording => 'Pause recording';
}
