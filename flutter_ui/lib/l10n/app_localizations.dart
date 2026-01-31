import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_sr.dart';

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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
    Locale('de'),
    Locale('en'),
    Locale('sr'),
  ];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'FluxForge Studio'**
  String get appTitle;

  /// DAW section name
  ///
  /// In en, this message translates to:
  /// **'DAW'**
  String get sectionDaw;

  /// Middleware section name
  ///
  /// In en, this message translates to:
  /// **'Middleware'**
  String get sectionMiddleware;

  /// SlotLab section name
  ///
  /// In en, this message translates to:
  /// **'SlotLab'**
  String get sectionSlotLab;

  /// No description provided for @tabTimeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get tabTimeline;

  /// No description provided for @tabEvents.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get tabEvents;

  /// No description provided for @tabMix.
  ///
  /// In en, this message translates to:
  /// **'Mix'**
  String get tabMix;

  /// No description provided for @tabMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get tabMusic;

  /// No description provided for @tabDsp.
  ///
  /// In en, this message translates to:
  /// **'DSP'**
  String get tabDsp;

  /// No description provided for @tabBake.
  ///
  /// In en, this message translates to:
  /// **'Bake'**
  String get tabBake;

  /// No description provided for @tabEngine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get tabEngine;

  /// No description provided for @actionSpin.
  ///
  /// In en, this message translates to:
  /// **'Spin'**
  String get actionSpin;

  /// No description provided for @actionStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get actionStop;

  /// No description provided for @actionPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get actionPlay;

  /// No description provided for @actionPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get actionPause;

  /// No description provided for @actionExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get actionExport;

  /// No description provided for @actionImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get actionImport;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionLoad.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get actionLoad;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get actionDuplicate;

  /// No description provided for @actionRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get actionRename;

  /// No description provided for @actionCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get actionCreate;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get actionConfirm;

  /// No description provided for @actionApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get actionApply;

  /// No description provided for @actionReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get actionReset;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get actionOpen;

  /// No description provided for @actionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// No description provided for @actionRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get actionRemove;

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @actionPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get actionPreview;

  /// No description provided for @actionRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get actionRefresh;

  /// No description provided for @actionSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get actionSearch;

  /// No description provided for @actionFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get actionFilter;

  /// No description provided for @actionSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get actionSort;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @actionPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get actionPaste;

  /// No description provided for @actionCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get actionCut;

  /// No description provided for @actionUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get actionUndo;

  /// No description provided for @actionRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get actionRedo;

  /// No description provided for @actionSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get actionSelectAll;

  /// No description provided for @actionClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get actionClearAll;

  /// No description provided for @labelVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get labelVolume;

  /// No description provided for @labelPan.
  ///
  /// In en, this message translates to:
  /// **'Pan'**
  String get labelPan;

  /// No description provided for @labelMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get labelMute;

  /// No description provided for @labelSolo.
  ///
  /// In en, this message translates to:
  /// **'Solo'**
  String get labelSolo;

  /// No description provided for @labelBypass.
  ///
  /// In en, this message translates to:
  /// **'Bypass'**
  String get labelBypass;

  /// No description provided for @labelGain.
  ///
  /// In en, this message translates to:
  /// **'Gain'**
  String get labelGain;

  /// No description provided for @labelFrequency.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get labelFrequency;

  /// No description provided for @labelResonance.
  ///
  /// In en, this message translates to:
  /// **'Resonance'**
  String get labelResonance;

  /// No description provided for @labelAttack.
  ///
  /// In en, this message translates to:
  /// **'Attack'**
  String get labelAttack;

  /// No description provided for @labelRelease.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get labelRelease;

  /// No description provided for @labelThreshold.
  ///
  /// In en, this message translates to:
  /// **'Threshold'**
  String get labelThreshold;

  /// No description provided for @labelRatio.
  ///
  /// In en, this message translates to:
  /// **'Ratio'**
  String get labelRatio;

  /// No description provided for @labelDelay.
  ///
  /// In en, this message translates to:
  /// **'Delay'**
  String get labelDelay;

  /// No description provided for @labelReverb.
  ///
  /// In en, this message translates to:
  /// **'Reverb'**
  String get labelReverb;

  /// No description provided for @labelDryWet.
  ///
  /// In en, this message translates to:
  /// **'Dry/Wet'**
  String get labelDryWet;

  /// No description provided for @labelBpm.
  ///
  /// In en, this message translates to:
  /// **'BPM'**
  String get labelBpm;

  /// No description provided for @labelKey.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get labelKey;

  /// No description provided for @labelTimeSignature.
  ///
  /// In en, this message translates to:
  /// **'Time Signature'**
  String get labelTimeSignature;

  /// No description provided for @labelSampleRate.
  ///
  /// In en, this message translates to:
  /// **'Sample Rate'**
  String get labelSampleRate;

  /// No description provided for @labelBitDepth.
  ///
  /// In en, this message translates to:
  /// **'Bit Depth'**
  String get labelBitDepth;

  /// No description provided for @labelChannels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get labelChannels;

  /// No description provided for @labelDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get labelDuration;

  /// No description provided for @labelSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get labelSize;

  /// No description provided for @eventName.
  ///
  /// In en, this message translates to:
  /// **'Event Name'**
  String get eventName;

  /// No description provided for @eventStage.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get eventStage;

  /// No description provided for @eventLayers.
  ///
  /// In en, this message translates to:
  /// **'Layers'**
  String get eventLayers;

  /// No description provided for @eventPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get eventPriority;

  /// No description provided for @eventBus.
  ///
  /// In en, this message translates to:
  /// **'Bus'**
  String get eventBus;

  /// No description provided for @containerBlend.
  ///
  /// In en, this message translates to:
  /// **'Blend Container'**
  String get containerBlend;

  /// No description provided for @containerRandom.
  ///
  /// In en, this message translates to:
  /// **'Random Container'**
  String get containerRandom;

  /// No description provided for @containerSequence.
  ///
  /// In en, this message translates to:
  /// **'Sequence Container'**
  String get containerSequence;

  /// No description provided for @busTypeMaster.
  ///
  /// In en, this message translates to:
  /// **'Master'**
  String get busTypeMaster;

  /// No description provided for @busTypeMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get busTypeMusic;

  /// No description provided for @busTypeSfx.
  ///
  /// In en, this message translates to:
  /// **'SFX'**
  String get busTypeSfx;

  /// No description provided for @busTypeVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get busTypeVoice;

  /// No description provided for @busTypeAmbience.
  ///
  /// In en, this message translates to:
  /// **'Ambience'**
  String get busTypeAmbience;

  /// No description provided for @busTypeUi.
  ///
  /// In en, this message translates to:
  /// **'UI'**
  String get busTypeUi;

  /// No description provided for @winTierSmall.
  ///
  /// In en, this message translates to:
  /// **'Small Win'**
  String get winTierSmall;

  /// No description provided for @winTierBig.
  ///
  /// In en, this message translates to:
  /// **'Big Win'**
  String get winTierBig;

  /// No description provided for @winTierSuper.
  ///
  /// In en, this message translates to:
  /// **'Super Win'**
  String get winTierSuper;

  /// No description provided for @winTierMega.
  ///
  /// In en, this message translates to:
  /// **'Mega Win'**
  String get winTierMega;

  /// No description provided for @winTierEpic.
  ///
  /// In en, this message translates to:
  /// **'Epic Win'**
  String get winTierEpic;

  /// No description provided for @winTierUltra.
  ///
  /// In en, this message translates to:
  /// **'Ultra Win'**
  String get winTierUltra;

  /// No description provided for @featureFreeSpins.
  ///
  /// In en, this message translates to:
  /// **'Free Spins'**
  String get featureFreeSpins;

  /// No description provided for @featureBonus.
  ///
  /// In en, this message translates to:
  /// **'Bonus'**
  String get featureBonus;

  /// No description provided for @featureHoldWin.
  ///
  /// In en, this message translates to:
  /// **'Hold & Win'**
  String get featureHoldWin;

  /// No description provided for @featureJackpot.
  ///
  /// In en, this message translates to:
  /// **'Jackpot'**
  String get featureJackpot;

  /// No description provided for @featureCascade.
  ///
  /// In en, this message translates to:
  /// **'Cascade'**
  String get featureCascade;

  /// No description provided for @featureGamble.
  ///
  /// In en, this message translates to:
  /// **'Gamble'**
  String get featureGamble;

  /// No description provided for @statusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get statusConnected;

  /// No description provided for @statusDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get statusDisconnected;

  /// No description provided for @statusLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get statusLoading;

  /// No description provided for @statusError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get statusError;

  /// No description provided for @statusSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get statusSuccess;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusActive;

  /// No description provided for @statusInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get statusInactive;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'An error occurred'**
  String get errorGeneric;

  /// No description provided for @errorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get errorNotFound;

  /// No description provided for @errorInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'Invalid input'**
  String get errorInvalidInput;

  /// No description provided for @errorFileNotFound.
  ///
  /// In en, this message translates to:
  /// **'File not found'**
  String get errorFileNotFound;

  /// No description provided for @errorConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get errorConnectionFailed;

  /// No description provided for @errorExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get errorExportFailed;

  /// No description provided for @errorImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get errorImportFailed;

  /// No description provided for @errorSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed'**
  String get errorSaveFailed;

  /// No description provided for @errorLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Load failed'**
  String get errorLoadFailed;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this?'**
  String get confirmDelete;

  /// No description provided for @confirmDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard unsaved changes?'**
  String get confirmDiscard;

  /// No description provided for @confirmOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite existing file?'**
  String get confirmOverwrite;

  /// No description provided for @tooltipSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tooltipSettings;

  /// No description provided for @tooltipHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get tooltipHelp;

  /// No description provided for @tooltipFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Toggle Fullscreen'**
  String get tooltipFullscreen;

  /// No description provided for @tooltipMinimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get tooltipMinimize;

  /// No description provided for @tooltipMaximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get tooltipMaximize;

  /// No description provided for @projectNew.
  ///
  /// In en, this message translates to:
  /// **'New Project'**
  String get projectNew;

  /// No description provided for @projectOpen.
  ///
  /// In en, this message translates to:
  /// **'Open Project'**
  String get projectOpen;

  /// No description provided for @projectSave.
  ///
  /// In en, this message translates to:
  /// **'Save Project'**
  String get projectSave;

  /// No description provided for @projectSaveAs.
  ///
  /// In en, this message translates to:
  /// **'Save Project As'**
  String get projectSaveAs;

  /// No description provided for @projectExport.
  ///
  /// In en, this message translates to:
  /// **'Export Project'**
  String get projectExport;

  /// No description provided for @projectImport.
  ///
  /// In en, this message translates to:
  /// **'Import Project'**
  String get projectImport;

  /// No description provided for @projectRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent Projects'**
  String get projectRecent;

  /// No description provided for @audioImport.
  ///
  /// In en, this message translates to:
  /// **'Import Audio'**
  String get audioImport;

  /// No description provided for @audioExport.
  ///
  /// In en, this message translates to:
  /// **'Export Audio'**
  String get audioExport;

  /// No description provided for @audioPool.
  ///
  /// In en, this message translates to:
  /// **'Audio Pool'**
  String get audioPool;

  /// No description provided for @audioPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview Audio'**
  String get audioPreview;

  /// No description provided for @audioBrowser.
  ///
  /// In en, this message translates to:
  /// **'Audio Browser'**
  String get audioBrowser;

  /// No description provided for @settingsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneral;

  /// No description provided for @settingsAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get settingsAudio;

  /// No description provided for @settingsDisplay.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get settingsDisplay;

  /// No description provided for @settingsKeyboard.
  ///
  /// In en, this message translates to:
  /// **'Keyboard'**
  String get settingsKeyboard;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageSerbian.
  ///
  /// In en, this message translates to:
  /// **'Serbian'**
  String get languageSerbian;

  /// No description provided for @languageGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get languageGerman;

  /// No description provided for @languageSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get languageSpanish;

  /// No description provided for @languageFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get languageFrench;

  /// No description provided for @languageJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get languageJapanese;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get languageChinese;

  /// No description provided for @nEventsRegistered.
  ///
  /// In en, this message translates to:
  /// **'{count} events registered'**
  String nEventsRegistered(int count);

  /// No description provided for @nFilesSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} files selected'**
  String nFilesSelected(int count);

  /// No description provided for @durationSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String durationSeconds(double seconds);

  /// No description provided for @percentComplete.
  ///
  /// In en, this message translates to:
  /// **'{percent}% complete'**
  String percentComplete(int percent);
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
      <String>['de', 'en', 'sr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'sr':
      return AppLocalizationsSr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
