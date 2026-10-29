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
  String get switchView => 'Vaihda näkymää';

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

  @override
  String get concurrencyWarning => 'Samanaikaisuusvaroitus';

  @override
  String get concurrencyMessage =>
      'Tätä tietuetta on muutettu muokkauksesi aikana.\nValitse:\n• \"Peruuta\" peruuttaaksesi tallennuksen;\n• \"Vertaa\" nähdäksesi muutetun version;\n• \"Kirjoita silti\" tallentaaksesi nykyisen versiosi.';

  @override
  String get compare => 'Vertaa';

  @override
  String get writeAnyway => 'Kirjoita silti';

  @override
  String get concurrencyException => 'Samanaikaisuusvirhe';

  @override
  String compareTabTitle(String name) {
    return 'Vertaa: $name';
  }

  @override
  String get fieldNotSupported => 'Ei vielä tuettu';

  @override
  String get ok => 'OK';

  @override
  String get alwaysIgnore => 'Ohita aina';

  @override
  String get applicationError => 'Sovellusvirhe';

  @override
  String get details => 'Tiedot';

  @override
  String httpError(int code, String text) {
    return 'Virhe: \"[$code] $text\". Yritä myöhemmin uudelleen.';
  }

  @override
  String networkError(String details) {
    return 'Palvelimeen ei saada yhteyttä. $details';
  }

  @override
  String invalidRequired(String field) {
    return '\"$field\" on pakollinen.';
  }

  @override
  String invalidDomain(String field) {
    return '\"$field\" ei ole kelvollinen toimialueensa mukaan.';
  }

  @override
  String invalidChildren(String field) {
    return 'Kentän \"$field\" arvot eivät ole kelvollisia.';
  }

  @override
  String get invalidRecordTitle => 'Tietue ei ole kelvollinen';

  @override
  String get selectAction => 'Valitse toiminto';

  @override
  String get noActionDefined => 'Toimintoa ei ole määritetty.';

  @override
  String get preValidation => 'Esitarkistus';

  @override
  String buttonClickedBy(String users) {
    return 'Käyttäjät: $users';
  }

  @override
  String get discardChanges => 'Hylkää muutokset';

  @override
  String get saveAndNew => 'Tallenna ja uusi';

  @override
  String get addAndNew => 'Lisää ja uusi';

  @override
  String get applyChanges => 'Ota muutokset käyttöön';

  @override
  String get find => 'Etsi';

  @override
  String get remove => 'Poista';

  @override
  String get searchMenu => 'Etsi…';

  @override
  String get createMenu => 'Luo…';

  @override
  String searchTitle(String title) {
    return 'Etsi $title';
  }

  @override
  String createNamed(String name) {
    return 'Luo \"$name\"…';
  }

  @override
  String get revisions => 'Versiot…';

  @override
  String get currentRevision => 'Nykyinen';

  @override
  String get selectRevision => 'Valitse versio';

  @override
  String get filters => 'Suodattimet';

  @override
  String get bookmarkFilter => 'Lisää suodatin kirjanmerkkeihin';

  @override
  String get removeBookmark => 'Poista kirjanmerkki';

  @override
  String get bookmarks => 'Kirjanmerkit';

  @override
  String get bookmarkName => 'Kirjanmerkin nimi:';

  @override
  String get showInactive => 'Näytä passiiviset tietueet';

  @override
  String get showActive => 'Näytä aktiiviset tietueet';

  @override
  String get fieldId => 'ID';

  @override
  String get createdBy => 'Luonut';

  @override
  String get createdAt => 'Luotu';

  @override
  String get modifiedBy => 'Muokannut';

  @override
  String get modifiedAt => 'Muokattu';

  @override
  String get rangeFrom => 'Alkaen';

  @override
  String get rangeTo => 'Asti';

  @override
  String get favorites => 'Suosikit';

  @override
  String get addToFavorites => 'Lisää suosikkeihin';

  @override
  String get removeFromFavorites => 'Poista suosikeista';

  @override
  String get noFavorites => 'Merkitse valikon kohtia suosikeiksi';

  @override
  String get globalSearch => 'Yleinen haku';

  @override
  String get boardNotSupported => 'Koontinäyttöjä ei vielä tueta.';

  @override
  String get selectMenuEntry => 'Valitse valikon kohta';
}
