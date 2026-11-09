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
  String get selectMenuEntry => 'Valitse valikon kohta';

  @override
  String get selectColor => 'Valitse väri';

  @override
  String get addValue => 'Lisää arvo';

  @override
  String get translate => 'Käännä';

  @override
  String get saveBeforeTranslate =>
      'Tietue on tallennettava ennen käännösten lisäämistä.';

  @override
  String get noOtherLanguage => 'Muita kieliä ei ole saatavilla.';

  @override
  String get edit => 'Muokkaa';

  @override
  String get fuzzy => 'Epätarkka';

  @override
  String get columns => 'Sarakkeet';

  @override
  String get resetColumnWidths => 'Palauta sarakeleveydet';

  @override
  String get copySelectedRows => 'Kopioi valitut rivit';

  @override
  String get notifications => 'Ilmoitukset';

  @override
  String get noNotifications => 'Ei ilmoituksia tällä hetkellä';

  @override
  String get allNotifications => 'Kaikki ilmoitukset…';

  @override
  String get closeAllTabsQuestion =>
      'Toiminto vaatii kaikkien välilehtien sulkemisen.\nHaluatko jatkaa?';

  @override
  String get editUserPreferences => 'Muokkaa käyttäjän asetuksia';

  @override
  String get saveAs => 'Tallenna nimellä…';

  @override
  String get selectFile => 'Valitse…';

  @override
  String get clear => 'Tyhjennä';

  @override
  String get openFile => 'Avaa…';

  @override
  String attachmentsOf(Object name) {
    return 'Liitteet ($name)';
  }

  @override
  String notesOf(Object name) {
    return 'Muistiinpanot ($name)';
  }

  @override
  String logsOf(Object name) {
    return 'Lokit ($name)';
  }

  @override
  String attachmentCount(Object count) {
    return 'Liite ($count)';
  }

  @override
  String get addFiles => 'Lisää…';

  @override
  String get manage => 'Hallitse…';

  @override
  String get logModel => 'Malli';

  @override
  String get logModule => 'Moduuli';

  @override
  String get logXmlId => 'XML-tunnus';

  @override
  String get logCreatedBy => 'Luonut';

  @override
  String get logCreatedAt => 'Luotu';

  @override
  String get logModifiedBy => 'Viimeksi muokannut';

  @override
  String get logModifiedAt => 'Viimeksi muokattu';

  @override
  String get exportData => 'Vie tiedot…';

  @override
  String get importData => 'Tuo tiedot…';

  @override
  String csvExportTitle(Object name) {
    return 'CSV-vienti: $name';
  }

  @override
  String csvImportTitle(Object name) {
    return 'CSV-tuonti: $name';
  }

  @override
  String get csvAllFields => 'Kaikki kentät';

  @override
  String get csvFieldsSelected => 'Valitut kentät';

  @override
  String get csvRemoveAll => 'Tyhjennä';

  @override
  String get csvParameters => 'CSV-parametrit';

  @override
  String get csvDelimiter => 'Erotin';

  @override
  String get csvQuoteChar => 'Lainausmerkki';

  @override
  String get csvEncoding => 'Merkistö';

  @override
  String get csvLocaleFormat => 'Käytä paikallista muotoa';

  @override
  String get csvAddFieldNames => 'Lisää kenttien nimet';

  @override
  String get csvListedRecords => 'Luetellut tietueet';

  @override
  String get csvSelectedRecords => 'Valitut tietueet';

  @override
  String get csvIgnoreSearchLimit => 'Ohita hakuraja';

  @override
  String get csvPredefinedExports => 'Valmiit viennit';

  @override
  String get csvSaveExport => 'Tallenna vienti';

  @override
  String get csvDeleteExport => 'Poista vienti';

  @override
  String get csvExportName => 'Mikä on tämän viennin nimi?';

  @override
  String csvOverrideExport(Object name) {
    return 'Korvataanko määritys \'$name\'?';
  }

  @override
  String csvRecordsSaved(Object count) {
    return 'Tallennetut tietueet: $count';
  }

  @override
  String get csvExportFailed => 'Vienti epäonnistui';

  @override
  String get csvFileToImport => 'Tuotava tiedosto';

  @override
  String get csvLinesToSkip => 'Ohitettavat rivit';

  @override
  String get csvAutoDetect => 'Tunnista automaattisesti';

  @override
  String get csvImport => 'Tuo';

  @override
  String get csvSelectImportFile => 'Valitse ensin tuontitiedosto.';

  @override
  String csvUnknownHeader(Object name) {
    return 'Tuntematon sarakeotsikko \"$name\"';
  }

  @override
  String get csvDetectionFailed => 'Tunnistus epäonnistui';

  @override
  String csvRecordsImported(Object count) {
    return 'Tuodut tietueet: $count';
  }

  @override
  String get csvImportFailed => 'Tuonti epäonnistui';

  @override
  String csvFieldString(Object name) {
    return '$name (teksti)';
  }

  @override
  String csvFieldModelName(Object name) {
    return '$name (mallin nimi)';
  }

  @override
  String csvFieldRecordName(Object name) {
    return '$name/Tietueen nimi';
  }

  @override
  String get open => 'Avaa';

  @override
  String get recordMenu => 'Tietuevalikko';

  @override
  String get menuSwitchView => 'Vaihda näkymää';

  @override
  String get menuPrevious => 'Edellinen';

  @override
  String get menuNext => 'Seuraava';

  @override
  String get menuSearch => 'Hae';

  @override
  String get menuNew => 'Uusi';

  @override
  String get menuSave => 'Tallenna';

  @override
  String get menuReload => 'Lataa uudelleen/Kumoa';

  @override
  String get menuDuplicate => 'Monista';

  @override
  String get menuDelete => 'Poista…';

  @override
  String get menuLogs => 'Näytä lokit…';

  @override
  String get menuRevisions => 'Näytä versiot…';

  @override
  String get menuAttachments => 'Liitteet…';

  @override
  String get menuNotes => 'Muistiinpanot…';

  @override
  String get menuActions => 'Toiminnot…';

  @override
  String get menuRelate => 'Liittyvät…';

  @override
  String get menuReport => 'Raportti…';

  @override
  String get menuEmail => 'Sähköposti…';

  @override
  String get menuCloseTab => 'Sulje välilehti';

  @override
  String get keyboardShortcuts => 'Pikanäppäimet';

  @override
  String get shortcutsGlobal => 'Yleiset';

  @override
  String get shortcutsForm => 'Lomake';

  @override
  String get shortcutsRelation => 'Viitekentät';

  @override
  String get shortcutsList => 'Luettelokentät';

  @override
  String get shortcutsDate => 'Päivämääräkentät';

  @override
  String get shortcutSearchMenu => 'Hae valikosta';

  @override
  String get shortcutToggleMenu => 'Näytä/piilota valikko';

  @override
  String get shortcutPreviousTab => 'Edellinen välilehti';

  @override
  String get shortcutNextTab => 'Seuraava välilehti';

  @override
  String get shortcutQuit => 'Lopeta';

  @override
  String get shortcutRelationNew => 'Luo uusi viite';

  @override
  String get shortcutRelationOpen => 'Avaa/hae viite';

  @override
  String get shortcutListSwitch => 'Vaihda näkymää';

  @override
  String get shortcutListNew => 'Luo/valitse uusi rivi';

  @override
  String get shortcutListOpen => 'Avaa viite';

  @override
  String get shortcutListDelete => 'Merkitse rivi poistettavaksi';

  @override
  String get shortcutListRemove => 'Merkitse rivi irrotettavaksi';

  @override
  String get shortcutListUndelete => 'Poista poistomerkintä';

  @override
  String get shortcutDateToday => 'Tänään';

  @override
  String get shortcutDateAdd =>
      'Lisää sekunti/minuutti/tunti/päivä/viikko/kuukausi/vuosi';

  @override
  String get shortcutDateSubtract =>
      'Vähennä sekunti/minuutti/tunti/päivä/viikko/kuukausi/vuosi';

  @override
  String get keyDelete => 'Delete';

  @override
  String get keyInsert => 'Insert';

  @override
  String get ctxCopy => 'Kopioi';

  @override
  String get ctxCopyRow => 'Kopioi rivi';

  @override
  String get ctxCopyRows => 'Kopioi rivit';

  @override
  String get ctxCopyColumn => 'Kopioi sarake';

  @override
  String get ctxPasteRows => 'Liitä rivit';

  @override
  String get ctxEdit => 'Muokkaa…';

  @override
  String get ctxPrint => 'Tulosta…';

  @override
  String get x2mCreate => 'Luo uusi tietue';

  @override
  String get x2mEdit => 'Muokkaa valittua tietuetta';

  @override
  String get x2mDelete => 'Poista valittu tietue';

  @override
  String get x2mAdd => 'Lisää olemassa oleva tietue';

  @override
  String get x2mRemove => 'Irrota valittu tietue';

  @override
  String get x2mUndelete => 'Palauta valittu tietue';

  @override
  String get x2mRestore => 'Palauta valittu tietue';

  @override
  String get x2mSwitch => 'Vaihda';

  @override
  String get x2mPrevious => 'Edellinen';

  @override
  String get x2mNext => 'Seuraava';

  @override
  String get x2mMore => 'Lisää';

  @override
  String get reportBug => 'Ilmoita virheestä';

  @override
  String get selectionTitle => 'Valinta';

  @override
  String get yourSelection => 'Valintasi:';

  @override
  String emailTitle(Object name) {
    return 'Sähköposti $name';
  }

  @override
  String get emailTo => 'Vastaanottaja';

  @override
  String get emailCc => 'Kopio';

  @override
  String get emailBcc => 'Piilokopio';

  @override
  String get emailSubject => 'Aihe';

  @override
  String get emailBody => 'Viesti';

  @override
  String get emailReports => 'Raportit';

  @override
  String get emailAttachments => 'Liitteet';

  @override
  String get emailFiles => 'Tiedostot';

  @override
  String get emailAddFile => 'Valitse tiedosto';

  @override
  String get emailRemoveFile => 'Poista tiedosto';

  @override
  String get emailSend => 'Lähetä';

  @override
  String get emailTemplate => 'Malli';

  @override
  String get emailSent => 'Sähköposti lähetetty.';

  @override
  String get attachmentPreview => 'Liitteen esikatselu';

  @override
  String get noAttachment => 'Ei liitettä.';

  @override
  String get profile => 'Profiili';

  @override
  String get editProfiles => 'Muokkaa profiileja…';

  @override
  String get profiles => 'Profiilit';

  @override
  String get profileName => 'Profiilin nimi';

  @override
  String get newProfile => 'Uusi profiili';

  @override
  String get deleteProfile => 'Poista profiili';

  @override
  String get renameProfile => 'Nimeä uudelleen';

  @override
  String get profileNameTaken => 'Tämä profiilin nimi on jo käytössä.';

  @override
  String get incompatibleServer => 'Palvelimen versio ei ole yhteensopiva.';

  @override
  String get couldNotConnect => 'Palvelimeen ei saatu yhteyttä.';

  @override
  String get copyUrl => 'Kopioi URL';

  @override
  String get urlCopied => 'URL kopioitu.';

  @override
  String get openTrytonUrl => 'Avaa Tryton-URL';

  @override
  String urlOtherProfile(Object target, Object profile) {
    return 'URL kuuluu kohteeseen $target. Kirjaudutaanko profiililla \"$profile\"?';
  }

  @override
  String urlNoProfile(Object target) {
    return 'URL kuuluu kohteeseen $target; sille ei ole profiilia.';
  }

  @override
  String get chat => 'Keskustelu';

  @override
  String get chatInternal => 'Tee tästä sisäinen viesti';

  @override
  String get chatInternalTag => 'sisäinen';

  @override
  String get chatFollowers => 'Näytä seuraajat';

  @override
  String get chatSubscribe => 'Tilaa';

  @override
  String get chatUnsubscribe => 'Peru tilaus';

  @override
  String get chatAddFollower => 'Lisää seuraaja';

  @override
  String chatUnsubscribeQuestion(Object name) {
    return 'Haluatko varmasti poistaa käyttäjän \"$name\" tältä kanavalta?';
  }

  @override
  String get chatEmpty => 'Ei vielä viestejä.';
}
