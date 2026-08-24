class CatalogTaxonomyEntry {
  const CatalogTaxonomyEntry({
    required this.label,
    required this.sort,
    required this.headings,
  });

  final String label;
  final int sort;
  final List<String> headings;
}

class CatalogTaxonomy {
  CatalogTaxonomy._();

  static const pharmacyType = CatalogTaxonomyEntry(
    label: 'ยาและเวชภัณฑ์',
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
    CatalogTaxonomyEntry(label: 'ผักสด', sort: 10, headings: <String>['ผักใบ', 'ผักสวนครัว', 'ผักสด']),
    CatalogTaxonomyEntry(label: 'ผลไม้', sort: 20, headings: <String>['ผลไม้สด', 'มะม่วง', 'กล้วย', 'ส้ม', 'ทุเรียน', 'แก้วมังกร']),
    CatalogTaxonomyEntry(label: 'เนื้อสัตว์', sort: 30, headings: <String>['หมูสด', 'ไก่สด', 'เนื้อสด', 'เนื้อสัตว์']),
    CatalogTaxonomyEntry(label: 'อาหารทะเลสด', sort: 40, headings: <String>['ปลาสด', 'กุ้งสด', 'ปูสด', 'หอยสด', 'ปลาหมึกสด', 'อาหารทะเลสด']),
    CatalogTaxonomyEntry(label: 'อาหารทะเลแปรรูป', sort: 50, headings: <String>['ปลาหมึกแห้ง', 'ปลาแห้ง / ปลาแดดเดียว', 'อาหารทะเลแปรรูป']),
    CatalogTaxonomyEntry(label: 'ไข่ / เต้าหู้', sort: 60, headings: <String>['ไข่', 'เต้าหู้']),
    CatalogTaxonomyEntry(label: 'อาหารพร้อมทาน', sort: 70, headings: <String>['อาหารพร้อมทาน']),
    CatalogTaxonomyEntry(label: 'ของแห้ง / วัตถุดิบ', sort: 80, headings: <String>['ข้าวสาร', 'เส้น / บะหมี่', 'ของแห้ง / วัตถุดิบ']),
    CatalogTaxonomyEntry(label: 'เครื่องปรุง / ซอส', sort: 90, headings: <String>['น้ำปลา', 'ซอส / ซีอิ๊ว', 'เครื่องปรุง / ซอส']),
    CatalogTaxonomyEntry(label: 'ขนม / เบเกอรี่', sort: 100, headings: <String>['ขนม', 'เบเกอรี่']),
    CatalogTaxonomyEntry(label: 'เครื่องดื่ม', sort: 110, headings: <String>['น้ำดื่ม', 'ชา', 'กาแฟ', 'เครื่องดื่ม']),
    CatalogTaxonomyEntry(label: 'เสื้อผ้า', sort: 120, headings: <String>['เสื้อ', 'กางเกง', 'กระโปรง', 'เสื้อผ้า']),
    CatalogTaxonomyEntry(label: 'ชุดนักเรียน / เครื่องแบบ', sort: 130, headings: <String>['ชุดนักเรียน']),
    CatalogTaxonomyEntry(label: 'รองเท้า / กระเป๋า', sort: 140, headings: <String>['รองเท้านักเรียน', 'รองเท้า', 'กระเป๋า']),
    CatalogTaxonomyEntry(label: 'ของใช้ในบ้าน', sort: 150, headings: <String>['ซักผ้า', 'ล้างจาน', 'ของใช้ในบ้าน']),
    CatalogTaxonomyEntry(label: 'ของใช้ส่วนตัว', sort: 160, headings: <String>['ของใช้ส่วนตัว']),
    CatalogTaxonomyEntry(label: 'เครื่องเขียน / อุปกรณ์เรียน', sort: 170, headings: <String>['สมุด / กระดาษ', 'ปากกา / ดินสอ']),
    CatalogTaxonomyEntry(label: 'ของสด', sort: 190, headings: <String>['ของสด']),
    CatalogTaxonomyEntry(label: 'อื่นๆ', sort: 500000, headings: <String>['อื่นๆ']),
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
