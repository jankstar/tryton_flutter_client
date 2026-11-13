// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Danish (`da`).
class AppLocalizationsDa extends AppLocalizations {
  AppLocalizationsDa([String locale = 'da']) : super(locale);

  @override
  String get appTitle => 'Tryton Flutter Client';

  @override
  String get appSubtitle => 'Tryton ERP-klient';

  @override
  String get username => 'Brugernavn';

  @override
  String get password => 'Adgangskode';

  @override
  String get database => 'Database';

  @override
  String get serverUrl => 'Server-URL';

  @override
  String get required => 'Påkrævet';

  @override
  String get signIn => 'Log ind';

  @override
  String get signOut => 'Log ud';

  @override
  String get loadDatabases => 'Indlæs databaser';

  @override
  String get additionalInputRequired => 'Yderligere input påkrævet';

  @override
  String get reloadMenu => 'Genindlæs menu';

  @override
  String get noMenuEntriesFound => 'Ingen menupunkter fundet.';

  @override
  String get retry => 'Prøv igen';

  @override
  String get error => 'Fejl';

  @override
  String get search => 'Søg…';

  @override
  String selected(int count) {
    return '$count valgt';
  }

  @override
  String get deleteRecords => 'Slet poster';

  @override
  String get reallyDeleteRecords =>
      'Er du sikker på, at du vil fjerne disse poster?';

  @override
  String get noRecordsFound => 'Ingen poster fundet.';

  @override
  String get createNew => 'Opret ny';

  @override
  String get attachments => 'Vedhæftede filer';

  @override
  String get duplicate => 'Dupliker';

  @override
  String get openEdit => 'Åbn / Rediger';

  @override
  String get reload => 'Genindlæs';

  @override
  String get delete => 'Slet';

  @override
  String get moreActions => 'Flere handlinger';

  @override
  String get launchActions => 'Start handlinger';

  @override
  String get relatedRecords => 'Relaterede poster';

  @override
  String get reports => 'Rapporter';

  @override
  String get email => 'E-mail';

  @override
  String get save => 'Gem';

  @override
  String get cancel => 'Annuller';

  @override
  String get recordCreated => 'Post oprettet.';

  @override
  String get saved => 'Gemt.';

  @override
  String get deleteRecord => 'Slet post';

  @override
  String get reallyDelete => 'Er du sikker på, at du vil fjerne denne post?';

  @override
  String get add => 'Tilføj';

  @override
  String get noEntries => 'Ingen poster.';

  @override
  String get apply => 'Anvend';

  @override
  String get openRecord => 'Åbn post';

  @override
  String get clearField => 'Ryd felt';

  @override
  String get searchRecord => 'Søg post';

  @override
  String entries(int count) {
    return '$count poster';
  }

  @override
  String get generatingReport => 'Genererer rapport…';

  @override
  String reportGenerated(String name, String format) {
    return 'Rapport \"$name\" ($format) genereret.';
  }

  @override
  String actionNotSupported(String name, String type) {
    return '\"$name\" ($type) understøttes endnu ikke.';
  }

  @override
  String executingButton(String name) {
    return 'Udfører knap \"$name\"…';
  }

  @override
  String get language => 'Sprog';

  @override
  String get sessionExpired => 'Session udløbet';

  @override
  String get preferences => 'Præferencer';

  @override
  String get help => 'Hjælp';

  @override
  String get collapse => 'Skjul';

  @override
  String get expand => 'Udvid';

  @override
  String get openInForm => 'Åbn i formular';

  @override
  String get undelete => 'Fortryd sletning';

  @override
  String get switchToForm => 'Skift til formular';

  @override
  String get switchView => 'Skift visning';

  @override
  String get close => 'Luk';

  @override
  String get boolYes => 'Ja';

  @override
  String get boolNo => 'Nej';

  @override
  String get clearSearch => 'Ryd';

  @override
  String get previousRecord => 'Forrige';

  @override
  String get nextRecord => 'Næste';

  @override
  String get viewLogs => 'Vis logfiler';

  @override
  String get note => 'Note';

  @override
  String get wizard => 'Guide';

  @override
  String versionMismatch(String server, String client) {
    return 'Inkompatibel serverversion. Server $server, klient $client.';
  }

  @override
  String get recordModified =>
      'Denne post er blevet ændret.\nVil du gemme den?';

  @override
  String get yes => 'Ja';

  @override
  String get no => 'Nej';

  @override
  String get concurrencyWarning => 'Advarsel om samtidig adgang';

  @override
  String get concurrencyMessage =>
      'Denne post er blevet ændret, mens du redigerede den.';

