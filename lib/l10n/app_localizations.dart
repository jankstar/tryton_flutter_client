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

  /// Tooltip: switch between the views (list/form) of a screen
  ///
  /// In en, this message translates to:
  /// **'Switch view'**
  String get switchView;

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
  /// **'Incompatible version of the server. Server {server}, client {client}.'**
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

  /// Title of the concurrency dialog (record modified on server)
  ///
  /// In en, this message translates to:
  /// **'Concurrency Warning'**
  String get concurrencyWarning;

  /// Body of the concurrency dialog
  ///
  /// In en, this message translates to:
  /// **'This record has been modified while you were editing it.\nChoose:\n• \"Cancel\" to cancel saving;\n• \"Compare\" to see the modified version;\n• \"Write Anyway\" to save your current version.'**
  String get concurrencyMessage;

  /// Concurrency dialog: open the server version
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get compare;

  /// Concurrency dialog: save without timestamp
  ///
  /// In en, this message translates to:
  /// **'Write Anyway'**
  String get writeAnyway;

  /// Simple message for a concurrency conflict on several records
  ///
  /// In en, this message translates to:
  /// **'Concurrency Exception'**
  String get concurrencyException;

  /// Title of the tab showing the server version
  ///
  /// In en, this message translates to:
  /// **'Compare: {name}'**
  String compareTabTitle(String name);

  /// Placeholder for field types/widgets without an own widget yet
  ///
  /// In en, this message translates to:
  /// **'Not supported yet'**
  String get fieldNotSupported;

  /// OK button in dialogs
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// UserWarning dialog: do not show this warning again
  ///
  /// In en, this message translates to:
  /// **'Always ignore'**
  String get alwaysIgnore;

  /// Title of the dialog for unexpected server exceptions
  ///
  /// In en, this message translates to:
  /// **'Application Error'**
  String get applicationError;

  /// Expandable details (traceback) in the application error dialog
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// HTTP error message
  ///
  /// In en, this message translates to:
  /// **'Error: \"[{code}] {text}\". Try again later.'**
  String httpError(int code, String text);

  /// Server cannot be reached (connection error)
  ///
  /// In en, this message translates to:
  /// **'Unable to reach the server. {details}'**
  String networkError(String details);

  /// Validation: required field is empty (spec 5.5)
  ///
  /// In en, this message translates to:
  /// **'\"{field}\" is required.'**
  String invalidRequired(String field);

  /// Validation: value violates the field domain
  ///
  /// In en, this message translates to:
  /// **'\"{field}\" is not valid according to its domain.'**
  String invalidDomain(String field);

  /// Validation: invalid x2many child records
  ///
  /// In en, this message translates to:
  /// **'The values of \"{field}\" are not valid.'**
  String invalidChildren(String field);

  /// Title of the dialog listing invalid fields before saving
  ///
  /// In en, this message translates to:
  /// **'Record not valid'**
  String get invalidRecordTitle;

  /// Title of the dialog choosing one of several actions of a keyword
  ///
  /// In en, this message translates to:
  /// **'Select your action'**
  String get selectAction;

  /// Message when a keyword has no action
  ///
  /// In en, this message translates to:
  /// **'No action defined.'**
  String get noActionDefined;

  /// Title of the warning when a button pre-validation fails
  ///
  /// In en, this message translates to:
  /// **'Pre-validation'**
  String get preValidation;

  /// Tooltip of a button rule counter: users who clicked
  ///
  /// In en, this message translates to:
  /// **'By: {users}'**
  String buttonClickedBy(String users);

  /// Popup/search dialog text
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get discardChanges;

  /// Popup/search dialog text
  ///
  /// In en, this message translates to:
  /// **'Save and New'**
  String get saveAndNew;

  /// Popup/search dialog text
  ///
  /// In en, this message translates to:
  /// **'Add and New'**
  String get addAndNew;

  /// Popup/search dialog text
  ///
  /// In en, this message translates to:
  /// **'Apply changes'**
  String get applyChanges;

  /// Popup/search dialog text
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get find;

  /// Popup/search dialog text
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// Popup/search dialog text
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get searchMenu;

  /// Popup/search dialog text
  ///
  /// In en, this message translates to:
  /// **'Create...'**
  String get createMenu;

  /// Title of the search dialog
  ///
  /// In en, this message translates to:
  /// **'Search {title}'**
  String searchTitle(String title);

  /// Autocomplete entry creating a record with the typed text
  ///
  /// In en, this message translates to:
  /// **'Create \"{name}\"...'**
  String createNamed(String name);

  /// Revision view (spec 11.7)
  ///
  /// In en, this message translates to:
  /// **'Revisions...'**
  String get revisions;

  /// Revision view (spec 11.7)
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get currentRevision;

  /// Revision view (spec 11.7)
  ///
  /// In en, this message translates to:
  /// **'Select a revision'**
  String get selectRevision;

  /// Search bar (spec 8.4)
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filters;

  /// Search bar (spec 8.4)
  ///
  /// In en, this message translates to:
  /// **'Bookmark this filter'**
  String get bookmarkFilter;

  /// Search bar (spec 8.4)
  ///
  /// In en, this message translates to:
  /// **'Remove this bookmark'**
  String get removeBookmark;

  /// Search bar (spec 8.4)
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarks;

  /// Search bar (spec 8.4)
  ///
  /// In en, this message translates to:
  /// **'Bookmark Name:'**
  String get bookmarkName;

  /// Search bar (spec 8.4)
  ///
  /// In en, this message translates to:
  /// **'Show inactive records'**
  String get showInactive;

  /// Search bar (spec 8.4)
  ///
  /// In en, this message translates to:
  /// **'Show active records'**
  String get showActive;

  /// Search bar (spec 8.4)
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get fieldId;

  /// Search bar (spec 8.4)
  ///
  /// In en, this message translates to:
  /// **'Created by'**
  String get createdBy;

  /// Search bar (spec 8.4)
  ///
  /// In en, this message translates to:
  /// **'Created at'**
  String get createdAt;

  /// Search bar (spec 8.4)
  ///
  /// In en, this message translates to:
  /// **'Modified by'**
  String get modifiedBy;

  /// Search bar (spec 8.4)
  ///
  /// In en, this message translates to:
  /// **'Modified at'**
  String get modifiedAt;

  /// Search bar (spec 8.4)
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get rangeFrom;

  /// Search bar (spec 8.4)
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get rangeTo;

  /// Menu, favorites, global search, tabs (spec 10.1/10.2)
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// Menu, favorites, global search, tabs (spec 10.1/10.2)
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get addToFavorites;

  /// Menu, favorites, global search, tabs (spec 10.1/10.2)
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get removeFromFavorites;

  /// Menu, favorites, global search, tabs (spec 10.1/10.2)
  ///
  /// In en, this message translates to:
  /// **'Check menu entries to add favorites'**
  String get noFavorites;

  /// Menu, favorites, global search, tabs (spec 10.1/10.2)
  ///
  /// In en, this message translates to:
  /// **'Global search'**
  String get globalSearch;

  /// Menu, favorites, global search, tabs (spec 10.1/10.2)
  ///
  /// In en, this message translates to:
  /// **'Choose a menu entry'**
  String get selectMenuEntry;

  /// No description provided for @selectColor.
  ///
  /// In en, this message translates to:
  /// **'Select a color'**
  String get selectColor;

  /// No description provided for @addValue.
  ///
  /// In en, this message translates to:
  /// **'Add value'**
  String get addValue;

  /// No description provided for @translate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get translate;

  /// No description provided for @saveBeforeTranslate.
  ///
  /// In en, this message translates to:
  /// **'You need to save the record before adding translations.'**
  String get saveBeforeTranslate;

  /// No description provided for @noOtherLanguage.
  ///
  /// In en, this message translates to:
  /// **'No other language available.'**
  String get noOtherLanguage;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @fuzzy.
  ///
  /// In en, this message translates to:
  /// **'Fuzzy'**
  String get fuzzy;

  /// No description provided for @columns.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get columns;

  /// No description provided for @resetColumnWidths.
  ///
  /// In en, this message translates to:
  /// **'Reset column widths'**
  String get resetColumnWidths;

  /// No description provided for @copySelectedRows.
  ///
  /// In en, this message translates to:
  /// **'Copy selected rows'**
  String get copySelectedRows;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications at this time'**
  String get noNotifications;

  /// No description provided for @allNotifications.
  ///
  /// In en, this message translates to:
  /// **'All Notifications...'**
  String get allNotifications;

  /// No description provided for @closeAllTabsQuestion.
  ///
  /// In en, this message translates to:
  /// **'The following action requires to close all tabs.\nDo you want to continue?'**
  String get closeAllTabsQuestion;

  /// No description provided for @editUserPreferences.
  ///
  /// In en, this message translates to:
  /// **'Edit User Preferences'**
  String get editUserPreferences;

  /// No description provided for @saveAs.
  ///
  /// In en, this message translates to:
  /// **'Save As...'**
  String get saveAs;

  /// No description provided for @selectFile.
  ///
  /// In en, this message translates to:
  /// **'Select...'**
  String get selectFile;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @openFile.
  ///
  /// In en, this message translates to:
  /// **'Open...'**
  String get openFile;

  /// No description provided for @attachmentsOf.
  ///
  /// In en, this message translates to:
  /// **'Attachments ({name})'**
  String attachmentsOf(Object name);

  /// No description provided for @notesOf.
  ///
  /// In en, this message translates to:
  /// **'Notes ({name})'**
  String notesOf(Object name);

  /// No description provided for @logsOf.
  ///
  /// In en, this message translates to:
  /// **'Logs ({name})'**
  String logsOf(Object name);

  /// No description provided for @attachmentCount.
  ///
  /// In en, this message translates to:
  /// **'Attachment ({count})'**
  String attachmentCount(Object count);

  /// No description provided for @addFiles.
  ///
  /// In en, this message translates to:
  /// **'Add...'**
  String get addFiles;

  /// No description provided for @manage.
  ///
  /// In en, this message translates to:
  /// **'Manage...'**
  String get manage;

  /// No description provided for @logModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get logModel;

  /// No description provided for @logModule.
  ///
  /// In en, this message translates to:
  /// **'Module'**
  String get logModule;

  /// No description provided for @logXmlId.
  ///
  /// In en, this message translates to:
  /// **'XML ID'**
  String get logXmlId;

  /// No description provided for @logCreatedBy.
  ///
  /// In en, this message translates to:
  /// **'Created by'**
  String get logCreatedBy;

  /// No description provided for @logCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created at'**
  String get logCreatedAt;

  /// No description provided for @logModifiedBy.
  ///
  /// In en, this message translates to:
  /// **'Last modified by'**
  String get logModifiedBy;

  /// No description provided for @logModifiedAt.
  ///
  /// In en, this message translates to:
  /// **'Last modified at'**
  String get logModifiedAt;

  /// No description provided for @exportData.
  ///
  /// In en, this message translates to:
  /// **'Export Data...'**
  String get exportData;

  /// No description provided for @importData.
  ///
  /// In en, this message translates to:
  /// **'Import Data...'**
  String get importData;

  /// No description provided for @csvExportTitle.
  ///
  /// In en, this message translates to:
  /// **'CSV Export: {name}'**
  String csvExportTitle(Object name);

  /// No description provided for @csvImportTitle.
  ///
  /// In en, this message translates to:
  /// **'CSV Import: {name}'**
  String csvImportTitle(Object name);

  /// No description provided for @csvAllFields.
  ///
  /// In en, this message translates to:
  /// **'All Fields'**
  String get csvAllFields;

  /// No description provided for @csvFieldsSelected.
  ///
  /// In en, this message translates to:
  /// **'Fields Selected'**
  String get csvFieldsSelected;

  /// No description provided for @csvRemoveAll.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get csvRemoveAll;

  /// No description provided for @csvParameters.
  ///
  /// In en, this message translates to:
  /// **'CSV Parameters'**
  String get csvParameters;

  /// No description provided for @csvDelimiter.
  ///
  /// In en, this message translates to:
  /// **'Delimiter'**
  String get csvDelimiter;

  /// No description provided for @csvQuoteChar.
  ///
  /// In en, this message translates to:
  /// **'Quote char'**
  String get csvQuoteChar;

  /// No description provided for @csvEncoding.
  ///
  /// In en, this message translates to:
  /// **'Encoding'**
  String get csvEncoding;

  /// No description provided for @csvLocaleFormat.
  ///
  /// In en, this message translates to:
  /// **'Use locale format'**
  String get csvLocaleFormat;

  /// No description provided for @csvAddFieldNames.
  ///
  /// In en, this message translates to:
  /// **'Add field names'**
  String get csvAddFieldNames;

  /// No description provided for @csvListedRecords.
  ///
  /// In en, this message translates to:
  /// **'Listed Records'**
  String get csvListedRecords;

  /// No description provided for @csvSelectedRecords.
  ///
  /// In en, this message translates to:
  /// **'Selected Records'**
  String get csvSelectedRecords;

  /// No description provided for @csvIgnoreSearchLimit.
  ///
  /// In en, this message translates to:
  /// **'Ignore search limit'**
  String get csvIgnoreSearchLimit;

  /// No description provided for @csvPredefinedExports.
  ///
  /// In en, this message translates to:
  /// **'Predefined exports'**
  String get csvPredefinedExports;

  /// No description provided for @csvSaveExport.
  ///
  /// In en, this message translates to:
  /// **'Save Export'**
  String get csvSaveExport;

  /// No description provided for @csvDeleteExport.
  ///
  /// In en, this message translates to:
  /// **'Delete Export'**
  String get csvDeleteExport;

  /// No description provided for @csvExportName.
  ///
  /// In en, this message translates to:
  /// **'What is the name of this export?'**
  String get csvExportName;

  /// No description provided for @csvOverrideExport.
  ///
  /// In en, this message translates to:
  /// **'Override \'{name}\' definition?'**
  String csvOverrideExport(Object name);

  /// No description provided for @csvRecordsSaved.
  ///
  /// In en, this message translates to:
  /// **'Records saved: {count}'**
  String csvRecordsSaved(Object count);

  /// No description provided for @csvExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get csvExportFailed;

  /// No description provided for @csvFileToImport.
  ///
  /// In en, this message translates to:
  /// **'File to Import'**
  String get csvFileToImport;

  /// No description provided for @csvLinesToSkip.
  ///
  /// In en, this message translates to:
  /// **'Lines to Skip'**
  String get csvLinesToSkip;

  /// No description provided for @csvAutoDetect.
  ///
  /// In en, this message translates to:
  /// **'Auto-Detect'**
  String get csvAutoDetect;

  /// No description provided for @csvImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get csvImport;

  /// No description provided for @csvSelectImportFile.
  ///
  /// In en, this message translates to:
  /// **'You must select an import file first.'**
  String get csvSelectImportFile;

  /// No description provided for @csvUnknownHeader.
  ///
  /// In en, this message translates to:
  /// **'Unknown column header \"{name}\"'**
  String csvUnknownHeader(Object name);

  /// No description provided for @csvDetectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Detection failed'**
  String get csvDetectionFailed;

  /// No description provided for @csvRecordsImported.
  ///
  /// In en, this message translates to:
  /// **'Records imported: {count}'**
  String csvRecordsImported(Object count);

  /// No description provided for @csvImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get csvImportFailed;

  /// No description provided for @csvFieldString.
  ///
  /// In en, this message translates to:
  /// **'{name} (string)'**
  String csvFieldString(Object name);

  /// No description provided for @csvFieldModelName.
  ///
  /// In en, this message translates to:
  /// **'{name} (model name)'**
  String csvFieldModelName(Object name);

  /// No description provided for @csvFieldRecordName.
  ///
  /// In en, this message translates to:
  /// **'{name}/Record Name'**
  String csvFieldRecordName(Object name);

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @recordMenu.
  ///
  /// In en, this message translates to:
  /// **'Record menu'**
  String get recordMenu;

  /// No description provided for @menuSwitchView.
  ///
  /// In en, this message translates to:
  /// **'Switch View'**
  String get menuSwitchView;

  /// No description provided for @menuPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get menuPrevious;

  /// No description provided for @menuNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get menuNext;

  /// No description provided for @menuSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get menuSearch;

  /// No description provided for @menuNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get menuNew;

  /// No description provided for @menuSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get menuSave;

  /// No description provided for @menuReload.
  ///
  /// In en, this message translates to:
  /// **'Reload/Undo'**
  String get menuReload;

  /// No description provided for @menuDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get menuDuplicate;

  /// No description provided for @menuDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete...'**
  String get menuDelete;

  /// No description provided for @menuLogs.
  ///
  /// In en, this message translates to:
  /// **'View Logs...'**
  String get menuLogs;

  /// No description provided for @menuRevisions.
  ///
  /// In en, this message translates to:
  /// **'Show revisions...'**
  String get menuRevisions;

  /// No description provided for @menuAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments...'**
  String get menuAttachments;

  /// No description provided for @menuNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes...'**
  String get menuNotes;

  /// No description provided for @menuActions.
  ///
  /// In en, this message translates to:
  /// **'Actions...'**
  String get menuActions;

  /// No description provided for @menuRelate.
  ///
  /// In en, this message translates to:
  /// **'Relate...'**
  String get menuRelate;

  /// No description provided for @menuReport.
  ///
  /// In en, this message translates to:
  /// **'Report...'**
  String get menuReport;

  /// No description provided for @menuEmail.
  ///
  /// In en, this message translates to:
  /// **'Email...'**
  String get menuEmail;

  /// No description provided for @menuCloseTab.
  ///
  /// In en, this message translates to:
  /// **'Close Tab'**
  String get menuCloseTab;

  /// No description provided for @keyboardShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcuts'**
  String get keyboardShortcuts;

  /// No description provided for @shortcutsGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global'**
  String get shortcutsGlobal;

  /// No description provided for @shortcutsForm.
  ///
  /// In en, this message translates to:
  /// **'Form'**
  String get shortcutsForm;

  /// No description provided for @shortcutsRelation.
  ///
  /// In en, this message translates to:
  /// **'Relation Entries'**
  String get shortcutsRelation;

  /// No description provided for @shortcutsList.
  ///
  /// In en, this message translates to:
  /// **'List Entries'**
  String get shortcutsList;

  /// No description provided for @shortcutsDate.
  ///
  /// In en, this message translates to:
  /// **'Date Entries'**
  String get shortcutsDate;

  /// No description provided for @shortcutSearchMenu.
  ///
  /// In en, this message translates to:
  /// **'Search menu'**
  String get shortcutSearchMenu;

  /// No description provided for @shortcutToggleMenu.
  ///
  /// In en, this message translates to:
  /// **'Toggle menu'**
  String get shortcutToggleMenu;

  /// No description provided for @shortcutPreviousTab.
  ///
  /// In en, this message translates to:
  /// **'Previous tab'**
  String get shortcutPreviousTab;

  /// No description provided for @shortcutNextTab.
  ///
  /// In en, this message translates to:
  /// **'Next tab'**
  String get shortcutNextTab;

  /// No description provided for @shortcutQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get shortcutQuit;

  /// No description provided for @shortcutRelationNew.
  ///
  /// In en, this message translates to:
  /// **'Create new relation'**
  String get shortcutRelationNew;

  /// No description provided for @shortcutRelationOpen.
  ///
  /// In en, this message translates to:
  /// **'Open/Search relation'**
  String get shortcutRelationOpen;

  /// No description provided for @shortcutListSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch view'**
  String get shortcutListSwitch;

  /// No description provided for @shortcutListNew.
  ///
  /// In en, this message translates to:
  /// **'Create/Select new line'**
  String get shortcutListNew;

  /// No description provided for @shortcutListOpen.
  ///
  /// In en, this message translates to:
  /// **'Open relation'**
  String get shortcutListOpen;

  /// No description provided for @shortcutListDelete.
  ///
  /// In en, this message translates to:
  /// **'Mark line for deletion/removal'**
  String get shortcutListDelete;

  /// No description provided for @shortcutListRemove.
  ///
  /// In en, this message translates to:
  /// **'Mark line for removal'**
  String get shortcutListRemove;

  /// No description provided for @shortcutListUndelete.
  ///
  /// In en, this message translates to:
  /// **'Unmark line for deletion'**
  String get shortcutListUndelete;

  /// No description provided for @shortcutDateToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get shortcutDateToday;

  /// No description provided for @shortcutDateAdd.
  ///
  /// In en, this message translates to:
  /// **'Add second/minute/hour/day/week/month/year'**
  String get shortcutDateAdd;

  /// No description provided for @shortcutDateSubtract.
  ///
  /// In en, this message translates to:
  /// **'Subtract second/minute/hour/day/week/month/year'**
  String get shortcutDateSubtract;

  /// No description provided for @keyDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get keyDelete;

  /// No description provided for @keyInsert.
  ///
  /// In en, this message translates to:
  /// **'Insert'**
  String get keyInsert;

  /// No description provided for @ctxCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get ctxCopy;

  /// No description provided for @ctxCopyRow.
  ///
  /// In en, this message translates to:
  /// **'Copy Row'**
  String get ctxCopyRow;

  /// No description provided for @ctxCopyRows.
  ///
  /// In en, this message translates to:
  /// **'Copy Rows'**
  String get ctxCopyRows;

  /// No description provided for @ctxCopyColumn.
  ///
  /// In en, this message translates to:
  /// **'Copy Column'**
  String get ctxCopyColumn;

  /// No description provided for @ctxPasteRows.
  ///
  /// In en, this message translates to:
  /// **'Paste Rows'**
  String get ctxPasteRows;

  /// No description provided for @ctxEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit...'**
  String get ctxEdit;

  /// No description provided for @ctxPrint.
  ///
  /// In en, this message translates to:
  /// **'Print...'**
  String get ctxPrint;

  /// No description provided for @x2mCreate.
  ///
  /// In en, this message translates to:
  /// **'Create a new record'**
  String get x2mCreate;

  /// No description provided for @x2mEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit selected record'**
  String get x2mEdit;

  /// No description provided for @x2mDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete selected record'**
  String get x2mDelete;

  /// No description provided for @x2mAdd.
  ///
  /// In en, this message translates to:
  /// **'Add existing record'**
  String get x2mAdd;

  /// No description provided for @x2mRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove selected record'**
  String get x2mRemove;

  /// No description provided for @x2mUndelete.
  ///
  /// In en, this message translates to:
  /// **'Undelete selected record'**
  String get x2mUndelete;

  /// No description provided for @x2mRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore selected record'**
  String get x2mRestore;

  /// No description provided for @x2mSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get x2mSwitch;

  /// No description provided for @x2mPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get x2mPrevious;

  /// No description provided for @x2mNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get x2mNext;

  /// No description provided for @x2mMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get x2mMore;

  /// No description provided for @reportBug.
  ///
  /// In en, this message translates to:
  /// **'Report Bug'**
  String get reportBug;

  /// No description provided for @selectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Selection'**
  String get selectionTitle;

  /// No description provided for @yourSelection.
  ///
  /// In en, this message translates to:
  /// **'Your selection:'**
  String get yourSelection;

  /// No description provided for @emailTitle.
  ///
  /// In en, this message translates to:
  /// **'Email {name}'**
  String emailTitle(Object name);

  /// No description provided for @emailTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get emailTo;

  /// No description provided for @emailCc.
  ///
  /// In en, this message translates to:
  /// **'Cc'**
  String get emailCc;

  /// No description provided for @emailBcc.
  ///
  /// In en, this message translates to:
  /// **'Bcc'**
  String get emailBcc;

  /// No description provided for @emailSubject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get emailSubject;

  /// No description provided for @emailBody.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get emailBody;

  /// No description provided for @emailReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get emailReports;

  /// No description provided for @emailAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get emailAttachments;

  /// No description provided for @emailFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get emailFiles;

  /// No description provided for @emailAddFile.
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get emailAddFile;

  /// No description provided for @emailRemoveFile.
  ///
  /// In en, this message translates to:
  /// **'Remove File'**
  String get emailRemoveFile;

  /// No description provided for @emailSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get emailSend;

  /// No description provided for @emailTemplate.
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get emailTemplate;

  /// No description provided for @emailSent.
  ///
  /// In en, this message translates to:
  /// **'Email sent.'**
  String get emailSent;

  /// No description provided for @attachmentPreview.
  ///
  /// In en, this message translates to:
  /// **'Attachment preview'**
  String get attachmentPreview;

  /// No description provided for @noAttachment.
  ///
  /// In en, this message translates to:
  /// **'No attachment.'**
  String get noAttachment;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @editProfiles.
  ///
  /// In en, this message translates to:
  /// **'Edit profiles…'**
  String get editProfiles;

  /// No description provided for @profiles.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get profiles;

  /// No description provided for @profileName.
  ///
  /// In en, this message translates to:
  /// **'Profile name'**
  String get profileName;

  /// No description provided for @newProfile.
  ///
  /// In en, this message translates to:
  /// **'New profile'**
  String get newProfile;

  /// No description provided for @deleteProfile.
  ///
  /// In en, this message translates to:
  /// **'Delete profile'**
  String get deleteProfile;

  /// No description provided for @renameProfile.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameProfile;

  /// No description provided for @profileNameTaken.
  ///
  /// In en, this message translates to:
  /// **'This profile name is already used.'**
  String get profileNameTaken;

  /// No description provided for @incompatibleServer.
  ///
  /// In en, this message translates to:
  /// **'Incompatible version of the server.'**
  String get incompatibleServer;

  /// No description provided for @couldNotConnect.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the server.'**
  String get couldNotConnect;

  /// No description provided for @copyUrl.
  ///
  /// In en, this message translates to:
  /// **'Copy URL'**
  String get copyUrl;

  /// No description provided for @urlCopied.
  ///
  /// In en, this message translates to:
  /// **'URL copied.'**
  String get urlCopied;

  /// No description provided for @openTrytonUrl.
  ///
  /// In en, this message translates to:
  /// **'Open Tryton URL'**
  String get openTrytonUrl;

  /// No description provided for @urlOtherProfile.
  ///
  /// In en, this message translates to:
  /// **'The URL belongs to {target}. Log in with profile \"{profile}\"?'**
  String urlOtherProfile(Object target, Object profile);

  /// No description provided for @urlNoProfile.
  ///
  /// In en, this message translates to:
  /// **'The URL belongs to {target}; there is no profile for it.'**
  String urlNoProfile(Object target);

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @chatInternal.
  ///
  /// In en, this message translates to:
  /// **'Make this an internal message'**
  String get chatInternal;

  /// No description provided for @chatInternalTag.
  ///
  /// In en, this message translates to:
  /// **'internal'**
  String get chatInternalTag;

  /// No description provided for @chatFollowers.
  ///
  /// In en, this message translates to:
  /// **'Show followers'**
  String get chatFollowers;

  /// No description provided for @chatSubscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get chatSubscribe;

  /// No description provided for @chatUnsubscribe.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe'**
  String get chatUnsubscribe;

  /// No description provided for @chatAddFollower.
  ///
  /// In en, this message translates to:
  /// **'Add a follower'**
  String get chatAddFollower;

  /// No description provided for @chatUnsubscribeQuestion.
  ///
  /// In en, this message translates to:
  /// **'Are you sure to unsubscribe \"{name}\" from this channel?'**
  String chatUnsubscribeQuestion(Object name);

  /// No description provided for @chatEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.'**
  String get chatEmpty;

  /// No description provided for @calendarToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get calendarToday;

  /// No description provided for @calendarMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get calendarMonth;

  /// No description provided for @calendarWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get calendarWeek;

  /// No description provided for @calendarDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get calendarDay;

  /// No description provided for @scanCode.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scanCode;

  /// No description provided for @codeScanner.
  ///
  /// In en, this message translates to:
  /// **'Code Scanner'**
  String get codeScanner;

  /// No description provided for @scanCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get scanCodeHint;

  /// No description provided for @scanCodeSound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get scanCodeSound;

  /// No description provided for @scanCodeCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get scanCodeCamera;

  /// No description provided for @scanCodeNoCamera.
  ///
  /// In en, this message translates to:
  /// **'No camera available – enter or scan the code with a hand scanner.'**
  String get scanCodeNoCamera;

  /// No description provided for @allTabs.
  ///
  /// In en, this message translates to:
  /// **'All tabs'**
  String get allTabs;

  /// No description provided for @connectionSecure.
  ///
  /// In en, this message translates to:
  /// **'Encrypted connection (HTTPS)'**
  String get connectionSecure;

  /// No description provided for @connectionInsecure.
  ///
  /// In en, this message translates to:
  /// **'Unencrypted connection (HTTP) – the password is sent in plain text'**
  String get connectionInsecure;

  /// No description provided for @documentation.
  ///
  /// In en, this message translates to:
  /// **'Documentation…'**
  String get documentation;

  /// No description provided for @aboutMenu.
  ///
  /// In en, this message translates to:
  /// **'About…'**
  String get aboutMenu;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get aboutVersion;

  /// No description provided for @aboutBasedOn.
  ///
  /// In en, this message translates to:
  /// **'Based on the Tryton desktop client and SAO – Copyright (C) 2004-2026 Tryton'**
  String get aboutBasedOn;

  /// No description provided for @aboutProjectPage.
  ///
  /// In en, this message translates to:
  /// **'Project page'**
  String get aboutProjectPage;

  /// No description provided for @aboutCredits.
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get aboutCredits;

  /// No description provided for @aboutLicense.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get aboutLicense;

  /// No description provided for @aboutCopyright.
  ///
  /// In en, this message translates to:
  /// **'Copyright'**
  String get aboutCopyright;

  /// No description provided for @aboutThirdParty.
  ///
  /// In en, this message translates to:
  /// **'Third-party licenses'**
  String get aboutThirdParty;

  /// No description provided for @aboutAuthors.
  ///
  /// In en, this message translates to:
  /// **'Authors of this client'**
  String get aboutAuthors;

  /// No description provided for @aboutOriginalAuthors.
  ///
  /// In en, this message translates to:
  /// **'Authors of the Tryton client (original)'**
  String get aboutOriginalAuthors;

  /// No description provided for @aboutTranslations.
  ///
  /// In en, this message translates to:
  /// **'Translations'**
  String get aboutTranslations;

  /// No description provided for @aboutNoWarranty.
  ///
  /// In en, this message translates to:
  /// **'This program comes with absolutely no warranty.'**
  String get aboutNoWarranty;

  /// No description provided for @aboutSeeLicense.
  ///
  /// In en, this message translates to:
  /// **'See the {license} for details.'**
  String aboutSeeLicense(String license);

  /// No description provided for @aboutGplName.
  ///
  /// In en, this message translates to:
  /// **'GNU General Public License, version 3 or later'**
  String get aboutGplName;

  /// No description provided for @appDevelopment.
  ///
  /// In en, this message translates to:
  /// **'development'**
  String get appDevelopment;

  /// No description provided for @appPrerelease.
  ///
  /// In en, this message translates to:
  /// **'Test version'**
  String get appPrerelease;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Wrong user name or password.'**
  String get loginFailed;

  /// No description provided for @tooManyRequests.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Try again later.'**
  String get tooManyRequests;

  /// No description provided for @databaseNotFound.
  ///
  /// In en, this message translates to:
  /// **'Database not found.'**
  String get databaseNotFound;

  /// No description provided for @serverForbidden.
  ///
  /// In en, this message translates to:
  /// **'The server does not allow this.'**
  String get serverForbidden;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset forgotten password'**
  String get resetPassword;

  /// No description provided for @resetPasswordTooltip.
  ///
  /// In en, this message translates to:
  /// **'Send you an email to reset your password.'**
  String get resetPasswordTooltip;

  /// No description provided for @resetPasswordSent.
  ///
  /// In en, this message translates to:
  /// **'A request to reset your password has been sent.\nPlease check your mailbox.'**
  String get resetPasswordSent;

  /// No description provided for @resetPasswordNeedsUser.
  ///
  /// In en, this message translates to:
  /// **'Enter server, database and user name first.'**
  String get resetPasswordNeedsUser;
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
