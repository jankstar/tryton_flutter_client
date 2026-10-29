// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'Tryton Flutter Client';

  @override
  String get appSubtitle => 'Cliente ERP Tryton';

  @override
  String get username => 'Nome de utilizador';

  @override
  String get password => 'Palavra-passe';

  @override
  String get database => 'Base de dados';

  @override
  String get serverUrl => 'URL do servidor';

  @override
  String get required => 'Obrigatório';

  @override
  String get signIn => 'Entrar';

  @override
  String get signOut => 'Sair';

  @override
  String get loadDatabases => 'Carregar bases de dados';

  @override
  String get additionalInputRequired => 'Entrada adicional necessária';

  @override
  String get reloadMenu => 'Recarregar menu';

  @override
  String get noMenuEntriesFound => 'Nenhuma entrada de menu encontrada.';

  @override
  String get retry => 'Tentar novamente';

  @override
  String get error => 'Erro';

  @override
  String get search => 'Pesquisar…';

  @override
  String selected(int count) {
    return '$count selecionado(s)';
  }

  @override
  String get deleteRecords => 'Eliminar registos';

  @override
  String reallyDeleteRecords(int count) {
    return 'Eliminar $count registo(s)?';
  }

  @override
  String get noRecordsFound => 'Nenhum registo encontrado.';

  @override
  String get createNew => 'Criar novo';

  @override
  String get attachments => 'Anexos';

  @override
  String get duplicate => 'Duplicar';

  @override
  String get openEdit => 'Abrir / Editar';

  @override
  String get reload => 'Recarregar';

  @override
  String get delete => 'Eliminar';

  @override
  String get moreActions => 'Mais ações';

  @override
  String get launchActions => 'Executar ações';

  @override
  String get relatedRecords => 'Registos relacionados';

  @override
  String get reports => 'Relatórios';

  @override
  String get email => 'E-mail';

  @override
  String get save => 'Guardar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get recordCreated => 'Registo criado.';

  @override
  String get saved => 'Guardado.';

  @override
  String get deleteRecord => 'Eliminar registo';

  @override
  String get reallyDelete => 'Eliminar? Esta ação não pode ser desfeita.';

  @override
  String get add => 'Adicionar';

  @override
  String get noEntries => 'Sem entradas.';

  @override
  String get apply => 'Aplicar';

  @override
  String get openRecord => 'Abrir registo';

  @override
  String get clearField => 'Limpar campo';

  @override
  String get searchRecord => 'Pesquisar registo';

  @override
  String entries(int count) {
    return '$count entradas';
  }

  @override
  String get generatingReport => 'A gerar relatório…';

  @override
  String reportGenerated(String name, String format) {
    return 'Relatório \"$name\" ($format) gerado.';
  }

  @override
  String actionNotSupported(String name, String type) {
    return '\"$name\" ($type) ainda não é suportado.';
  }

  @override
  String executingButton(String name) {
    return 'A executar botão \"$name\"…';
  }

  @override
  String get language => 'Idioma';

  @override
  String get sessionExpired => 'Sessão expirada';

  @override
  String get preferences => 'Preferências';

  @override
  String get help => 'Ajuda';

  @override
  String get collapse => 'Recolher';

  @override
  String get expand => 'Expandir';

  @override
  String get openInForm => 'Abrir no formulário';

  @override
  String get undelete => 'Recuperar';

  @override
  String get switchToForm => 'Alternar para formulário';

  @override
  String get switchView => 'Alternar visualização';

  @override
  String get close => 'Fechar';

  @override
  String get boolYes => 'Sim';

  @override
  String get boolNo => 'Não';

  @override
  String get clearSearch => 'Limpar';

  @override
  String get previousRecord => 'Anterior';

  @override
  String get nextRecord => 'Próximo';

  @override
  String get viewLogs => 'Ver registros';

  @override
  String get note => 'Nota';

  @override
  String get wizard => 'Assistente';

  @override
  String versionMismatch(String server, String client) {
    return 'Versão do servidor $server incompatível (cliente espera $client).';
  }

  @override
  String get recordModified =>
      'Este registro foi modificado.\nDeseja salvá-lo?';

  @override
  String get yes => 'Sim';

  @override
  String get no => 'Não';

  @override
  String get concurrencyWarning => 'Aviso de concorrência';

  @override
  String get concurrencyMessage =>
      'Este registo foi modificado enquanto o editava.\nEscolha:\n• \"Cancelar\" para cancelar a gravação;\n• \"Comparar\" para ver a versão modificada;\n• \"Gravar mesmo assim\" para guardar a sua versão atual.';

  @override
  String get compare => 'Comparar';

  @override
  String get writeAnyway => 'Gravar mesmo assim';

  @override
  String get concurrencyException => 'Exceção de concorrência';

  @override
  String compareTabTitle(String name) {
    return 'Comparar: $name';
  }

  @override
  String get fieldNotSupported => 'Ainda não suportado';

  @override
  String get ok => 'OK';

  @override
  String get alwaysIgnore => 'Ignorar sempre';

  @override
  String get applicationError => 'Erro da aplicação';

  @override
  String get details => 'Detalhes';

  @override
  String httpError(int code, String text) {
    return 'Erro: \"[$code] $text\". Tente novamente mais tarde.';
  }

  @override
  String networkError(String details) {
    return 'Não é possível contactar o servidor. $details';
  }

  @override
  String invalidRequired(String field) {
    return '\"$field\" é obrigatório.';
  }

  @override
  String invalidDomain(String field) {
    return '\"$field\" não é válido de acordo com o domínio.';
  }

  @override
  String invalidChildren(String field) {
    return 'Os valores de \"$field\" não são válidos.';
  }

  @override
  String get invalidRecordTitle => 'Registo não válido';

  @override
  String get selectAction => 'Selecione sua ação';

  @override
  String get noActionDefined => 'Nenhuma ação definida.';

  @override
  String get preValidation => 'Pré-validação';

  @override
  String buttonClickedBy(String users) {
    return 'Por: $users';
  }

  @override
  String get discardChanges => 'Descartar alterações';

  @override
  String get saveAndNew => 'Salvar e novo';

  @override
  String get addAndNew => 'Adicionar e novo';

  @override
  String get applyChanges => 'Aplicar alterações';

  @override
  String get find => 'Procurar';

  @override
  String get remove => 'Remover';

  @override
  String get searchMenu => 'Procurar…';

  @override
  String get createMenu => 'Criar…';

  @override
  String searchTitle(String title) {
    return 'Procurar $title';
  }

  @override
  String createNamed(String name) {
    return 'Criar \"$name\"…';
  }

  @override
  String get revisions => 'Revisões…';

  @override
  String get currentRevision => 'Atual';

  @override
  String get selectRevision => 'Selecione uma revisão';

  @override
  String get filters => 'Filtros';

  @override
  String get bookmarkFilter => 'Favoritar este filtro';

  @override
  String get removeBookmark => 'Remover favorito';

  @override
  String get bookmarks => 'Favoritos';

  @override
  String get bookmarkName => 'Nome do favorito:';

  @override
  String get showInactive => 'Mostrar registros inativos';

  @override
  String get showActive => 'Mostrar registros ativos';

  @override
  String get fieldId => 'ID';

  @override
  String get createdBy => 'Criado por';

  @override
  String get createdAt => 'Criado em';

  @override
  String get modifiedBy => 'Modificado por';

  @override
  String get modifiedAt => 'Modificado em';

  @override
  String get rangeFrom => 'De';

  @override
  String get rangeTo => 'Até';

  @override
  String get favorites => 'Favoritos';

  @override
  String get addToFavorites => 'Adicionar aos favoritos';

  @override
  String get removeFromFavorites => 'Remover dos favoritos';

  @override
  String get noFavorites => 'Marque entradas do menu para adicionar favoritos';

  @override
  String get globalSearch => 'Pesquisa global';

  @override
  String get boardNotSupported => 'Painéis ainda não são suportados.';

  @override
  String get selectMenuEntry => 'Escolha uma entrada do menu';
}
