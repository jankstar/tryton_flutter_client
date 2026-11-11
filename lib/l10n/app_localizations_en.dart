// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Tryton Flutter Client';

  @override
  String get appSubtitle => 'Tryton ERP Client';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get database => 'Database';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get required => 'Required';

  @override
  String get signIn => 'Sign in';

  @override
  String get signOut => 'Sign out';

  @override
  String get loadDatabases => 'Load databases';

  @override
  String get additionalInputRequired => 'Additional input required';

  @override
  String get reloadMenu => 'Reload menu';

  @override
  String get noMenuEntriesFound => 'No menu entries found.';

  @override
  String get retry => 'Retry';

  @override
  String get error => 'Error';

  @override
  String get search => 'Search…';

  @override
  String selected(int count) {
    return '$count selected';
  }

  @override
  String get deleteRecords => 'Delete records';

  @override
  String reallyDeleteRecords(int count) {
    return 'Really delete $count record(s)?';
  }

  @override
  String get noRecordsFound => 'No records found.';

  @override
  String get createNew => 'Create new';

  @override
  String get attachments => 'Attachments';

  @override
  String get duplicate => 'Duplicate';

  @override
  String get openEdit => 'Open / Edit';

  @override
  String get reload => 'Reload';

  @override
  String get delete => 'Delete';

  @override
  String get moreActions => 'More actions';

  @override
  String get launchActions => 'Launch actions';

  @override
  String get relatedRecords => 'Related records';

  @override
  String get reports => 'Reports';

  @override
  String get email => 'Email';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get recordCreated => 'Record created.';

  @override
  String get saved => 'Saved.';

  @override
  String get deleteRecord => 'Delete record';

  @override
  String get reallyDelete => 'Really delete? This cannot be undone.';

  @override
  String get add => 'Add';

  @override
  String get noEntries => 'No entries.';

  @override
  String get apply => 'Apply';

  @override
  String get openRecord => 'Open record';

  @override
  String get clearField => 'Clear field';

  @override
  String get searchRecord => 'Search record';

  @override
  String entries(int count) {
    return '$count entries';
  }

  @override
  String get generatingReport => 'Generating report…';

  @override
  String reportGenerated(String name, String format) {
    return 'Report \"$name\" ($format) generated.';
  }

  @override
  String actionNotSupported(String name, String type) {
    return '\"$name\" ($type) is not yet supported.';
  }

  @override
  String executingButton(String name) {
    return 'Executing button \"$name\"…';
  }

  @override
  String get language => 'Language';

  @override
  String get sessionExpired => 'Session expired';

  @override
  String get preferences => 'Preferences';

  @override
  String get help => 'Help';

  @override
  String get collapse => 'Collapse';

  @override
  String get expand => 'Expand';

  @override
  String get openInForm => 'Open in form';

  @override
  String get undelete => 'Undelete';

  @override
  String get switchToForm => 'Switch to form';

  @override
  String get switchView => 'Switch view';

  @override
  String get close => 'Close';

  @override
  String get boolYes => 'Yes';

  @override
  String get boolNo => 'No';

  @override
  String get clearSearch => 'Clear';

  @override
  String get previousRecord => 'Previous';

  @override
  String get nextRecord => 'Next';

  @override
  String get viewLogs => 'View logs';

  @override
  String get note => 'Note';

  @override
  String get wizard => 'Wizard';

  @override
  String versionMismatch(String server, String client) {
    return 'Incompatible version of the server. Server $server, client $client.';
  }

  @override
  String get recordModified =>
      'This record has been modified.\nDo you want to save it?';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get concurrencyWarning => 'Concurrency Warning';

  @override
  String get concurrencyMessage =>
      'This record has been modified while you were editing it.\nChoose:\n• \"Cancel\" to cancel saving;\n• \"Compare\" to see the modified version;\n• \"Write Anyway\" to save your current version.';

  @override
  String get compare => 'Compare';

  @override
  String get writeAnyway => 'Write Anyway';

  @override
  String get concurrencyException => 'Concurrency Exception';

  @override
  String compareTabTitle(String name) {
    return 'Compare: $name';
  }

  @override
  String get fieldNotSupported => 'Not supported yet';

  @override
  String get ok => 'OK';

  @override
  String get alwaysIgnore => 'Always ignore';

  @override
  String get applicationError => 'Application Error';

  @override
  String get details => 'Details';

  @override
  String httpError(int code, String text) {
    return 'Error: \"[$code] $text\". Try again later.';
  }

  @override
  String networkError(String details) {
    return 'Unable to reach the server. $details';
  }

  @override
  String invalidRequired(String field) {
    return '\"$field\" is required.';
  }

  @override
  String invalidDomain(String field) {
    return '\"$field\" is not valid according to its domain.';
  }

  @override
  String invalidChildren(String field) {
    return 'The values of \"$field\" are not valid.';
  }

  @override
  String get invalidRecordTitle => 'Record not valid';

  @override
  String get selectAction => 'Select your action';

  @override
  String get noActionDefined => 'No action defined.';

  @override
  String get preValidation => 'Pre-validation';

  @override
  String buttonClickedBy(String users) {
    return 'By: $users';
  }

  @override
  String get discardChanges => 'Discard changes';

  @override
  String get saveAndNew => 'Save and New';

  @override
  String get addAndNew => 'Add and New';

  @override
  String get applyChanges => 'Apply changes';

  @override
  String get find => 'Find';

  @override
  String get remove => 'Remove';

  @override
  String get searchMenu => 'Search...';

  @override
  String get createMenu => 'Create...';

  @override
  String searchTitle(String title) {
    return 'Search $title';
  }

  @override
  String createNamed(String name) {
    return 'Create \"$name\"...';
  }

  @override
  String get revisions => 'Revisions...';

  @override
  String get currentRevision => 'Current';

  @override
  String get selectRevision => 'Select a revision';

  @override
  String get filters => 'Filters';

  @override
  String get bookmarkFilter => 'Bookmark this filter';

  @override
  String get removeBookmark => 'Remove this bookmark';

  @override
  String get bookmarks => 'Bookmarks';

  @override
  String get bookmarkName => 'Bookmark Name:';

  @override
  String get showInactive => 'Show inactive records';

  @override
  String get showActive => 'Show active records';

  @override
  String get fieldId => 'ID';

  @override
  String get createdBy => 'Created by';

  @override
  String get createdAt => 'Created at';

  @override
  String get modifiedBy => 'Modified by';

  @override
  String get modifiedAt => 'Modified at';

  @override
  String get rangeFrom => 'From';

  @override
  String get rangeTo => 'To';

  @override
  String get favorites => 'Favorites';

  @override
  String get addToFavorites => 'Add to favorites';

  @override
  String get removeFromFavorites => 'Remove from favorites';

  @override
  String get noFavorites => 'Check menu entries to add favorites';

  @override
  String get globalSearch => 'Global search';

  @override
  String get selectMenuEntry => 'Choose a menu entry';

  @override
  String get selectColor => 'Select a color';

  @override
  String get addValue => 'Add value';

  @override
  String get translate => 'Translate';

  @override
  String get saveBeforeTranslate =>
      'You need to save the record before adding translations.';

  @override
  String get noOtherLanguage => 'No other language available.';

  @override
  String get edit => 'Edit';

  @override
  String get fuzzy => 'Fuzzy';

  @override
  String get columns => 'Columns';

  @override
  String get resetColumnWidths => 'Reset column widths';

  @override
  String get copySelectedRows => 'Copy selected rows';

  @override
  String get notifications => 'Notifications';

  @override
  String get noNotifications => 'No notifications at this time';

  @override
  String get allNotifications => 'All Notifications...';

  @override
  String get closeAllTabsQuestion =>
      'The following action requires to close all tabs.\nDo you want to continue?';

  @override
  String get editUserPreferences => 'Edit User Preferences';

  @override
  String get saveAs => 'Save As...';

  @override
  String get selectFile => 'Select...';

  @override
  String get clear => 'Clear';

  @override
  String get openFile => 'Open...';

  @override
  String attachmentsOf(Object name) {
    return 'Attachments ($name)';
  }

  @override
  String notesOf(Object name) {
    return 'Notes ($name)';
  }

  @override
  String logsOf(Object name) {
    return 'Logs ($name)';
  }

  @override
  String attachmentCount(Object count) {
    return 'Attachment ($count)';
  }

  @override
  String get addFiles => 'Add...';

  @override
  String get manage => 'Manage...';

  @override
  String get logModel => 'Model';

  @override
  String get logModule => 'Module';

  @override
  String get logXmlId => 'XML ID';

  @override
  String get logCreatedBy => 'Created by';

  @override
  String get logCreatedAt => 'Created at';

  @override
  String get logModifiedBy => 'Last modified by';

  @override
  String get logModifiedAt => 'Last modified at';

  @override
  String get exportData => 'Export Data...';

  @override
  String get importData => 'Import Data...';

  @override
  String csvExportTitle(Object name) {
    return 'CSV Export: $name';
  }

  @override
  String csvImportTitle(Object name) {
    return 'CSV Import: $name';
  }

  @override
  String get csvAllFields => 'All Fields';

  @override
  String get csvFieldsSelected => 'Fields Selected';

  @override
  String get csvRemoveAll => 'Clear';

  @override
  String get csvParameters => 'CSV Parameters';

  @override
  String get csvDelimiter => 'Delimiter';

  @override
  String get csvQuoteChar => 'Quote char';

  @override
  String get csvEncoding => 'Encoding';

  @override
  String get csvLocaleFormat => 'Use locale format';

  @override
  String get csvAddFieldNames => 'Add field names';

  @override
  String get csvListedRecords => 'Listed Records';

  @override
  String get csvSelectedRecords => 'Selected Records';

  @override
  String get csvIgnoreSearchLimit => 'Ignore search limit';

  @override
  String get csvPredefinedExports => 'Predefined exports';

  @override
  String get csvSaveExport => 'Save Export';

  @override
  String get csvDeleteExport => 'Delete Export';

  @override
  String get csvExportName => 'What is the name of this export?';

  @override
  String csvOverrideExport(Object name) {
    return 'Override \'$name\' definition?';
  }

  @override
  String csvRecordsSaved(Object count) {
    return 'Records saved: $count';
  }

  @override
  String get csvExportFailed => 'Export failed';

  @override
  String get csvFileToImport => 'File to Import';

  @override
  String get csvLinesToSkip => 'Lines to Skip';

  @override
  String get csvAutoDetect => 'Auto-Detect';

  @override
  String get csvImport => 'Import';

  @override
  String get csvSelectImportFile => 'You must select an import file first.';

  @override
  String csvUnknownHeader(Object name) {
    return 'Unknown column header \"$name\"';
  }

  @override
  String get csvDetectionFailed => 'Detection failed';

  @override
  String csvRecordsImported(Object count) {
    return 'Records imported: $count';
  }

  @override
  String get csvImportFailed => 'Import failed';

  @override
  String csvFieldString(Object name) {
    return '$name (string)';
  }

  @override
  String csvFieldModelName(Object name) {
    return '$name (model name)';
  }

  @override
  String csvFieldRecordName(Object name) {
    return '$name/Record Name';
  }

  @override
  String get open => 'Open';

  @override
  String get recordMenu => 'Record menu';

  @override
  String get menuSwitchView => 'Switch View';

  @override
  String get menuPrevious => 'Previous';

  @override
  String get menuNext => 'Next';

  @override
  String get menuSearch => 'Search';

  @override
  String get menuNew => 'New';

  @override
  String get menuSave => 'Save';

  @override
  String get menuReload => 'Reload/Undo';

  @override
  String get menuDuplicate => 'Duplicate';

  @override
  String get menuDelete => 'Delete...';

  @override
  String get menuLogs => 'View Logs...';

  @override
  String get menuRevisions => 'Show revisions...';

  @override
  String get menuAttachments => 'Attachments...';

  @override
  String get menuNotes => 'Notes...';

  @override
  String get menuActions => 'Actions...';

  @override
  String get menuRelate => 'Relate...';

  @override
  String get menuReport => 'Report...';

  @override
  String get menuEmail => 'Email...';

  @override
  String get menuCloseTab => 'Close Tab';

  @override
  String get keyboardShortcuts => 'Keyboard Shortcuts';

  @override
  String get shortcutsGlobal => 'Global';

  @override
  String get shortcutsForm => 'Form';

  @override
  String get shortcutsRelation => 'Relation Entries';

  @override
  String get shortcutsList => 'List Entries';

  @override
  String get shortcutsDate => 'Date Entries';

  @override
  String get shortcutSearchMenu => 'Search menu';

  @override
  String get shortcutToggleMenu => 'Toggle menu';

  @override
  String get shortcutPreviousTab => 'Previous tab';

  @override
  String get shortcutNextTab => 'Next tab';

  @override
  String get shortcutQuit => 'Quit';

  @override
  String get shortcutRelationNew => 'Create new relation';

  @override
  String get shortcutRelationOpen => 'Open/Search relation';

  @override
  String get shortcutListSwitch => 'Switch view';

  @override
  String get shortcutListNew => 'Create/Select new line';

  @override
  String get shortcutListOpen => 'Open relation';

  @override
  String get shortcutListDelete => 'Mark line for deletion/removal';

  @override
  String get shortcutListRemove => 'Mark line for removal';

  @override
  String get shortcutListUndelete => 'Unmark line for deletion';

  @override
  String get shortcutDateToday => 'Today';

  @override
  String get shortcutDateAdd => 'Add second/minute/hour/day/week/month/year';

  @override
  String get shortcutDateSubtract =>
      'Subtract second/minute/hour/day/week/month/year';

  @override
  String get keyDelete => 'Delete';

  @override
  String get keyInsert => 'Insert';

  @override
  String get ctxCopy => 'Copy';

  @override
  String get ctxCopyRow => 'Copy Row';

  @override
  String get ctxCopyRows => 'Copy Rows';

  @override
  String get ctxCopyColumn => 'Copy Column';

  @override
  String get ctxPasteRows => 'Paste Rows';

  @override
  String get ctxEdit => 'Edit...';

  @override
  String get ctxPrint => 'Print...';

  @override
  String get x2mCreate => 'Create a new record';

  @override
  String get x2mEdit => 'Edit selected record';

  @override
  String get x2mDelete => 'Delete selected record';

  @override
  String get x2mAdd => 'Add existing record';

  @override
  String get x2mRemove => 'Remove selected record';

  @override
  String get x2mUndelete => 'Undelete selected record';

  @override
  String get x2mRestore => 'Restore selected record';

  @override
  String get x2mSwitch => 'Switch';

  @override
  String get x2mPrevious => 'Previous';

  @override
  String get x2mNext => 'Next';

  @override
  String get x2mMore => 'More';

  @override
  String get reportBug => 'Report Bug';

  @override
  String get selectionTitle => 'Selection';

  @override
  String get yourSelection => 'Your selection:';

  @override
  String emailTitle(Object name) {
    return 'Email $name';
  }

  @override
  String get emailTo => 'To';

  @override
  String get emailCc => 'Cc';

  @override
  String get emailBcc => 'Bcc';

  @override
  String get emailSubject => 'Subject';

  @override
  String get emailBody => 'Body';

  @override
  String get emailReports => 'Reports';

  @override
  String get emailAttachments => 'Attachments';

  @override
  String get emailFiles => 'Files';

  @override
  String get emailAddFile => 'Select File';

  @override
  String get emailRemoveFile => 'Remove File';

  @override
  String get emailSend => 'Send';

  @override
  String get emailTemplate => 'Template';

  @override
  String get emailSent => 'Email sent.';

  @override
  String get attachmentPreview => 'Attachment preview';

  @override
  String get noAttachment => 'No attachment.';

  @override
  String get profile => 'Profile';

  @override
  String get editProfiles => 'Edit profiles…';

  @override
  String get profiles => 'Profiles';

  @override
  String get profileName => 'Profile name';

  @override
  String get newProfile => 'New profile';

  @override
  String get deleteProfile => 'Delete profile';

  @override
  String get renameProfile => 'Rename';

  @override
  String get profileNameTaken => 'This profile name is already used.';

  @override
  String get incompatibleServer => 'Incompatible version of the server.';

  @override
  String get couldNotConnect => 'Could not connect to the server.';

  @override
  String get copyUrl => 'Copy URL';

  @override
  String get urlCopied => 'URL copied.';

  @override
  String get openTrytonUrl => 'Open Tryton URL';

  @override
  String urlOtherProfile(Object target, Object profile) {
    return 'The URL belongs to $target. Log in with profile \"$profile\"?';
  }

  @override
  String urlNoProfile(Object target) {
    return 'The URL belongs to $target; there is no profile for it.';
  }

  @override
  String get chat => 'Chat';

  @override
  String get chatInternal => 'Make this an internal message';

  @override
  String get chatInternalTag => 'internal';

  @override
  String get chatFollowers => 'Show followers';

  @override
  String get chatSubscribe => 'Subscribe';

  @override
  String get chatUnsubscribe => 'Unsubscribe';

  @override
  String get chatAddFollower => 'Add a follower';

  @override
  String chatUnsubscribeQuestion(Object name) {
    return 'Are you sure to unsubscribe \"$name\" from this channel?';
  }

  @override
  String get chatEmpty => 'No messages yet.';

  @override
  String get calendarToday => 'Today';

  @override
  String get calendarMonth => 'Month';

  @override
  String get calendarWeek => 'Week';

  @override
  String get calendarDay => 'Day';

  @override
  String get scanCode => 'Scan';

  @override
  String get codeScanner => 'Code Scanner';

  @override
  String get scanCodeHint => 'Code';

  @override
  String get scanCodeSound => 'Sound';

  @override
  String get scanCodeCamera => 'Camera';

  @override
  String get scanCodeNoCamera =>
      'No camera available – enter or scan the code with a hand scanner.';

  @override
  String get allTabs => 'All tabs';

  @override
  String get connectionSecure => 'Encrypted connection (HTTPS)';

  @override
  String get connectionInsecure =>
      'Unencrypted connection (HTTP) – the password is sent in plain text';

  @override
  String get documentation => 'Documentation…';

  @override
  String get aboutMenu => 'About…';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutBasedOn =>
      'Based on the Tryton desktop client and SAO – Copyright (C) 2004-2026 Tryton';

  @override
  String get aboutProjectPage => 'Project page';

  @override
  String get aboutCredits => 'Credits';

  @override
  String get aboutLicense => 'License';

  @override
  String get aboutCopyright => 'Copyright';

  @override
  String get aboutThirdParty => 'Third-party licenses';

  @override
  String get aboutAuthors => 'Authors of this client';

  @override
  String get aboutOriginalAuthors => 'Authors of the Tryton client (original)';

  @override
  String get aboutTranslations => 'Translations';

  @override
  String get aboutNoWarranty =>
      'This program comes with absolutely no warranty.';

  @override
  String aboutSeeLicense(String license) {
    return 'See the $license for details.';
  }

  @override
  String get aboutGplName => 'GNU General Public License, version 3 or later';

  @override
  String get appDevelopment => 'development';

  @override
  String get appPrerelease => 'Test version';
}
