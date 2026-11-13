// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Tryton Flutter Client';

  @override
  String get appSubtitle => 'Client ERP Tryton';

  @override
  String get username => 'Nom d\'utilisateur';

  @override
  String get password => 'Mot de passe';

  @override
  String get database => 'Base de données';

  @override
  String get serverUrl => 'URL du serveur';

  @override
  String get required => 'Obligatoire';

  @override
  String get signIn => 'Se connecter';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get loadDatabases => 'Charger les bases de données';

  @override
  String get additionalInputRequired => 'Saisie supplémentaire requise';

  @override
  String get reloadMenu => 'Recharger le menu';

  @override
  String get noMenuEntriesFound => 'Aucune entrée de menu trouvée.';

  @override
  String get retry => 'Réessayer';

  @override
  String get error => 'Erreur';

  @override
  String get search => 'Rechercher…';

  @override
  String selected(int count) {
    return '$count sélectionné(s)';
  }

  @override
  String get deleteRecords => 'Supprimer les enregistrements';

  @override
  String reallyDeleteRecords(int count) {
    return 'Supprimer $count enregistrement(s) ?';
  }

  @override
  String get noRecordsFound => 'Aucun enregistrement trouvé.';

  @override
  String get createNew => 'Créer nouveau';

  @override
  String get attachments => 'Pièces jointes';

  @override
  String get duplicate => 'Dupliquer';

  @override
  String get openEdit => 'Ouvrir / Modifier';

  @override
  String get reload => 'Recharger';

  @override
  String get delete => 'Supprimer';

  @override
  String get moreActions => 'Plus d\'actions';

  @override
  String get launchActions => 'Lancer des actions';

  @override
  String get relatedRecords => 'Enregistrements liés';

  @override
  String get reports => 'Rapports';

  @override
  String get email => 'E-mail';

  @override
  String get save => 'Enregistrer';

  @override
  String get cancel => 'Annuler';

  @override
  String get recordCreated => 'Enregistrement créé.';

  @override
  String get saved => 'Enregistré.';

  @override
  String get deleteRecord => 'Supprimer l\'enregistrement';

  @override
  String get reallyDelete =>
      'Confirmer la suppression ? Cette action est irréversible.';

  @override
  String get add => 'Ajouter';

  @override
  String get noEntries => 'Aucune entrée.';

  @override
  String get apply => 'Appliquer';

  @override
  String get openRecord => 'Ouvrir l\'enregistrement';

  @override
  String get clearField => 'Vider le champ';

  @override
  String get searchRecord => 'Rechercher un enregistrement';

  @override
  String entries(int count) {
    return '$count entrée(s)';
  }

  @override
  String get generatingReport => 'Génération du rapport…';

  @override
  String reportGenerated(String name, String format) {
    return 'Rapport \"$name\" ($format) généré.';
  }

  @override
  String actionNotSupported(String name, String type) {
    return '\"$name\" ($type) n\'est pas encore pris en charge.';
  }

  @override
  String executingButton(String name) {
    return 'Exécution du bouton \"$name\"…';
  }

  @override
  String get language => 'Langue';

  @override
  String get sessionExpired => 'Session expirée';

  @override
  String get preferences => 'Préférences';

  @override
  String get help => 'Aide';

  @override
  String get collapse => 'Réduire';

  @override
  String get expand => 'Développer';

  @override
  String get openInForm => 'Ouvrir dans le formulaire';

  @override
  String get undelete => 'Restaurer';

  @override
  String get switchToForm => 'Basculer vers le formulaire';

  @override
  String get switchView => 'Changer de vue';

  @override
  String get close => 'Fermer';

  @override
  String get boolYes => 'Oui';

  @override
  String get boolNo => 'Non';

  @override
  String get clearSearch => 'Effacer';

  @override
  String get previousRecord => 'Précédent';

  @override
  String get nextRecord => 'Suivant';

  @override
  String get viewLogs => 'Voir les journaux';

  @override
  String get note => 'Note';

  @override
  String get wizard => 'Assistant';

  @override
  String versionMismatch(String server, String client) {
    return 'Version du serveur incompatible. Serveur $server, client $client.';
  }

  @override
  String get recordModified =>
      'Cet enregistrement a été modifié.\nVoulez-vous l\'enregistrer?';

  @override
  String get yes => 'Oui';

  @override
  String get no => 'Non';

  @override
  String get concurrencyWarning => 'Avertissement d\'accès concurrent';

  @override
  String get concurrencyMessage =>
      'Cet enregistrement a été modifié pendant que vous l\'éditiez.\nChoisissez :\n• « Annuler » pour annuler l\'enregistrement ;\n• « Comparer » pour voir la version modifiée ;\n• « Écrire quand même » pour enregistrer votre version actuelle.';

  @override
  String get compare => 'Comparer';

  @override
  String get writeAnyway => 'Écrire quand même';

  @override
  String get concurrencyException => 'Exception d\'accès concurrent';

  @override
  String compareTabTitle(String name) {
    return 'Comparer : $name';
  }

  @override
  String get fieldNotSupported => 'Pas encore pris en charge';

  @override
  String get ok => 'OK';

  @override
  String get alwaysIgnore => 'Toujours ignorer';

  @override
  String get applicationError => 'Erreur de l\'application';

  @override
  String get details => 'Détails';

  @override
  String httpError(int code, String text) {
    return 'Erreur : « [$code] $text ». Réessayez plus tard.';
  }

  @override
  String networkError(String details) {
    return 'Impossible de joindre le serveur. $details';
  }

  @override
  String invalidRequired(String field) {
    return '« $field » est obligatoire.';
  }

  @override
  String invalidDomain(String field) {
    return '« $field » n\'est pas valide selon son domaine.';
  }

  @override
  String invalidChildren(String field) {
    return 'Les valeurs de « $field » ne sont pas valides.';
  }

  @override
  String get invalidRecordTitle => 'Enregistrement non valide';

  @override
  String get selectAction => 'Sélectionnez votre action';

  @override
  String get noActionDefined => 'Aucune action définie.';

  @override
  String get preValidation => 'Pré-validation';

  @override
  String buttonClickedBy(String users) {
    return 'Par : $users';
  }

  @override
  String get discardChanges => 'Annuler les modifications';

  @override
  String get saveAndNew => 'Enregistrer et nouveau';

  @override
  String get addAndNew => 'Ajouter et nouveau';

  @override
  String get applyChanges => 'Appliquer les modifications';

  @override
  String get find => 'Rechercher';

  @override
  String get remove => 'Retirer';

  @override
  String get searchMenu => 'Rechercher…';

  @override
  String get createMenu => 'Créer…';

  @override
  String searchTitle(String title) {
    return 'Rechercher $title';
  }

  @override
  String createNamed(String name) {
    return 'Créer « $name »…';
  }

  @override
  String get revisions => 'Révisions…';

  @override
  String get currentRevision => 'Actuelle';

  @override
  String get selectRevision => 'Sélectionnez une révision';

  @override
  String get filters => 'Filtres';

  @override
  String get bookmarkFilter => 'Ajouter ce filtre aux favoris';

  @override
  String get removeBookmark => 'Supprimer ce favori';

  @override
  String get bookmarks => 'Favoris';

  @override
  String get bookmarkName => 'Nom du favori :';

  @override
  String get showInactive => 'Afficher les enregistrements inactifs';

  @override
  String get showActive => 'Afficher les enregistrements actifs';

  @override
  String get fieldId => 'ID';

  @override
  String get createdBy => 'Créé par';

  @override
  String get createdAt => 'Créé le';

  @override
  String get modifiedBy => 'Modifié par';

  @override
  String get modifiedAt => 'Modifié le';

  @override
  String get rangeFrom => 'De';

  @override
  String get rangeTo => 'À';

  @override
  String get favorites => 'Favoris';

  @override
  String get addToFavorites => 'Ajouter aux favoris';

  @override
  String get removeFromFavorites => 'Retirer des favoris';

  @override
  String get noFavorites =>
      'Cochez des entrées du menu pour ajouter des favoris';

  @override
  String get globalSearch => 'Recherche globale';

  @override
  String get selectMenuEntry => 'Choisissez une entrée de menu';

  @override
  String get selectColor => 'Choisir une couleur';

  @override
  String get addValue => 'Ajouter une valeur';

  @override
  String get translate => 'Traduire';

  @override
  String get saveBeforeTranslate =>
      'Vous devez enregistrer l\'enregistrement avant d\'ajouter des traductions.';

  @override
  String get noOtherLanguage => 'Aucune autre langue disponible.';

  @override
  String get edit => 'Modifier';

  @override
  String get fuzzy => 'Approximative';

  @override
  String get columns => 'Colonnes';

  @override
  String get resetColumnWidths => 'Réinitialiser la largeur des colonnes';

  @override
  String get copySelectedRows => 'Copier les lignes sélectionnées';

  @override
  String get notifications => 'Notifications';

  @override
  String get noNotifications => 'Aucune notification pour le moment';

  @override
  String get allNotifications => 'Toutes les notifications…';

  @override
  String get closeAllTabsQuestion =>
      'Cette action nécessite de fermer tous les onglets.\nVoulez-vous continuer ?';

  @override
  String get editUserPreferences => 'Modifier les préférences utilisateur';

  @override
  String get saveAs => 'Enregistrer sous…';

  @override
  String get selectFile => 'Sélectionner…';

  @override
  String get clear => 'Effacer';

  @override
  String get openFile => 'Ouvrir…';

  @override
  String attachmentsOf(Object name) {
    return 'Pièces jointes ($name)';
  }

  @override
  String notesOf(Object name) {
    return 'Notes ($name)';
  }

  @override
  String logsOf(Object name) {
    return 'Journaux ($name)';
  }

  @override
  String attachmentCount(Object count) {
    return 'Pièce jointe ($count)';
  }

  @override
  String get addFiles => 'Ajouter…';

  @override
  String get manage => 'Gérer…';

  @override
  String get logModel => 'Modèle';

  @override
  String get logModule => 'Module';

  @override
  String get logXmlId => 'ID XML';

  @override
  String get logCreatedBy => 'Créé par';

  @override
  String get logCreatedAt => 'Créé le';

  @override
  String get logModifiedBy => 'Modifié par';

  @override
  String get logModifiedAt => 'Modifié le';

  @override
  String get exportData => 'Exporter les données…';

  @override
  String get importData => 'Importer des données…';

  @override
  String csvExportTitle(Object name) {
    return 'Export CSV : $name';
  }

  @override
  String csvImportTitle(Object name) {
    return 'Import CSV : $name';
  }

  @override
  String get csvAllFields => 'Tous les champs';

  @override
  String get csvFieldsSelected => 'Champs sélectionnés';

  @override
  String get csvRemoveAll => 'Effacer';

  @override
  String get csvParameters => 'Paramètres CSV';

  @override
  String get csvDelimiter => 'Séparateur';

  @override
  String get csvQuoteChar => 'Guillemet';

  @override
  String get csvEncoding => 'Encodage';

  @override
  String get csvLocaleFormat => 'Utiliser le format local';

  @override
  String get csvAddFieldNames => 'Ajouter les noms des champs';

  @override
  String get csvListedRecords => 'Enregistrements listés';

  @override
  String get csvSelectedRecords => 'Enregistrements sélectionnés';

  @override
  String get csvIgnoreSearchLimit => 'Ignorer la limite de recherche';

  @override
  String get csvPredefinedExports => 'Exports prédéfinis';

  @override
  String get csvSaveExport => 'Enregistrer l\'export';

  @override
  String get csvDeleteExport => 'Supprimer l\'export';

  @override
  String get csvExportName => 'Quel est le nom de cet export ?';

  @override
  String csvOverrideExport(Object name) {
    return 'Écraser la définition de « $name » ?';
  }

  @override
  String csvRecordsSaved(Object count) {
    return 'Enregistrements sauvegardés : $count';
  }

  @override
  String get csvExportFailed => 'Échec de l\'export';

  @override
  String get csvFileToImport => 'Fichier à importer';

  @override
  String get csvLinesToSkip => 'Lignes à ignorer';

  @override
  String get csvAutoDetect => 'Détection automatique';

  @override
  String get csvImport => 'Importer';

  @override
  String get csvSelectImportFile =>
      'Vous devez d\'abord sélectionner un fichier à importer.';

  @override
  String csvUnknownHeader(Object name) {
    return 'En-tête de colonne inconnu « $name »';
  }

  @override
  String get csvDetectionFailed => 'Échec de la détection';

  @override
  String csvRecordsImported(Object count) {
    return 'Enregistrements importés : $count';
  }

  @override
  String get csvImportFailed => 'Échec de l\'import';

  @override
  String csvFieldString(Object name) {
    return '$name (texte)';
  }

  @override
  String csvFieldModelName(Object name) {
    return '$name (nom du modèle)';
  }

  @override
  String csvFieldRecordName(Object name) {
    return '$name/Nom de l\'enregistrement';
  }

  @override
  String get open => 'Ouvrir';

  @override
  String get recordMenu => 'Menu de l\'enregistrement';

  @override
  String get menuSwitchView => 'Changer de vue';

  @override
  String get menuPrevious => 'Précédent';

  @override
  String get menuNext => 'Suivant';

  @override
  String get menuSearch => 'Rechercher';

  @override
  String get menuNew => 'Nouveau';

  @override
  String get menuSave => 'Enregistrer';

  @override
  String get menuReload => 'Recharger/Annuler';

  @override
  String get menuDuplicate => 'Dupliquer';

  @override
  String get menuDelete => 'Supprimer…';

  @override
  String get menuLogs => 'Voir les journaux…';

  @override
  String get menuRevisions => 'Voir les révisions…';

  @override
  String get menuAttachments => 'Pièces jointes…';

  @override
  String get menuNotes => 'Notes…';

  @override
  String get menuActions => 'Actions…';

  @override
  String get menuRelate => 'Relations…';

  @override
  String get menuReport => 'Rapport…';

  @override
  String get menuEmail => 'E-mail…';

  @override
  String get menuCloseTab => 'Fermer l\'onglet';

  @override
  String get keyboardShortcuts => 'Raccourcis clavier';

  @override
  String get shortcutsGlobal => 'Général';

  @override
  String get shortcutsForm => 'Formulaire';

  @override
  String get shortcutsRelation => 'Champs de relation';

  @override
  String get shortcutsList => 'Champs de liste';

  @override
  String get shortcutsDate => 'Champs de date';

  @override
  String get shortcutSearchMenu => 'Rechercher dans le menu';

  @override
  String get shortcutToggleMenu => 'Afficher/masquer le menu';

  @override
  String get shortcutPreviousTab => 'Onglet précédent';

  @override
  String get shortcutNextTab => 'Onglet suivant';

  @override
  String get shortcutQuit => 'Quitter';

  @override
  String get shortcutRelationNew => 'Créer une nouvelle relation';

  @override
  String get shortcutRelationOpen => 'Ouvrir/rechercher la relation';

  @override
  String get shortcutListSwitch => 'Changer de vue';

  @override
  String get shortcutListNew => 'Créer/sélectionner une nouvelle ligne';

  @override
  String get shortcutListOpen => 'Ouvrir la relation';

  @override
  String get shortcutListDelete => 'Marquer la ligne pour suppression/retrait';

  @override
  String get shortcutListRemove => 'Marquer la ligne pour retrait';

  @override
  String get shortcutListUndelete => 'Annuler le marquage de suppression';

  @override
  String get shortcutDateToday => 'Aujourd\'hui';

  @override
  String get shortcutDateAdd =>
      'Ajouter seconde/minute/heure/jour/semaine/mois/année';

  @override
  String get shortcutDateSubtract =>
      'Retirer seconde/minute/heure/jour/semaine/mois/année';

  @override
  String get keyDelete => 'Suppr';

  @override
  String get keyInsert => 'Inser';

  @override
  String get ctxCopy => 'Copier';

  @override
  String get ctxCopyRow => 'Copier la ligne';

  @override
  String get ctxCopyRows => 'Copier les lignes';

  @override
  String get ctxCopyColumn => 'Copier la colonne';

  @override
  String get ctxPasteRows => 'Coller les lignes';

  @override
  String get ctxEdit => 'Modifier…';

  @override
  String get ctxPrint => 'Imprimer…';

  @override
  String get x2mCreate => 'Créer un nouvel enregistrement';

  @override
  String get x2mEdit => 'Modifier l\'enregistrement sélectionné';

  @override
  String get x2mDelete => 'Supprimer l\'enregistrement sélectionné';

  @override
  String get x2mAdd => 'Ajouter un enregistrement existant';

  @override
  String get x2mRemove => 'Retirer l\'enregistrement sélectionné';

  @override
  String get x2mUndelete => 'Restaurer l\'enregistrement sélectionné';

  @override
  String get x2mRestore => 'Rétablir l\'enregistrement sélectionné';

  @override
  String get x2mSwitch => 'Basculer';

  @override
  String get x2mPrevious => 'Précédent';

  @override
  String get x2mNext => 'Suivant';

  @override
  String get x2mMore => 'Plus';

  @override
  String get reportBug => 'Signaler un bogue';

  @override
  String get selectionTitle => 'Sélection';

  @override
  String get yourSelection => 'Votre sélection :';

  @override
  String emailTitle(Object name) {
    return 'E-mail $name';
  }

  @override
  String get emailTo => 'À';

  @override
  String get emailCc => 'Cc';

  @override
  String get emailBcc => 'Cci';

  @override
  String get emailSubject => 'Objet';

  @override
  String get emailBody => 'Corps';

  @override
  String get emailReports => 'Rapports';

  @override
  String get emailAttachments => 'Pièces jointes';

  @override
  String get emailFiles => 'Fichiers';

  @override
  String get emailAddFile => 'Sélectionner un fichier';

  @override
  String get emailRemoveFile => 'Retirer le fichier';

  @override
  String get emailSend => 'Envoyer';

  @override
  String get emailTemplate => 'Modèle';

  @override
  String get emailSent => 'E-mail envoyé.';

  @override
  String get attachmentPreview => 'Aperçu des pièces jointes';

  @override
  String get noAttachment => 'Aucune pièce jointe.';

  @override
  String get profile => 'Profil';

  @override
  String get editProfiles => 'Modifier les profils…';

  @override
  String get profiles => 'Profils';

  @override
  String get profileName => 'Nom du profil';

  @override
  String get newProfile => 'Nouveau profil';

  @override
  String get deleteProfile => 'Supprimer le profil';

  @override
  String get renameProfile => 'Renommer';

  @override
  String get profileNameTaken => 'Ce nom de profil est déjà utilisé.';

  @override
  String get incompatibleServer => 'Version du serveur incompatible.';

  @override
  String get couldNotConnect => 'Impossible de se connecter au serveur.';

  @override
  String get copyUrl => 'Copier l\'URL';

  @override
  String get urlCopied => 'URL copiée.';

  @override
  String get openTrytonUrl => 'Ouvrir une URL Tryton';

  @override
  String urlOtherProfile(Object target, Object profile) {
    return 'L\'URL appartient à $target. Se connecter avec le profil « $profile » ?';
  }

  @override
  String urlNoProfile(Object target) {
    return 'L\'URL appartient à $target ; aucun profil n\'existe pour elle.';
  }

  @override
  String get chat => 'Discussion';

  @override
  String get chatInternal => 'En faire un message interne';

  @override
  String get chatInternalTag => 'interne';

  @override
  String get chatFollowers => 'Afficher les abonnés';

  @override
  String get chatSubscribe => 'S\'abonner';

  @override
  String get chatUnsubscribe => 'Se désabonner';

  @override
  String get chatAddFollower => 'Ajouter un abonné';

  @override
  String chatUnsubscribeQuestion(Object name) {
    return 'Désabonner « $name » de ce canal ?';
  }

  @override
  String get chatEmpty => 'Aucun message pour l\'instant.';

  @override
  String get calendarToday => 'Aujourd\'hui';

  @override
  String get calendarMonth => 'Mois';

  @override
  String get calendarWeek => 'Semaine';

  @override
  String get calendarDay => 'Jour';

  @override
  String get scanCode => 'Scanner';

  @override
  String get codeScanner => 'Lecteur de codes';

  @override
  String get scanCodeHint => 'Code';

  @override
  String get scanCodeSound => 'Son';

  @override
  String get scanCodeCamera => 'Caméra';

  @override
  String get scanCodeNoCamera =>
      'Aucune caméra disponible – saisissez le code ou lisez-le avec un lecteur manuel.';

  @override
  String get allTabs => 'Tous les onglets';

  @override
  String get connectionSecure => 'Connexion chiffrée (HTTPS)';

  @override
  String get connectionInsecure =>
      'Connexion non chiffrée (HTTP) – le mot de passe est transmis en clair';

  @override
  String get documentation => 'Documentation…';

  @override
  String get aboutMenu => 'À propos…';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutBasedOn =>
      'Basé sur le client de bureau Tryton et SAO – Copyright (C) 2004-2026 Tryton';

  @override
  String get aboutProjectPage => 'Page du projet';

  @override
  String get aboutCredits => 'Crédits';

  @override
  String get aboutLicense => 'Licence';

  @override
  String get aboutCopyright => 'Copyright';

  @override
  String get aboutThirdParty => 'Licences tierces';

  @override
  String get aboutAuthors => 'Auteurs de ce client';

  @override
  String get aboutOriginalAuthors => 'Auteurs du client Tryton (original)';

  @override
  String get aboutTranslations => 'Traductions';

  @override
  String get aboutNoWarranty => 'Ce programme est fourni sans aucune garantie.';

  @override
  String aboutSeeLicense(String license) {
    return 'Consultez la $license pour plus de détails.';
  }

  @override
  String get aboutGplName =>
      'GNU General Public License, version 3 ou ultérieure';

  @override
  String get appDevelopment => 'développement';

  @override
  String get appPrerelease => 'Version de test';

  @override
  String get loginFailed => 'Nom d\'utilisateur ou mot de passe incorrect.';

  @override
  String get tooManyRequests => 'Trop de demandes. Réessayez plus tard.';

  @override
  String get databaseNotFound => 'Base de données introuvable.';

  @override
  String get serverForbidden => 'Le serveur ne le permet pas.';

  @override
  String get resetPassword => 'Réinitialiser le mot de passe oublié';

  @override
  String get resetPasswordTooltip =>
      'Envoyez-vous un courriel pour réinitialiser votre mot de passe.';

  @override
  String get resetPasswordSent =>
      'Une demande de réinitialisation de votre mot de passe a été envoyée.\nVeuillez consulter votre boîte aux lettres.';

  @override
  String get resetPasswordNeedsUser =>
      'Indiquez d\'abord le serveur, la base de données et l\'utilisateur.';
}
