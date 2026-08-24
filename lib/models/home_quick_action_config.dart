class HomeQuickActionSpec {
  const HomeQuickActionSpec({
    required this.id,
    required this.labelTh,
    this.serviceType,
    this.hidesHomeProducts = false,
  });

  final String id;
  final String labelTh;
  final String? serviceType;
  final bool hidesHomeProducts;
}

class HomeQuickActionConfig {
  const HomeQuickActionConfig(this._enabled);

  static const List<HomeQuickActionSpec> specs = <HomeQuickActionSpec>[
    HomeQuickActionSpec(id: 'travel', labelTh: 'เดินทาง'),
    HomeQuickActionSpec(
      id: 'restaurant',
      labelTh: 'ร้านอาหาร',
      serviceType: 'ร้านอาหาร',
      hidesHomeProducts: true,
    ),
    HomeQuickActionSpec(
      id: 'market',
      labelTh: 'ตลาด',
      serviceType: 'ตลาด',
      hidesHomeProducts: true,
    ),
    HomeQuickActionSpec(
      id: 'shop',
      labelTh: 'ร้านค้า',
      serviceType: 'ร้านค้า',
      hidesHomeProducts: true,
    ),
    HomeQuickActionSpec(
      id: 'pharmacy',
      labelTh: 'ร้านขายยา',
      serviceType: 'ร้านขายยา',
      hidesHomeProducts: true,
    ),
    HomeQuickActionSpec(id: 'shop-map', labelTh: 'แผนที่'),
    HomeQuickActionSpec(
      id: 'nationwide-shipping',
      labelTh: 'สินค้าส่งทั่วประเทศ',
      hidesHomeProducts: true,
    ),
    HomeQuickActionSpec(id: 'more', labelTh: 'เพิ่มเติม'),
  ];

  static const Set<String> ids = <String>{
    'travel',
    'restaurant',
    'market',
    'shop',
    'pharmacy',
    'shop-map',
    'nationwide-shipping',
    'more',
  };

  static const Map<String, String> retailServiceTypeById = <String, String>{
    'restaurant': 'ร้านอาหาร',
    'market': 'ตลาด',
    'shop': 'ร้านค้า',
    'pharmacy': 'ร้านขายยา',
  };

  static const HomeQuickActionConfig defaults = HomeQuickActionConfig(
    <String, bool>{},
  );

  final Map<String, bool> _enabled;

  factory HomeQuickActionConfig.fromFirestore(Map<String, dynamic>? data) {
    final raw = data?['quickActions'];
    if (raw is! Map) {
      return defaults;
    }

    final enabled = <String, bool>{};
    for (final entry in raw.entries) {
      final id = entry.key.toString().trim();
      if (!ids.contains(id)) {
        continue;
      }
      enabled[id] = entry.value != false;
    }
    return HomeQuickActionConfig(enabled);
  }

  bool isEnabled(String id) => _enabled[id] != false;

  bool get nationwideEnabled => isEnabled('nationwide-shipping');

  Set<String> get enabledRetailServiceTypes {
    return <String>{
      for (final entry in retailServiceTypeById.entries)
        if (isEnabled(entry.key)) entry.value,
    };
  }

  String get signature {
    return specs.map((spec) => '${spec.id}:${isEnabled(spec.id)}').join(',');
  }

  Map<String, bool> get enabledById {
    return <String, bool>{
      for (final spec in specs) spec.id: isEnabled(spec.id),
    };
  }
}
