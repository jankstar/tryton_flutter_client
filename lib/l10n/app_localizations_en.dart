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
    return 'Incompatible server version $server (client expects $client).';
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
  String get boardNotSupported => 'Dashboards are not supported yet.';

  @override
  String get selectMenuEntry => 'Choose a menu entry';
}
