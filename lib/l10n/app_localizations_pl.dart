// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get appTitle => 'Tryton Flutter Client';

  @override
  String get appSubtitle => 'Klient ERP Tryton';

  @override
  String get username => 'Nazwa użytkownika';

  @override
  String get password => 'Hasło';

  @override
  String get database => 'Baza danych';

  @override
  String get serverUrl => 'Adres URL serwera';

  @override
  String get required => 'Wymagane';

  @override
  String get signIn => 'Zaloguj się';

  @override
  String get signOut => 'Wyloguj się';

  @override
  String get loadDatabases => 'Załaduj bazy danych';

  @override
  String get additionalInputRequired => 'Wymagane dodatkowe dane';

  @override
  String get reloadMenu => 'Odśwież menu';

  @override
  String get noMenuEntriesFound => 'Nie znaleziono pozycji menu.';

  @override
  String get retry => 'Spróbuj ponownie';

  @override
  String get error => 'Błąd';

  @override
  String get search => 'Szukaj…';

  @override
  String selected(int count) {
    return 'Wybrano: $count';
  }

  @override
  String get deleteRecords => 'Usuń rekordy';

  @override
  String reallyDeleteRecords(int count) {
    return 'Czy na pewno usunąć $count rekord(y)?';
  }

  @override
  String get noRecordsFound => 'Nie znaleziono rekordów.';

  @override
  String get createNew => 'Utwórz nowy';

  @override
  String get attachments => 'Załączniki';

  @override
  String get duplicate => 'Duplikuj';

  @override
  String get openEdit => 'Otwórz / Edytuj';

  @override
  String get reload => 'Odśwież';

  @override
  String get delete => 'Usuń';

  @override
  String get moreActions => 'Więcej akcji';

  @override
  String get launchActions => 'Uruchom akcje';

  @override
  String get relatedRecords => 'Powiązane rekordy';

  @override
  String get reports => 'Raporty';

  @override
  String get email => 'E-mail';

  @override
  String get save => 'Zapisz';

  @override
  String get cancel => 'Anuluj';

  @override
  String get recordCreated => 'Rekord został utworzony.';

  @override
  String get saved => 'Zapisano.';

  @override
  String get deleteRecord => 'Usuń rekord';

  @override
  String get reallyDelete =>
      'Czy na pewno usunąć? Tej operacji nie można cofnąć.';

  @override
  String get add => 'Dodaj';

  @override
  String get noEntries => 'Brak wpisów.';

  @override
  String get apply => 'Zastosuj';

  @override
  String get openRecord => 'Otwórz rekord';

  @override
  String get clearField => 'Wyczyść pole';

  @override
  String get searchRecord => 'Szukaj rekordu';

  @override
  String entries(int count) {
    return '$count wpis(y)';
  }

  @override
  String get generatingReport => 'Generowanie raportu…';

  @override
  String reportGenerated(String name, String format) {
    return 'Raport \"$name\" ($format) został wygenerowany.';
  }

  @override
  String actionNotSupported(String name, String type) {
    return '\"$name\" ($type) nie jest jeszcze obsługiwany.';
  }

  @override
  String executingButton(String name) {
    return 'Wykonywanie przycisku \"$name\"…';
  }

  @override
  String get language => 'Język';

  @override
  String get sessionExpired => 'Sesja wygasła';

  @override
  String get preferences => 'Preferencje';

  @override
  String get help => 'Pomoc';

  @override
  String get collapse => 'Zwiń';

  @override
  String get expand => 'Rozwiń';

  @override
  String get openInForm => 'Otwórz w formularzu';

  @override
  String get undelete => 'Przywróć';

  @override
  String get switchToForm => 'Przełącz na formularz';

  @override
  String get switchView => 'Przełącz widok';

  @override
  String get close => 'Zamknij';

  @override
  String get boolYes => 'Tak';

  @override
  String get boolNo => 'Nie';

  @override
  String get clearSearch => 'Wyczyść';

  @override
  String get previousRecord => 'Poprzedni';

  @override
  String get nextRecord => 'Następny';

  @override
  String get viewLogs => 'Pokaż dzienniki';

  @override
  String get note => 'Notatka';

  @override
  String get wizard => 'Kreator';

  @override
  String versionMismatch(String server, String client) {
    return 'Niekompatybilna wersja serwera $server (klient oczekuje $client).';
  }

  @override
  String get recordModified =>
      'Ten rekord został zmodyfikowany.\nCzy chcesz go zapisać?';

  @override
  String get yes => 'Tak';

  @override
  String get no => 'Nie';

  @override
  String get concurrencyWarning => 'Ostrzeżenie o współbieżności';

  @override
  String get concurrencyMessage =>
      'Ten rekord został zmieniony podczas jego edycji.\nWybierz:\n• „Anuluj”, aby anulować zapis;\n• „Porównaj”, aby zobaczyć zmienioną wersję;\n• „Zapisz mimo to”, aby zapisać bieżącą wersję.';

  @override
  String get compare => 'Porównaj';

  @override
  String get writeAnyway => 'Zapisz mimo to';

  @override
  String get concurrencyException => 'Wyjątek współbieżności';

  @override
  String compareTabTitle(String name) {
    return 'Porównaj: $name';
  }

  @override
  String get fieldNotSupported => 'Jeszcze nieobsługiwane';

  @override
  String get ok => 'OK';

  @override
  String get alwaysIgnore => 'Zawsze ignoruj';

  @override
  String get applicationError => 'Błąd aplikacji';

  @override
  String get details => 'Szczegóły';

  @override
  String httpError(int code, String text) {
    return 'Błąd: „[$code] $text”. Spróbuj ponownie później.';
  }

  @override
  String networkError(String details) {
    return 'Nie można połączyć się z serwerem. $details';
  }

  @override
  String invalidRequired(String field) {
    return '„$field” jest wymagane.';
  }

  @override
  String invalidDomain(String field) {
    return '„$field” jest nieprawidłowe według domeny.';
  }

  @override
  String invalidChildren(String field) {
    return 'Wartości „$field” są nieprawidłowe.';
  }

  @override
  String get invalidRecordTitle => 'Rekord nieprawidłowy';

  @override
  String get selectAction => 'Wybierz akcję';

  @override
  String get noActionDefined => 'Nie zdefiniowano akcji.';

  @override
  String get preValidation => 'Wstępna walidacja';

  @override
  String buttonClickedBy(String users) {
    return 'Przez: $users';
  }

  @override
  String get discardChanges => 'Odrzuć zmiany';

  @override
  String get saveAndNew => 'Zapisz i nowy';

  @override
  String get addAndNew => 'Dodaj i nowy';

  @override
  String get applyChanges => 'Zastosuj zmiany';

  @override
  String get find => 'Szukaj';

  @override
  String get remove => 'Usuń';

  @override
  String get searchMenu => 'Szukaj…';

  @override
  String get createMenu => 'Utwórz…';

  @override
  String searchTitle(String title) {
    return 'Szukaj: $title';
  }

  @override
  String createNamed(String name) {
    return 'Utwórz „$name”…';
  }

  @override
  String get revisions => 'Wersje…';

  @override
  String get currentRevision => 'Bieżąca';

  @override
  String get selectRevision => 'Wybierz wersję';

  @override
  String get filters => 'Filtry';

  @override
  String get bookmarkFilter => 'Dodaj filtr do zakładek';

  @override
  String get removeBookmark => 'Usuń zakładkę';

  @override
  String get bookmarks => 'Zakładki';

  @override
  String get bookmarkName => 'Nazwa zakładki:';

  @override
  String get showInactive => 'Pokaż nieaktywne rekordy';

  @override
  String get showActive => 'Pokaż aktywne rekordy';

  @override
  String get fieldId => 'ID';

  @override
  String get createdBy => 'Utworzone przez';

  @override
  String get createdAt => 'Utworzono';

  @override
  String get modifiedBy => 'Zmienione przez';

  @override
  String get modifiedAt => 'Zmieniono';

  @override
  String get rangeFrom => 'Od';

  @override
  String get rangeTo => 'Do';

  @override
  String get favorites => 'Ulubione';

  @override
  String get addToFavorites => 'Dodaj do ulubionych';

  @override
  String get removeFromFavorites => 'Usuń z ulubionych';

  @override
  String get noFavorites => 'Zaznacz pozycje menu, aby dodać ulubione';

  @override
  String get globalSearch => 'Wyszukiwanie globalne';

  @override
  String get selectMenuEntry => 'Wybierz pozycję menu';

  @override
  String get selectColor => 'Wybierz kolor';

  @override
  String get addValue => 'Dodaj wartość';

  @override
  String get translate => 'Przetłumacz';

  @override
  String get saveBeforeTranslate =>
      'Musisz zapisać rekord przed dodaniem tłumaczeń.';

  @override
  String get noOtherLanguage => 'Brak innych dostępnych języków.';

  @override
  String get edit => 'Edytuj';

  @override
  String get fuzzy => 'Niepewne';

  @override
  String get columns => 'Kolumny';

  @override
  String get resetColumnWidths => 'Resetuj szerokości kolumn';

  @override
  String get copySelectedRows => 'Kopiuj zaznaczone wiersze';

  @override
  String get notifications => 'Powiadomienia';

  @override
  String get noNotifications => 'Brak powiadomień';

  @override
  String get allNotifications => 'Wszystkie powiadomienia…';

  @override
  String get closeAllTabsQuestion =>
      'Ta akcja wymaga zamknięcia wszystkich kart.\nCzy chcesz kontynuować?';

  @override
  String get editUserPreferences => 'Edytuj preferencje użytkownika';

  @override
  String get saveAs => 'Zapisz jako…';

  @override
  String get selectFile => 'Wybierz…';

  @override
  String get clear => 'Wyczyść';

  @override
  String get openFile => 'Otwórz…';

  @override
  String attachmentsOf(Object name) {
    return 'Załączniki ($name)';
  }

  @override
  String notesOf(Object name) {
    return 'Notatki ($name)';
  }

  @override
  String logsOf(Object name) {
    return 'Dzienniki ($name)';
  }

  @override
  String attachmentCount(Object count) {
    return 'Załącznik ($count)';
  }

  @override
  String get addFiles => 'Dodaj…';

  @override
  String get manage => 'Zarządzaj…';

  @override
  String get logModel => 'Model';

  @override
  String get logModule => 'Moduł';

  @override
  String get logXmlId => 'ID XML';

  @override
  String get logCreatedBy => 'Utworzone przez';

  @override
  String get logCreatedAt => 'Utworzone';

  @override
  String get logModifiedBy => 'Ostatnio zmienione przez';

  @override
  String get logModifiedAt => 'Ostatnio zmienione';

  @override
  String get exportData => 'Eksportuj dane…';

  @override
  String get importData => 'Importuj dane…';

  @override
  String csvExportTitle(Object name) {
    return 'Eksport CSV: $name';
  }

  @override
  String csvImportTitle(Object name) {
    return 'Import CSV: $name';
  }

  @override
  String get csvAllFields => 'Wszystkie pola';

  @override
  String get csvFieldsSelected => 'Wybrane pola';

  @override
  String get csvRemoveAll => 'Wyczyść';

  @override
  String get csvParameters => 'Parametry CSV';

  @override
  String get csvDelimiter => 'Separator';

  @override
  String get csvQuoteChar => 'Cudzysłów';

  @override
  String get csvEncoding => 'Kodowanie';

  @override
  String get csvLocaleFormat => 'Użyj formatu lokalnego';

  @override
  String get csvAddFieldNames => 'Dodaj nazwy pól';

  @override
  String get csvListedRecords => 'Wyświetlone rekordy';

  @override
  String get csvSelectedRecords => 'Zaznaczone rekordy';

  @override
  String get csvIgnoreSearchLimit => 'Ignoruj limit wyszukiwania';

  @override
  String get csvPredefinedExports => 'Predefiniowane eksporty';

  @override
  String get csvSaveExport => 'Zapisz eksport';

  @override
  String get csvDeleteExport => 'Usuń eksport';

  @override
  String get csvExportName => 'Jaka jest nazwa tego eksportu?';

  @override
  String csvOverrideExport(Object name) {
    return 'Nadpisać definicję „$name”?';
  }

  @override
  String csvRecordsSaved(Object count) {
    return 'Zapisane rekordy: $count';
  }

  @override
  String get csvExportFailed => 'Eksport nie powiódł się';

  @override
  String get csvFileToImport => 'Plik do importu';

  @override
  String get csvLinesToSkip => 'Wiersze do pominięcia';

  @override
  String get csvAutoDetect => 'Wykryj automatycznie';

  @override
  String get csvImport => 'Importuj';

  @override
  String get csvSelectImportFile => 'Najpierw wybierz plik do importu.';

  @override
  String csvUnknownHeader(Object name) {
    return 'Nieznany nagłówek kolumny „$name”';
  }

  @override
  String get csvDetectionFailed => 'Wykrywanie nie powiodło się';

  @override
  String csvRecordsImported(Object count) {
    return 'Zaimportowane rekordy: $count';
  }

  @override
  String get csvImportFailed => 'Import nie powiódł się';

  @override
  String csvFieldString(Object name) {
    return '$name (tekst)';
  }

  @override
  String csvFieldModelName(Object name) {
    return '$name (nazwa modelu)';
  }

  @override
  String csvFieldRecordName(Object name) {
    return '$name/Nazwa rekordu';
  }

  @override
  String get open => 'Otwórz';

  @override
  String get recordMenu => 'Menu rekordu';

  @override
  String get menuSwitchView => 'Przełącz widok';

  @override
  String get menuPrevious => 'Poprzedni';

  @override
  String get menuNext => 'Następny';

  @override
  String get menuSearch => 'Szukaj';

  @override
  String get menuNew => 'Nowy';

  @override
  String get menuSave => 'Zapisz';

  @override
  String get menuReload => 'Przeładuj/Cofnij';

  @override
  String get menuDuplicate => 'Duplikuj';

  @override
  String get menuDelete => 'Usuń…';

  @override
  String get menuLogs => 'Pokaż logi…';

  @override
  String get menuRevisions => 'Pokaż wersje…';

  @override
  String get menuAttachments => 'Załączniki…';

  @override
  String get menuNotes => 'Notatki…';

  @override
  String get menuActions => 'Akcje…';

  @override
  String get menuRelate => 'Powiązane…';

  @override
  String get menuReport => 'Raport…';

  @override
  String get menuEmail => 'E-mail…';

  @override
  String get menuCloseTab => 'Zamknij kartę';

  @override
  String get keyboardShortcuts => 'Skróty klawiszowe';

  @override
  String get shortcutsGlobal => 'Ogólne';

  @override
  String get shortcutsForm => 'Formularz';

  @override
  String get shortcutsRelation => 'Pola relacji';

  @override
  String get shortcutsList => 'Pola list';

  @override
  String get shortcutsDate => 'Pola daty';

  @override
  String get shortcutSearchMenu => 'Szukaj w menu';

  @override
  String get shortcutToggleMenu => 'Pokaż/ukryj menu';

  @override
  String get shortcutPreviousTab => 'Poprzednia karta';

  @override
  String get shortcutNextTab => 'Następna karta';

  @override
  String get shortcutQuit => 'Zakończ';

  @override
  String get shortcutRelationNew => 'Utwórz nową relację';

  @override
  String get shortcutRelationOpen => 'Otwórz/szukaj relacji';

  @override
  String get shortcutListSwitch => 'Przełącz widok';

  @override
  String get shortcutListNew => 'Utwórz/wybierz nowy wiersz';

  @override
  String get shortcutListOpen => 'Otwórz relację';

  @override
  String get shortcutListDelete => 'Oznacz wiersz do usunięcia';

  @override
  String get shortcutListRemove => 'Oznacz wiersz do odłączenia';

  @override
  String get shortcutListUndelete => 'Cofnij oznaczenie usunięcia';

  @override
  String get shortcutDateToday => 'Dziś';

  @override
  String get shortcutDateAdd =>
      'Dodaj sekundę/minutę/godzinę/dzień/tydzień/miesiąc/rok';

  @override
  String get shortcutDateSubtract =>
      'Odejmij sekundę/minutę/godzinę/dzień/tydzień/miesiąc/rok';

  @override
  String get keyDelete => 'Delete';

  @override
  String get keyInsert => 'Insert';

  @override
  String get ctxCopy => 'Kopiuj';

  @override
  String get ctxCopyRow => 'Kopiuj wiersz';

  @override
  String get ctxCopyRows => 'Kopiuj wiersze';

  @override
  String get ctxCopyColumn => 'Kopiuj kolumnę';

  @override
  String get ctxPasteRows => 'Wklej wiersze';

  @override
  String get ctxEdit => 'Edytuj…';

  @override
  String get ctxPrint => 'Drukuj…';

  @override
  String get x2mCreate => 'Utwórz nowy rekord';

  @override
  String get x2mEdit => 'Edytuj wybrany rekord';

  @override
  String get x2mDelete => 'Usuń wybrany rekord';

  @override
  String get x2mAdd => 'Dodaj istniejący rekord';

  @override
  String get x2mRemove => 'Odłącz wybrany rekord';

  @override
  String get x2mUndelete => 'Przywróć wybrany rekord';

  @override
  String get x2mRestore => 'Przywróć wybrany rekord';

  @override
  String get x2mSwitch => 'Przełącz';

  @override
  String get x2mPrevious => 'Poprzedni';

  @override
  String get x2mNext => 'Następny';

  @override
  String get x2mMore => 'Więcej';

  @override
  String get reportBug => 'Zgłoś błąd';

  @override
  String get selectionTitle => 'Wybór';

  @override
  String get yourSelection => 'Twój wybór:';

  @override
  String emailTitle(Object name) {
    return 'E-mail $name';
  }

  @override
  String get emailTo => 'Do';

  @override
  String get emailCc => 'DW';

  @override
  String get emailBcc => 'UDW';

  @override
  String get emailSubject => 'Temat';

  @override
  String get emailBody => 'Treść';

  @override
  String get emailReports => 'Raporty';

  @override
  String get emailAttachments => 'Załączniki';

  @override
  String get emailFiles => 'Pliki';

  @override
  String get emailAddFile => 'Wybierz plik';

  @override
  String get emailRemoveFile => 'Usuń plik';

  @override
  String get emailSend => 'Wyślij';

  @override
  String get emailTemplate => 'Szablon';

  @override
  String get emailSent => 'E-mail wysłany.';

  @override
  String get attachmentPreview => 'Podgląd załącznika';

  @override
  String get noAttachment => 'Brak załącznika.';

  @override
  String get profile => 'Profil';

  @override
  String get editProfiles => 'Edytuj profile…';

  @override
  String get profiles => 'Profile';

  @override
  String get profileName => 'Nazwa profilu';

  @override
  String get newProfile => 'Nowy profil';

  @override
  String get deleteProfile => 'Usuń profil';

  @override
  String get renameProfile => 'Zmień nazwę';

  @override
  String get profileNameTaken => 'Ta nazwa profilu jest już używana.';

  @override
  String get incompatibleServer => 'Niezgodna wersja serwera.';

  @override
  String get couldNotConnect => 'Nie można połączyć się z serwerem.';

  @override
  String get copyUrl => 'Kopiuj URL';

  @override
  String get urlCopied => 'Skopiowano URL.';

  @override
  String get openTrytonUrl => 'Otwórz URL Tryton';

  @override
  String urlOtherProfile(Object target, Object profile) {
    return 'URL należy do $target. Zalogować się profilem \"$profile\"?';
  }

  @override
  String urlNoProfile(Object target) {
    return 'URL należy do $target; brak profilu dla niego.';
  }

  @override
  String get chat => 'Czat';

  @override
  String get chatInternal => 'Oznacz jako wiadomość wewnętrzną';

  @override
  String get chatInternalTag => 'wewnętrzna';

  @override
  String get chatFollowers => 'Pokaż obserwujących';

  @override
  String get chatSubscribe => 'Subskrybuj';

  @override
  String get chatUnsubscribe => 'Anuluj subskrypcję';

  @override
  String get chatAddFollower => 'Dodaj obserwującego';

  @override
  String chatUnsubscribeQuestion(Object name) {
    return 'Czy na pewno wypisać \"$name\" z tego kanału?';
  }

  @override
  String get chatEmpty => 'Brak wiadomości.';

  @override
  String get calendarToday => 'Dziś';

  @override
  String get calendarMonth => 'Miesiąc';

  @override
  String get calendarWeek => 'Tydzień';

  @override
  String get calendarDay => 'Dzień';

  @override
  String get scanCode => 'Skanuj';

  @override
  String get codeScanner => 'Skaner kodów';

  @override
  String get scanCodeHint => 'Kod';

  @override
  String get scanCodeSound => 'Dźwięk';

  @override
  String get scanCodeCamera => 'Kamera';

  @override
  String get scanCodeNoCamera =>
      'Brak kamery – wpisz kod lub zeskanuj go skanerem ręcznym.';

  @override
  String get allTabs => 'Wszystkie karty';
}
