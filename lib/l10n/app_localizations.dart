import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_da.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fi.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_nl.dart';
import 'app_localizations_pl.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_sv.dart';

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
    Locale('da'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fi'),
    Locale('fr'),
    Locale('nl'),
    Locale('pl'),
    Locale('pt'),
    Locale('ru'),
    Locale('sv'),
  ];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'Tryton Flutter Client'**
  String get appTitle;

  /// Application subtitle on login screen
  ///
  /// In en, this message translates to:
  /// **'Tryton ERP Client'**
  String get appSubtitle;

  /// Label for the username field
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// Label for the password field
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// Label for the database selector
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get database;

  /// Label for the server URL field
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get serverUrl;

  /// Validation message for empty required fields
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// Login button label
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// Logout button tooltip
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// Tooltip for the refresh databases button
  ///
  /// In en, this message translates to:
  /// **'Load databases'**
  String get loadDatabases;

  /// Shown when MFA or extra login step is needed
  ///
  /// In en, this message translates to:
  /// **'Additional input required'**
  String get additionalInputRequired;

  /// Tooltip for the menu refresh button
  ///
  /// In en, this message translates to:
  /// **'Reload menu'**
  String get reloadMenu;

  /// Shown when the server returns an empty menu
  ///
  /// In en, this message translates to:
  /// **'No menu entries found.'**
  String get noMenuEntriesFound;

  /// Button label to retry a failed operation
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Generic error label
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// Placeholder text in the search bar
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get search;

  /// Number of selected rows in a list view
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selected(int count);

  /// Dialog title for multi-record deletion
  ///
  /// In en, this message translates to:
  /// **'Delete records'**
  String get deleteRecords;

  /// Confirmation message for deleting multiple records
  ///
  /// In en, this message translates to:
  /// **'Really delete {count} record(s)?'**
  String reallyDeleteRecords(int count);

  /// Shown when a list view returns no results
  ///
  /// In en, this message translates to:
  /// **'No records found.'**
  String get noRecordsFound;

  /// Button label to create a new record
  ///
  /// In en, this message translates to:
  /// **'Create new'**
  String get createNew;

  /// Tooltip for the attachments button
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachments;

  /// Tooltip for the duplicate/copy button
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicate;

  /// Tooltip for the open/edit button in list views
  ///
  /// In en, this message translates to:
  /// **'Open / Edit'**
  String get openEdit;

  /// Tooltip for the reload button
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// Button/tooltip label to delete a record
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Tooltip for the overflow actions menu
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActions;

  /// Toolbar submenu header for keyword actions
  ///
  /// In en, this message translates to:
  /// **'Launch actions'**
  String get launchActions;

  /// Toolbar submenu header for relate actions
  ///
  /// In en, this message translates to:
  /// **'Related records'**
  String get relatedRecords;

  /// Toolbar submenu header for report actions
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// Toolbar submenu header for email templates
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// Button label to save a record
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Button label to cancel a dialog or operation
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Snackbar shown after a new record is created
  ///
  /// In en, this message translates to:
  /// **'Record created.'**
  String get recordCreated;

  /// Snackbar shown after saving a record
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get saved;

  /// Confirmation dialog title for deleting a single record
  ///
  /// In en, this message translates to:
  /// **'Delete record'**
  String get deleteRecord;

  /// Confirmation dialog body for deleting a record
  ///
  /// In en, this message translates to:
  /// **'Really delete? This cannot be undone.'**
  String get reallyDelete;

  /// Button label to add a row in an inline tree widget
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// Shown when an inline One2Many table is empty
  ///
  /// In en, this message translates to:
  /// **'No entries.'**
  String get noEntries;

  /// Button label to apply/confirm a row dialog
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// Tooltip for the open-related-record button on Many2One fields
  ///
  /// In en, this message translates to:
  /// **'Open record'**
  String get openRecord;

  /// Tooltip for the clear button on Many2One fields
  ///
  /// In en, this message translates to:
  /// **'Clear field'**
  String get clearField;

  /// Tooltip for the search button on Many2One fields
  ///
  /// In en, this message translates to:
  /// **'Search record'**
  String get searchRecord;

  /// Entry count shown for X2Many fields in read-only mode
  ///
  /// In en, this message translates to:
  /// **'{count} entries'**
  String entries(int count);

  /// Snackbar shown while a report is being generated
  ///
  /// In en, this message translates to:
  /// **'Generating report…'**
  String get generatingReport;

  /// Snackbar shown after a report is successfully generated
  ///
  /// In en, this message translates to:
  /// **'Report \"{name}\" ({format}) generated.'**
  String reportGenerated(String name, String format);

  /// Snackbar shown when an action type is not yet implemented
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" ({type}) is not yet supported.'**
  String actionNotSupported(String name, String type);

  /// Snackbar shown when a form button is triggered
  ///
  /// In en, this message translates to:
  /// **'Executing button \"{name}\"…'**
  String executingButton(String name);

  /// Label for the language selector
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Title of the re-login dialog when session expires
  ///
  /// In en, this message translates to:
  /// **'Session expired'**
  String get sessionExpired;

  /// Menu item and screen title for user preferences
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// Menu item for help
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get help;

  /// Tooltip to collapse a tree node
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get collapse;

  /// Tooltip to expand a tree node
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get expand;

  /// Tooltip to open an embedded tree record in full form view
  ///
  /// In en, this message translates to:
  /// **'Open in form'**
  String get openInForm;

  /// Tooltip to undo a pending delete in embedded tree
  ///
  /// In en, this message translates to:
  /// **'Undelete'**
  String get undelete;

  /// Tooltip to switch selected list records to form view
  ///
  /// In en, this message translates to:
  /// **'Switch to form'**
  String get switchToForm;

  /// Tooltip/button to close the current view and return to menu
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Display value for boolean true in list/form
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get boolYes;

  /// Display value for boolean false in list/form
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get boolNo;

  /// Tooltip for the clear button in the search bar
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearSearch;

  /// Tooltip for the previous-record navigation button
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previousRecord;

  /// Tooltip for the next-record navigation button
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get nextRecord;

  /// Tooltip for the view-logs button in the form toolbar
  ///
  /// In en, this message translates to:
  /// **'View logs'**
  String get viewLogs;

  /// Tooltip for the note/chat button in the form toolbar
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get note;

  /// Action type label shown when a wizard is not yet supported
  ///
  /// In en, this message translates to:
  /// **'Wizard'**
  String get wizard;

  /// Error shown when server major.minor version doesn't match the client
  ///
  /// In en, this message translates to:
  /// **'Incompatible server version {server} (client expects {client}).'**
  String versionMismatch(String server, String client);

  /// Dialog shown when navigating away from a modified record
  ///
  /// In en, this message translates to:
  /// **'This record has been modified.\nDo you want to save it?'**
  String get recordModified;

  /// Affirmative answer in dialogs
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// Negative answer in dialogs
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'da',
    'de',
    'en',
    'es',
    'fi',
    'fr',
    'nl',
    'pl',
    'pt',
    'ru',
    'sv',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'da':
      return AppLocalizationsDa();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fi':
      return AppLocalizationsFi();
    case 'fr':
      return AppLocalizationsFr();
    case 'nl':
      return AppLocalizationsNl();
    case 'pl':
      return AppLocalizationsPl();
    case 'pt':
      return AppLocalizationsPt();
    case 'ru':
      return AppLocalizationsRu();
    case 'sv':
      return AppLocalizationsSv();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
