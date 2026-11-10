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
  String get selectMenuEntry => 'Escolha uma entrada do menu';

  @override
  String get selectColor => 'Selecionar uma cor';

  @override
  String get addValue => 'Adicionar valor';

  @override
  String get translate => 'Traduzir';

  @override
  String get saveBeforeTranslate =>
      'Você precisa salvar o registro antes de adicionar traduções.';

  @override
  String get noOtherLanguage => 'Nenhum outro idioma disponível.';

  @override
  String get edit => 'Editar';

  @override
  String get fuzzy => 'Aproximada';

  @override
  String get columns => 'Colunas';

  @override
  String get resetColumnWidths => 'Redefinir larguras das colunas';

  @override
  String get copySelectedRows => 'Copiar linhas selecionadas';

  @override
  String get notifications => 'Notificações';

  @override
  String get noNotifications => 'Nenhuma notificação no momento';

  @override
  String get allNotifications => 'Todas as notificações…';

  @override
  String get closeAllTabsQuestion =>
      'A ação seguinte requer o fechamento de todas as abas.\nDeseja continuar?';

  @override
  String get editUserPreferences => 'Editar preferências do usuário';

  @override
  String get saveAs => 'Salvar como…';

  @override
  String get selectFile => 'Selecionar…';

  @override
  String get clear => 'Limpar';

  @override
  String get openFile => 'Abrir…';

  @override
  String attachmentsOf(Object name) {
    return 'Anexos ($name)';
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
    return 'Anexo ($count)';
  }

  @override
  String get addFiles => 'Adicionar…';

  @override
  String get manage => 'Gerenciar…';

  @override
  String get logModel => 'Modelo';

  @override
  String get logModule => 'Módulo';

  @override
  String get logXmlId => 'ID XML';

  @override
  String get logCreatedBy => 'Criado por';

  @override
  String get logCreatedAt => 'Criado em';

  @override
  String get logModifiedBy => 'Modificado por';

  @override
  String get logModifiedAt => 'Modificado em';

  @override
  String get exportData => 'Exportar dados…';

  @override
  String get importData => 'Importar dados…';

  @override
  String csvExportTitle(Object name) {
    return 'Exportar CSV: $name';
  }

  @override
  String csvImportTitle(Object name) {
    return 'Importar CSV: $name';
  }

  @override
  String get csvAllFields => 'Todos os campos';

  @override
  String get csvFieldsSelected => 'Campos selecionados';

  @override
  String get csvRemoveAll => 'Limpar';

  @override
  String get csvParameters => 'Parâmetros CSV';

  @override
  String get csvDelimiter => 'Delimitador';

  @override
  String get csvQuoteChar => 'Aspas';

  @override
  String get csvEncoding => 'Codificação';

  @override
  String get csvLocaleFormat => 'Usar formato local';

  @override
  String get csvAddFieldNames => 'Adicionar nomes dos campos';

  @override
  String get csvListedRecords => 'Registros listados';

  @override
  String get csvSelectedRecords => 'Registros selecionados';

  @override
  String get csvIgnoreSearchLimit => 'Ignorar limite de pesquisa';

  @override
  String get csvPredefinedExports => 'Exportações predefinidas';

  @override
  String get csvSaveExport => 'Salvar exportação';

  @override
  String get csvDeleteExport => 'Excluir exportação';

  @override
  String get csvExportName => 'Qual é o nome desta exportação?';

  @override
  String csvOverrideExport(Object name) {
    return 'Substituir a definição de \'$name\'?';
  }

  @override
  String csvRecordsSaved(Object count) {
    return 'Registros salvos: $count';
  }

  @override
  String get csvExportFailed => 'Falha na exportação';

  @override
  String get csvFileToImport => 'Arquivo a importar';

  @override
  String get csvLinesToSkip => 'Linhas a ignorar';

  @override
  String get csvAutoDetect => 'Detectar automaticamente';

  @override
  String get csvImport => 'Importar';

  @override
  String get csvSelectImportFile =>
      'Selecione primeiro um arquivo de importação.';

  @override
  String csvUnknownHeader(Object name) {
    return 'Cabeçalho de coluna desconhecido \"$name\"';
  }

  @override
  String get csvDetectionFailed => 'Falha na detecção';

  @override
  String csvRecordsImported(Object count) {
    return 'Registros importados: $count';
  }

  @override
  String get csvImportFailed => 'Falha na importação';

  @override
  String csvFieldString(Object name) {
    return '$name (texto)';
  }

  @override
  String csvFieldModelName(Object name) {
    return '$name (nome do modelo)';
  }

  @override
  String csvFieldRecordName(Object name) {
    return '$name/Nome do registro';
  }

  @override
  String get open => 'Abrir';

  @override
  String get recordMenu => 'Menu do registro';

  @override
  String get menuSwitchView => 'Alternar visualização';

  @override
  String get menuPrevious => 'Anterior';

  @override
  String get menuNext => 'Próximo';

  @override
  String get menuSearch => 'Pesquisar';

  @override
  String get menuNew => 'Novo';

  @override
  String get menuSave => 'Salvar';

  @override
  String get menuReload => 'Recarregar/Desfazer';

  @override
  String get menuDuplicate => 'Duplicar';

  @override
  String get menuDelete => 'Excluir…';

  @override
  String get menuLogs => 'Ver registros…';

  @override
  String get menuRevisions => 'Mostrar revisões…';

  @override
  String get menuAttachments => 'Anexos…';

  @override
  String get menuNotes => 'Notas…';

  @override
  String get menuActions => 'Ações…';

  @override
  String get menuRelate => 'Relacionados…';

  @override
  String get menuReport => 'Relatório…';

  @override
  String get menuEmail => 'E-mail…';

  @override
  String get menuCloseTab => 'Fechar aba';

  @override
  String get keyboardShortcuts => 'Atalhos de teclado';

  @override
  String get shortcutsGlobal => 'Geral';

  @override
  String get shortcutsForm => 'Formulário';

  @override
  String get shortcutsRelation => 'Campos de relação';

  @override
  String get shortcutsList => 'Campos de lista';

  @override
  String get shortcutsDate => 'Campos de data';

  @override
  String get shortcutSearchMenu => 'Pesquisar no menu';

  @override
  String get shortcutToggleMenu => 'Mostrar/ocultar menu';

  @override
  String get shortcutPreviousTab => 'Aba anterior';

  @override
  String get shortcutNextTab => 'Próxima aba';

  @override
  String get shortcutQuit => 'Sair';

  @override
  String get shortcutRelationNew => 'Criar nova relação';

  @override
  String get shortcutRelationOpen => 'Abrir/pesquisar relação';

  @override
  String get shortcutListSwitch => 'Alternar visualização';

  @override
  String get shortcutListNew => 'Criar/selecionar nova linha';

  @override
  String get shortcutListOpen => 'Abrir relação';

  @override
  String get shortcutListDelete => 'Marcar linha para exclusão/remoção';

  @override
  String get shortcutListRemove => 'Marcar linha para remoção';

  @override
  String get shortcutListUndelete => 'Desmarcar exclusão da linha';

  @override
  String get shortcutDateToday => 'Hoje';

  @override
  String get shortcutDateAdd => 'Somar segundo/minuto/hora/dia/semana/mês/ano';

  @override
  String get shortcutDateSubtract =>
      'Subtrair segundo/minuto/hora/dia/semana/mês/ano';

  @override
  String get keyDelete => 'Delete';

  @override
  String get keyInsert => 'Insert';

  @override
  String get ctxCopy => 'Copiar';

  @override
  String get ctxCopyRow => 'Copiar linha';

  @override
  String get ctxCopyRows => 'Copiar linhas';

  @override
  String get ctxCopyColumn => 'Copiar coluna';

  @override
  String get ctxPasteRows => 'Colar linhas';

  @override
  String get ctxEdit => 'Editar…';

  @override
  String get ctxPrint => 'Imprimir…';

  @override
  String get x2mCreate => 'Criar um novo registro';

  @override
  String get x2mEdit => 'Editar o registro selecionado';

  @override
  String get x2mDelete => 'Excluir o registro selecionado';

  @override
  String get x2mAdd => 'Adicionar registro existente';

  @override
  String get x2mRemove => 'Remover o registro selecionado';

  @override
  String get x2mUndelete => 'Restaurar o registro selecionado';

  @override
  String get x2mRestore => 'Restaurar o registro selecionado';

  @override
  String get x2mSwitch => 'Alternar';

  @override
  String get x2mPrevious => 'Anterior';

  @override
  String get x2mNext => 'Próximo';

  @override
  String get x2mMore => 'Mais';

  @override
  String get reportBug => 'Relatar erro';

  @override
  String get selectionTitle => 'Seleção';

  @override
  String get yourSelection => 'Sua seleção:';

  @override
  String emailTitle(Object name) {
    return 'E-mail $name';
  }

  @override
  String get emailTo => 'Para';

  @override
  String get emailCc => 'Cc';

  @override
  String get emailBcc => 'Cco';

  @override
  String get emailSubject => 'Assunto';

  @override
  String get emailBody => 'Corpo';

  @override
  String get emailReports => 'Relatórios';

  @override
  String get emailAttachments => 'Anexos';

  @override
  String get emailFiles => 'Arquivos';

  @override
  String get emailAddFile => 'Selecionar arquivo';

  @override
  String get emailRemoveFile => 'Remover arquivo';

  @override
  String get emailSend => 'Enviar';

  @override
  String get emailTemplate => 'Modelo';

  @override
  String get emailSent => 'E-mail enviado.';

  @override
  String get attachmentPreview => 'Pré-visualização do anexo';

  @override
  String get noAttachment => 'Nenhum anexo.';

  @override
  String get profile => 'Perfil';

  @override
  String get editProfiles => 'Editar perfis…';

  @override
  String get profiles => 'Perfis';

  @override
  String get profileName => 'Nome do perfil';

  @override
  String get newProfile => 'Novo perfil';

  @override
  String get deleteProfile => 'Excluir perfil';

  @override
  String get renameProfile => 'Renomear';

  @override
  String get profileNameTaken => 'Este nome de perfil já está em uso.';

  @override
  String get incompatibleServer => 'Versão do servidor incompatível.';

  @override
  String get couldNotConnect => 'Não foi possível conectar ao servidor.';

  @override
  String get copyUrl => 'Copiar URL';

  @override
  String get urlCopied => 'URL copiada.';

  @override
  String get openTrytonUrl => 'Abrir URL do Tryton';

  @override
  String urlOtherProfile(Object target, Object profile) {
    return 'A URL pertence a $target. Entrar com o perfil \"$profile\"?';
  }

  @override
  String urlNoProfile(Object target) {
    return 'A URL pertence a $target; não há perfil para ela.';
  }

  @override
  String get chat => 'Chat';

  @override
  String get chatInternal => 'Tornar esta uma mensagem interna';

  @override
  String get chatInternalTag => 'interna';

  @override
  String get chatFollowers => 'Mostrar seguidores';

  @override
  String get chatSubscribe => 'Inscrever-se';

  @override
  String get chatUnsubscribe => 'Cancelar inscrição';

  @override
  String get chatAddFollower => 'Adicionar seguidor';

  @override
  String chatUnsubscribeQuestion(Object name) {
    return 'Tem certeza de cancelar a inscrição de \"$name\" neste canal?';
  }

  @override
  String get chatEmpty => 'Ainda não há mensagens.';

  @override
  String get calendarToday => 'Hoje';

  @override
  String get calendarMonth => 'Mês';

  @override
  String get calendarWeek => 'Semana';

  @override
  String get calendarDay => 'Dia';

  @override
  String get scanCode => 'Digitalizar';

  @override
  String get codeScanner => 'Leitor de códigos';

  @override
  String get scanCodeHint => 'Código';

  @override
  String get scanCodeSound => 'Som';

  @override
  String get scanCodeCamera => 'Câmera';

  @override
  String get scanCodeNoCamera =>
      'Nenhuma câmera disponível – digite o código ou leia-o com um leitor manual.';

  @override
  String get allTabs => 'Todas as abas';

  @override
  String get connectionSecure => 'Conexão criptografada (HTTPS)';

  @override
  String get connectionInsecure =>
      'Conexão não criptografada (HTTP) – a senha é enviada em texto simples';
}
