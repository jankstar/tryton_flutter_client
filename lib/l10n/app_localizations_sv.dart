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

  @override
  String get favorites => 'Favoriter';

  @override
  String get addToFavorites => 'Lägg till i favoriter';

  @override
  String get removeFromFavorites => 'Ta bort från favoriter';

  @override
  String get noFavorites => 'Markera menyposter för att lägga till favoriter';

  @override
  String get globalSearch => 'Global sökning';

  @override
  String get selectMenuEntry => 'Välj en menypost';

  @override
  String get selectColor => 'Välj en färg';

  @override
  String get addValue => 'Lägg till värde';

  @override
  String get translate => 'Översätt';

  @override
  String get saveBeforeTranslate =>
      'Du måste spara posten innan du lägger till översättningar.';

  @override
  String get noOtherLanguage => 'Inget annat språk tillgängligt.';

  @override
  String get edit => 'Redigera';

  @override
  String get fuzzy => 'Osäker';

  @override
  String get columns => 'Kolumner';

  @override
  String get resetColumnWidths => 'Återställ kolumnbredder';

  @override
  String get copySelectedRows => 'Kopiera markerade rader';

  @override
  String get notifications => 'Aviseringar';

  @override
  String get noNotifications => 'Inga aviseringar just nu';

  @override
  String get allNotifications => 'Alla aviseringar …';

  @override
  String get closeAllTabsQuestion =>
      'Åtgärden kräver att alla flikar stängs.\nVill du fortsätta?';

  @override
  String get editUserPreferences => 'Redigera användarinställningar';

  @override
  String get saveAs => 'Spara som …';

  @override
  String get selectFile => 'Välj …';

  @override
  String get clear => 'Rensa';

  @override
  String get openFile => 'Öppna …';

  @override
  String attachmentsOf(Object name) {
    return 'Bilagor ($name)';
  }

  @override
  String notesOf(Object name) {
    return 'Anteckningar ($name)';
  }

  @override
  String logsOf(Object name) {
    return 'Loggar ($name)';
  }

  @override
  String attachmentCount(Object count) {
    return 'Bilaga ($count)';
  }

  @override
  String get addFiles => 'Lägg till …';

  @override
  String get manage => 'Hantera …';

  @override
  String get logModel => 'Modell';

  @override
  String get logModule => 'Modul';

  @override
  String get logXmlId => 'XML-id';

  @override
  String get logCreatedBy => 'Skapad av';

  @override
  String get logCreatedAt => 'Skapad';

  @override
  String get logModifiedBy => 'Senast ändrad av';

  @override
  String get logModifiedAt => 'Senast ändrad';

  @override
  String get exportData => 'Exportera data…';

  @override
  String get importData => 'Importera data…';

  @override
  String csvExportTitle(Object name) {
    return 'CSV-export: $name';
  }

  @override
  String csvImportTitle(Object name) {
    return 'CSV-import: $name';
  }

  @override
  String get csvAllFields => 'Alla fält';

  @override
  String get csvFieldsSelected => 'Valda fält';

  @override
  String get csvRemoveAll => 'Rensa';

  @override
  String get csvParameters => 'CSV-parametrar';

  @override
  String get csvDelimiter => 'Avgränsare';

  @override
  String get csvQuoteChar => 'Citattecken';

  @override
  String get csvEncoding => 'Teckenkodning';

  @override
  String get csvLocaleFormat => 'Använd lokalt format';

  @override
  String get csvAddFieldNames => 'Lägg till fältnamn';

  @override
  String get csvListedRecords => 'Listade poster';

  @override
  String get csvSelectedRecords => 'Valda poster';

  @override
  String get csvIgnoreSearchLimit => 'Ignorera sökgräns';

  @override
  String get csvPredefinedExports => 'Fördefinierade exporter';

  @override
  String get csvSaveExport => 'Spara export';

  @override
  String get csvDeleteExport => 'Ta bort export';

  @override
  String get csvExportName => 'Vad heter denna export?';

  @override
  String csvOverrideExport(Object name) {
    return 'Skriva över definitionen av \'$name\'?';
  }

  @override
  String csvRecordsSaved(Object count) {
    return 'Sparade poster: $count';
  }

  @override
  String get csvExportFailed => 'Exporten misslyckades';

  @override
  String get csvFileToImport => 'Fil att importera';

  @override
  String get csvLinesToSkip => 'Rader att hoppa över';

  @override
  String get csvAutoDetect => 'Identifiera automatiskt';

  @override
  String get csvImport => 'Importera';

  @override
  String get csvSelectImportFile => 'Du måste först välja en importfil.';

  @override
  String csvUnknownHeader(Object name) {
    return 'Okänd kolumnrubrik \"$name\"';
  }

  @override
  String get csvDetectionFailed => 'Identifieringen misslyckades';

  @override
  String csvRecordsImported(Object count) {
    return 'Importerade poster: $count';
  }

  @override
  String get csvImportFailed => 'Importen misslyckades';

  @override
  String csvFieldString(Object name) {
    return '$name (text)';
  }

  @override
  String csvFieldModelName(Object name) {
    return '$name (modellnamn)';
  }

  @override
  String csvFieldRecordName(Object name) {
    return '$name/Postnamn';
  }

  @override
  String get open => 'Öppna';

  @override
  String get recordMenu => 'Postmeny';

  @override
  String get menuSwitchView => 'Byt vy';

  @override
  String get menuPrevious => 'Föregående';

  @override
  String get menuNext => 'Nästa';

  @override
  String get menuSearch => 'Sök';

  @override
  String get menuNew => 'Ny';

  @override
  String get menuSave => 'Spara';

  @override
  String get menuReload => 'Läs om/Ångra';

  @override
  String get menuDuplicate => 'Duplicera';

  @override
  String get menuDelete => 'Ta bort …';

  @override
  String get menuLogs => 'Visa loggar …';

  @override
  String get menuRevisions => 'Visa revisioner …';

  @override
  String get menuAttachments => 'Bilagor …';

  @override
  String get menuNotes => 'Anteckningar …';

  @override
  String get menuActions => 'Åtgärder …';

  @override
  String get menuRelate => 'Relaterade …';

  @override
  String get menuReport => 'Rapport …';

  @override
  String get menuEmail => 'E-post …';

  @override
  String get menuCloseTab => 'Stäng flik';

  @override
  String get keyboardShortcuts => 'Kortkommandon';

  @override
  String get shortcutsGlobal => 'Allmänt';

  @override
  String get shortcutsForm => 'Formulär';

  @override
  String get shortcutsRelation => 'Relationsfält';

  @override
  String get shortcutsList => 'Listfält';

  @override
  String get shortcutsDate => 'Datumfält';

  @override
  String get shortcutSearchMenu => 'Sök i menyn';

  @override
  String get shortcutToggleMenu => 'Visa/dölj meny';

  @override
  String get shortcutPreviousTab => 'Föregående flik';

  @override
  String get shortcutNextTab => 'Nästa flik';

  @override
  String get shortcutQuit => 'Avsluta';

  @override
  String get shortcutRelationNew => 'Skapa ny relation';

  @override
  String get shortcutRelationOpen => 'Öppna/sök relation';

  @override
  String get shortcutListSwitch => 'Byt vy';

  @override
  String get shortcutListNew => 'Skapa/välj ny rad';

  @override
  String get shortcutListOpen => 'Öppna relation';

  @override
  String get shortcutListDelete => 'Markera rad för borttagning';

  @override
  String get shortcutListRemove => 'Markera rad för frikoppling';

  @override
  String get shortcutListUndelete => 'Ta bort borttagningsmarkering';

  @override
  String get shortcutDateToday => 'Idag';

  @override
  String get shortcutDateAdd =>
      'Lägg till sekund/minut/timme/dag/vecka/månad/år';

  @override
  String get shortcutDateSubtract =>
      'Dra av sekund/minut/timme/dag/vecka/månad/år';

  @override
  String get keyDelete => 'Delete';

  @override
  String get keyInsert => 'Insert';

  @override
  String get ctxCopy => 'Kopiera';

  @override
  String get ctxCopyRow => 'Kopiera rad';

  @override
  String get ctxCopyRows => 'Kopiera rader';

  @override
  String get ctxCopyColumn => 'Kopiera kolumn';

  @override
  String get ctxPasteRows => 'Klistra in rader';

  @override
  String get ctxEdit => 'Redigera …';

  @override
  String get ctxPrint => 'Skriv ut …';

  @override
  String get x2mCreate => 'Skapa en ny post';

  @override
  String get x2mEdit => 'Redigera vald post';

  @override
  String get x2mDelete => 'Ta bort vald post';

  @override
  String get x2mAdd => 'Lägg till befintlig post';

  @override
  String get x2mRemove => 'Koppla bort vald post';

  @override
  String get x2mUndelete => 'Återställ vald post';

  @override
  String get x2mRestore => 'Återställ vald post';

  @override
  String get x2mSwitch => 'Växla';

  @override
  String get x2mPrevious => 'Föregående';

  @override
  String get x2mNext => 'Nästa';

  @override
  String get x2mMore => 'Mer';
}
