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
  String get switchView => 'Ansicht wechseln';

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

  @override
  String get concurrencyWarning => 'Warnung: Gleichzeitiger Zugriff';

  @override
  String get concurrencyMessage =>
      'Dieser Datensatz wurde geändert, während Sie ihn bearbeitet haben.\nWählen Sie:\n• „Abbrechen“, um das Speichern abzubrechen;\n• „Vergleichen“, um die geänderte Version anzuzeigen;\n• „Trotzdem schreiben“, um Ihre aktuelle Version zu speichern.';

  @override
  String get compare => 'Vergleichen';

  @override
  String get writeAnyway => 'Trotzdem schreiben';

  @override
  String get concurrencyException => 'Gleichzeitiger Zugriff';

  @override
  String compareTabTitle(String name) {
    return 'Vergleichen: $name';
  }

  @override
  String get fieldNotSupported => 'Wird noch nicht unterstützt';

  @override
  String get ok => 'OK';

  @override
  String get alwaysIgnore => 'Immer ignorieren';

  @override
  String get applicationError => 'Anwendungsfehler';

  @override
  String get details => 'Details';

  @override
  String httpError(int code, String text) {
    return 'Fehler: „[$code] $text“. Bitte später erneut versuchen.';
  }

  @override
  String networkError(String details) {
    return 'Server nicht erreichbar. $details';
  }

  @override
  String invalidRequired(String field) {
    return '„$field“ ist erforderlich.';
  }

  @override
  String invalidDomain(String field) {
    return '„$field“ ist laut Domain nicht gültig.';
  }

  @override
  String invalidChildren(String field) {
    return 'Die Werte von „$field“ sind nicht gültig.';
  }

  @override
  String get invalidRecordTitle => 'Datensatz nicht gültig';

  @override
  String get selectAction => 'Aktion auswählen';

  @override
  String get noActionDefined => 'Keine Aktion definiert.';

  @override
  String get preValidation => 'Vorabprüfung';

  @override
  String buttonClickedBy(String users) {
    return 'Von: $users';
  }

  @override
  String get discardChanges => 'Änderungen verwerfen';

  @override
  String get saveAndNew => 'Speichern und Neu';

  @override
  String get addAndNew => 'Hinzufügen und Neu';

  @override
  String get applyChanges => 'Änderungen übernehmen';

  @override
  String get find => 'Suchen';

  @override
  String get remove => 'Entfernen';

  @override
  String get searchMenu => 'Suchen…';

  @override
  String get createMenu => 'Neu…';

  @override
  String searchTitle(String title) {
    return '$title suchen';
  }

  @override
  String createNamed(String name) {
    return '„$name“ anlegen…';
  }

  @override
  String get revisions => 'Revisionen…';

  @override
  String get currentRevision => 'Aktuell';

  @override
  String get selectRevision => 'Revision auswählen';

  @override
  String get filters => 'Filter';

  @override
  String get bookmarkFilter => 'Filter als Lesezeichen speichern';

  @override
  String get removeBookmark => 'Lesezeichen entfernen';

  @override
  String get bookmarks => 'Lesezeichen';

  @override
  String get bookmarkName => 'Name des Lesezeichens:';

  @override
  String get showInactive => 'Inaktive Datensätze anzeigen';

  @override
  String get showActive => 'Aktive Datensätze anzeigen';

  @override
  String get fieldId => 'ID';

  @override
  String get createdBy => 'Erstellt von';

  @override
  String get createdAt => 'Erstellt am';

  @override
  String get modifiedBy => 'Geändert von';

  @override
  String get modifiedAt => 'Geändert am';

  @override
  String get rangeFrom => 'Von';

  @override
  String get rangeTo => 'Bis';

  @override
  String get favorites => 'Favoriten';

  @override
  String get addToFavorites => 'Zu Favoriten hinzufügen';

  @override
  String get removeFromFavorites => 'Aus Favoriten entfernen';

  @override
  String get noFavorites =>
      'Menüeinträge mit dem Stern als Favoriten markieren';

  @override
  String get globalSearch => 'Globale Suche';

  @override
  String get selectMenuEntry => 'Wähle einen Menüeintrag';

  @override
  String get selectColor => 'Farbe wählen';

  @override
  String get addValue => 'Wert hinzufügen';

  @override
  String get translate => 'Übersetzen';

  @override
  String get saveBeforeTranslate =>
      'Sie müssen den Datensatz speichern, bevor Sie Übersetzungen hinzufügen.';

  @override
  String get noOtherLanguage => 'Keine andere Sprache verfügbar.';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get fuzzy => 'Unscharf';

  @override
  String get columns => 'Spalten';

  @override
  String get resetColumnWidths => 'Spaltenbreiten zurücksetzen';

  @override
  String get copySelectedRows => 'Ausgewählte Zeilen kopieren';

  @override
  String get notifications => 'Benachrichtigungen';

  @override
  String get noNotifications => 'Derzeit keine Benachrichtigungen';

  @override
  String get allNotifications => 'Alle Benachrichtigungen …';

  @override
  String get closeAllTabsQuestion =>
      'Für diese Aktion müssen alle Tabs geschlossen werden.\nMöchten Sie fortfahren?';

  @override
  String get editUserPreferences => 'Benutzereinstellungen bearbeiten';

  @override
  String get saveAs => 'Speichern unter …';

  @override
  String get selectFile => 'Auswählen …';

  @override
  String get clear => 'Leeren';

  @override
  String get openFile => 'Öffnen …';

  @override
  String attachmentsOf(Object name) {
    return 'Anhänge ($name)';
  }

  @override
  String notesOf(Object name) {
    return 'Notizen ($name)';
  }

  @override
  String logsOf(Object name) {
    return 'Protokolle ($name)';
  }

  @override
  String attachmentCount(Object count) {
    return 'Anhang ($count)';
  }

  @override
  String get addFiles => 'Hinzufügen …';

  @override
  String get manage => 'Verwalten …';

  @override
  String get logModel => 'Modell';

  @override
  String get logModule => 'Modul';

  @override
  String get logXmlId => 'XML-ID';

  @override
  String get logCreatedBy => 'Erstellt von';

  @override
  String get logCreatedAt => 'Erstellt am';

  @override
  String get logModifiedBy => 'Zuletzt geändert von';

  @override
  String get logModifiedAt => 'Zuletzt geändert am';

  @override
  String get exportData => 'Daten exportieren …';

  @override
  String get importData => 'Daten importieren …';

  @override
  String csvExportTitle(Object name) {
    return 'CSV-Export: $name';
  }

  @override
  String csvImportTitle(Object name) {
    return 'CSV-Import: $name';
  }

  @override
  String get csvAllFields => 'Alle Felder';

  @override
  String get csvFieldsSelected => 'Ausgewählte Felder';

  @override
  String get csvRemoveAll => 'Alle entfernen';

  @override
  String get csvParameters => 'CSV-Parameter';

  @override
  String get csvDelimiter => 'Trennzeichen';

  @override
  String get csvQuoteChar => 'Anführungszeichen';

  @override
  String get csvEncoding => 'Kodierung';

  @override
  String get csvLocaleFormat => 'Lokales Format verwenden';

  @override
  String get csvAddFieldNames => 'Feldnamen hinzufügen';

  @override
  String get csvListedRecords => 'Aufgelistete Datensätze';

  @override
  String get csvSelectedRecords => 'Ausgewählte Datensätze';

  @override
  String get csvIgnoreSearchLimit => 'Suchlimit ignorieren';

  @override
  String get csvPredefinedExports => 'Vordefinierte Exporte';

  @override
  String get csvSaveExport => 'Export speichern';

  @override
  String get csvDeleteExport => 'Export löschen';

  @override
  String get csvExportName => 'Wie soll dieser Export heißen?';

  @override
  String csvOverrideExport(Object name) {
    return 'Definition von „$name“ überschreiben?';
  }

  @override
  String csvRecordsSaved(Object count) {
    return 'Gespeicherte Datensätze: $count';
  }

  @override
  String get csvExportFailed => 'Export fehlgeschlagen';

  @override
  String get csvFileToImport => 'Zu importierende Datei';

  @override
  String get csvLinesToSkip => 'Zu überspringende Zeilen';

  @override
  String get csvAutoDetect => 'Automatisch erkennen';

  @override
  String get csvImport => 'Importieren';

  @override
  String get csvSelectImportFile => 'Bitte zuerst eine Importdatei auswählen.';

  @override
  String csvUnknownHeader(Object name) {
    return 'Unbekannte Spaltenüberschrift „$name“';
  }

  @override
  String get csvDetectionFailed => 'Erkennung fehlgeschlagen';

  @override
  String csvRecordsImported(Object count) {
    return 'Importierte Datensätze: $count';
  }

  @override
  String get csvImportFailed => 'Import fehlgeschlagen';

  @override
  String csvFieldString(Object name) {
    return '$name (Text)';
  }

  @override
  String csvFieldModelName(Object name) {
    return '$name (Modellname)';
  }

  @override
  String csvFieldRecordName(Object name) {
    return '$name/Datensatzname';
  }

  @override
  String get open => 'Öffnen';

  @override
  String get recordMenu => 'Datensatz-Menü';

  @override
  String get menuSwitchView => 'Ansicht wechseln';

  @override
  String get menuPrevious => 'Vorheriger';

  @override
  String get menuNext => 'Nächster';

  @override
  String get menuSearch => 'Suchen';

  @override
  String get menuNew => 'Neu';

  @override
  String get menuSave => 'Speichern';

  @override
  String get menuReload => 'Neu laden/Rückgängig';

  @override
  String get menuDuplicate => 'Duplizieren';

  @override
  String get menuDelete => 'Löschen …';

  @override
  String get menuLogs => 'Protokolle anzeigen …';

  @override
  String get menuRevisions => 'Revisionen anzeigen …';

  @override
  String get menuAttachments => 'Anhänge …';

  @override
  String get menuNotes => 'Notizen …';

  @override
  String get menuActions => 'Aktionen …';

  @override
  String get menuRelate => 'Verknüpfen …';

  @override
  String get menuReport => 'Bericht …';

  @override
  String get menuEmail => 'E-Mail …';

  @override
  String get menuCloseTab => 'Tab schließen';

  @override
  String get keyboardShortcuts => 'Tastenkürzel';

  @override
  String get shortcutsGlobal => 'Allgemein';

  @override
  String get shortcutsForm => 'Formular';

  @override
  String get shortcutsRelation => 'Relationsfelder';

  @override
  String get shortcutsList => 'Listenfelder';

  @override
  String get shortcutsDate => 'Datumsfelder';

  @override
  String get shortcutSearchMenu => 'Menü durchsuchen';

  @override
  String get shortcutToggleMenu => 'Menü ein-/ausblenden';

  @override
  String get shortcutPreviousTab => 'Vorheriger Tab';

  @override
  String get shortcutNextTab => 'Nächster Tab';

  @override
  String get shortcutQuit => 'Beenden';

  @override
  String get shortcutRelationNew => 'Neue Relation anlegen';

  @override
  String get shortcutRelationOpen => 'Relation öffnen/suchen';

  @override
  String get shortcutListSwitch => 'Ansicht wechseln';

  @override
  String get shortcutListNew => 'Neue Zeile anlegen/auswählen';

  @override
  String get shortcutListOpen => 'Relation öffnen';

  @override
  String get shortcutListDelete => 'Zeile zum Löschen/Entfernen markieren';

  @override
  String get shortcutListRemove => 'Zeile zum Entfernen markieren';

  @override
  String get shortcutListUndelete => 'Löschmarkierung aufheben';

  @override
  String get shortcutDateToday => 'Heute';

  @override
  String get shortcutDateAdd =>
      'Sekunde/Minute/Stunde/Tag/Woche/Monat/Jahr addieren';

  @override
  String get shortcutDateSubtract =>
      'Sekunde/Minute/Stunde/Tag/Woche/Monat/Jahr abziehen';

  @override
  String get keyDelete => 'Entf';

  @override
  String get keyInsert => 'Einfg';

  @override
  String get ctxCopy => 'Kopieren';

  @override
  String get ctxCopyRow => 'Zeile kopieren';

  @override
  String get ctxCopyRows => 'Zeilen kopieren';

  @override
  String get ctxCopyColumn => 'Spalte kopieren';

  @override
  String get ctxPasteRows => 'Zeilen einfügen';

  @override
  String get ctxEdit => 'Bearbeiten …';

  @override
  String get ctxPrint => 'Drucken …';

  @override
  String get x2mCreate => 'Neuen Datensatz anlegen';

  @override
  String get x2mEdit => 'Ausgewählten Datensatz bearbeiten';

  @override
  String get x2mDelete => 'Ausgewählten Datensatz löschen';

  @override
  String get x2mAdd => 'Bestehenden Datensatz hinzufügen';

  @override
  String get x2mRemove => 'Ausgewählten Datensatz entfernen';

  @override
  String get x2mUndelete => 'Wiederherstellen';

  @override
  String get x2mRestore => 'Wiederherstellen';

  @override
  String get x2mSwitch => 'Wechseln';

  @override
  String get x2mPrevious => 'Vorheriger';

  @override
  String get x2mNext => 'Nächster';

  @override
  String get x2mMore => 'Mehr';

  @override
  String get reportBug => 'Fehler melden';

  @override
  String get selectionTitle => 'Auswahl';

  @override
  String get yourSelection => 'Ihre Auswahl:';

  @override
  String emailTitle(Object name) {
    return 'E-Mail $name';
  }

  @override
  String get emailTo => 'An';

  @override
  String get emailCc => 'Cc';

  @override
  String get emailBcc => 'Bcc';

  @override
  String get emailSubject => 'Betreff';

  @override
  String get emailBody => 'Text';

  @override
  String get emailReports => 'Berichte';

  @override
  String get emailAttachments => 'Anhänge';

  @override
  String get emailFiles => 'Dateien';

  @override
  String get emailAddFile => 'Datei auswählen';

  @override
  String get emailRemoveFile => 'Datei entfernen';

  @override
  String get emailSend => 'Senden';

  @override
  String get emailTemplate => 'Vorlage';

  @override
  String get emailSent => 'E-Mail gesendet.';

  @override
  String get attachmentPreview => 'Anhang-Vorschau';

  @override
  String get noAttachment => 'Kein Anhang.';

  @override
  String get profile => 'Profil';

  @override
  String get editProfiles => 'Profile bearbeiten…';

  @override
  String get profiles => 'Profile';

  @override
  String get profileName => 'Profilname';

  @override
  String get newProfile => 'Neues Profil';

  @override
  String get deleteProfile => 'Profil löschen';

  @override
  String get renameProfile => 'Umbenennen';

  @override
  String get profileNameTaken => 'Dieser Profilname ist schon vergeben.';

  @override
  String get incompatibleServer => 'Inkompatible Version des Servers.';

  @override
  String get couldNotConnect => 'Keine Verbindung zum Server.';

  @override
  String get copyUrl => 'URL kopieren';

  @override
  String get urlCopied => 'URL kopiert.';

  @override
  String get openTrytonUrl => 'Tryton-URL öffnen';

  @override
  String urlOtherProfile(Object target, Object profile) {
    return 'Die URL gehört zu $target. Mit Profil „$profile“ anmelden?';
  }

  @override
  String urlNoProfile(Object target) {
    return 'Die URL gehört zu $target; dafür gibt es kein Profil.';
  }

  @override
  String get chat => 'Chat';

  @override
  String get chatInternal => 'Als interne Nachricht senden';

  @override
  String get chatInternalTag => 'intern';

  @override
  String get chatFollowers => 'Follower anzeigen';

  @override
  String get chatSubscribe => 'Abonnieren';

  @override
  String get chatUnsubscribe => 'Abbestellen';

  @override
  String get chatAddFollower => 'Follower hinzufügen';

  @override
  String chatUnsubscribeQuestion(Object name) {
    return '„$name“ wirklich von diesem Kanal abmelden?';
  }

  @override
  String get chatEmpty => 'Noch keine Nachrichten.';
}
