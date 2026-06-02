// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Finnish (`fi`).
class AppLocalizationsFi extends AppLocalizations {
  AppLocalizationsFi([String locale = 'fi']) : super(locale);

  @override
  String get appTitle => 'Tryton Flutter Client';

  @override
  String get appSubtitle => 'Tryton ERP -asiakas';

  @override
  String get username => 'Käyttäjänimi';

  @override
  String get password => 'Salasana';

  @override
  String get database => 'Tietokanta';

  @override
  String get serverUrl => 'Palvelimen URL';

  @override
  String get required => 'Pakollinen';

  @override
  String get signIn => 'Kirjaudu sisään';

  @override
  String get signOut => 'Kirjaudu ulos';

  @override
  String get loadDatabases => 'Lataa tietokannat';

  @override
  String get additionalInputRequired => 'Lisäsyöte vaaditaan';

  @override
  String get reloadMenu => 'Lataa valikko uudelleen';

  @override
  String get noMenuEntriesFound => 'Valikkokohtia ei löydy.';

  @override
  String get retry => 'Yritä uudelleen';

  @override
  String get error => 'Virhe';

  @override
  String get search => 'Hae…';

  @override
  String selected(int count) {
    return '$count valittu';
  }

  @override
  String get deleteRecords => 'Poista tietueet';

  @override
  String reallyDeleteRecords(int count) {
    return 'Poistetaanko $count tietue(tta)?';
  }

  @override
  String get noRecordsFound => 'Tietueita ei löydy.';

  @override
  String get createNew => 'Luo uusi';

  @override
  String get attachments => 'Liitteet';

  @override
  String get duplicate => 'Kopioi';

  @override
  String get openEdit => 'Avaa / Muokkaa';

  @override
  String get reload => 'Lataa uudelleen';

  @override
  String get delete => 'Poista';

  @override
  String get moreActions => 'Lisää toimintoja';

  @override
  String get launchActions => 'Käynnistä toiminnot';

  @override
  String get relatedRecords => 'Liittyvät tietueet';

  @override
  String get reports => 'Raportit';

  @override
  String get email => 'Sähköposti';

  @override
  String get save => 'Tallenna';

  @override
  String get cancel => 'Peruuta';

  @override
  String get recordCreated => 'Tietue luotu.';

  @override
  String get saved => 'Tallennettu.';

  @override
  String get deleteRecord => 'Poista tietue';

  @override
  String get reallyDelete => 'Poistetaanko? Tätä toimintoa ei voi kumota.';

  @override
  String get add => 'Lisää';

  @override
  String get noEntries => 'Ei merkintöjä.';

  @override
  String get apply => 'Käytä';

  @override
  String get openRecord => 'Avaa tietue';

  @override
  String get clearField => 'Tyhjennä kenttä';

  @override
  String get searchRecord => 'Hae tietue';

  @override
  String entries(int count) {
    return '$count merkintää';
  }

  @override
  String get generatingReport => 'Luodaan raporttia…';

  @override
  String reportGenerated(String name, String format) {
    return 'Raportti \"$name\" ($format) luotu.';
  }

  @override
  String actionNotSupported(String name, String type) {
    return '\"$name\" ($type) ei ole vielä tuettu.';
  }

  @override
  String executingButton(String name) {
    return 'Suoritetaan painiketta \"$name\"…';
  }

  @override
  String get language => 'Kieli';

  @override
  String get sessionExpired => 'Istunto vanhentunut';

  @override
  String get preferences => 'Asetukset';

  @override
  String get help => 'Ohje';

  @override
  String get collapse => 'Tiivistä';

  @override
  String get expand => 'Laajenna';

  @override
  String get openInForm => 'Avaa lomakkeessa';

  @override
  String get undelete => 'Kumoa poisto';

  @override
  String get switchToForm => 'Vaihda lomakkeeseen';

  @override
  String get close => 'Sulje';

  @override
  String get boolYes => 'Kyllä';

  @override
  String get boolNo => 'Ei';

  @override
  String get clearSearch => 'Tyhjennä';

  @override
  String get previousRecord => 'Edellinen';

  @override
  String get nextRecord => 'Seuraava';

  @override
  String get viewLogs => 'Näytä lokit';

  @override
  String get note => 'Muistiinpano';

  @override
  String get wizard => 'Ohjattu toiminto';

  @override
  String versionMismatch(String server, String client) {
    return 'Yhteensopimaton palvelinversio $server (asiakas odottaa $client).';
  }

  @override
  String get recordModified =>
      'Tätä tietuetta on muutettu.\nHaluatko tallentaa sen?';

  @override
  String get yes => 'Kyllä';

  @override
  String get no => 'Ei';
}
