// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Swedish (`sv`).
class AppLocalizationsSv extends AppLocalizations {
  AppLocalizationsSv([String locale = 'sv']) : super(locale);

  @override
  String get appTitle => 'Tryton Flutter Client';

  @override
  String get appSubtitle => 'Tryton ERP-klient';

  @override
  String get username => 'Användarnamn';

  @override
  String get password => 'Lösenord';

  @override
  String get database => 'Databas';

  @override
  String get serverUrl => 'Server-URL';

  @override
  String get required => 'Obligatoriskt';

  @override
  String get signIn => 'Logga in';

  @override
  String get signOut => 'Logga ut';

  @override
  String get loadDatabases => 'Ladda databaser';

  @override
  String get additionalInputRequired => 'Ytterligare inmatning krävs';

  @override
  String get reloadMenu => 'Ladda om meny';

  @override
  String get noMenuEntriesFound => 'Inga menyposter hittades.';

  @override
  String get retry => 'Försök igen';

  @override
  String get error => 'Fel';

  @override
  String get search => 'Sök…';

  @override
  String selected(int count) {
    return '$count markerade';
  }

  @override
  String get deleteRecords => 'Ta bort poster';

  @override
  String reallyDeleteRecords(int count) {
    return 'Ta bort $count post(er)?';
  }

  @override
  String get noRecordsFound => 'Inga poster hittades.';

  @override
  String get createNew => 'Skapa ny';

  @override
  String get attachments => 'Bilagor';

  @override
  String get duplicate => 'Duplicera';

  @override
  String get openEdit => 'Öppna / Redigera';

  @override
  String get reload => 'Ladda om';

  @override
  String get delete => 'Ta bort';

  @override
  String get moreActions => 'Fler åtgärder';

  @override
  String get launchActions => 'Starta åtgärder';

  @override
  String get relatedRecords => 'Relaterade poster';

  @override
  String get reports => 'Rapporter';

  @override
  String get email => 'E-post';

  @override
  String get save => 'Spara';

  @override
  String get cancel => 'Avbryt';

  @override
  String get recordCreated => 'Post skapad.';

  @override
  String get saved => 'Sparad.';

  @override
  String get deleteRecord => 'Ta bort post';

  @override
  String get reallyDelete => 'Ta bort? Denna åtgärd kan inte ångras.';

  @override
  String get add => 'Lägg till';

  @override
  String get noEntries => 'Inga poster.';

  @override
  String get apply => 'Tillämpa';

  @override
  String get openRecord => 'Öppna post';

  @override
  String get clearField => 'Rensa fält';

  @override
  String get searchRecord => 'Sök post';

  @override
  String entries(int count) {
    return '$count poster';
  }

  @override
  String get generatingReport => 'Genererar rapport…';

  @override
  String reportGenerated(String name, String format) {
    return 'Rapport \"$name\" ($format) genererad.';
  }

  @override
  String actionNotSupported(String name, String type) {
    return '\"$name\" ($type) stöds inte ännu.';
  }

  @override
  String executingButton(String name) {
    return 'Kör knapp \"$name\"…';
  }

  @override
  String get language => 'Språk';

  @override
  String get sessionExpired => 'Sessionen har gått ut';

  @override
  String get preferences => 'Inställningar';

  @override
  String get help => 'Hjälp';

  @override
  String get collapse => 'Fäll ihop';

  @override
  String get expand => 'Expandera';

  @override
  String get openInForm => 'Öppna i formulär';

  @override
  String get undelete => 'Ångra borttagning';

  @override
  String get switchToForm => 'Byt till formulär';

  @override
  String get close => 'Stäng';

  @override
  String get boolYes => 'Ja';

  @override
  String get boolNo => 'Nej';

  @override
  String get clearSearch => 'Rensa';

  @override
  String get previousRecord => 'Föregående';

  @override
  String get nextRecord => 'Nästa';

  @override
  String get viewLogs => 'Visa loggar';

  @override
  String get note => 'Anteckning';

  @override
  String get wizard => 'Guide';

  @override
  String versionMismatch(String server, String client) {
    return 'Inkompatibel serverversion $server (klienten förväntar sig $client).';
  }

  @override
  String get recordModified => 'Denna post har ändrats.\nVill du spara den?';

  @override
  String get yes => 'Ja';

  @override
  String get no => 'Nej';
}
