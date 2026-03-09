/// UCS Naming Service — Universal Category System for game audio assets
///
/// Industry-standard naming convention: `CATsub_VENdor_Project_Descriptor_####`
///
/// Features:
/// - Full UCS category/subcategory database
/// - Parse existing names into UCS components
/// - Generate compliant names from components
/// - Auto-detect category from track/clip context
/// - Batch rename with sequential numbering
/// - Vendor/project presets
library;

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// UCS CATEGORY DATABASE
// ═══════════════════════════════════════════════════════════════════════════════

/// A UCS category with subcategories
class UcsCategory {
  final String id;          // e.g. 'AMB'
  final String name;        // e.g. 'Ambience'
  final List<UcsSubCategory> subCategories;

  const UcsCategory({
    required this.id,
    required this.name,
    required this.subCategories,
  });
}

/// A UCS subcategory
class UcsSubCategory {
  final String id;          // e.g. 'Urbn'
  final String name;        // e.g. 'Urban'

  const UcsSubCategory({required this.id, required this.name});
}

/// Parsed UCS name components
class UcsName {
  final String catId;       // Category: AMB, BOOM, CRASH, etc.
  final String subId;       // Subcategory: Urbn, Mtl, etc.
  final String vendor;      // Vendor/creator code: FF, BSND, etc.
  final String project;     // Project name
  final String descriptor;  // Free-form description
  final int? number;        // Sequential number (####)

  const UcsName({
    required this.catId,
    this.subId = '',
    this.vendor = '',
    this.project = '',
    this.descriptor = '',
    this.number,
  });

  /// Format as standard UCS string: CATsub_VENdor_Project_Descriptor_####
  String format({bool includeNumber = true}) {
    final parts = <String>[];

    // CATsub (category + subcategory joined)
    final catSub = subId.isNotEmpty ? '$catId$subId' : catId;
    parts.add(catSub);

    // Vendor
    if (vendor.isNotEmpty) parts.add(vendor);

    // Project
    if (project.isNotEmpty) parts.add(project);

    // Descriptor
    if (descriptor.isNotEmpty) parts.add(descriptor);

    // Number
    if (includeNumber && number != null) {
      parts.add(number!.toString().padLeft(4, '0'));
    }

    return parts.join('_');
  }

