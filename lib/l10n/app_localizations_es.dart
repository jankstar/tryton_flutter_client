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
  String reallyDeleteRecords(int count) {
    return '¿Eliminar $count registro(s)?';
  }

  @override
  String get noRecordsFound => 'No se encontraron registros.';

  @override
  String get createNew => 'Crear nuevo';

  @override
  String get attachments => 'Archivos adjuntos';

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
  String get launchActions => 'Ejecutar acciones';

  @override
  String get relatedRecords => 'Registros relacionados';

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
  String get reallyDelete => '¿Eliminar? Esta acción no se puede deshacer.';

  @override
  String get add => 'Agregar';

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
  String get switchView => 'Cambiar vista';

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
    return 'Versión del servidor $server incompatible (el cliente espera $client).';
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
      'Este registro ha sido modificado mientras lo editaba.\nElija:\n• «Cancelar» para cancelar el guardado;\n• «Comparar» para ver la versión modificada;\n• «Guardar de todos modos» para guardar su versión actual.';

  @override
  String get compare => 'Comparar';

  @override
  String get writeAnyway => 'Guardar de todos modos';

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
  String get applicationError => 'Error de la aplicación';

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
  String get noActionDefined => 'No hay ninguna acción definida.';

  @override
  String get preValidation => 'Validación previa';

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
  String get remove => 'Quitar';

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
  String get bookmarkFilter => 'Marcar este filtro';

  @override
  String get removeBookmark => 'Quitar marcador';

  @override
  String get bookmarks => 'Marcadores';

  @override
  String get bookmarkName => 'Nombre del marcador:';

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
  String get rangeFrom => 'Desde';

  @override
  String get rangeTo => 'Hasta';

  @override
  String get favorites => 'Favoritos';

  @override
  String get addToFavorites => 'Añadir a favoritos';

  @override
  String get removeFromFavorites => 'Quitar de favoritos';

  @override
  String get noFavorites => 'Marque entradas del menú para añadir favoritos';

  @override
  String get globalSearch => 'Búsqueda global';

  @override
  String get selectMenuEntry => 'Elija una entrada del menú';

  @override
  String get selectColor => 'Seleccionar un color';

  @override
  String get addValue => 'Añadir valor';

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
  String get editUserPreferences => 'Editar preferencias del usuario';

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
    return 'Adjunto ($count)';
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
  String get logModifiedBy => 'Modificado por';

  @override
  String get logModifiedAt => 'Modificado el';

  @override
  String get exportData => 'Exportar datos…';

  @override
  String get importData => 'Importar datos…';

  @override
  String csvExportTitle(Object name) {
    return 'Exportar CSV: $name';
  }

  @override
  String csvImportTitle(Object name) {
    return 'Importar CSV: $name';
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
  String get csvDelimiter => 'Delimitador';

  @override
  String get csvQuoteChar => 'Comilla';

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
  String get csvIgnoreSearchLimit => 'Ignorar el límite de búsqueda';

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
  String get csvExportFailed => 'La exportación falló';

  @override
  String get csvFileToImport => 'Archivo a importar';

  @override
  String get csvLinesToSkip => 'Líneas a omitir';

  @override
  String get csvAutoDetect => 'Autodetectar';

  @override
  String get csvImport => 'Importar';

  @override
  String get csvSelectImportFile =>
      'Primero debe seleccionar un archivo de importación.';

  @override
  String csvUnknownHeader(Object name) {
    return 'Cabecera de columna desconocida \"$name\"';
  }

  @override
  String get csvDetectionFailed => 'La detección falló';

  @override
  String csvRecordsImported(Object count) {
    return 'Registros importados: $count';
  }

  @override
  String get csvImportFailed => 'La importación falló';

  @override
  String csvFieldString(Object name) {
    return '$name (texto)';
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
  String get menuSwitchView => 'Cambiar vista';

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
  String get shortcutsGlobal => 'General';

  @override
  String get shortcutsForm => 'Formulario';

  @override
  String get shortcutsRelation => 'Campos de relación';

  @override
  String get shortcutsList => 'Campos de lista';

  @override
  String get shortcutsDate => 'Campos de fecha';

  @override
  String get shortcutSearchMenu => 'Buscar en el menú';

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
  String get shortcutRelationOpen => 'Abrir/buscar relación';

  @override
  String get shortcutListSwitch => 'Cambiar vista';

  @override
  String get shortcutListNew => 'Crear/seleccionar nueva línea';

  @override
  String get shortcutListOpen => 'Abrir relación';

  @override
  String get shortcutListDelete => 'Marcar línea para eliminar/quitar';

  @override
  String get shortcutListRemove => 'Marcar línea para quitar';

  @override
  String get shortcutListUndelete => 'Desmarcar línea para eliminar';

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
  String get x2mEdit => 'Editar el registro seleccionado';

  @override
  String get x2mDelete => 'Eliminar el registro seleccionado';

  @override
  String get x2mAdd => 'Añadir un registro existente';

  @override
  String get x2mRemove => 'Quitar el registro seleccionado';

  @override
  String get x2mUndelete => 'Recuperar el registro seleccionado';

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
}
