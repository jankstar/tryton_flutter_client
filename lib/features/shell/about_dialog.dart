import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/session/session.dart';
import '../../l10n/app_localizations.dart';
import '../actions/action_service.dart' show DialogActionUi;

// "About …" (spec 11.12; Python client gui/window/about.py, a
// Gtk.AboutDialog): the Tryton logo, name, version, comments, copyright,
// links, Credits, License, Copyright and the third-party licences.

/// The Tryton logo of the Python client (data/pixmaps/tryton/tryton.svg,
/// Apache 2.0 like the other icons of that directory).
const trytonLogoAsset = 'assets/icons/tryton/tryton.svg';

/// Name of the app (window title, About, licences).
const appName = 'Tryton Flutter Client';

/// Project page of this client.
const appProjectUrl = 'https://github.com/jankstar/tryton_flutter_client';

/// The licence of the warranty note (GTK `GTK_LICENSE_GPL_3_0`).
const gplUrl = 'https://www.gnu.org/licenses/gpl-3.0.html';

/// Tryton's site (Python `set_website`).
const trytonUrl = 'https://www.tryton.org/';

/// Copyright of this client; the original clients (Python `COPYRIGHT`).
const appCopyright = 'Copyright (C) 2026 jankstar';

/// Authors of this client.
const appAuthors = ['jankstar'];

/// Authors of the Tryton client (Python about.py `AUTHORS`).
const trytonAuthors = [
  'Bertrand Chenal <bertrand.chenal@b2ck.com>',
  'Cédric Krier <cedric.krier@b2ck.com>',
  'Franz Wiesinger',
  'Hartmut Goebel',
  'Korbinian Preisler <info@virtual-things.biz>',
  'Mathias Behrle <mbehrle@m9s.biz>',
  'Maxime Richez <maxime.richez@saluc.com>',
  'Nicolas Évrard <nicolas.evrard@b2ck.com>',
  'Sednacom <contact@sednacom.fr>',
  'Udo Spallek <info@virtual-things.biz>',
];

/// The languages of the user interface (Credits → Translations).
const appTranslations = [
  'Dansk', 'Deutsch', 'English', 'Español', 'Français', 'Nederlands',
  'Polski', 'Português', 'Русский', 'Suomi', 'Svenska',
];

/// A test version: the release label has a suffix (`8.0.0-beta.1`, the
/// workflow's `8.0.0-dev.N`).
bool isPrerelease([String label = kAppLabel]) => label.contains('-');

/// Version text: the release label (`8.0.0-beta.1 (Build 42)`), in a
/// local build without label `8.0.0 (development)`.
String appVersionText(AppLocalizations l,
    {String label = kAppLabel, String build = kAppBuild}) {
  final version = label.isEmpty ? '$kAppVersion (${l.appDevelopment})' : label;
  return build.isEmpty ? version : '$version (Build $build)';
}

/// "Test version" next to the version of a pre-release (About, login).
class PrereleaseBadge extends StatelessWidget {
  final String label;
  const PrereleaseBadge({super.key, this.label = kAppLabel});

  @override
  Widget build(BuildContext context) {
    if (!isPrerelease(label)) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('prerelease-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(context.l10n.appPrerelease,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onTertiaryContainer)),
    );
  }
}

/// The Tryton documentation of the series (Python `open_documentation`:
/// `https://docs.tryton.org/<major.minor>`, `latest` for an odd minor –
/// a development series).
String documentationUrl([String series = kClientVersion]) {
  final parts = series.split('.');
  final minor = parts.length > 1 ? int.tryParse(parts[1]) : null;
  return 'https://docs.tryton.org/${minor != null && minor.isOdd ? 'latest' : series}';
}

/// Shows "About …": a dialog, on narrow screens (< 600 px) a full-screen
/// page. [openUrl] opens the links (default: the URL opener of the app).
Future<void> showAboutTryton(BuildContext context,
    {void Function(String url)? openUrl}) {
  final open = openUrl ?? (url) => DialogActionUi(context).openUrl(url);
  final narrow = MediaQuery.sizeOf(context).width < 600;
  if (narrow) {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.aboutMenu)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: AboutContent(openUrl: open),
          ),
        ),
      ),
    ));
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: AboutContent(openUrl: open),
        ),
      ),
    ),
  );
}

/// The content of "About …" (dialog and page): like the Python client
/// the Tryton logo, name and version (without its comments).
class AboutContent extends StatelessWidget {
  final void Function(String url) openUrl;
  const AboutContent({super.key, required this.openUrl});

