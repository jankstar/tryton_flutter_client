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
  String get boardNotSupported => 'Pulpity nie są jeszcze obsługiwane.';

  @override
  String get selectMenuEntry => 'Wybierz pozycję menu';
}
