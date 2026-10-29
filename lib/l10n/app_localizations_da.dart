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
  String reallyDeleteRecords(int count) {
    return 'Slet $count post(er)?';
  }

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
  String get reallyDelete => 'Slet? Denne handling kan ikke fortrydes.';

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
    return 'Inkompatibel serverversion $server (klienten forventer $client).';
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
      'Denne post er blevet ændret, mens du redigerede den.\nVælg:\n• \"Annuller\" for at annullere gemningen;\n• \"Sammenlign\" for at se den ændrede version;\n• \"Skriv alligevel\" for at gemme din nuværende version.';

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
}
