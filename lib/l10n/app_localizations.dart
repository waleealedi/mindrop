import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// Hint under the record button while idle
  ///
  /// In en, this message translates to:
  /// **'Tap and start talking'**
  String get hintIdle;

  /// No description provided for @hintRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording — tap to stop'**
  String get hintRecording;

  /// No description provided for @hintPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused — tap to resume'**
  String get hintPaused;

  /// Headline above the record button's hint line while idle
  ///
  /// In en, this message translates to:
  /// **'Ready to capture…'**
  String get recordStatusIdle;

  /// No description provided for @recordStatusRecording.
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get recordStatusRecording;

  /// No description provided for @recordStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'On hold'**
  String get recordStatusPaused;

  /// No description provided for @savedLocally.
  ///
  /// In en, this message translates to:
  /// **'Your idea is saved on this device'**
  String get savedLocally;

  /// No description provided for @recordStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start recording. Try again.'**
  String get recordStartFailed;

  /// No description provided for @recordNotSaved.
  ///
  /// In en, this message translates to:
  /// **'The recording wasn\'t saved'**
  String get recordNotSaved;

  /// No description provided for @micPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Microphone access needed'**
  String get micPermissionTitle;

  /// No description provided for @micPermissionRationale.
  ///
  /// In en, this message translates to:
  /// **'Mindrop needs your microphone so you can capture ideas by voice.'**
  String get micPermissionRationale;

  /// No description provided for @micPermissionBlocked.
  ///
  /// In en, this message translates to:
  /// **'Microphone access is permanently denied. Open app settings to enable it.'**
  String get micPermissionBlocked;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @allow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allow;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// Shown when the user taps the pending chip to retry uploads manually
  ///
  /// In en, this message translates to:
  /// **'Retrying upload…'**
  String get uploadRetrying;

  /// Chip showing how many recordings are queued for upload
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 waiting to upload} other{{count} waiting to upload}}'**
  String pendingUploads(int count);

  /// Title of the screen listing previously recorded ideas
  ///
  /// In en, this message translates to:
  /// **'Your Ideas'**
  String get historyTitle;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No ideas recorded yet'**
  String get historyEmpty;

  /// No description provided for @historyOpenTooltip.
  ///
  /// In en, this message translates to:
  /// **'View recorded ideas'**
  String get historyOpenTooltip;

  /// No description provided for @statusRecorded.
  ///
  /// In en, this message translates to:
  /// **'Waiting to upload'**
  String get statusRecorded;

  /// No description provided for @statusUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading'**
  String get statusUploading;

  /// No description provided for @statusUploaded.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get statusUploaded;

  /// No description provided for @statusTranscribing.
  ///
  /// In en, this message translates to:
  /// **'Transcribing'**
  String get statusTranscribing;

  /// No description provided for @statusAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing'**
  String get statusAnalyzing;

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed'**
  String get statusFailed;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this idea?'**
  String get deleteConfirmTitle;

  /// No description provided for @deleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This recording and its transcript will be permanently deleted from your device and from the cloud.'**
  String get deleteConfirmBody;

  /// Header icon tooltip and confirm-dialog button for clearing every recording at once
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get deleteAll;

  /// No description provided for @deleteAllConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete all ideas?'**
  String get deleteAllConfirmTitle;

  /// No description provided for @deleteAllConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'All recordings and their transcripts will be permanently deleted from your device and from the cloud. This can\'t be undone.'**
  String get deleteAllConfirmBody;

  /// No description provided for @playbackLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this recording'**
  String get playbackLoadError;

  /// Placeholder on the playback screen before the backend transcript arrives
  ///
  /// In en, this message translates to:
  /// **'No transcript yet — it appears here once processing finishes'**
  String get transcriptPending;

  /// No description provided for @analysisTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get analysisTasks;

  /// No description provided for @analysisGoals.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get analysisGoals;

  /// No description provided for @analysisIdeas.
  ///
  /// In en, this message translates to:
  /// **'Ideas'**
  String get analysisIdeas;

  /// No description provided for @analysisTopics.
  ///
  /// In en, this message translates to:
  /// **'Topics'**
  String get analysisTopics;

  /// Shown when analysis ran but the recording genuinely contained no tasks, goals or ideas
  ///
  /// In en, this message translates to:
  /// **'Nothing to extract from this one'**
  String get analysisEmpty;

  /// No description provided for @mindMapTitle.
  ///
  /// In en, this message translates to:
  /// **'Mind map'**
  String get mindMapTitle;

  /// No description provided for @mindMapOpen.
  ///
  /// In en, this message translates to:
  /// **'View mind map'**
  String get mindMapOpen;

  /// Empty state on the mind map screen when a recording has no analysis yet
  ///
  /// In en, this message translates to:
  /// **'Nothing to map yet — the mind map appears once this recording has been organised'**
  String get mindMapEmpty;

  /// No description provided for @mindMapRecordingNode.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get mindMapRecordingNode;

  /// Tooltip on the mind map header button that returns pan and zoom to the initial fitted view
  ///
  /// In en, this message translates to:
  /// **'Recentre the map'**
  String get mindMapResetView;

  /// Shown on the playback screen while backend analysis is still running
  ///
  /// In en, this message translates to:
  /// **'Organising this idea…'**
  String get analysisPending;

  /// No description provided for @a11yStartRecording.
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get a11yStartRecording;

  /// No description provided for @a11yStopRecording.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get a11yStopRecording;

  /// No description provided for @a11yPlayRecording.
  ///
  /// In en, this message translates to:
  /// **'Play recording'**
  String get a11yPlayRecording;

  /// No description provided for @a11yPauseRecording.
  ///
  /// In en, this message translates to:
  /// **'Pause recording'**
  String get a11yPauseRecording;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