  @override
  String get compare => 'Sammenlign';

  @override
  String get writeAnyway => 'Skriv alligevel';

  @override
  String get concurrencyException => 'Samtidig adgang';

  @override
  String compareTabTitle(String name) {
    return 'Sammenlign: $name';
  }

  @override
  String get fieldNotSupported => 'Understøttes endnu ikke';

  @override
  String get ok => 'OK';

  @override
  String get alwaysIgnore => 'Ignorer altid';

  @override
  String get applicationError => 'Programfejl';

  @override
  String get details => 'Detaljer';

  @override
  String httpError(int code, String text) {
    return 'Fejl: \"[$code] $text\". Prøv igen senere.';
  }

  @override
  String networkError(String details) {
    return 'Kan ikke nå serveren. $details';
  }

  @override
  String invalidRequired(String field) {
    return '\"$field\" er påkrævet.';
  }

  @override
  String invalidDomain(String field) {
    return '\"$field\" er ikke gyldig i henhold til domænet.';
  }

  @override
  String invalidChildren(String field) {
    return 'Værdierne i \"$field\" er ikke gyldige.';
  }

  @override
  String get invalidRecordTitle => 'Posten er ikke gyldig';

  @override
  String get selectAction => 'Vælg handling';

  @override
  String get noActionDefined => 'Ingen handling defineret.';

  @override
  String get preValidation => 'Forhåndsvalidering';

  @override
  String buttonClickedBy(String users) {
    return 'Af: $users';
  }

  @override
  String get discardChanges => 'Kassér ændringer';

  @override
  String get saveAndNew => 'Gem og ny';

  @override
  String get addAndNew => 'Tilføj og ny';

  @override
  String get applyChanges => 'Anvend ændringer';

  @override
  String get find => 'Find';

  @override
  String get remove => 'Fjern';

  @override
  String get searchMenu => 'Søg…';

  @override
  String get createMenu => 'Opret…';

  @override
  String searchTitle(String title) {
    return 'Søg $title';
  }

  @override
  String createNamed(String name) {
    return 'Opret \"$name\"…';
  }

  @override
  String get revisions => 'Revisioner…';

  @override
  String get currentRevision => 'Aktuel';

  @override
  String get selectRevision => 'Vælg en revision';

  @override
  String get filters => 'Filtre';

  @override
  String get bookmarkFilter => 'Bogmærk dette filter';

  @override
  String get removeBookmark => 'Fjern bogmærke';

  @override
  String get bookmarks => 'Bogmærker';

  @override
  String get bookmarkName => 'Bogmærkets navn:';

  @override
  String get showInactive => 'Vis inaktive poster';

  @override
  String get showActive => 'Vis aktive poster';

  @override
  String get fieldId => 'ID';

  @override
  String get createdBy => 'Oprettet af';

  @override
  String get createdAt => 'Oprettet';

  @override
  String get modifiedBy => 'Ændret af';

  @override
  String get modifiedAt => 'Ændret';

  @override
  String get rangeFrom => 'Fra';

  @override
  String get rangeTo => 'Til';

  @override
  String get favorites => 'Favoritter';

  @override
  String get addToFavorites => 'Føj til favoritter';

  @override
  String get removeFromFavorites => 'Fjern fra favoritter';

  @override
  String get noFavorites => 'Markér menupunkter for at tilføje favoritter';

  @override
  String get globalSearch => 'Global søgning';

  @override
  String get selectMenuEntry => 'Vælg et menupunkt';

  @override
  String get selectColor => 'Vælg en farve';

  @override
  String get addValue => 'Tilføj værdi';

  @override
  String get translate => 'Oversæt';

  @override
  String get saveBeforeTranslate =>
      'Du skal gemme posten, før du tilføjer oversættelser.';

  @override
  String get noOtherLanguage => 'Intet andet sprog tilgængeligt.';

  @override
  String get edit => 'Rediger';

  @override
  String get fuzzy => 'Usikker';

  @override
  String get columns => 'Kolonner';

  @override
  String get resetColumnWidths => 'Nulstil kolonnebredder';

  @override
  String get copySelectedRows => 'Kopiér valgte rækker';

  @override
  String get notifications => 'Notifikationer';

  @override
  String get noNotifications => 'Ingen notifikationer i øjeblikket';

  @override
  String get allNotifications => 'Alle notifikationer …';

  @override
  String get closeAllTabsQuestion =>
      'Denne handling kræver, at alle faner lukkes.\nVil du fortsætte?';

  @override
  String get editUserPreferences => 'Rediger brugerindstillinger';

