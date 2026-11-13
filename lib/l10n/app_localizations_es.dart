// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Tryton Flutter Client';

  @override
  String get appSubtitle => 'Cliente ERP Tryton';

  @override
  String get username => 'Usuario';

  @override
  String get password => 'Contraseña';

  @override
  String get database => 'Base de datos';

  @override
  String get serverUrl => 'URL del servidor';

  @override
  String get required => 'Obligatorio';

  @override
  String get signIn => 'Iniciar sesión';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get loadDatabases => 'Cargar bases de datos';

  @override
  String get additionalInputRequired => 'Se requiere información adicional';

  @override
  String get reloadMenu => 'Recargar menú';

  @override
  String get noMenuEntriesFound => 'No se encontraron entradas de menú.';

  @override
  String get retry => 'Reintentar';

  @override
  String get error => 'Error';

  @override
  String get search => 'Buscar…';

  @override
  String selected(int count) {
    return '$count seleccionado(s)';
  }

  @override
  String get deleteRecords => 'Eliminar registros';

  @override
  String get reallyDeleteRecords =>
      '¿Está seguro que quiere eliminar estos registros?';

  @override
  String get noRecordsFound => 'No se encontraron registros.';

  @override
  String get createNew => 'Crear nuevo';

  @override
  String get attachments => 'Adjuntos';

  @override
  String get duplicate => 'Duplicar';

  @override
  String get openEdit => 'Abrir / Editar';

  @override
  String get reload => 'Recargar';

  @override
  String get delete => 'Eliminar';

  @override
  String get moreActions => 'Más acciones';

  @override
  String get launchActions => 'Ejecutar acción';

  @override
  String get relatedRecords => 'Abrir registros relacionados';

  @override
  String get reports => 'Informes';

  @override
  String get email => 'Correo electrónico';

  @override
  String get save => 'Guardar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get recordCreated => 'Registro creado.';

  @override
  String get saved => 'Guardado.';

  @override
  String get deleteRecord => 'Eliminar registro';

  @override
  String get reallyDelete => '¿Está seguro que quiere eliminar este registro?';

  @override
  String get add => 'Añadir';

  @override
  String get noEntries => 'Sin entradas.';

  @override
  String get apply => 'Aplicar';

  @override
  String get openRecord => 'Abrir registro';

  @override
  String get clearField => 'Limpiar campo';

  @override
  String get searchRecord => 'Buscar registro';

  @override
  String entries(int count) {
    return '$count entradas';
  }

  @override
  String get generatingReport => 'Generando informe…';

  @override
  String reportGenerated(String name, String format) {
    return 'Informe \"$name\" ($format) generado.';
  }

  @override
  String actionNotSupported(String name, String type) {
    return '\"$name\" ($type) aún no está soportado.';
  }

  @override
  String executingButton(String name) {
    return 'Ejecutando botón \"$name\"…';
  }

  @override
  String get language => 'Idioma';

  @override
  String get sessionExpired => 'Sesión caducada';

  @override
  String get preferences => 'Preferencias';

  @override
  String get help => 'Ayuda';

  @override
  String get collapse => 'Contraer';

  @override
  String get expand => 'Expandir';

  @override
  String get openInForm => 'Abrir en formulario';

  @override
  String get undelete => 'Recuperar';

  @override
  String get switchToForm => 'Cambiar al formulario';

  @override
  String get switchView => 'Cambiar de vista';

  @override
  String get close => 'Cerrar';

  @override
  String get boolYes => 'Sí';

  @override
  String get boolNo => 'No';

  @override
  String get clearSearch => 'Limpiar';

  @override
  String get previousRecord => 'Anterior';

  @override
  String get nextRecord => 'Siguiente';

  @override
  String get viewLogs => 'Ver registros';

  @override
  String get note => 'Nota';

  @override
  String get wizard => 'Asistente';

  @override
  String versionMismatch(String server, String client) {
    return 'El cliente no es compatible con la versión del servidor. Servidor $server, cliente $client.';
  }

  @override
  String get recordModified =>
      'Este registro ha sido modificado.\n¿Desea guardarlo?';

  @override
  String get yes => 'Sí';

  @override
  String get no => 'No';

  @override
  String get concurrencyWarning => 'Aviso de concurrencia';

  @override
  String get concurrencyMessage =>
      'Este registro ha sido modificado mientras lo editaba.';

  @override
  String get compare => 'Comparar';

  @override
  String get writeAnyway => 'Guardar de todas formas';

  @override
  String get concurrencyException => 'Excepción de concurrencia';

  @override
  String compareTabTitle(String name) {
    return 'Comparar: $name';
  }

  @override
  String get fieldNotSupported => 'Aún no compatible';

  @override
  String get ok => 'Aceptar';

  @override
  String get alwaysIgnore => 'Ignorar siempre';

  @override
  String get applicationError => 'Error de aplicación';

  @override
  String get details => 'Detalles';

  @override
  String httpError(int code, String text) {
    return 'Error: «[$code] $text». Inténtelo de nuevo más tarde.';
  }

  @override
  String networkError(String details) {
    return 'No se puede conectar con el servidor. $details';
  }

  @override
  String invalidRequired(String field) {
    return '\"$field\" es obligatorio.';
  }

  @override
  String invalidDomain(String field) {
    return '\"$field\" no es válido según su dominio.';
  }

  @override
  String invalidChildren(String field) {
    return 'Los valores de \"$field\" no son válidos.';
  }

  @override
  String get invalidRecordTitle => 'Registro no válido';

  @override
  String get selectAction => 'Seleccione su acción';

  @override
  String get noActionDefined => 'No se ha definido ninguna acción.';

  @override
  String get preValidation => 'Prevalidación';

  @override
  String buttonClickedBy(String users) {
    return 'Por: $users';
  }

  @override
  String get discardChanges => 'Descartar cambios';

  @override
  String get saveAndNew => 'Guardar y nuevo';

  @override
  String get addAndNew => 'Añadir y nuevo';

  @override
  String get applyChanges => 'Aplicar cambios';

  @override
  String get find => 'Buscar';

  @override
  String get remove => 'Eliminar';

  @override
  String get searchMenu => 'Buscar…';

  @override
  String get createMenu => 'Crear…';

  @override
  String searchTitle(String title) {
    return 'Buscar $title';
  }

  @override
  String createNamed(String name) {
    return 'Crear \"$name\"…';
  }

  @override
  String get revisions => 'Revisiones…';

  @override
  String get currentRevision => 'Actual';

  @override
  String get selectRevision => 'Seleccione una revisión';

  @override
  String get filters => 'Filtros';

  @override
  String get bookmarkFilter => 'Guardar como búsqueda favorita';

  @override
  String get removeBookmark => 'Eliminar de las búsquedas favoritas';

  @override
  String get bookmarks => 'Búsquedas favoritas';

  @override
  String get bookmarkName => 'Nombre de la búsqueda favorita:';

  @override
  String get showInactive => 'Mostrar registros inactivos';

  @override
  String get showActive => 'Mostrar registros activos';

  @override
  String get fieldId => 'ID';

  @override
  String get createdBy => 'Creado por';

  @override
  String get createdAt => 'Creado el';

  @override
  String get modifiedBy => 'Modificado por';

  @override
  String get modifiedAt => 'Modificado el';

  @override
  String get rangeFrom => 'De';

  @override
  String get rangeTo => 'Hasta';

  @override
  String get favorites => 'Favoritos';

  @override
  String get addToFavorites => 'Agregar a favoritos';

  @override
  String get removeFromFavorites => 'Eliminar de favoritos';

  @override
  String get noFavorites =>
      'Marca las opciones del menú para añadirlas a tus favoritos';

  @override
  String get globalSearch => 'Búsqueda global';

  @override
  String get selectMenuEntry => 'Elija una entrada del menú';

  @override
  String get selectColor => 'Seleccione un color';

  @override
  String get addValue => 'Añadir un valor';

  @override
  String get translate => 'Traducir';

  @override
  String get saveBeforeTranslate =>
      'Debe guardar el registro antes de añadir traducciones.';

  @override
  String get noOtherLanguage => 'No hay otro idioma disponible.';

  @override
  String get edit => 'Editar';

  @override
  String get fuzzy => 'Aproximada';

  @override
  String get columns => 'Columnas';

  @override
  String get resetColumnWidths => 'Restablecer anchos de columna';

  @override
  String get copySelectedRows => 'Copiar filas seleccionadas';

  @override
  String get notifications => 'Notificaciones';

  @override
  String get noNotifications => 'No hay notificaciones en este momento';

  @override
  String get allNotifications => 'Todas las notificaciones…';

  @override
  String get closeAllTabsQuestion =>
      'La siguiente acción requiere cerrar todas las pestañas.\n¿Desea continuar?';

  @override
  String get editUserPreferences => 'Editar preferencias de usuario';

  @override
  String get saveAs => 'Guardar como…';

  @override
  String get selectFile => 'Seleccionar…';

  @override
  String get clear => 'Limpiar';

  @override
  String get openFile => 'Abrir…';

  @override
  String attachmentsOf(Object name) {
    return 'Adjuntos ($name)';
  }

  @override
  String notesOf(Object name) {
    return 'Notas ($name)';
  }

  @override
  String logsOf(Object name) {
    return 'Registros ($name)';
  }

  @override
  String attachmentCount(Object count) {
    return 'Adjuntos ($count)';
  }

  @override
  String get addFiles => 'Añadir…';

  @override
  String get manage => 'Gestionar…';

  @override
  String get logModel => 'Modelo';

  @override
  String get logModule => 'Módulo';

  @override
  String get logXmlId => 'ID XML';

  @override
  String get logCreatedBy => 'Creado por';

  @override
  String get logCreatedAt => 'Creado el';

  @override
  String get logModifiedBy => 'Última modificación por';

  @override
  String get logModifiedAt => 'Última modificación el';

  @override
  String get exportData => 'Exportar datos…';

  @override
  String get importData => 'Importar datos…';

  @override
  String csvExportTitle(Object name) {
    return 'Exportación CSV: $name';
  }

  @override
  String csvImportTitle(Object name) {
    return 'Importación CSV: $name';
  }

  @override
  String get csvAllFields => 'Todos los campos';

  @override
  String get csvFieldsSelected => 'Campos seleccionados';

  @override
  String get csvRemoveAll => 'Limpiar';

  @override
  String get csvParameters => 'Parámetros CSV';

  @override
  String get csvDelimiter => 'Separador';

  @override
  String get csvQuoteChar => 'Delimitador de texto';

  @override
  String get csvEncoding => 'Codificación';

  @override
  String get csvLocaleFormat => 'Usar formato local';

  @override
  String get csvAddFieldNames => 'Añadir nombres de campo';

  @override
  String get csvListedRecords => 'Registros listados';

  @override
  String get csvSelectedRecords => 'Registros seleccionados';

  @override
  String get csvIgnoreSearchLimit => 'Ignorar límite de búsqueda';

  @override
  String get csvPredefinedExports => 'Exportaciones predefinidas';

  @override
  String get csvSaveExport => 'Guardar exportación';

  @override
  String get csvDeleteExport => 'Eliminar exportación';

  @override
  String get csvExportName => '¿Cuál es el nombre de esta exportación?';

  @override
  String csvOverrideExport(Object name) {
    return '¿Sobrescribir la definición de \'$name\'?';
  }

  @override
  String csvRecordsSaved(Object count) {
    return 'Registros guardados: $count';
  }

  @override
  String get csvExportFailed => 'Ha fallado la exportación';

  @override
  String get csvFileToImport => 'Archivo a importar';

  @override
  String get csvLinesToSkip => 'Líneas a omitir';

  @override
  String get csvAutoDetect => 'Auto-detectar';

  @override
  String get csvImport => 'Importar';

  @override
  String get csvSelectImportFile =>
      'Primero debe elegir un archivo a importar.';

  @override
  String csvUnknownHeader(Object name) {
    return 'Cabecera de columna desconocida: \"$name\"';
  }

  @override
  String get csvDetectionFailed => 'Ha fallado la detección';

  @override
  String csvRecordsImported(Object count) {
    return 'Registros importados: $count';
  }

  @override
  String get csvImportFailed => 'Ha fallado la importación';

  @override
  String csvFieldString(Object name) {
    return '$name (cadena)';
  }

  @override
  String csvFieldModelName(Object name) {
    return '$name (nombre del modelo)';
  }

  @override
  String csvFieldRecordName(Object name) {
    return '$name/Nombre del registro';
  }

  @override
  String get open => 'Abrir';

  @override
  String get recordMenu => 'Menú del registro';

  @override
  String get menuSwitchView => 'Cambiar de vista';

  @override
  String get menuPrevious => 'Anterior';

  @override
  String get menuNext => 'Siguiente';

  @override
  String get menuSearch => 'Buscar';

  @override
  String get menuNew => 'Nuevo';

  @override
  String get menuSave => 'Guardar';

  @override
  String get menuReload => 'Recargar/Deshacer';

  @override
  String get menuDuplicate => 'Duplicar';

  @override
  String get menuDelete => 'Eliminar…';

  @override
  String get menuLogs => 'Ver registros…';

  @override
  String get menuRevisions => 'Mostrar revisiones…';

  @override
  String get menuAttachments => 'Adjuntos…';

  @override
  String get menuNotes => 'Notas…';

  @override
  String get menuActions => 'Acciones…';

  @override
  String get menuRelate => 'Relacionado…';

  @override
  String get menuReport => 'Informe…';

  @override
  String get menuEmail => 'Correo electrónico…';

  @override
  String get menuCloseTab => 'Cerrar pestaña';

  @override
  String get keyboardShortcuts => 'Atajos de teclado';

  @override
  String get shortcutsGlobal => 'Global';

  @override
  String get shortcutsForm => 'Formulario';

  @override
  String get shortcutsRelation => 'Entradas relacionadas';

  @override
  String get shortcutsList => 'Lista de entradas';

  @override
  String get shortcutsDate => 'Campos de fecha';

  @override
  String get shortcutSearchMenu => 'Menú de búsqueda';

  @override
  String get shortcutToggleMenu => 'Mostrar/ocultar menú';

  @override
  String get shortcutPreviousTab => 'Pestaña anterior';

  @override
  String get shortcutNextTab => 'Pestaña siguiente';

  @override
  String get shortcutQuit => 'Salir';

  @override
  String get shortcutRelationNew => 'Crear nueva relación';

  @override
  String get shortcutRelationOpen => 'Abrir/Buscar relación';

  @override
  String get shortcutListSwitch => 'Cambiar de vista';

  @override
  String get shortcutListNew => 'Crear/Seleccionar línea nueva';

  @override
  String get shortcutListOpen => 'Abrir relación';

  @override
  String get shortcutListDelete => 'Marcar linea para eliminar/suprimir';

  @override
  String get shortcutListRemove => 'Marcar para eliminar';

  @override
  String get shortcutListUndelete => 'Desmarcar para eliminación';

  @override
  String get shortcutDateToday => 'Hoy';

  @override
  String get shortcutDateAdd => 'Sumar segundo/minuto/hora/día/semana/mes/año';

  @override
  String get shortcutDateSubtract =>
      'Restar segundo/minuto/hora/día/semana/mes/año';

  @override
  String get keyDelete => 'Supr';

  @override
  String get keyInsert => 'Insert';

  @override
  String get ctxCopy => 'Copiar';

  @override
  String get ctxCopyRow => 'Copiar fila';

  @override
  String get ctxCopyRows => 'Copiar filas';

  @override
  String get ctxCopyColumn => 'Copiar columna';

  @override
  String get ctxPasteRows => 'Pegar filas';

  @override
  String get ctxEdit => 'Editar…';

  @override
  String get ctxPrint => 'Imprimir…';

  @override
  String get x2mCreate => 'Crear un nuevo registro';

  @override
  String get x2mEdit => 'Editar registro seleccionado';

  @override
  String get x2mDelete => 'Eliminar registro seleccionado';

  @override
  String get x2mAdd => 'Añadir un registro existente';

  @override
  String get x2mRemove => 'Eliminar registro seleccionado';

  @override
  String get x2mUndelete => 'Recuperar registro seleccionado';

  @override
  String get x2mRestore => 'Restaurar el registro seleccionado';

  @override
  String get x2mSwitch => 'Cambiar';

  @override
  String get x2mPrevious => 'Anterior';

  @override
  String get x2mNext => 'Siguiente';

  @override
  String get x2mMore => 'Más';

  @override
  String get reportBug => 'Informar del error';

  @override
  String get selectionTitle => 'Selección';

  @override
  String get yourSelection => 'Su selección:';

  @override
  String emailTitle(Object name) {
    return 'Correo electrónico $name';
  }

  @override
  String get emailTo => 'A';

  @override
  String get emailCc => 'Cc';

  @override
  String get emailBcc => 'Cco';

  @override
  String get emailSubject => 'Asunto';

  @override
  String get emailBody => 'Cuerpo';

  @override
  String get emailReports => 'Informes';

  @override
  String get emailAttachments => 'Adjuntos';

  @override
  String get emailFiles => 'Archivos';

  @override
  String get emailAddFile => 'Seleccionar un archivo';

  @override
  String get emailRemoveFile => 'Eliminar archivo';

  @override
  String get emailSend => 'Enviar';

  @override
  String get emailTemplate => 'Plantilla';

  @override
  String get emailSent => 'Correo enviado.';

  @override
  String get attachmentPreview => 'Vista previa de adjuntos';

  @override
  String get noAttachment => 'Sin adjuntos.';

  @override
  String get profile => 'Perfil';

  @override
  String get editProfiles => 'Editar perfiles…';

  @override
  String get profiles => 'Perfiles';

  @override
  String get profileName => 'Nombre del perfil';

  @override
  String get newProfile => 'Añadir un nuevo perfil';

  @override
  String get deleteProfile => 'Eliminar perfil';

  @override
  String get renameProfile => 'Renombrar';

  @override
  String get profileNameTaken => 'Este nombre de perfil ya se usa.';

  @override
  String get incompatibleServer =>
      'El cliente no es compatible con la versión del servidor.';

  @override
  String get couldNotConnect => 'No se ha podido conectar con el servidor.';

  @override
  String get copyUrl => 'Copiar la URL';

  @override
  String get urlCopied => 'URL copiada.';

  @override
  String get openTrytonUrl => 'Abrir URL de Tryton';

  @override
  String urlOtherProfile(Object target, Object profile) {
    return 'La URL pertenece a $target. ¿Iniciar sesión con el perfil \"$profile\"?';
  }

  @override
  String urlNoProfile(Object target) {
    return 'La URL pertenece a $target; no hay ningún perfil para ella.';
  }

  @override
  String get chat => 'Chat';

  @override
  String get chatInternal => 'Convierte esto en un mensaje interno';

  @override
  String get chatInternalTag => 'interno';

  @override
  String get chatFollowers => 'Mostrar seguidores';

  @override
  String get chatSubscribe => 'Suscribirse';

  @override
  String get chatUnsubscribe => 'Darse de baja';

  @override
  String get chatAddFollower => 'Añadir un seguidor';

  @override
  String chatUnsubscribeQuestion(Object name) {
    return '¿Estás seguro de que quieres dar de baja a \"$name\" de este canal?';
  }

  @override
  String get chatEmpty => 'Aún no hay mensajes.';

  @override
  String get calendarToday => 'Hoy';

  @override
  String get calendarMonth => 'Mes';

  @override
  String get calendarWeek => 'Semana';

  @override
  String get calendarDay => 'Día';

  @override
  String get scanCode => 'Escanear';

  @override
  String get codeScanner => 'Escáner de códigos';

  @override
  String get scanCodeHint => 'Código';

  @override
  String get scanCodeSound => 'Sonido';

  @override
  String get scanCodeCamera => 'Cámara';

  @override
  String get scanCodeNoCamera =>
      'No hay cámara disponible: introduzca el código o escanéelo con un lector de mano.';

  @override
  String get allTabs => 'Todas las pestañas';

  @override
  String get connectionSecure => 'Conexión cifrada (HTTPS)';

  @override
  String get connectionInsecure =>
      'Conexión sin cifrar (HTTP): la contraseña se envía en texto plano';

  @override
  String get documentation => 'Documentación…';

  @override
  String get aboutMenu => 'Acerca de…';

  @override
  String get aboutVersion => 'Versión';

  @override
  String get aboutBasedOn =>
      'Basado en el cliente de escritorio de Tryton y SAO – Copyright (C) 2004-2026 Tryton';

  @override
  String get aboutProjectPage => 'Página del proyecto';

  @override
  String get aboutCredits => 'Créditos';

  @override
  String get aboutLicense => 'Licencia';

  @override
  String get aboutCopyright => 'Copyright';

  @override
  String get aboutThirdParty => 'Licencias de terceros';

  @override
  String get aboutAuthors => 'Autores de este cliente';

  @override
  String get aboutOriginalAuthors => 'Autores del cliente Tryton (original)';

  @override
  String get aboutTranslations => 'Traducciones';

  @override
  String get aboutNoWarranty => 'Este programa no tiene ninguna garantía.';

  @override
  String aboutSeeLicense(String license) {
    return 'Consulte la $license para más detalles.';
  }

  @override
  String get aboutGplName =>
      'GNU General Public License, versión 3 o posterior';

  @override
  String get appDevelopment => 'desarrollo';

  @override
  String get appPrerelease => 'Versión de prueba';

  @override
  String get loginFailed => 'Usuario o contraseña incorrectos.';

  @override
  String get tooManyRequests =>
      'Demasiadas peticiones. Inténtelo de nuevo más tarde.';

  @override
  String get databaseNotFound => 'Base de datos no encontrada.';

  @override
  String get serverForbidden => 'El servidor no lo permite.';

  @override
  String get resetPassword => 'Restablecer contraseña';

  @override
  String get resetPasswordTooltip =>
      'Recibe un correo para restablecer tu contraseña.';

  @override
  String get resetPasswordSent =>
      'Se ha mandado una solicitud para restablecer tu contraseña.\nPor favor revisa tu buzón de correo.';

  @override
  String get resetPasswordNeedsUser =>
      'Indica primero el servidor, la base de datos y el usuario.';

  @override
  String get openReport => 'Abrir informe';

  @override
  String get printReport => 'Imprimir informe';

  @override
  String get aboutTranslationsTryton =>
      'Muchos textos de las traducciones del proyecto Tryton';
}
