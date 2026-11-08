import 'package:flutter/material.dart';

import '../../core/l10n/locale_provider.dart';
import '../../features/model/concurrency.dart';
import '../dialogs/tryton_dialogs.dart';

/// "Concurrency Warning" (spec 2.6, 11.3): Cancel / Compare / Write
/// Anyway; Cancel is the default, closing counts as Cancel too.
Future<ConcurrencyChoice> showConcurrencyDialog(BuildContext context) =>
    showConcurrency(context);

/// Plain "Concurrency Exception" message (several records involved).
Future<void> showConcurrencyMessage(BuildContext context) =>
    showWarning(context, context.l10n.concurrencyException);