  Widget _link(String label, String url) => TextButton.icon(
        key: ValueKey('about-link-$url'),
        icon: const Icon(Icons.open_in_new, size: 16),
        label: Text(label),
        onPressed: () => openUrl(url),
      );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('about-content'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(trytonLogoAsset,
            key: const ValueKey('about-logo'), width: 250, height: 100),
        const SizedBox(height: 12),
        Text(appName, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text('${l.aboutVersion} ${appVersionText(l)}',
                key: const ValueKey('about-version'),
                style: theme.textTheme.bodyMedium),
            const PrereleaseBadge(),
          ],
        ),
        const SizedBox(height: 16),
        Text(appCopyright,
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        Text(l.aboutBasedOn,
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        _WarrantyNote(openUrl: openUrl),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, children: [
          _link(l.aboutProjectPage, appProjectUrl),
          _link('tryton.org', trytonUrl),
        ]),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const ValueKey('about-credits'),
              onPressed: () => _showCredits(context),
              child: Text(l.aboutCredits),
            ),
            OutlinedButton(
              key: const ValueKey('about-license'),
              onPressed: () => _showText(context, l.aboutLicense, 'LICENSE'),
              child: Text(l.aboutLicense),
            ),
            OutlinedButton(
              key: const ValueKey('about-copyright'),
              onPressed: () => _showText(context, l.aboutCopyright, 'COPYRIGHT',
                  monospace: true),
              child: Text(l.aboutCopyright),
            ),
            OutlinedButton(
              key: const ValueKey('about-third-party'),
              onPressed: () => showLicensePage(
                context: context,
                applicationName: appName,
                applicationVersion: appVersionText(l),
                applicationIcon: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.asset('assets/app_icon.png', width: 48, height: 48),
                ),
                applicationLegalese: appCopyright,
              ),
              child: Text(l.aboutThirdParty),
            ),
            FilledButton(
              key: const ValueKey('about-close'),
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(l.close),
            ),
          ],
        ),
      ],
    );
  }

  /// Credits (Python `set_authors`, `set_translator_credits`).
  Future<void> _showCredits(BuildContext context) {
    final l = context.l10n;
    Widget section(String title, List<String> lines) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final line in lines) Text(line),
          ]),
        );
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('about-credits-dialog'),
        title: Text(l.aboutCredits),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              section(l.aboutAuthors, appAuthors),
              section(l.aboutOriginalAuthors, trytonAuthors),
              section(l.aboutTranslations, appTranslations),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.close),
          ),
        ],
      ),
    );
  }

  /// [asset] (LICENSE, COPYRIGHT) scrollable in a dialog.
  Future<void> _showText(BuildContext context, String title, String asset,
      {bool monospace = false}) {
    final l = context.l10n;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: ValueKey('about-text-$asset'),
        title: Text(title),
        content: SizedBox(
          width: 640,
          height: 480,
          child: FutureBuilder<String>(
            future: rootBundle.loadString(asset),
            builder: (context, snapshot) => snapshot.hasData
                ? Scrollbar(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        snapshot.data!,
                        style: monospace
                            ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
                            : const TextStyle(fontSize: 13),
                      ),
                    ),
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.close),
          ),
        ],
      ),
    );
  }
}

/// "This program comes with absolutely no warranty. See the GNU General
/// Public License, version 3 or later for details." (Gtk.AboutDialog with
/// `set_license_type(GPL_3_0)`), the licence name a link.
class _WarrantyNote extends StatefulWidget {
  final void Function(String url) openUrl;
  const _WarrantyNote({required this.openUrl});

  @override
  State<_WarrantyNote> createState() => _WarrantyNoteState();
}

class _WarrantyNoteState extends State<_WarrantyNote> {
  late final _link = TapGestureRecognizer()
    ..onTap = () => widget.openUrl(gplUrl);

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    // the sentence around the licence name (placeholder in the translation)
    const marker = '\u0000';
    final parts = l.aboutSeeLicense(marker).split(marker);
    return Text.rich(
      key: const ValueKey('about-warranty'),
      textAlign: TextAlign.center,
      TextSpan(style: style, children: [
        TextSpan(text: '${l.aboutNoWarranty}\n'),
        TextSpan(text: parts.first),
        TextSpan(
          text: l.aboutGplName,
          style: style?.copyWith(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline),
          recognizer: _link,
        ),
        if (parts.length > 1) TextSpan(text: parts.last),
      ]),
    );
  }
}
