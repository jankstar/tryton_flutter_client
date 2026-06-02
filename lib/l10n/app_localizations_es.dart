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
}