  @override
  String get saveAs => 'Gem som …';

  @override
  String get selectFile => 'Vælg …';

  @override
  String get clear => 'Ryd';

  @override
  String get openFile => 'Åbn …';

  @override
  String attachmentsOf(Object name) {
    return 'Vedhæftninger ($name)';
  }

  @override
  String notesOf(Object name) {
    return 'Noter ($name)';
  }

  @override
  String logsOf(Object name) {
    return 'Logfiler ($name)';
  }

  @override
  String attachmentCount(Object count) {
    return 'Vedhæftning ($count)';
  }

  @override
  String get addFiles => 'Tilføj …';

  @override
  String get manage => 'Administrer …';

  @override
  String get logModel => 'Model';

  @override
  String get logModule => 'Modul';

  @override
  String get logXmlId => 'XML-id';

  @override
  String get logCreatedBy => 'Oprettet af';

  @override
  String get logCreatedAt => 'Oprettet';

  @override
  String get logModifiedBy => 'Sidst ændret af';

  @override
  String get logModifiedAt => 'Sidst ændret';

  @override
  String get exportData => 'Eksporter data …';

  @override
  String get importData => 'Importer data …';

  @override
  String csvExportTitle(Object name) {
    return 'CSV-eksport: $name';
  }

  @override
  String csvImportTitle(Object name) {
    return 'CSV-import: $name';
  }

  @override
  String get csvAllFields => 'Alle felter';

  @override
  String get csvFieldsSelected => 'Valgte felter';

  @override
  String get csvRemoveAll => 'Ryd';

  @override
  String get csvParameters => 'CSV-parametre';

  @override
  String get csvDelimiter => 'Skilletegn';

  @override
  String get csvQuoteChar => 'Citattegn';

  @override
  String get csvEncoding => 'Kodning';

  @override
  String get csvLocaleFormat => 'Brug lokalt format';

  @override
  String get csvAddFieldNames => 'Tilføj feltnavne';

  @override
  String get csvListedRecords => 'Viste poster';

  @override
  String get csvSelectedRecords => 'Valgte poster';

  @override
  String get csvIgnoreSearchLimit => 'Ignorer søgegrænse';

  @override
  String get csvPredefinedExports => 'Foruddefinerede eksporter';

  @override
  String get csvSaveExport => 'Gem eksport';

  @override
  String get csvDeleteExport => 'Slet eksport';

  @override
  String get csvExportName => 'Hvad skal denne eksport hedde?';

  @override
  String csvOverrideExport(Object name) {
    return 'Overskriv definitionen af \'$name\'?';
  }

  @override
  String csvRecordsSaved(Object count) {
    return 'Gemte poster: $count';
  }

  @override
  String get csvExportFailed => 'Eksport mislykkedes';

  @override
  String get csvFileToImport => 'Fil der skal importeres';

  @override
  String get csvLinesToSkip => 'Linjer der springes over';

  @override
  String get csvAutoDetect => 'Auto-detekter';

  @override
  String get csvImport => 'Importer';

  @override
  String get csvSelectImportFile => 'Du skal først vælge en importfil.';

  @override
  String csvUnknownHeader(Object name) {
    return 'Ukendt kolonneoverskrift \"$name\"';
  }

  @override
  String get csvDetectionFailed => 'Detektering mislykkedes';

  @override
  String csvRecordsImported(Object count) {
    return 'Importerede poster: $count';
  }

  @override
  String get csvImportFailed => 'Import mislykkedes';

  @override
  String csvFieldString(Object name) {
    return '$name (tekst)';
  }

  @override
  String csvFieldModelName(Object name) {
    return '$name (modelnavn)';
  }

  @override
  String csvFieldRecordName(Object name) {
    return '$name/Postnavn';
  }

  @override
  String get open => 'Åbn';

  @override
  String get recordMenu => 'Postmenu';

  @override
  String get menuSwitchView => 'Skift visning';

  @override
  String get menuPrevious => 'Forrige';

  @override
  String get menuNext => 'Næste';

  @override
  String get menuSearch => 'Søg';

  @override
  String get menuNew => 'Ny';

  @override
  String get menuSave => 'Gem';

  @override
  String get menuReload => 'Genindlæs/Fortryd';

  @override
  String get menuDuplicate => 'Dupliker';

  @override
  String get menuDelete => 'Slet …';

  @override
  String get menuLogs => 'Vis logge …';

  @override
  String get menuRevisions => 'Vis revisioner …';

  @override
  String get menuAttachments => 'Vedhæftninger …';

