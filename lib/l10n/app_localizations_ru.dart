// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Tryton Flutter Client';

  @override
  String get appSubtitle => 'Клиент ERP Tryton';

  @override
  String get username => 'Имя пользователя';

  @override
  String get password => 'Пароль';

  @override
  String get database => 'База данных';

  @override
  String get serverUrl => 'URL сервера';

  @override
  String get required => 'Обязательное поле';

  @override
  String get signIn => 'Войти';

  @override
  String get signOut => 'Выйти';

  @override
  String get loadDatabases => 'Загрузить базы данных';

  @override
  String get additionalInputRequired => 'Требуется дополнительный ввод';

  @override
  String get reloadMenu => 'Обновить меню';

  @override
  String get noMenuEntriesFound => 'Пункты меню не найдены.';

  @override
  String get retry => 'Повторить';

  @override
  String get error => 'Ошибка';

  @override
  String get search => 'Поиск…';

  @override
  String selected(int count) {
    return 'Выбрано: $count';
  }

  @override
  String get deleteRecords => 'Удалить записи';

  @override
  String reallyDeleteRecords(int count) {
    return 'Удалить $count запись(ей)?';
  }

  @override
  String get noRecordsFound => 'Записи не найдены.';

  @override
  String get createNew => 'Создать новый';

  @override
  String get attachments => 'Вложения';

  @override
  String get duplicate => 'Дублировать';

  @override
  String get openEdit => 'Открыть / Редактировать';

  @override
  String get reload => 'Обновить';

  @override
  String get delete => 'Удалить';

  @override
  String get moreActions => 'Дополнительные действия';

  @override
  String get launchActions => 'Запустить действия';

  @override
  String get relatedRecords => 'Связанные записи';

  @override
  String get reports => 'Отчёты';

  @override
  String get email => 'Электронная почта';

  @override
  String get save => 'Сохранить';

  @override
  String get cancel => 'Отмена';

  @override
  String get recordCreated => 'Запись создана.';

  @override
  String get saved => 'Сохранено.';

  @override
  String get deleteRecord => 'Удалить запись';

  @override
  String get reallyDelete => 'Удалить? Это действие нельзя отменить.';

  @override
  String get add => 'Добавить';

  @override
  String get noEntries => 'Нет записей.';

  @override
  String get apply => 'Применить';

  @override
  String get openRecord => 'Открыть запись';

  @override
  String get clearField => 'Очистить поле';

  @override
  String get searchRecord => 'Найти запись';

  @override
  String entries(int count) {
    return '$count запись(ей)';
  }

  @override
  String get generatingReport => 'Формирование отчёта…';

  @override
  String reportGenerated(String name, String format) {
    return 'Отчёт \"$name\" ($format) сформирован.';
  }

  @override
  String actionNotSupported(String name, String type) {
    return '\"$name\" ($type) пока не поддерживается.';
  }

  @override
  String executingButton(String name) {
    return 'Выполняется кнопка \"$name\"…';
  }

  @override
  String get language => 'Язык';

  @override
  String get sessionExpired => 'Сеанс истёк';

  @override
  String get preferences => 'Настройки';

  @override
  String get help => 'Справка';

  @override
  String get collapse => 'Свернуть';

  @override
  String get expand => 'Развернуть';

  @override
  String get openInForm => 'Открыть в форме';

  @override
  String get undelete => 'Восстановить';

  @override
  String get switchToForm => 'Перейти к форме';

  @override
  String get close => 'Закрыть';

  @override
  String get boolYes => 'Да';

  @override
  String get boolNo => 'Нет';

  @override
  String get clearSearch => 'Очистить';

  @override
  String get previousRecord => 'Предыдущий';

  @override
  String get nextRecord => 'Следующий';

  @override
  String get viewLogs => 'Просмотр журнала';

  @override
  String get note => 'Заметка';

  @override
  String get wizard => 'Мастер';

  @override
  String versionMismatch(String server, String client) {
    return 'Несовместимая версия сервера $server (клиент ожидает $client).';
  }

  @override
  String get recordModified =>
      'Эта запись была изменена.\nВы хотите сохранить её?';

  @override
  String get yes => 'Да';

  @override
  String get no => 'Нет';
}
