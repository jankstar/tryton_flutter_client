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
    return 'Version du serveur $server incompatible (le client attend $client).';
  }

  @override
  String get recordModified =>
      'Cet enregistrement a été modifié.\nVoulez-vous l\'enregistrer?';

  @override
  String get yes => 'Oui';

  @override
  String get no => 'Non';
}
