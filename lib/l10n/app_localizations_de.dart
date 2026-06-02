// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Tryton Flutter Client';

  @override
  String get appSubtitle => 'Tryton ERP-Client';

  @override
  String get username => 'Benutzername';

  @override
  String get password => 'Passwort';

  @override
  String get database => 'Datenbank';

  @override
  String get serverUrl => 'Server-URL';

  @override
  String get required => 'Erforderlich';

  @override
  String get signIn => 'Anmelden';

  @override
  String get signOut => 'Abmelden';

  @override
  String get loadDatabases => 'Datenbanken laden';

  @override
  String get additionalInputRequired => 'Zusätzliche Eingabe erforderlich';

  @override
  String get reloadMenu => 'Menü neu laden';

  @override
  String get noMenuEntriesFound => 'Keine Menüeinträge gefunden.';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get error => 'Fehler';

  @override
  String get search => 'Suchen…';

  @override
  String selected(int count) {
    return '$count ausgewählt';
  }

  @override
  String get deleteRecords => 'Datensätze löschen';

  @override
  String reallyDeleteRecords(int count) {
    return 'Wirklich $count Datensatz/Datensätze löschen?';
  }

  @override
  String get noRecordsFound => 'Keine Datensätze gefunden.';

  @override
  String get createNew => 'Neu erstellen';

  @override
  String get attachments => 'Anhänge';

  @override
  String get duplicate => 'Duplizieren';

  @override
  String get openEdit => 'Öffnen / Bearbeiten';

  @override
  String get reload => 'Neu laden';

  @override
  String get delete => 'Löschen';

  @override
  String get moreActions => 'Weitere Aktionen';

  @override
  String get launchActions => 'Aktionen starten';

  @override
  String get relatedRecords => 'Verknüpfte Datensätze';

  @override
  String get reports => 'Berichte';

  @override
  String get email => 'E-Mail';

  @override
  String get save => 'Speichern';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get recordCreated => 'Datensatz erstellt.';

  @override
  String get saved => 'Gespeichert.';

  @override
  String get deleteRecord => 'Datensatz löschen';

  @override
  String get reallyDelete =>
      'Wirklich löschen? Dies kann nicht rückgängig gemacht werden.';

  @override
  String get add => 'Hinzufügen';

  @override
  String get noEntries => 'Keine Einträge.';

  @override
  String get apply => 'Anwenden';

  @override
  String get openRecord => 'Datensatz öffnen';

  @override
  String get clearField => 'Feld leeren';

  @override
  String get searchRecord => 'Datensatz suchen';

  @override
  String entries(int count) {
    return '$count Einträge';
  }

  @override
  String get generatingReport => 'Bericht wird erstellt…';

  @override
  String reportGenerated(String name, String format) {
    return 'Bericht \"$name\" ($format) erstellt.';
  }

  @override
  String actionNotSupported(String name, String type) {
    return '\"$name\" ($type) wird noch nicht unterstützt.';
  }

  @override
  String executingButton(String name) {
    return 'Schaltfläche \"$name\" wird ausgeführt…';
  }

  @override
  String get language => 'Sprache';

  @override
  String get sessionExpired => 'Sitzung abgelaufen';

  @override
  String get preferences => 'Einstellungen';

  @override
  String get help => 'Hilfe';

  @override
  String get collapse => 'Zuklappen';

  @override
  String get expand => 'Aufklappen';

  @override
  String get openInForm => 'Im Formular öffnen';

  @override
  String get undelete => 'Löschung rückgängig machen';

  @override
  String get switchToForm => 'Zum Formular wechseln';

  @override
  String get close => 'Schließen';

  @override
  String get boolYes => 'Ja';

  @override
  String get boolNo => 'Nein';

  @override
  String get clearSearch => 'Leeren';

  @override
  String get previousRecord => 'Vorheriger';

  @override
  String get nextRecord => 'Nächster';

  @override
  String get viewLogs => 'Protokoll anzeigen';

  @override
  String get note => 'Notiz';

  @override
  String get wizard => 'Assistent';

  @override
  String versionMismatch(String server, String client) {
    return 'Inkompatible Serverversion $server (Client erwartet $client).';
  }

  @override
  String get recordModified =>
      'Dieser Datensatz wurde geändert.\nMöchten Sie ihn speichern?';

  @override
  String get yes => 'Ja';

  @override
  String get no => 'Nein';
}
