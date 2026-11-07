import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/xml/form_xml_parser.dart';
import 'package:tryton_flutter_client/core/xml/view_definition.dart';

/// Form parser (spec 9.1, 9.2.1; Python `XMLViewParser._node_attributes`).
void main() {
  const fields = {
    'name': {
      'type': 'char',
      'string': 'Name',
      'help': 'The name',
      'size': 64,
      'translate': true,
      'states': '{"readonly": true}',
    },
    'lines': {
      'type': 'one2many',
      'string': 'Lines',
      'relation': 'sale.line',
      'relation_field': 'sale',
      'add_remove': '[]',
      'create': true,
      'delete': false,
      'order': [
        ['sequence', 'ASC']
      ],
    },
    'amount': {
      'type': 'numeric',
      'string': 'Amount',
      'symbol': 'currency',
      'monetary': true,
    },
  };

  FormRoot parse(String arch) =>
      FormXmlParser().parse(arch, fields: fields);

  test('root attributes, col ≤ 0 kept', () {
    final root = parse('<form col="0" cursor="name" creatable="0" '
        'on_write="on_write_x" scan_code="submit"/>');
    expect(root.col, 0);
    expect(root.cursor, 'name');
    expect(root.creatable, isFalse);
    expect(root.onWrite, 'on_write_x');
    expect(root.scanCode, 'submit');
    expect(parse('<form/>').creatable, isTrue);
    expect(parse('<form/>').col, 4);
  });

  test('field: all attributes converted (9.1/9.2.1)', () {
    final root = parse('<form><field name="lines" colspan="3" '
        'xexpand="0" xfill="1" yexpand="1" yfill="0" xalign="0.25" '
        'yalign="1" height="200" width="300" help="Own help" '
        'mode="form,tree" view_ids="168,166" completion="0" create="0" '
        'delete="1" product="product,unit" pre_validate="1" '
        'filename="name" filename_visible="1" spell="de" factor="100" '
        'grouping="0" format="&quot;%H:%M&quot;" visible="1" '
        'readonly="1" widget="many2many"/></form>');
    final f = root.children.single as FieldNode;
    expect(f.colspan, 3);
    expect(f.attrs['xexpand'], 0);
    expect((f.xexpand, f.xfill, f.yexpand, f.yfill), (false, true, true, false));
    expect((f.xalign, f.yalign), (0.25, 1.0));
    expect((f.height, f.width), (200, 300));
    expect(f.help, 'Own help');
    expect(f.mode, ['form', 'tree']);
    expect(f.viewIds, [168, 166]);
    expect(f.completion, isFalse);
    expect((f.create, f.delete), (false, true));
    expect(f.product, ['product', 'unit']);
    expect(f.preValidate, isTrue);
    expect((f.filename, f.filenameVisible), ('name', true));
    expect(f.spell, 'de');
    expect(f.factor, 100);
    expect(f.grouping, isFalse);
    expect(f.format, '"%H:%M"');
    expect(f.visible, isTrue);
    expect(f.attrs['readonly'], isTrue, reason: 'readonly → bool');
    expect(f.readonly, isTrue);
    expect(f.widget, 'many2many', reason: 'XML widget wins');
  });

  test('field: defaults and completion from the field description', () {
    final root = parse('<form><field name="name"/><field name="lines"/>'
        '<field name="amount"/></form>');
    final [name, lines, amount] = root.children.cast<FieldNode>();
    expect(name.widget, 'char', reason: 'widget = field type');
    expect(name.help, 'The name');
    expect(name.attrs['size'], 64);
    expect(name.attrs['translate'], isTrue);
    expect(name.states, {'readonly': true});
    expect(name.attrs['string'], 'Name');
    expect(name.string, isNull, reason: 'no label override from XML');
    expect(lines.mode, ['tree', 'form']);
    expect(lines.viewIds, isEmpty);
    expect(lines.attrs['relation'], 'sale.line');
    expect(lines.attrs['relation_field'], 'sale');
    expect(lines.attrs['add_remove'], '[]');
    expect(lines.create, isTrue);
    expect(lines.delete, isFalse);
    expect(lines.attrs['order'], [
      ['sequence', 'ASC']
    ]);
    expect(lines.completion, isTrue);
    expect(lines.factor, 1);
    expect(lines.grouping, isTrue);
    expect(lines.preValidate, isFalse);
    expect(amount.attrs['symbol'], 'currency');
    expect(amount.attrs['monetary'], isTrue);
    expect(amount.help, isNull);
  });

  test('XML attributes win over the field description', () {
    final root = parse('<form><field name="lines" create="0" '
        'help="x"/></form>');
    final f = root.children.single as FieldNode;
    expect(f.create, isFalse);
    expect(f.help, 'x');
  });

  test('label, separator: string, states, alignment', () {
    final root = parse('<form><label name="name"/>'
        '<label string="Free" xalign="0.0" '
        'states="{&quot;invisible&quot;: true}"/>'
        '<separator string="Sep" name="name" '
        'states="{&quot;invisible&quot;: false}"/></form>');
    final [l1, l2, sep] = root.children;
    expect((l1 as LabelNode).fieldName, 'name');
    expect(l1.attrs['string'], 'Name:', reason: 'field string + ":"');
    expect(l1.string, isNull);
    expect((l2 as LabelNode).xalign, 0.0);
    expect(l2.states, {'invisible': true});
    expect((sep as SeparatorNode).string, 'Sep');
    expect(sep.name, 'name');
    expect(sep.colspan, 4);
    expect(sep.states, {'invisible': false});
  });

  test('group, page, notebook: id, states, col, expandable', () {
    final root = parse('<form><group id="g1" col="-1" string="G" '
        'expandable="0" homogeneous="1" '
        'states="{&quot;invisible&quot;: true}"><field name="name"/></group>'
        '<group id="g2" expandable="1"/><group id="g3"/>'
        '<notebook colspan="2"><page id="p1" string="P" col="6" icon="tryton-x" '
        'states="{&quot;readonly&quot;: true}"/></notebook></form>');
    final [g1, g2, g3, nb] = root.children;
    expect((g1 as GroupNode).id, 'g1');
    expect(g1.col, -1);
    expect(g1.expandable, isTrue);
    expect(g1.expanded, isFalse);
    expect(g1.homogeneous, isTrue);
    expect(g1.states, {'invisible': true});
    expect((g2 as GroupNode).expandable, isTrue);
    expect(g2.expanded, isTrue);
    expect((g3 as GroupNode).expandable, isFalse);
    expect((nb as NotebookNode).colspan, 2);
    final page = nb.pages.single;
    expect((page.id, page.col, page.icon), ('p1', 6, 'tryton-x'));
    expect(page.states, {'readonly': true});
  });

  test('link and image', () {
    final root = parse('<form><link id="42" icon="tryton-sale" '
        'empty="hide" colspan="2" states="{&quot;invisible&quot;: false}"/>'
        '<image name="tryton-party" size="32" border="circle"/>'
        '<image name="photo_url" type="url" url_size="s"/></form>');
    final [link, img, url] = root.children;
    expect((link as LinkNode).actionId, 42);
    expect(link.icon, 'tryton-sale');
    expect(link.hideEmpty, isTrue);
    expect(link.colspan, 2);
    expect(link.states, {'invisible': false});
    expect((img as ImageNode).name, 'tryton-party');
    expect((img.type, img.size, img.border), ('icon', 32, 'circle'));
    expect((url as ImageNode).type, 'url');
    expect(url.size, 48);
    expect(url.urlSize, 's');
  });

  test('hpaned/vpaned as groups with expand defaults', () {
    final root = parse('<form><hpaned position="200"><child>'
        '<field name="name"/></child><child/></hpaned>'
        '<vpaned/></form>');
    final [h, v] = root.children.cast<GroupNode>();
    expect((h.col, h.colspan, h.yexpand), (2, 4, true));
    expect(h.attrs['position'], 200);
    expect(h.children, hasLength(2));
    expect(v.col, 1);
  });
}
