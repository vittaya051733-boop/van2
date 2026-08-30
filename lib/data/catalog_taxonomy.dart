import '../l10n/l10n.dart';
import '../services/locale_service.dart';

class CatalogTaxonomyEntry {
  const CatalogTaxonomyEntry({
    required this.label,
    this.labelEn,
    required this.sort,
    required this.headings,
  });

  final String label;
  final String? labelEn;
  final int sort;
  final List<String> headings;

  String get displayLabel {
    if (!LocaleService.instance.isEnglish) {
      return label;
    }
    return labelEn ?? L10n.catalogTaxonomyLabel(label);
  }

  List<String> get displayHeadings =>
      headings.map(CatalogTaxonomy.displayHeading).toList(growable: false);
}

class CatalogTaxonomy {
  CatalogTaxonomy._();

  static const pharmacyType = CatalogTaxonomyEntry(
    label: 'ยาและเวชภัณฑ์',
    labelEn: 'Medicine & health products',
    sort: 180,
    headings: <String>[
      'ยาแก้ปวด / ลดไข้',
      'ยาแก้แพ้ / หวัด / ไอ',
      'ยาทางเดินอาหาร',
      'ยาภายนอก',
      'เวชภัณฑ์',
      'อุปกรณ์การแพทย์',
      'วิตามิน / อาหารเสริม',
      'แม่และเด็ก',
      'สุขภาพช่องปาก',
      'ดูแลผิว / ของใช้ส่วนตัว',
      'ยาและเวชภัณฑ์',
    ],
  );

  static const marketTypes = <CatalogTaxonomyEntry>[
    CatalogTaxonomyEntry(label: 'ผักสด', labelEn: 'Fresh vegetables', sort: 10, headings: <String>['ผักใบ', 'ผักสวนครัว', 'ผักสด']),
    CatalogTaxonomyEntry(label: 'ผลไม้', labelEn: 'Fruit', sort: 20, headings: <String>['ผลไม้สด', 'มะม่วง', 'กล้วย', 'ส้ม', 'ทุเรียน', 'แก้วมังกร']),
    CatalogTaxonomyEntry(label: 'เนื้อสัตว์', labelEn: 'Meat', sort: 30, headings: <String>['หมูสด', 'ไก่สด', 'เนื้อสด', 'เนื้อสัตว์']),
    CatalogTaxonomyEntry(label: 'อาหารทะเลสด', labelEn: 'Fresh seafood', sort: 40, headings: <String>['ปลาสด', 'กุ้งสด', 'ปูสด', 'หอยสด', 'ปลาหมึกสด', 'อาหารทะเลสด']),
    CatalogTaxonomyEntry(label: 'อาหารทะเลแปรรูป', labelEn: 'Processed seafood', sort: 50, headings: <String>['ปลาหมึกแห้ง', 'ปลาแห้ง / ปลาแดดเดียว', 'อาหารทะเลแปรรูป']),
    CatalogTaxonomyEntry(label: 'ไข่ / เต้าหู้', labelEn: 'Eggs / tofu', sort: 60, headings: <String>['ไข่', 'เต้าหู้']),
    CatalogTaxonomyEntry(label: 'อาหารพร้อมทาน', labelEn: 'Ready-to-eat food', sort: 70, headings: <String>['อาหารพร้อมทาน']),
    CatalogTaxonomyEntry(label: 'ของแห้ง / วัตถุดิบ', labelEn: 'Dry goods / ingredients', sort: 80, headings: <String>['ข้าวสาร', 'เส้น / บะหมี่', 'ของแห้ง / วัตถุดิบ']),
    CatalogTaxonomyEntry(label: 'เครื่องปรุง / ซอส', labelEn: 'Seasonings / sauces', sort: 90, headings: <String>['น้ำปลา', 'ซอส / ซีอิ๊ว', 'เครื่องปรุง / ซอส']),
    CatalogTaxonomyEntry(label: 'ขนม / เบเกอรี่', labelEn: 'Snacks / bakery', sort: 100, headings: <String>['ขนม', 'เบเกอรี่']),
    CatalogTaxonomyEntry(label: 'เครื่องดื่ม', labelEn: 'Beverages', sort: 110, headings: <String>['น้ำดื่ม', 'ชา', 'กาแฟ', 'เครื่องดื่ม']),
    CatalogTaxonomyEntry(label: 'เสื้อผ้า', labelEn: 'Clothing', sort: 120, headings: <String>['เสื้อ', 'กางเกง', 'กระโปรง', 'เสื้อผ้า']),
    CatalogTaxonomyEntry(label: 'ชุดนักเรียน / เครื่องแบบ', labelEn: 'School uniforms', sort: 130, headings: <String>['ชุดนักเรียน']),
    CatalogTaxonomyEntry(label: 'รองเท้า / กระเป๋า', labelEn: 'Shoes / bags', sort: 140, headings: <String>['รองเท้านักเรียน', 'รองเท้า', 'กระเป๋า']),
    CatalogTaxonomyEntry(label: 'ของใช้ในบ้าน', labelEn: 'Household items', sort: 150, headings: <String>['ซักผ้า', 'ล้างจาน', 'ของใช้ในบ้าน']),
    CatalogTaxonomyEntry(label: 'ของใช้ส่วนตัว', labelEn: 'Personal care', sort: 160, headings: <String>['ของใช้ส่วนตัว']),
    CatalogTaxonomyEntry(label: 'เครื่องเขียน / อุปกรณ์เรียน', labelEn: 'Stationery / school supplies', sort: 170, headings: <String>['สมุด / กระดาษ', 'ปากกา / ดินสอ']),
    CatalogTaxonomyEntry(label: 'ของสด', labelEn: 'Fresh goods', sort: 190, headings: <String>['ของสด']),
    CatalogTaxonomyEntry(label: 'อื่นๆ', labelEn: 'Other', sort: 500000, headings: <String>['อื่นๆ']),
  ];

  static List<CatalogTaxonomyEntry> typesForServiceType(String? serviceType) {
    if (_normalizeServiceType(serviceType) == 'ร้านขายยา') {
      return const <CatalogTaxonomyEntry>[pharmacyType];
    }
    return marketTypes;
  }

  static List<String> headingsFor(String? serviceType, String catalogType) {
    for (final entry in typesForServiceType(serviceType)) {
      if (entry.label == catalogType) {
        return entry.headings;
      }
    }
    return const <String>['อื่นๆ'];
  }

  static String displayHeading(String heading) =>
      L10n.catalogTaxonomyLabel(heading);

  static String _normalizeServiceType(String? rawValue) {
    final normalized = rawValue?.trim().toLowerCase() ?? '';
    if (normalized.contains('ตลาด') || normalized.contains('market')) {
      return 'ตลาด';
    }
    if (normalized.contains('ร้านขายยา') ||
        normalized == 'ยาและเวชภัณฑ์' ||
        normalized.contains('pharmacy')) {
      return 'ร้านขายยา';
    }
    return rawValue?.trim() ?? '';
  }

  static String slugForLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return 'other';
    }
    final slug = trimmed
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^\p{L}\p{N}\-_]', unicode: true), '');
    return slug.isNotEmpty ? slug : 'other';
  }
}
