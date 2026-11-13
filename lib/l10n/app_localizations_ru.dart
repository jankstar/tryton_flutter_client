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
  String get reallyDeleteRecords =>
      'Вы уверены, что хотите удалить эти записи?';

  @override
  String get noRecordsFound => 'Записи не найдены.';

  @override
  String get createNew => 'Создать новый';

  @override
  String get attachments => 'Вложения';

  @override
  String get duplicate => 'Копировать';

  @override
  String get openEdit => 'Открыть / Редактировать';

  @override
  String get reload => 'Обновить';

  @override
  String get delete => 'Удалить';

  @override
  String get moreActions => 'Дополнительные действия';

  @override
  String get launchActions => 'Выполнить действие';

  @override
  String get relatedRecords => 'Открыть связанные записи';

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
  String get reallyDelete => 'Вы уверены, что хотите удалить эту запись?';

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
  String get searchRecord => 'Поиск записи';

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
  String get switchView => 'Переключить вид';

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
    return 'Несовместимая версия сервера. Сервер $server, клиент $client.';
  }

  @override
  String get recordModified =>
      'Эта запись была изменена.\nВы хотите сохранить её?';

  @override
  String get yes => 'Да';

  @override
  String get no => 'Нет';

  @override
  String get concurrencyWarning => 'Предупреждение о параллельном изменении';

  @override
  String get concurrencyMessage =>
      'Эта запись была изменена, пока вы её редактировали.';

  @override
  String get compare => 'Сравнить';

  @override
  String get writeAnyway => 'Записать все равно';

  @override
  String get concurrencyException => 'Ошибка параллельного изменения';

  @override
  String compareTabTitle(String name) {
    return 'Сравнить: $name';
  }

  @override
  String get fieldNotSupported => 'Пока не поддерживается';

  @override
  String get ok => 'OK';

  @override
  String get alwaysIgnore => 'Всегда игнорировать';

  @override
  String get applicationError => 'Ошибка приложения';

  @override
  String get details => 'Подробности';

  @override
  String httpError(int code, String text) {
    return 'Ошибка: «[$code] $text». Повторите попытку позже.';
  }

  @override
  String networkError(String details) {
    return 'Не удаётся связаться с сервером. $details';
  }

  @override
  String invalidRequired(String field) {
    return '«$field» обязательно для заполнения.';
  }

  @override
  String invalidDomain(String field) {
    return '«$field» недопустимо согласно домену.';
  }

  @override
  String invalidChildren(String field) {
    return 'Значения «$field» недопустимы.';
  }

  @override
  String get invalidRecordTitle => 'Запись недопустима';

  @override
  String get selectAction => 'Выберите действие';

  @override
  String get noActionDefined => 'Действие не определено.';

  @override
  String get preValidation => 'Предварительная проверка';

  @override
  String buttonClickedBy(String users) {
    return 'Кем: $users';
  }

  @override
  String get discardChanges => 'Отменить изменения';

  @override
  String get saveAndNew => 'Сохранить и создать';

  @override
  String get addAndNew => 'Добавить и создать';

  @override
  String get applyChanges => 'Применить изменения';

  @override
  String get find => 'Найти';

  @override
  String get remove => 'Удалить';

  @override
  String get searchMenu => 'Поиск…';

  @override
  String get createMenu => 'Создать…';

  @override
  String searchTitle(String title) {
    return 'Поиск: $title';
  }

  @override
  String createNamed(String name) {
    return 'Создать «$name»…';
  }

  @override
  String get revisions => 'Ревизии…';

  @override
  String get currentRevision => 'Текущая';

  @override
  String get selectRevision => 'Выберите ревизию';

  @override
  String get filters => 'Фильтры';

  @override
  String get bookmarkFilter => 'Запомнить этот фильтр';

  @override
  String get removeBookmark => 'Удалить эту закладку';

  @override
  String get bookmarks => 'Закладки';

  @override
  String get bookmarkName => 'Имя закладки:';

  @override
  String get showInactive => 'Показать неактивные записи';

  @override
  String get showActive => 'Показать активные записи';

  @override
  String get fieldId => 'ID';

  @override
  String get createdBy => 'Создано';

  @override
  String get createdAt => 'Дата создания';

  @override
  String get modifiedBy => 'Изменено';

  @override
  String get modifiedAt => 'Дата изменения';

  @override
  String get rangeFrom => 'С';

  @override
  String get rangeTo => 'По';

  @override
  String get favorites => 'Избранное';

  @override
  String get addToFavorites => 'Добавить в избранное';

  @override
  String get removeFromFavorites => 'Удалить из избранного';

  @override
  String get noFavorites => 'Отметьте пункты меню, чтобы добавить в избранное';

  @override
  String get globalSearch => 'Глобальный поиск';

  @override
  String get selectMenuEntry => 'Выберите пункт меню';

  @override
  String get selectColor => 'Выберите цвет';

  @override
  String get addValue => 'Добавить значение';

  @override
  String get translate => 'Перевести';

  @override
  String get saveBeforeTranslate =>
      'Перед добавлением переводов необходимо сохранить запись.';

  @override
  String get noOtherLanguage => 'Другие языки недоступны.';

  @override
  String get edit => 'Редактировать';

  @override
  String get fuzzy => 'Неточный';

  @override
  String get columns => 'Столбцы';

  @override
  String get resetColumnWidths => 'Сбросить ширину столбцов';

  @override
  String get copySelectedRows => 'Копировать выбранные строки';

  @override
  String get notifications => 'Уведомления';

  @override
  String get noNotifications => 'Сейчас нет уведомлений';

  @override
  String get allNotifications => 'Все уведомления…';

  @override
  String get closeAllTabsQuestion =>
      'Для этого действия нужно закрыть все вкладки.\nПродолжить?';

  @override
  String get editUserPreferences => 'Изменить настройки пользователя';

  @override
  String get saveAs => 'Сохранить как…';

  @override
  String get selectFile => 'Выбрать…';

  @override
  String get clear => 'Очистить';

  @override
  String get openFile => 'Открыть…';

  @override
  String attachmentsOf(Object name) {
    return 'Вложения ($name)';
  }

  @override
  String notesOf(Object name) {
    return 'Заметки ($name)';
  }

  @override
  String logsOf(Object name) {
    return 'Журналы ($name)';
  }

  @override
  String attachmentCount(Object count) {
    return 'Вложение ($count)';
  }

  @override
  String get addFiles => 'Добавить…';

  @override
  String get manage => 'Управлять…';

  @override
  String get logModel => 'Модель';

  @override
  String get logModule => 'Модуль';

  @override
  String get logXmlId => 'XML ID';

  @override
  String get logCreatedBy => 'Создано';

  @override
  String get logCreatedAt => 'Дата создания';

  @override
  String get logModifiedBy => 'Изменено';

  @override
  String get logModifiedAt => 'Дата изменения';

  @override
  String get exportData => 'Экспорт данных…';

  @override
  String get importData => 'Импорт данных…';

  @override
  String csvExportTitle(Object name) {
    return 'Экспорт CSV: $name';
  }

  @override
  String csvImportTitle(Object name) {
    return 'Импорт CSV: $name';
  }

  @override
  String get csvAllFields => 'Все поля';

  @override
  String get csvFieldsSelected => 'Выбранные поля';

  @override
  String get csvRemoveAll => 'Очистить';

  @override
  String get csvParameters => 'Параметры CSV';

  @override
  String get csvDelimiter => 'Разделитель';

  @override
  String get csvQuoteChar => 'Кавычки';

  @override
  String get csvEncoding => 'Кодировка';

  @override
  String get csvLocaleFormat => 'Использовать локальный формат';

  @override
  String get csvAddFieldNames => 'Добавить имена полей';

  @override
  String get csvListedRecords => 'Показанные записи';

  @override
  String get csvSelectedRecords => 'Выбранные записи';

  @override
  String get csvIgnoreSearchLimit => 'Игнорировать лимит поиска';

  @override
  String get csvPredefinedExports => 'Предопределённые экспорты';

  @override
  String get csvSaveExport => 'Сохранить экспорт';

  @override
  String get csvDeleteExport => 'Удалить экспорт';

  @override
  String get csvExportName => 'Укажите имя для экспорта.';

  @override
  String csvOverrideExport(Object name) {
    return 'Перезаписать определение «$name»?';
  }

  @override
  String csvRecordsSaved(Object count) {
    return 'Сохранено записей: $count';
  }

  @override
  String get csvExportFailed => 'Ошибка экспорта';

  @override
  String get csvFileToImport => 'Файл для импорта';

  @override
  String get csvLinesToSkip => 'Строки для пропуска';

  @override
  String get csvAutoDetect => 'Автоопределение';

  @override
  String get csvImport => 'Импорт';

  @override
  String get csvSelectImportFile => 'Сначала выберите файл для импорта.';

  @override
  String csvUnknownHeader(Object name) {
    return 'Неизвестный заголовок столбца «$name»';
  }

  @override
  String get csvDetectionFailed => 'Ошибка определения';

  @override
  String csvRecordsImported(Object count) {
    return 'Импортировано записей: $count';
  }

  @override
  String get csvImportFailed => 'Ошибка импорта';

  @override
  String csvFieldString(Object name) {
    return '$name (текст)';
  }

  @override
  String csvFieldModelName(Object name) {
    return '$name (имя модели)';
  }

  @override
  String csvFieldRecordName(Object name) {
    return '$name/имя записи';
  }

  @override
  String get open => 'Открыть';

  @override
  String get recordMenu => 'Меню записи';

  @override
  String get menuSwitchView => 'Переключить вид';

  @override
  String get menuPrevious => 'Предыдущий';

  @override
  String get menuNext => 'Следующий';

  @override
  String get menuSearch => 'Поиск';

  @override
  String get menuNew => 'Новый';

  @override
  String get menuSave => 'Сохранить';

  @override
  String get menuReload => 'Обновить/Отменить';

  @override
  String get menuDuplicate => 'Копировать';

  @override
  String get menuDelete => 'Удалить…';

  @override
  String get menuLogs => 'Журнал…';

  @override
  String get menuRevisions => 'Показать ревизии…';

  @override
  String get menuAttachments => 'Вложения…';

  @override
  String get menuNotes => 'Заметки…';

  @override
  String get menuActions => 'Действия…';

  @override
  String get menuRelate => 'Связанные…';

  @override
  String get menuReport => 'Отчет…';

  @override
  String get menuEmail => 'Эл. почта…';

  @override
  String get menuCloseTab => 'Закрыть вкладку';

  @override
  String get keyboardShortcuts => 'Сочетания клавиш';

  @override
  String get shortcutsGlobal => 'Общие';

  @override
  String get shortcutsForm => 'Форма';

  @override
  String get shortcutsRelation => 'Поля связей';

  @override
  String get shortcutsList => 'Поля списков';

  @override
  String get shortcutsDate => 'Поля даты';

  @override
  String get shortcutSearchMenu => 'Поиск в меню';

  @override
  String get shortcutToggleMenu => 'Показать/скрыть меню';

  @override
  String get shortcutPreviousTab => 'Предыдущая вкладка';

  @override
  String get shortcutNextTab => 'Следующая вкладка';

  @override
  String get shortcutQuit => 'Выход';

  @override
  String get shortcutRelationNew => 'Создать новую связь';

  @override
  String get shortcutRelationOpen => 'Открыть / Поиск связей';

  @override
  String get shortcutListSwitch => 'Переключить вид';

  @override
  String get shortcutListNew => 'Создать/выбрать строку';

  @override
  String get shortcutListOpen => 'Открыть связь';

  @override
  String get shortcutListDelete => 'Пометить строку на удаление';

  @override
  String get shortcutListRemove => 'Пометить строку на отвязку';

  @override
  String get shortcutListUndelete => 'Убрать отметку на удаление';

  @override
  String get shortcutDateToday => 'Сегодня';

  @override
  String get shortcutDateAdd =>
      'Прибавить секунду/минуту/час/день/неделю/месяц/год';

  @override
  String get shortcutDateSubtract =>
      'Вычесть секунду/минуту/час/день/неделю/месяц/год';

  @override
  String get keyDelete => 'Delete';

  @override
  String get keyInsert => 'Insert';

  @override
  String get ctxCopy => 'Копировать';

  @override
  String get ctxCopyRow => 'Копировать строку';

  @override
  String get ctxCopyRows => 'Копировать строки';

  @override
  String get ctxCopyColumn => 'Копировать столбец';

  @override
  String get ctxPasteRows => 'Вставить строки';

  @override
  String get ctxEdit => 'Изменить…';

  @override
  String get ctxPrint => 'Печать…';

  @override
  String get x2mCreate => 'Создать новую запись';

  @override
  String get x2mEdit => 'Изменить выбранную запись';

  @override
  String get x2mDelete => 'Удалить выбранную запись';

  @override
  String get x2mAdd => 'Добавить существующую запись';

  @override
  String get x2mRemove => 'Отвязать выбранную запись';

  @override
  String get x2mUndelete => 'Восстановить выбранную запись';

  @override
  String get x2mRestore => 'Вернуть выбранную запись';

  @override
  String get x2mSwitch => 'Переключить';

  @override
  String get x2mPrevious => 'Предыдущий';

  @override
  String get x2mNext => 'Следующий';

  @override
  String get x2mMore => 'Ещё';

  @override
  String get reportBug => 'Сообщить об ошибке';

  @override
  String get selectionTitle => 'Выбор';

  @override
  String get yourSelection => 'Ваш выбор:';

  @override
  String emailTitle(Object name) {
    return 'Эл. почта $name';
  }

  @override
  String get emailTo => 'Кому';

  @override
  String get emailCc => 'Копия';

  @override
  String get emailBcc => 'Скрытая копия';

  @override
  String get emailSubject => 'Тема';

  @override
  String get emailBody => 'Текст';

  @override
  String get emailReports => 'Отчёты';

  @override
  String get emailAttachments => 'Вложения';

  @override
  String get emailFiles => 'Файлы';

  @override
  String get emailAddFile => 'Выбрать файл';

  @override
  String get emailRemoveFile => 'Удалить файл';

  @override
  String get emailSend => 'Отправить';

  @override
  String get emailTemplate => 'Шаблон';

  @override
  String get emailSent => 'Письмо отправлено.';

  @override
  String get attachmentPreview => 'Просмотр вложения';

  @override
  String get noAttachment => 'Нет вложений.';

  @override
  String get profile => 'Профиль';

  @override
  String get editProfiles => 'Изменить профили…';

  @override
  String get profiles => 'Профили';

  @override
  String get profileName => 'Имя профиля';

  @override
  String get newProfile => 'Новый профиль';

  @override
  String get deleteProfile => 'Удалить профиль';

  @override
  String get renameProfile => 'Переименовать';

  @override
  String get profileNameTaken => 'Это имя профиля уже используется.';

  @override
  String get incompatibleServer => 'Несовместимая версия сервера.';

  @override
  String get couldNotConnect => 'Не удалось подключиться к серверу.';

  @override
  String get copyUrl => 'Копировать URL';

  @override
  String get urlCopied => 'URL скопирован.';

  @override
  String get openTrytonUrl => 'Открыть URL Tryton';

  @override
  String urlOtherProfile(Object target, Object profile) {
    return 'URL относится к $target. Войти с профилем «$profile»?';
  }

  @override
  String urlNoProfile(Object target) {
    return 'URL относится к $target; для него нет профиля.';
  }

  @override
  String get chat => 'Чат';

  @override
  String get chatInternal => 'Сделать это внутренним сообщением';

  @override
  String get chatInternalTag => 'внутреннее';

  @override
  String get chatFollowers => 'Показать подписчиков';

  @override
  String get chatSubscribe => 'Подписаться';

  @override
  String get chatUnsubscribe => 'Отписаться';

  @override
  String get chatAddFollower => 'Добавить подписчика';

  @override
  String chatUnsubscribeQuestion(Object name) {
    return 'Отписать «$name» от этого канала?';
  }

  @override
  String get chatEmpty => 'Сообщений пока нет.';

  @override
  String get calendarToday => 'Сегодня';

  @override
  String get calendarMonth => 'Месяц';

  @override
  String get calendarWeek => 'Неделя';

  @override
  String get calendarDay => 'День';

  @override
  String get scanCode => 'Сканировать';

  @override
  String get codeScanner => 'Сканер кодов';

  @override
  String get scanCodeHint => 'Код';

  @override
  String get scanCodeSound => 'Звук';

  @override
  String get scanCodeCamera => 'Камера';

  @override
  String get scanCodeNoCamera =>
      'Камера недоступна — введите код или считайте его ручным сканером.';

  @override
  String get allTabs => 'Все вкладки';

  @override
  String get connectionSecure => 'Зашифрованное соединение (HTTPS)';

  @override
  String get connectionInsecure =>
      'Незашифрованное соединение (HTTP) — пароль передаётся открытым текстом';

  @override
  String get documentation => 'Документация…';

  @override
  String get aboutMenu => 'О программе…';

  @override
  String get aboutVersion => 'Версия';

  @override
  String get aboutBasedOn =>
      'Основан на настольном клиенте Tryton и SAO – Copyright (C) 2004-2026 Tryton';

  @override
  String get aboutProjectPage => 'Страница проекта';

  @override
  String get aboutCredits => 'Авторы';

  @override
  String get aboutLicense => 'Лицензия';

  @override
  String get aboutCopyright => 'Авторские права';

  @override
  String get aboutThirdParty => 'Лицензии сторонних компонентов';

  @override
  String get aboutAuthors => 'Авторы этого клиента';

  @override
  String get aboutOriginalAuthors => 'Авторы клиента Tryton (оригинал)';

  @override
  String get aboutTranslations => 'Переводы';

  @override
  String get aboutNoWarranty =>
      'Эта программа не предоставляет никаких гарантий.';

  @override
  String aboutSeeLicense(String license) {
    return 'Подробности см. в $license.';
  }

  @override
  String get aboutGplName =>
      'GNU General Public License версии 3 или более поздней';

  @override
  String get appDevelopment => 'разработка';

  @override
  String get appPrerelease => 'Тестовая версия';

  @override
  String get loginFailed => 'Неверное имя пользователя или пароль.';

  @override
  String get tooManyRequests =>
      'Слишком много запросов. Повторите попытку позже.';

  @override
  String get databaseNotFound => 'База данных не найдена.';

  @override
  String get serverForbidden => 'Сервер не разрешает это.';

  @override
  String get resetPassword => 'Сбросить забытый пароль';

  @override
  String get resetPasswordTooltip => 'Отправить письмо для сброса пароля.';

  @override
  String get resetPasswordSent =>
      'Запрос на сброс пароля отправлен.\nПроверьте почтовый ящик.';

  @override
  String get resetPasswordNeedsUser =>
      'Сначала укажите сервер, базу данных и имя пользователя.';

  @override
  String get openReport => 'Открыть отчет';

  @override
  String get printReport => 'Печать отчета';

  @override
  String get aboutTranslationsTryton =>
      'Многие тексты из переводов проекта Tryton';
}
