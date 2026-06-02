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
}