  @override
  String get menuNotes => 'Noter …';

  @override
  String get menuActions => 'Handlinger …';

  @override
  String get menuRelate => 'Relaterede …';

  @override
  String get menuReport => 'Rapport …';

  @override
  String get menuEmail => 'E-mail …';

  @override
  String get menuCloseTab => 'Luk fane';

  @override
  String get keyboardShortcuts => 'Tastaturgenveje';

  @override
  String get shortcutsGlobal => 'Generelt';

  @override
  String get shortcutsForm => 'Formular';

  @override
  String get shortcutsRelation => 'Relationsfelter';

  @override
  String get shortcutsList => 'Listefelter';

  @override
  String get shortcutsDate => 'Datofelter';

  @override
  String get shortcutSearchMenu => 'Søg i menu';

  @override
  String get shortcutToggleMenu => 'Vis/skjul menu';

  @override
  String get shortcutPreviousTab => 'Forrige fane';

  @override
  String get shortcutNextTab => 'Næste fane';

  @override
  String get shortcutQuit => 'Afslut';

  @override
  String get shortcutRelationNew => 'Opret ny relation';

  @override
  String get shortcutRelationOpen => 'Åbn/søg relation';

  @override
  String get shortcutListSwitch => 'Skift visning';

  @override
  String get shortcutListNew => 'Opret/vælg ny linje';

  @override
  String get shortcutListOpen => 'Åbn relation';

  @override
  String get shortcutListDelete => 'Markér linje til sletning/fjernelse';

  @override
  String get shortcutListRemove => 'Markér linje til fjernelse';

  @override
  String get shortcutListUndelete => 'Fjern sletningsmarkering';

  @override
  String get shortcutDateToday => 'I dag';

  @override
  String get shortcutDateAdd => 'Læg sekund/minut/time/dag/uge/måned/år til';

  @override
  String get shortcutDateSubtract =>
      'Træk sekund/minut/time/dag/uge/måned/år fra';

  @override
  String get keyDelete => 'Delete';

  @override
  String get keyInsert => 'Insert';

  @override
  String get ctxCopy => 'Kopiér';

  @override
  String get ctxCopyRow => 'Kopiér række';

  @override
  String get ctxCopyRows => 'Kopiér rækker';

  @override
  String get ctxCopyColumn => 'Kopiér kolonne';

  @override
  String get ctxPasteRows => 'Indsæt rækker';

  @override
  String get ctxEdit => 'Redigér …';

  @override
  String get ctxPrint => 'Udskriv …';

  @override
  String get x2mCreate => 'Opret en ny post';

  @override
  String get x2mEdit => 'Redigér valgte post';

  @override
  String get x2mDelete => 'Slet valgte post';

  @override
  String get x2mAdd => 'Tilføj eksisterende post';

  @override
  String get x2mRemove => 'Fjern valgte post';

  @override
  String get x2mUndelete => 'Gendan valgte post';

  @override
  String get x2mRestore => 'Gendan valgte post';

  @override
  String get x2mSwitch => 'Skift';

  @override
  String get x2mPrevious => 'Forrige';

  @override
  String get x2mNext => 'Næste';

  @override
  String get x2mMore => 'Mere';

  @override
  String get reportBug => 'Rapportér fejl';

  @override
  String get selectionTitle => 'Valg';

  @override
  String get yourSelection => 'Dit valg:';

  @override
  String emailTitle(Object name) {
    return 'E-mail $name';
  }

  @override
  String get emailTo => 'Til';

  @override
  String get emailCc => 'Cc';

  @override
  String get emailBcc => 'Bcc';

  @override
  String get emailSubject => 'Emne';

  @override
  String get emailBody => 'Tekst';

  @override
  String get emailReports => 'Rapporter';

  @override
  String get emailAttachments => 'Vedhæftninger';

  @override
  String get emailFiles => 'Filer';

  @override
  String get emailAddFile => 'Vælg fil';

  @override
  String get emailRemoveFile => 'Fjern fil';

  @override
  String get emailSend => 'Send';

  @override
  String get emailTemplate => 'Skabelon';

  @override
  String get emailSent => 'E-mail sendt.';

  @override
  String get attachmentPreview => 'Forhåndsvisning af vedhæftning';

  @override
  String get noAttachment => 'Ingen vedhæftning.';

  @override
  String get profile => 'Profil';

  @override
  String get editProfiles => 'Rediger profiler…';

  @override
  String get profiles => 'Profiler';

  @override
  String get profileName => 'Profilnavn';

  @override
  String get newProfile => 'Ny profil';

  @override
  String get deleteProfile => 'Slet profil';

