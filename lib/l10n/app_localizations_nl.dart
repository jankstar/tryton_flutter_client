// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get appTitle => 'Tryton Flutter Client';

  @override
  String get appSubtitle => 'Tryton ERP-client';

  @override
  String get username => 'Gebruikersnaam';

  @override
  String get password => 'Wachtwoord';

  @override
  String get database => 'Database';

  @override
  String get serverUrl => 'Server-URL';

  @override
  String get required => 'Verplicht';

  @override
  String get signIn => 'Inloggen';

  @override
  String get signOut => 'Uitloggen';

  @override
  String get loadDatabases => 'Databases laden';

  @override
  String get additionalInputRequired => 'Aanvullende invoer vereist';

  @override
  String get reloadMenu => 'Menu herladen';

  @override
  String get noMenuEntriesFound => 'Geen menu-items gevonden.';

  @override
  String get retry => 'Opnieuw proberen';

  @override
  String get error => 'Fout';

  @override
  String get search => 'Zoeken…';

  @override
  String selected(int count) {
    return '$count geselecteerd';
  }

  @override
  String get deleteRecords => 'Records verwijderen';

  @override
  String reallyDeleteRecords(int count) {
    return '$count record(s) verwijderen?';
  }

  @override
  String get noRecordsFound => 'Geen records gevonden.';

  @override
  String get createNew => 'Nieuw aanmaken';

  @override
  String get attachments => 'Bijlagen';

  @override
  String get duplicate => 'Dupliceren';

  @override
  String get openEdit => 'Openen / Bewerken';

  @override
  String get reload => 'Herladen';

  @override
  String get delete => 'Verwijderen';

  @override
  String get moreActions => 'Meer acties';

  @override
  String get launchActions => 'Acties starten';

  @override
  String get relatedRecords => 'Gerelateerde records';

  @override
  String get reports => 'Rapporten';

  @override
  String get email => 'E-mail';

  @override
  String get save => 'Opslaan';

  @override
  String get cancel => 'Annuleren';

  @override
  String get recordCreated => 'Record aangemaakt.';

  @override
  String get saved => 'Opgeslagen.';

  @override
  String get deleteRecord => 'Record verwijderen';

  @override
  String get reallyDelete =>
      'Verwijderen? Dit kan niet ongedaan worden gemaakt.';

  @override
  String get add => 'Toevoegen';

  @override
  String get noEntries => 'Geen vermeldingen.';

  @override
  String get apply => 'Toepassen';

  @override
  String get openRecord => 'Record openen';

  @override
  String get clearField => 'Veld wissen';

  @override
  String get searchRecord => 'Record zoeken';

  @override
  String entries(int count) {
    return '$count vermeldingen';
  }

  @override
  String get generatingReport => 'Rapport wordt gegenereerd…';

  @override
  String reportGenerated(String name, String format) {
    return 'Rapport \"$name\" ($format) gegenereerd.';
  }

  @override
  String actionNotSupported(String name, String type) {
    return '\"$name\" ($type) wordt nog niet ondersteund.';
  }

  @override
  String executingButton(String name) {
    return 'Knop \"$name\" wordt uitgevoerd…';
  }

  @override
  String get language => 'Taal';

  @override
  String get sessionExpired => 'Sessie verlopen';

  @override
  String get preferences => 'Voorkeuren';

  @override
  String get help => 'Help';

  @override
  String get collapse => 'Inklappen';

  @override
  String get expand => 'Uitklappen';

  @override
  String get openInForm => 'Openen in formulier';

  @override
  String get undelete => 'Wissen ongedaan maken';

  @override
  String get switchToForm => 'Naar formulier schakelen';

  @override
  String get switchView => 'Weergave wisselen';

  @override
  String get close => 'Sluiten';

  @override
  String get boolYes => 'Ja';

  @override
  String get boolNo => 'Nee';

  @override
  String get clearSearch => 'Wissen';

  @override
  String get previousRecord => 'Vorige';

  @override
  String get nextRecord => 'Volgende';

  @override
  String get viewLogs => 'Logboeken bekijken';

  @override
  String get note => 'Aantekening';

  @override
  String get wizard => 'Wizard';

  @override
  String versionMismatch(String server, String client) {
    return 'Onjuiste versie van de server. Server $server, client $client.';
  }

  @override
  String get recordModified => 'Dit record is gewijzigd.\nWilt u het opslaan?';

  @override
  String get yes => 'Ja';

  @override
  String get no => 'Nee';

  @override
  String get concurrencyWarning => 'Waarschuwing gelijktijdige toegang';

  @override
  String get concurrencyMessage =>
      'Dit record is gewijzigd terwijl u het bewerkte.\nKies:\n• \"Annuleren\" om het opslaan te annuleren;\n• \"Vergelijken\" om de gewijzigde versie te zien;\n• \"Toch schrijven\" om uw huidige versie op te slaan.';

  @override
  String get compare => 'Vergelijken';

  @override
  String get writeAnyway => 'Toch schrijven';

  @override
  String get concurrencyException => 'Fout door gelijktijdige toegang';

  @override
  String compareTabTitle(String name) {
    return 'Vergelijken: $name';
  }

  @override
  String get fieldNotSupported => 'Nog niet ondersteund';

  @override
  String get ok => 'OK';

  @override
  String get alwaysIgnore => 'Altijd negeren';

  @override
  String get applicationError => 'Toepassingsfout';

  @override
  String get details => 'Details';

  @override
  String httpError(int code, String text) {
    return 'Fout: \"[$code] $text\". Probeer het later opnieuw.';
  }

  @override
  String networkError(String details) {
    return 'Server niet bereikbaar. $details';
  }

  @override
  String invalidRequired(String field) {
    return '\"$field\" is verplicht.';
  }

  @override
  String invalidDomain(String field) {
    return '\"$field\" is niet geldig volgens het domein.';
  }

  @override
  String invalidChildren(String field) {
    return 'De waarden van \"$field\" zijn niet geldig.';
  }

  @override
  String get invalidRecordTitle => 'Record niet geldig';

  @override
  String get selectAction => 'Kies uw actie';

  @override
  String get noActionDefined => 'Geen actie gedefinieerd.';

  @override
  String get preValidation => 'Voorafgaande validatie';

  @override
  String buttonClickedBy(String users) {
    return 'Door: $users';
  }

  @override
  String get discardChanges => 'Wijzigingen verwerpen';

  @override
  String get saveAndNew => 'Opslaan en nieuw';

  @override
  String get addAndNew => 'Toevoegen en nieuw';

  @override
  String get applyChanges => 'Wijzigingen toepassen';

  @override
  String get find => 'Zoeken';

  @override
  String get remove => 'Verwijderen';

  @override
  String get searchMenu => 'Zoeken…';

  @override
  String get createMenu => 'Aanmaken…';

  @override
  String searchTitle(String title) {
    return '$title zoeken';
  }

  @override
  String createNamed(String name) {
    return '\"$name\" aanmaken…';
  }

  @override
  String get revisions => 'Revisies…';

  @override
  String get currentRevision => 'Huidig';

  @override
  String get selectRevision => 'Kies een revisie';

  @override
  String get filters => 'Filters';

  @override
  String get bookmarkFilter => 'Filter als bladwijzer opslaan';

  @override
  String get removeBookmark => 'Bladwijzer verwijderen';

  @override
  String get bookmarks => 'Bladwijzers';

  @override
  String get bookmarkName => 'Naam van de bladwijzer:';

  @override
  String get showInactive => 'Inactieve records tonen';

  @override
  String get showActive => 'Actieve records tonen';

  @override
  String get fieldId => 'ID';

  @override
  String get createdBy => 'Aangemaakt door';

  @override
  String get createdAt => 'Aangemaakt op';

  @override
  String get modifiedBy => 'Gewijzigd door';

  @override
  String get modifiedAt => 'Gewijzigd op';

  @override
  String get rangeFrom => 'Van';

  @override
  String get rangeTo => 'Tot';

  @override
  String get favorites => 'Favorieten';

  @override
  String get addToFavorites => 'Aan favorieten toevoegen';

  @override
  String get removeFromFavorites => 'Uit favorieten verwijderen';

  @override
  String get noFavorites => 'Vink menu-items aan om favorieten toe te voegen';

  @override
  String get globalSearch => 'Globaal zoeken';

  @override
  String get selectMenuEntry => 'Kies een menu-item';

  @override
  String get selectColor => 'Kies een kleur';

  @override
  String get addValue => 'Waarde toevoegen';

  @override
  String get translate => 'Vertalen';

  @override
  String get saveBeforeTranslate =>
      'U moet het record opslaan voordat u vertalingen toevoegt.';

  @override
  String get noOtherLanguage => 'Geen andere taal beschikbaar.';

  @override
  String get edit => 'Bewerken';

  @override
  String get fuzzy => 'Onzeker';

  @override
  String get columns => 'Kolommen';

  @override
  String get resetColumnWidths => 'Kolombreedtes herstellen';

  @override
  String get copySelectedRows => 'Geselecteerde rijen kopiëren';

  @override
  String get notifications => 'Meldingen';

  @override
  String get noNotifications => 'Momenteel geen meldingen';

  @override
  String get allNotifications => 'Alle meldingen…';

  @override
  String get closeAllTabsQuestion =>
      'Voor deze actie moeten alle tabbladen worden gesloten.\nWilt u doorgaan?';

  @override
  String get editUserPreferences => 'Gebruikersvoorkeuren bewerken';

  @override
  String get saveAs => 'Opslaan als…';

  @override
  String get selectFile => 'Selecteren…';

  @override
  String get clear => 'Wissen';

  @override
  String get openFile => 'Openen…';

  @override
  String attachmentsOf(Object name) {
    return 'Bijlagen ($name)';
  }

  @override
  String notesOf(Object name) {
    return 'Notities ($name)';
  }

  @override
  String logsOf(Object name) {
    return 'Logboeken ($name)';
  }

  @override
  String attachmentCount(Object count) {
    return 'Bijlage ($count)';
  }

  @override
  String get addFiles => 'Toevoegen…';

  @override
  String get manage => 'Beheren…';

  @override
  String get logModel => 'Model';

  @override
  String get logModule => 'Module';

  @override
  String get logXmlId => 'XML-ID';

  @override
  String get logCreatedBy => 'Aangemaakt door';

  @override
  String get logCreatedAt => 'Aangemaakt op';

  @override
  String get logModifiedBy => 'Laatst gewijzigd door';

  @override
  String get logModifiedAt => 'Laatst gewijzigd op';

  @override
  String get exportData => 'Gegevens exporteren…';

  @override
  String get importData => 'Gegevens importeren…';

  @override
  String csvExportTitle(Object name) {
    return 'CSV-export: $name';
  }

  @override
  String csvImportTitle(Object name) {
    return 'CSV-import: $name';
  }

  @override
  String get csvAllFields => 'Alle velden';

  @override
  String get csvFieldsSelected => 'Geselecteerde velden';

  @override
  String get csvRemoveAll => 'Wissen';

  @override
  String get csvParameters => 'CSV-parameters';

  @override
  String get csvDelimiter => 'Scheidingsteken';

  @override
  String get csvQuoteChar => 'Aanhalingsteken';

  @override
  String get csvEncoding => 'Codering';

  @override
  String get csvLocaleFormat => 'Lokaal formaat gebruiken';

  @override
  String get csvAddFieldNames => 'Veldnamen toevoegen';

  @override
  String get csvListedRecords => 'Getoonde records';

  @override
  String get csvSelectedRecords => 'Geselecteerde records';

  @override
  String get csvIgnoreSearchLimit => 'Zoeklimiet negeren';

  @override
  String get csvPredefinedExports => 'Voorgedefinieerde exports';

  @override
  String get csvSaveExport => 'Export opslaan';

  @override
  String get csvDeleteExport => 'Export verwijderen';

  @override
  String get csvExportName => 'Wat is de naam van deze export?';

  @override
  String csvOverrideExport(Object name) {
    return 'Definitie van \'$name\' overschrijven?';
  }

  @override
  String csvRecordsSaved(Object count) {
    return 'Opgeslagen records: $count';
  }

  @override
  String get csvExportFailed => 'Export mislukt';

  @override
  String get csvFileToImport => 'Te importeren bestand';

  @override
  String get csvLinesToSkip => 'Over te slaan regels';

  @override
  String get csvAutoDetect => 'Automatisch herkennen';

  @override
  String get csvImport => 'Importeren';

  @override
  String get csvSelectImportFile => 'Selecteer eerst een importbestand.';

  @override
  String csvUnknownHeader(Object name) {
    return 'Onbekende kolomkop \"$name\"';
  }

  @override
  String get csvDetectionFailed => 'Herkenning mislukt';

  @override
  String csvRecordsImported(Object count) {
    return 'Geïmporteerde records: $count';
  }

  @override
  String get csvImportFailed => 'Import mislukt';

  @override
  String csvFieldString(Object name) {
    return '$name (tekst)';
  }

  @override
  String csvFieldModelName(Object name) {
    return '$name (modelnaam)';
  }

  @override
  String csvFieldRecordName(Object name) {
    return '$name/Recordnaam';
  }

  @override
  String get open => 'Openen';

  @override
  String get recordMenu => 'Recordmenu';

  @override
  String get menuSwitchView => 'Andere weergave';

  @override
  String get menuPrevious => 'Vorige';

  @override
  String get menuNext => 'Volgende';

  @override
  String get menuSearch => 'Zoeken';

  @override
  String get menuNew => 'Nieuw';

  @override
  String get menuSave => 'Opslaan';

  @override
  String get menuReload => 'Herladen/Ongedaan maken';

  @override
  String get menuDuplicate => 'Dupliceren';

  @override
  String get menuDelete => 'Verwijderen…';

  @override
  String get menuLogs => 'Logboek bekijken…';

  @override
  String get menuRevisions => 'Revisies tonen…';

  @override
  String get menuAttachments => 'Bijlagen…';

  @override
  String get menuNotes => 'Notities…';

  @override
  String get menuActions => 'Acties…';

  @override
  String get menuRelate => 'Gerelateerd…';

  @override
  String get menuReport => 'Rapport…';

  @override
  String get menuEmail => 'E-mail…';

  @override
  String get menuCloseTab => 'Tabblad sluiten';

  @override
  String get keyboardShortcuts => 'Sneltoetsen';

  @override
  String get shortcutsGlobal => 'Algemeen';

  @override
  String get shortcutsForm => 'Formulier';

  @override
  String get shortcutsRelation => 'Relatievelden';

  @override
  String get shortcutsList => 'Lijstvelden';

  @override
  String get shortcutsDate => 'Datumvelden';

  @override
  String get shortcutSearchMenu => 'Menu doorzoeken';

  @override
  String get shortcutToggleMenu => 'Menu tonen/verbergen';

  @override
  String get shortcutPreviousTab => 'Vorig tabblad';

  @override
  String get shortcutNextTab => 'Volgend tabblad';

  @override
  String get shortcutQuit => 'Afsluiten';

  @override
  String get shortcutRelationNew => 'Nieuwe relatie aanmaken';

  @override
  String get shortcutRelationOpen => 'Relatie openen/zoeken';

  @override
  String get shortcutListSwitch => 'Andere weergave';

  @override
  String get shortcutListNew => 'Nieuwe regel aanmaken/kiezen';

  @override
  String get shortcutListOpen => 'Relatie openen';

  @override
  String get shortcutListDelete => 'Regel markeren voor verwijderen';

  @override
  String get shortcutListRemove => 'Regel markeren voor ontkoppelen';

  @override
  String get shortcutListUndelete => 'Verwijdermarkering opheffen';

  @override
  String get shortcutDateToday => 'Vandaag';

  @override
  String get shortcutDateAdd =>
      'Seconde/minuut/uur/dag/week/maand/jaar optellen';

  @override
  String get shortcutDateSubtract =>
      'Seconde/minuut/uur/dag/week/maand/jaar aftrekken';

  @override
  String get keyDelete => 'Delete';

  @override
  String get keyInsert => 'Insert';

  @override
  String get ctxCopy => 'Kopiëren';

  @override
  String get ctxCopyRow => 'Regel kopiëren';

  @override
  String get ctxCopyRows => 'Regels kopiëren';

  @override
  String get ctxCopyColumn => 'Kolom kopiëren';

  @override
  String get ctxPasteRows => 'Regels plakken';

  @override
  String get ctxEdit => 'Bewerken…';

  @override
  String get ctxPrint => 'Afdrukken…';

  @override
  String get x2mCreate => 'Nieuw record aanmaken';

  @override
  String get x2mEdit => 'Geselecteerd record bewerken';

  @override
  String get x2mDelete => 'Geselecteerd record verwijderen';

  @override
  String get x2mAdd => 'Bestaand record toevoegen';

  @override
  String get x2mRemove => 'Geselecteerd record ontkoppelen';

  @override
  String get x2mUndelete => 'Geselecteerd record herstellen';

  @override
  String get x2mRestore => 'Geselecteerd record terugzetten';

  @override
  String get x2mSwitch => 'Wisselen';

  @override
  String get x2mPrevious => 'Vorige';

  @override
  String get x2mNext => 'Volgende';

  @override
  String get x2mMore => 'Meer';

  @override
  String get reportBug => 'Fout melden';

  @override
  String get selectionTitle => 'Selectie';

  @override
  String get yourSelection => 'Uw selectie:';

  @override
  String emailTitle(Object name) {
    return 'E-mail $name';
  }

  @override
  String get emailTo => 'Aan';

  @override
  String get emailCc => 'Cc';

  @override
  String get emailBcc => 'Bcc';

  @override
  String get emailSubject => 'Onderwerp';

  @override
  String get emailBody => 'Inhoud';

  @override
  String get emailReports => 'Rapporten';

  @override
  String get emailAttachments => 'Bijlagen';

  @override
  String get emailFiles => 'Bestanden';

  @override
  String get emailAddFile => 'Bestand selecteren';

  @override
  String get emailRemoveFile => 'Bestand verwijderen';

  @override
  String get emailSend => 'Verzenden';

  @override
  String get emailTemplate => 'Sjabloon';

  @override
  String get emailSent => 'E-mail verzonden.';

  @override
  String get attachmentPreview => 'Voorbeeld van bijlage';

  @override
  String get noAttachment => 'Geen bijlage.';

  @override
  String get profile => 'Profiel';

  @override
  String get editProfiles => 'Profielen bewerken…';

  @override
  String get profiles => 'Profielen';

  @override
  String get profileName => 'Profielnaam';

  @override
  String get newProfile => 'Nieuw profiel';

  @override
  String get deleteProfile => 'Profiel verwijderen';

  @override
  String get renameProfile => 'Hernoemen';

  @override
  String get profileNameTaken => 'Deze profielnaam wordt al gebruikt.';

  @override
  String get incompatibleServer => 'Incompatibele serverversie.';

  @override
  String get couldNotConnect => 'Kan geen verbinding maken met de server.';

  @override
  String get copyUrl => 'URL kopiëren';

  @override
  String get urlCopied => 'URL gekopieerd.';

  @override
  String get openTrytonUrl => 'Tryton-URL openen';

  @override
  String urlOtherProfile(Object target, Object profile) {
    return 'De URL hoort bij $target. Aanmelden met profiel \"$profile\"?';
  }

  @override
  String urlNoProfile(Object target) {
    return 'De URL hoort bij $target; daar is geen profiel voor.';
  }

  @override
  String get chat => 'Chat';

  @override
  String get chatInternal => 'Maak dit een intern bericht';

  @override
  String get chatInternalTag => 'intern';

  @override
  String get chatFollowers => 'Volgers tonen';

  @override
  String get chatSubscribe => 'Abonneren';

  @override
  String get chatUnsubscribe => 'Afmelden';

  @override
  String get chatAddFollower => 'Volger toevoegen';

  @override
  String chatUnsubscribeQuestion(Object name) {
    return 'Weet u zeker dat u \"$name\" van dit kanaal wilt afmelden?';
  }

  @override
  String get chatEmpty => 'Nog geen berichten.';

  @override
  String get calendarToday => 'Vandaag';

  @override
  String get calendarMonth => 'Maand';

  @override
  String get calendarWeek => 'Week';

  @override
  String get calendarDay => 'Dag';

  @override
  String get scanCode => 'Scannen';

  @override
  String get codeScanner => 'Codescanner';

  @override
  String get scanCodeHint => 'Code';

  @override
  String get scanCodeSound => 'Geluid';

  @override
  String get scanCodeCamera => 'Camera';

  @override
  String get scanCodeNoCamera =>
      'Geen camera beschikbaar – voer de code in of scan hem met een handscanner.';

  @override
  String get allTabs => 'Alle tabbladen';

  @override
  String get connectionSecure => 'Versleutelde verbinding (HTTPS)';

  @override
  String get connectionInsecure =>
      'Onversleutelde verbinding (HTTP) – het wachtwoord wordt onversleuteld verzonden';

  @override
  String get documentation => 'Documentatie…';

  @override
  String get aboutMenu => 'Over…';

  @override
  String get aboutVersion => 'Versie';

  @override
  String get aboutBasedOn =>
      'Gebaseerd op de Tryton-desktopclient en SAO – Copyright (C) 2004-2026 Tryton';

  @override
  String get aboutProjectPage => 'Projectpagina';

  @override
  String get aboutCredits => 'Credits';

  @override
  String get aboutLicense => 'Licentie';

  @override
  String get aboutCopyright => 'Copyright';

  @override
  String get aboutThirdParty => 'Licenties van derden';

  @override
  String get aboutAuthors => 'Auteurs van deze client';

  @override
  String get aboutOriginalAuthors => 'Auteurs van de Tryton-client (origineel)';

  @override
  String get aboutTranslations => 'Vertalingen';

  @override
  String get aboutNoWarranty =>
      'Dit programma wordt geleverd zonder enige garantie.';

  @override
  String aboutSeeLicense(String license) {
    return 'Zie de $license voor details.';
  }

  @override
  String get aboutGplName => 'GNU General Public License, versie 3 of later';

  @override
  String get appDevelopment => 'ontwikkeling';

  @override
  String get appPrerelease => 'Testversie';

  @override
  String get loginFailed => 'Onjuiste gebruikersnaam of wachtwoord.';

  @override
  String get tooManyRequests =>
      'Te veel verzoeken. Probeer het later nog eens.';

  @override
  String get databaseNotFound => 'Database niet gevonden.';

  @override
  String get serverForbidden => 'De server staat dit niet toe.';

  @override
  String get resetPassword => 'Reset vergeten wachtwoord';

  @override
  String get resetPasswordTooltip =>
      'Stuurt u een email om het wachtwoord te resetten.';

  @override
  String get resetPasswordSent =>
      'Een verzoek om uw wachtwoord te resetten is verzonden.\nControleer uw mailbox.';

  @override
  String get resetPasswordNeedsUser =>
      'Vul eerst server, database en gebruikersnaam in.';

  @override
  String get openReport => 'Open rapport';

  @override
  String get printReport => 'Rapport afdrukken';
}
