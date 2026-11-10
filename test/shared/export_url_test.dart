import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';
import 'package:tryton_flutter_client/shared/utils/export_url.dart';

/// URL export (spec 11.9): character for character the URL of the
/// Python client 8.0 (`WinExport.get_url`). The expected strings were
/// produced with its code (json.dumps, urllib.parse.urlencode).
void main() {
  test('selected records: ids, context, fields, locale', () {
    expect(
        exportUrl(
          baseUrl: 'http://localhost:8000/',
          database: 'tryton',
          model: 'party.party',
          domain: [1, 2, 3],
          context: {'language': 'de'},
          fields: ['name', 'addresses/city'],
          encoding: 'utf_8_sig',
          delimiter: ',',
          quote: '"',
          localeFormat: true,
        ),
        'http://localhost:8000/tryton/data/party.party?d=%5B1%2C2%2C3%5D'
        '&c=%7B%22language%22%3A%22de%22%7D&f=name&f=addresses%2Fcity'
        '&enc=utf_8_sig&dl=%2C&qc=%22&loc=1');
  });

  test('search: domain with special characters, limit/page, order, date '
      'in the context, without header and locale', () {
    expect(
        exportUrl(
          baseUrl: 'http://localhost:8000',
          database: 'tryton',
          model: 'party.party',
          domain: [
            'OR',
            [
              ['name', 'ilike', '%Müller & Söhne%']
            ],
            [
              ['code', '=', 'a/b c']
            ],
          ],
          limit: 1000,
          page: 2,
          order: [
            ['name', 'ASC'],
            ['id', null],
          ],
          context: {
            'company': 1,
            'date': const TrytonDate(2026, 1, 31),
            'context_model': 'x.y',
          },
          fields: ['name', 'code'],
          encoding: 'utf_8_sig',
          delimiter: ';',
          quote: "'",
          header: false,
        ),
        'http://localhost:8000/tryton/data/party.party?d=%5B%22OR%22%2C%5B%5B'
        '%22name%22%2C%22ilike%22%2C%22%25M%5Cu00fcller+%26+S%5Cu00f6hne%25'
        '%22%5D%5D%2C%5B%5B%22code%22%2C%22%3D%22%2C%22a%2Fb+c%22%5D%5D%5D'
        '&s=1000&p=2&o=name%2CASC&o=id&c=%7B%22company%22%3A1%2C%22date%22'
        '%3A%7B%22__class__%22%3A%22date%22%2C%22year%22%3A2026%2C%22month'
        '%22%3A1%2C%22day%22%3A31%7D%2C%22context_model%22%3A%22x.y%22%7D'
        '&f=name&f=code&enc=utf_8_sig&dl=%3B&qc=%27&h=0');
  });

  test('host like the Python client: without port only for http:80 and '
      'https:445; no encoding, tab, euro sign', () {
    expect(
        exportUrl(
          baseUrl: 'https://erp.example.com:445/',
          database: 'db',
          model: 'account.invoice',
          domain: [
            ['state', '=', 'posted']
          ],
          fields: ['number'],
          encoding: '',
          delimiter: '\t',
          quote: '"',
          localeFormat: true,
        ),
        'https://erp.example.com/db/data/account.invoice?d=%5B%5B%22state%22'
        '%2C%22%3D%22%2C%22posted%22%5D%5D&f=number&dl=%09&qc=%22&loc=1');
    expect(
        exportUrl(
          baseUrl: 'https://erp.example.com/',
          database: 'db',
          model: 'm',
          domain: [],
          limit: 50,
          page: 0,
          fields: ['€'],
          encoding: 'utf_8',
          delimiter: ',',
          quote: '"',
          localeFormat: true,
        ),
        'https://erp.example.com:443/db/data/m?d=%5B%5D&s=50&p=0&f=%E2%82%AC'
        '&enc=utf_8&dl=%2C&qc=%22&loc=1');
  });
}