  @override
  String get renameProfile => 'Omdøb';

  @override
  String get profileNameTaken => 'Dette profilnavn er allerede i brug.';

  @override
  String get incompatibleServer => 'Inkompatibel serverversion.';

  @override
  String get couldNotConnect => 'Kunne ikke forbinde til serveren.';

  @override
  String get copyUrl => 'Kopiér URL';

  @override
  String get urlCopied => 'URL kopieret.';

  @override
  String get openTrytonUrl => 'Åbn Tryton-URL';

  @override
  String urlOtherProfile(Object target, Object profile) {
    return 'URL\'en hører til $target. Log ind med profilen \"$profile\"?';
  }

  @override
  String urlNoProfile(Object target) {
    return 'URL\'en hører til $target; der findes ingen profil til den.';
  }

  @override
  String get chat => 'Chat';

  @override
  String get chatInternal => 'Gør dette til en intern besked';

  @override
  String get chatInternalTag => 'intern';

  @override
  String get chatFollowers => 'Vis følgere';

  @override
  String get chatSubscribe => 'Abonnér';

  @override
  String get chatUnsubscribe => 'Afmeld';

  @override
  String get chatAddFollower => 'Tilføj en følger';

  @override
  String chatUnsubscribeQuestion(Object name) {
    return 'Er du sikker på at afmelde \"$name\" fra denne kanal?';
  }

  @override
  String get chatEmpty => 'Ingen beskeder endnu.';

  @override
  String get calendarToday => 'I dag';

  @override
  String get calendarMonth => 'Måned';

  @override
  String get calendarWeek => 'Uge';

  @override
  String get calendarDay => 'Dag';

  @override
  String get scanCode => 'Scan';

  @override
  String get codeScanner => 'Kodescanner';

  @override
  String get scanCodeHint => 'Kode';

  @override
  String get scanCodeSound => 'Lyd';

  @override
  String get scanCodeCamera => 'Kamera';

  @override
  String get scanCodeNoCamera =>
      'Intet kamera tilgængeligt – indtast koden eller scan den med en håndscanner.';

  @override
  String get allTabs => 'Alle faner';

  @override
  String get connectionSecure => 'Krypteret forbindelse (HTTPS)';

  @override
  String get connectionInsecure =>
      'Ukrypteret forbindelse (HTTP) – adgangskoden sendes i klartekst';

  @override
  String get documentation => 'Dokumentation…';

  @override
  String get aboutMenu => 'Om…';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutBasedOn =>
      'Baseret på Tryton-desktopklienten og SAO – Copyright (C) 2004-2026 Tryton';

  @override
  String get aboutProjectPage => 'Projektside';

  @override
  String get aboutCredits => 'Medvirkende';

  @override
  String get aboutLicense => 'Licens';

  @override
  String get aboutCopyright => 'Ophavsret';

  @override
  String get aboutThirdParty => 'Tredjepartslicenser';

  @override
  String get aboutAuthors => 'Forfattere af denne klient';

  @override
  String get aboutOriginalAuthors => 'Forfattere af Tryton-klienten (original)';

  @override
  String get aboutTranslations => 'Oversættelser';

  @override
  String get aboutNoWarranty =>
      'Dette program leveres uden nogen form for garanti.';

  @override
  String aboutSeeLicense(String license) {
    return 'Se $license for detaljer.';
  }

  @override
  String get aboutGplName =>
      'GNU General Public License, version 3 eller senere';

  @override
  String get appDevelopment => 'udvikling';

  @override
  String get appPrerelease => 'Testversion';

  @override
  String get loginFailed => 'Forkert brugernavn eller adgangskode.';

  @override
  String get tooManyRequests => 'For mange forespørgsler. Prøv igen senere.';

  @override
  String get databaseNotFound => 'Databasen blev ikke fundet.';

  @override
  String get serverForbidden => 'Serveren tillader ikke dette.';

  @override
  String get resetPassword => 'Nulstil glemt adgangskode';

  @override
  String get resetPasswordTooltip =>
      'Send dig en e-mail for at nulstille din adgangskode.';

  @override
  String get resetPasswordSent =>
      'En anmodning om at nulstille din adgangskode er sendt.\nTjek venligst din indbakke.';

  @override
  String get resetPasswordNeedsUser =>
      'Angiv først server, database og brugernavn.';

  @override
  String get openReport => 'Åbn rapport';

  @override
  String get printReport => 'Udskriv rapport';

  @override
  String get aboutTranslationsTryton =>
      'Mange tekster fra Tryton-projektets oversættelser';
}
