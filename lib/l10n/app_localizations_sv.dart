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
  String get switchView => 'Byt vy';

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

  @override
  String get concurrencyWarning => 'Varning för samtidig åtkomst';

  @override
  String get concurrencyMessage =>
      'Denna post har ändrats medan du redigerade den.\nVälj:\n• \"Avbryt\" för att avbryta sparandet;\n• \"Jämför\" för att se den ändrade versionen;\n• \"Skriv ändå\" för att spara din nuvarande version.';

  @override
  String get compare => 'Jämför';

  @override
  String get writeAnyway => 'Skriv ändå';

  @override
  String get concurrencyException => 'Fel vid samtidig åtkomst';

  @override
  String compareTabTitle(String name) {
    return 'Jämför: $name';
  }

  @override
  String get fieldNotSupported => 'Stöds inte ännu';

  @override
  String get ok => 'OK';

  @override
  String get alwaysIgnore => 'Ignorera alltid';

  @override
  String get applicationError => 'Programfel';

  @override
  String get details => 'Detaljer';

  @override
  String httpError(int code, String text) {
    return 'Fel: \"[$code] $text\". Försök igen senare.';
  }

  @override
  String networkError(String details) {
    return 'Kan inte nå servern. $details';
  }

  @override
  String invalidRequired(String field) {
    return '\"$field\" är obligatoriskt.';
  }

  @override
  String invalidDomain(String field) {
    return '\"$field\" är inte giltigt enligt domänen.';
  }

  @override
  String invalidChildren(String field) {
    return 'Värdena i \"$field\" är inte giltiga.';
  }

  @override
  String get invalidRecordTitle => 'Posten är inte giltig';

  @override
  String get selectAction => 'Välj åtgärd';

  @override
  String get noActionDefined => 'Ingen åtgärd definierad.';

  @override
  String get preValidation => 'Förhandsvalidering';

  @override
  String buttonClickedBy(String users) {
    return 'Av: $users';
  }

  @override
  String get discardChanges => 'Ignorera ändringar';

  @override
  String get saveAndNew => 'Spara och ny';

  @override
  String get addAndNew => 'Lägg till och ny';

  @override
  String get applyChanges => 'Verkställ ändringar';

  @override
  String get find => 'Sök';

  @override
  String get remove => 'Ta bort';

  @override
  String get searchMenu => 'Sök…';

  @override
  String get createMenu => 'Skapa…';

  @override
  String searchTitle(String title) {
    return 'Sök $title';
  }

  @override
  String createNamed(String name) {
    return 'Skapa \"$name\"…';
  }

  @override
  String get revisions => 'Revisioner…';

  @override
  String get currentRevision => 'Aktuell';

  @override
  String get selectRevision => 'Välj en revision';

  @override
  String get filters => 'Filter';

  @override
  String get bookmarkFilter => 'Bokmärk detta filter';

  @override
  String get removeBookmark => 'Ta bort bokmärke';

  @override
  String get bookmarks => 'Bokmärken';

  @override
  String get bookmarkName => 'Bokmärkets namn:';

  @override
  String get showInactive => 'Visa inaktiva poster';

  @override
  String get showActive => 'Visa aktiva poster';

  @override
  String get fieldId => 'ID';

  @override
  String get createdBy => 'Skapad av';

  @override
  String get createdAt => 'Skapad';

  @override
  String get modifiedBy => 'Ändrad av';

  @override
  String get modifiedAt => 'Ändrad';

  @override
  String get rangeFrom => 'Från';

  @override
  String get rangeTo => 'Till';
}
