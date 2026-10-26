import 'package:intl/intl.dart';

/// Display format for `datetime` fields (SAO default `%Y-%m-%d %H:%M:%S`).
final _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

/// Formats a `datetime` value in the device's local time zone.
/// `TrytonSerializer` already decodes server values (UTC) to local time;
/// `toLocal()` is a no-op then, but guards against UTC values from elsewhere.
String formatDateTimeValue(DateTime value) =>
    _dateTimeFormat.format(value.toLocal());
