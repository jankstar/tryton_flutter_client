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
    return 'Incompatibele serverversie $server (client verwacht $client).';
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
  String get boardNotSupported => 'Dashboards worden nog niet ondersteund.';

  @override
  String get selectMenuEntry => 'Kies een menu-item';
}