  UcsName copyWith({
    String? catId,
    String? subId,
    String? vendor,
    String? project,
    String? descriptor,
    int? number,
    bool clearNumber = false,
  }) {
    return UcsName(
      catId: catId ?? this.catId,
      subId: subId ?? this.subId,
      vendor: vendor ?? this.vendor,
      project: project ?? this.project,
      descriptor: descriptor ?? this.descriptor,
      number: clearNumber ? null : (number ?? this.number),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

class UcsNamingService extends ChangeNotifier {
  UcsNamingService._();
  static final instance = UcsNamingService._();

  // ─── State ────────────────────────────────────────────────────────────────

  String _vendor = '';
  String get vendor => _vendor;

  String _project = '';
  String get project => _project;

  int _startNumber = 1;
  int get startNumber => _startNumber;

  int _selectedCategoryIndex = 0;
  int get selectedCategoryIndex => _selectedCategoryIndex;

  int _selectedSubCategoryIndex = 0;
  int get selectedSubCategoryIndex => _selectedSubCategoryIndex;

  String _descriptor = '';
  String get descriptor => _descriptor;

  bool _includeNumber = true;
  bool get includeNumber => _includeNumber;

  bool _padToFour = true;
  bool get padToFour => _padToFour;

  // ─── Setters ──────────────────────────────────────────────────────────────

  void setVendor(String v) {
    _vendor = v.replaceAll('_', '').toUpperCase();
    notifyListeners();
  }

  void setProject(String v) {
    _project = v.replaceAll('_', '');
    notifyListeners();
  }

  void setStartNumber(int v) {
    _startNumber = v.clamp(0, 99999);
    notifyListeners();
  }

  void setSelectedCategory(int index) {
    _selectedCategoryIndex = index.clamp(0, categories.length - 1);
    _selectedSubCategoryIndex = 0;
    notifyListeners();
  }

  void setSelectedSubCategory(int index) {
    final cat = selectedCategory;
    _selectedSubCategoryIndex = index.clamp(0, cat.subCategories.length - 1);
    notifyListeners();
  }

  void setDescriptor(String v) {
    _descriptor = v.replaceAll('_', '-');
    notifyListeners();
  }

  void setIncludeNumber(bool v) {
    _includeNumber = v;
    notifyListeners();
  }

  void setPadToFour(bool v) {
    _padToFour = v;
    notifyListeners();
  }

  // ─── Computed ─────────────────────────────────────────────────────────────

  UcsCategory get selectedCategory => categories[_selectedCategoryIndex];

  UcsSubCategory? get selectedSubCategory {
    final cat = selectedCategory;
    if (cat.subCategories.isEmpty) return null;
    if (_selectedSubCategoryIndex >= cat.subCategories.length) return null;
    return cat.subCategories[_selectedSubCategoryIndex];
  }

  /// Generate a UCS name from current settings
  UcsName generateName({int? sequenceNumber}) {
    return UcsName(
      catId: selectedCategory.id,
      subId: selectedSubCategory?.id ?? '',
      vendor: _vendor,
      project: _project,
      descriptor: _descriptor,
      number: _includeNumber ? (sequenceNumber ?? _startNumber) : null,
    );
  }

  /// Generate formatted string from current settings
  String generateString({int? sequenceNumber}) {
    return generateName(sequenceNumber: sequenceNumber).format(
      includeNumber: _includeNumber,
    );
  }

  /// Generate batch of names with sequential numbering
  List<String> generateBatch(int count) {
    final results = <String>[];
    for (int i = 0; i < count; i++) {
      results.add(generateString(sequenceNumber: _startNumber + i));
    }
    return results;
  }

  // ─── Parsing ──────────────────────────────────────────────────────────────

  /// Parse a UCS-formatted filename into components
  static UcsName? parse(String name) {
    // Remove file extension if present
    final baseName = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;

    final parts = baseName.split('_');
    if (parts.isEmpty) return null;

    // First part: CATsub — try to match category prefix
    final catSub = parts[0];
    String catId = '';
    String subId = '';

    for (final cat in categories) {
      if (catSub.startsWith(cat.id)) {
        catId = cat.id;
        subId = catSub.substring(cat.id.length);
        break;
      }
    }

    if (catId.isEmpty) {
      // Unknown category — use full first part as catId
      catId = catSub;
    }

    // Try to extract number from last part
    int? number;
    int descriptorEndIndex = parts.length;
    if (parts.length > 1) {
      final lastPart = parts.last;
      final parsed = int.tryParse(lastPart);
      if (parsed != null) {
        number = parsed;
        descriptorEndIndex = parts.length - 1;
      }
    }

    // Extract vendor, project, descriptor from middle parts
    String vendor = '';
    String project = '';
    String descriptor = '';

    if (descriptorEndIndex > 1) {
      vendor = parts[1];
    }
    if (descriptorEndIndex > 2) {
      project = parts[2];
    }
    if (descriptorEndIndex > 3) {
      descriptor = parts.sublist(3, descriptorEndIndex).join('-');
    }

    return UcsName(
      catId: catId,
      subId: subId,
      vendor: vendor,
      project: project,
      descriptor: descriptor,
      number: number,
    );
  }

  /// Auto-detect category from a descriptive name (best-effort heuristic)
  static int detectCategoryIndex(String name) {
    final lower = name.toLowerCase();

    for (int i = 0; i < categories.length; i++) {
      final cat = categories[i];
      // Check if name contains category name
      if (lower.contains(cat.name.toLowerCase())) return i;
      // Check subcategory names
      for (final sub in cat.subCategories) {
        if (lower.contains(sub.name.toLowerCase())) return i;
      }
    }

    // Keyword-based detection
    final keywordMap = <String, int>{
      'ambient': 0, 'atmosphere': 0, 'room': 0, 'wind': 0, 'rain': 0,
      'animal': 1, 'bird': 1, 'dog': 1, 'cat': 1, 'insect': 1,
      'bell': 2, 'chime': 2, 'clock': 2,
      'boom': 3, 'explosion': 3, 'blast': 3, 'detonate': 3,
      'cartoon': 4, 'comic': 4, 'funny': 4, 'silly': 4,
      'crash': 5, 'smash': 5, 'shatter': 5, 'break': 5,
      'door': 6, 'creak': 6, 'slam': 6, 'hinge': 6,
      'drone': 7, 'hum': 7, 'tone': 7, 'buzz': 7,
      'electronic': 8, 'digital': 8, 'synth': 8, 'beep': 8,
      'fire': 9, 'flame': 9, 'burn': 9, 'torch': 9,
      'foley': 10, 'cloth': 10, 'footstep': 10, 'step': 10,
      'gun': 11, 'shot': 11, 'rifle': 11, 'pistol': 11,
      'horror': 12, 'scary': 12, 'creepy': 12, 'eerie': 12,
      'whoosh': 13, 'swish': 13, 'flyby': 13, 'pass': 13,
      'impact': 14, 'hit': 14, 'punch': 14, 'thud': 14,
      'machine': 15, 'engine': 15, 'motor': 15, 'gear': 15,
      'metal': 16, 'clang': 16, 'scrape': 16, 'ring': 16,
      'music': 17, 'melody': 17, 'stinger': 17, 'cue': 17,
      'nature': 18, 'forest': 18, 'ocean': 18, 'wave': 18,
      'sci-fi': 19, 'laser': 19, 'space': 19, 'alien': 19,
      'transition': 20, 'sweep': 20, 'rise': 20, 'swell': 20,
      'ui': 21, 'button': 21, 'click': 21, 'notification': 21,
      'vehicle': 22, 'car': 22, 'truck': 22, 'plane': 22,
      'voice': 23, 'speech': 23, 'vocal': 23, 'dialogue': 23,
      'water': 24, 'splash': 24, 'drip': 24, 'pour': 24,
      'weapon': 25, 'sword': 25, 'blade': 25, 'shield': 25,
      'wood': 26, 'lumber': 26, 'snap': 26, 'knock': 26,
    };

    for (final entry in keywordMap.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }

    return 0; // Default: Ambience
  }

  // ─── UCS Category Database ────────────────────────────────────────────────
  // Based on the Universal Category System v8.x standard

  static const List<UcsCategory> categories = [
    UcsCategory(id: 'AMB', name: 'Ambience', subCategories: [
      UcsSubCategory(id: 'Cntry', name: 'Country'),
      UcsSubCategory(id: 'City', name: 'City'),
      UcsSubCategory(id: 'Urbn', name: 'Urban'),
      UcsSubCategory(id: 'Ind', name: 'Industrial'),
      UcsSubCategory(id: 'Int', name: 'Interior'),
      UcsSubCategory(id: 'Ext', name: 'Exterior'),
      UcsSubCategory(id: 'Wthr', name: 'Weather'),
      UcsSubCategory(id: 'Undwtr', name: 'Underwater'),
    ]),
    UcsCategory(id: 'ANMLs', name: 'Animals', subCategories: [
      UcsSubCategory(id: 'Bird', name: 'Bird'),
      UcsSubCategory(id: 'Dog', name: 'Dog'),
      UcsSubCategory(id: 'Cat', name: 'Cat'),
      UcsSubCategory(id: 'Hrs', name: 'Horse'),
      UcsSubCategory(id: 'Ins', name: 'Insect'),
      UcsSubCategory(id: 'Wild', name: 'Wild'),
      UcsSubCategory(id: 'Farm', name: 'Farm'),
    ]),
    UcsCategory(id: 'BELL', name: 'Bells', subCategories: [
      UcsSubCategory(id: 'Chrch', name: 'Church'),
      UcsSubCategory(id: 'Clk', name: 'Clock'),
      UcsSubCategory(id: 'Chm', name: 'Chime'),
      UcsSubCategory(id: 'Sml', name: 'Small'),
    ]),
    UcsCategory(id: 'BOOM', name: 'Booms', subCategories: [
      UcsSubCategory(id: 'Xplo', name: 'Explosion'),
      UcsSubCategory(id: 'Sub', name: 'Sub'),
      UcsSubCategory(id: 'Dist', name: 'Distant'),
      UcsSubCategory(id: 'Lrg', name: 'Large'),
      UcsSubCategory(id: 'Sml', name: 'Small'),
    ]),
    UcsCategory(id: 'CRTN', name: 'Cartoon', subCategories: [
      UcsSubCategory(id: 'Boing', name: 'Boing'),
      UcsSubCategory(id: 'Slip', name: 'Slip'),
      UcsSubCategory(id: 'Pop', name: 'Pop'),
      UcsSubCategory(id: 'Sqsh', name: 'Squish'),
    ]),
    UcsCategory(id: 'CRSH', name: 'Crashes', subCategories: [
      UcsSubCategory(id: 'Gls', name: 'Glass'),
      UcsSubCategory(id: 'Mtl', name: 'Metal'),
      UcsSubCategory(id: 'Wood', name: 'Wood'),
      UcsSubCategory(id: 'Vhcl', name: 'Vehicle'),
      UcsSubCategory(id: 'Dstr', name: 'Destruction'),
    ]),
    UcsCategory(id: 'DOOR', name: 'Doors', subCategories: [
      UcsSubCategory(id: 'Opn', name: 'Open'),
      UcsSubCategory(id: 'Cls', name: 'Close'),
      UcsSubCategory(id: 'Slm', name: 'Slam'),
      UcsSubCategory(id: 'Crk', name: 'Creak'),
      UcsSubCategory(id: 'Knck', name: 'Knock'),
      UcsSubCategory(id: 'Mtl', name: 'Metal'),
      UcsSubCategory(id: 'Wood', name: 'Wood'),
    ]),
    UcsCategory(id: 'DRON', name: 'Drones', subCategories: [
      UcsSubCategory(id: 'Dark', name: 'Dark'),
      UcsSubCategory(id: 'Lght', name: 'Light'),
      UcsSubCategory(id: 'Tnl', name: 'Tonal'),
      UcsSubCategory(id: 'Ntrl', name: 'Neutral'),
      UcsSubCategory(id: 'Hrsh', name: 'Harsh'),
    ]),
    UcsCategory(id: 'ELEC', name: 'Electronic', subCategories: [
      UcsSubCategory(id: 'Beep', name: 'Beep'),
      UcsSubCategory(id: 'Buzz', name: 'Buzz'),
      UcsSubCategory(id: 'Zap', name: 'Zap'),
      UcsSubCategory(id: 'Glch', name: 'Glitch'),
      UcsSubCategory(id: 'Dgtl', name: 'Digital'),
    ]),
    UcsCategory(id: 'FIRE', name: 'Fire', subCategories: [
      UcsSubCategory(id: 'Flm', name: 'Flame'),
      UcsSubCategory(id: 'Trch', name: 'Torch'),
      UcsSubCategory(id: 'Cmpfr', name: 'Campfire'),
      UcsSubCategory(id: 'Blze', name: 'Blaze'),
      UcsSubCategory(id: 'Mtch', name: 'Match'),
    ]),
    UcsCategory(id: 'FOLY', name: 'Foley', subCategories: [
      UcsSubCategory(id: 'Clth', name: 'Cloth'),
      UcsSubCategory(id: 'Ftst', name: 'Footstep'),
      UcsSubCategory(id: 'Mvmt', name: 'Movement'),
      UcsSubCategory(id: 'Ppr', name: 'Paper'),
      UcsSubCategory(id: 'Body', name: 'Body'),
    ]),
    UcsCategory(id: 'GUN', name: 'Guns', subCategories: [
      UcsSubCategory(id: 'Pstl', name: 'Pistol'),
      UcsSubCategory(id: 'Rfl', name: 'Rifle'),
      UcsSubCategory(id: 'Shtgn', name: 'Shotgun'),
      UcsSubCategory(id: 'Auto', name: 'Automatic'),
      UcsSubCategory(id: 'Rld', name: 'Reload'),
      UcsSubCategory(id: 'Mech', name: 'Mechanism'),
    ]),
    UcsCategory(id: 'HORR', name: 'Horror', subCategories: [
      UcsSubCategory(id: 'Scrm', name: 'Scream'),
      UcsSubCategory(id: 'Grwl', name: 'Growl'),
      UcsSubCategory(id: 'Atmo', name: 'Atmosphere'),
      UcsSubCategory(id: 'Crpy', name: 'Creepy'),
      UcsSubCategory(id: 'Mnstr', name: 'Monster'),
    ]),
    UcsCategory(id: 'WHOOSH', name: 'Whooshes', subCategories: [
      UcsSubCategory(id: 'Air', name: 'Air'),
      UcsSubCategory(id: 'Swsh', name: 'Swish'),
      UcsSubCategory(id: 'Flyby', name: 'Flyby'),
      UcsSubCategory(id: 'Sml', name: 'Small'),
      UcsSubCategory(id: 'Lrg', name: 'Large'),
      UcsSubCategory(id: 'Trns', name: 'Transition'),
    ]),
    UcsCategory(id: 'IMPT', name: 'Impacts', subCategories: [
      UcsSubCategory(id: 'Mtl', name: 'Metal'),
      UcsSubCategory(id: 'Wood', name: 'Wood'),
      UcsSubCategory(id: 'Flsh', name: 'Flesh'),
      UcsSubCategory(id: 'Sft', name: 'Soft'),
      UcsSubCategory(id: 'Hrd', name: 'Hard'),
      UcsSubCategory(id: 'Sub', name: 'Sub'),
    ]),
    UcsCategory(id: 'MACH', name: 'Machines', subCategories: [
      UcsSubCategory(id: 'Engn', name: 'Engine'),
      UcsSubCategory(id: 'Mtr', name: 'Motor'),
      UcsSubCategory(id: 'Hydr', name: 'Hydraulic'),
      UcsSubCategory(id: 'Pnmt', name: 'Pneumatic'),
      UcsSubCategory(id: 'Elctr', name: 'Electrical'),
      UcsSubCategory(id: 'Gear', name: 'Gear'),
    ]),
    UcsCategory(id: 'MTL', name: 'Metal', subCategories: [
      UcsSubCategory(id: 'Clng', name: 'Clang'),
      UcsSubCategory(id: 'Scrp', name: 'Scrape'),
      UcsSubCategory(id: 'Ring', name: 'Ring'),
      UcsSubCategory(id: 'Bnce', name: 'Bounce'),
      UcsSubCategory(id: 'Chng', name: 'Chain'),
    ]),
    UcsCategory(id: 'MUSC', name: 'Musical', subCategories: [
      UcsSubCategory(id: 'Stng', name: 'Stinger'),
      UcsSubCategory(id: 'Cue', name: 'Cue'),
      UcsSubCategory(id: 'Loop', name: 'Loop'),
      UcsSubCategory(id: 'Inst', name: 'Instrument'),
      UcsSubCategory(id: 'Perc', name: 'Percussion'),
    ]),
    UcsCategory(id: 'NATR', name: 'Nature', subCategories: [
      UcsSubCategory(id: 'Frst', name: 'Forest'),
      UcsSubCategory(id: 'Ocn', name: 'Ocean'),
      UcsSubCategory(id: 'Rvr', name: 'River'),
      UcsSubCategory(id: 'Thnd', name: 'Thunder'),
      UcsSubCategory(id: 'Erth', name: 'Earth'),
      UcsSubCategory(id: 'Ice', name: 'Ice'),
    ]),
    UcsCategory(id: 'SCI', name: 'Sci-Fi', subCategories: [
      UcsSubCategory(id: 'Lsr', name: 'Laser'),
      UcsSubCategory(id: 'Spc', name: 'Space'),
      UcsSubCategory(id: 'Robt', name: 'Robot'),
      UcsSubCategory(id: 'Alrm', name: 'Alarm'),
      UcsSubCategory(id: 'Hlgm', name: 'Hologram'),
      UcsSubCategory(id: 'Wrp', name: 'Warp'),
    ]),
    UcsCategory(id: 'TRNS', name: 'Transitions', subCategories: [
      UcsSubCategory(id: 'Swp', name: 'Sweep'),
      UcsSubCategory(id: 'Rsr', name: 'Riser'),
      UcsSubCategory(id: 'Dwnr', name: 'Downer'),
      UcsSubCategory(id: 'Swell', name: 'Swell'),
      UcsSubCategory(id: 'Rvrs', name: 'Reverse'),
    ]),
    UcsCategory(id: 'UI', name: 'User Interface', subCategories: [
      UcsSubCategory(id: 'Btn', name: 'Button'),
      UcsSubCategory(id: 'Ntfn', name: 'Notification'),
      UcsSubCategory(id: 'Nav', name: 'Navigation'),
      UcsSubCategory(id: 'Err', name: 'Error'),
      UcsSubCategory(id: 'Cnfm', name: 'Confirm'),
      UcsSubCategory(id: 'Popup', name: 'Popup'),
    ]),
    UcsCategory(id: 'VEH', name: 'Vehicles', subCategories: [
      UcsSubCategory(id: 'Car', name: 'Car'),
      UcsSubCategory(id: 'Trk', name: 'Truck'),
      UcsSubCategory(id: 'Pln', name: 'Plane'),
      UcsSubCategory(id: 'Heli', name: 'Helicopter'),
      UcsSubCategory(id: 'Boat', name: 'Boat'),
      UcsSubCategory(id: 'Mtrc', name: 'Motorcycle'),
    ]),
    UcsCategory(id: 'VOX', name: 'Voice', subCategories: [
      UcsSubCategory(id: 'Dlg', name: 'Dialogue'),
      UcsSubCategory(id: 'Eff', name: 'Effort'),
      UcsSubCategory(id: 'Crwd', name: 'Crowd'),
      UcsSubCategory(id: 'Whsp', name: 'Whisper'),
      UcsSubCategory(id: 'Shout', name: 'Shout'),
    ]),
    UcsCategory(id: 'WTR', name: 'Water', subCategories: [
      UcsSubCategory(id: 'Splsh', name: 'Splash'),
      UcsSubCategory(id: 'Drip', name: 'Drip'),
      UcsSubCategory(id: 'Pour', name: 'Pour'),
      UcsSubCategory(id: 'Bbl', name: 'Bubble'),
      UcsSubCategory(id: 'Wave', name: 'Wave'),
      UcsSubCategory(id: 'Strm', name: 'Stream'),
    ]),
    UcsCategory(id: 'WPN', name: 'Weapons', subCategories: [
      UcsSubCategory(id: 'Swrd', name: 'Sword'),
      UcsSubCategory(id: 'Bld', name: 'Blade'),
      UcsSubCategory(id: 'Shld', name: 'Shield'),
      UcsSubCategory(id: 'Bow', name: 'Bow'),
      UcsSubCategory(id: 'Mace', name: 'Mace'),
      UcsSubCategory(id: 'Whip', name: 'Whip'),
    ]),
    UcsCategory(id: 'WOOD', name: 'Wood', subCategories: [
      UcsSubCategory(id: 'Crk', name: 'Creak'),
      UcsSubCategory(id: 'Snap', name: 'Snap'),
      UcsSubCategory(id: 'Knck', name: 'Knock'),
      UcsSubCategory(id: 'Scrp', name: 'Scrape'),
      UcsSubCategory(id: 'Brk', name: 'Break'),
    ]),
  ];

  /// Find category index by ID
  static int findCategoryIndex(String catId) {
    for (int i = 0; i < categories.length; i++) {
      if (categories[i].id == catId) return i;
    }
    return 0;
  }

  /// Find subcategory index within a category by ID
  static int findSubCategoryIndex(int catIndex, String subId) {
    if (subId.isEmpty) return 0;
    final cat = categories[catIndex];
    for (int i = 0; i < cat.subCategories.length; i++) {
      if (cat.subCategories[i].id == subId) return i;
    }
    return 0;
  }
}
