// ============================================================================
// FluxForge Studio — Feature Builder Block Options
// ============================================================================
// P13.0.4: Block option types and definitions
// Defines configurable options for feature blocks (toggle, dropdown, range, etc.)
// ============================================================================

/// Types of options that can be configured for a block.
enum BlockOptionType {
  /// Boolean toggle (on/off).
  toggle,

  /// Single selection from a list of choices.
  dropdown,

  /// Numeric value within a range.
  range,

  /// Multiple selections from a list.
  multiSelect,

  /// Integer count (spin count, reel count, etc.).
  count,

  /// Percentage value (0-100 or 0-1000 for per-mille).
  percentage,

  /// Text input for custom labels.
  text,

  /// Color picker for visual customization.
  color,
}

/// Definition of a configurable option for a feature block.
///
/// Each block can have multiple options that the user can configure.
/// Options are serialized to JSON for preset storage.
class BlockOption {
  /// Unique identifier for this option within the block.
  final String id;

  /// Human-readable display name.
  final String name;

  /// Optional description/tooltip text.
  final String? description;

  /// The type of input control to render.
  final BlockOptionType type;

  /// Default value for this option.
  final dynamic defaultValue;

  /// Current value (mutable).
  dynamic _value;

  /// For dropdown/multiSelect: available choices.
  final List<OptionChoice>? choices;

  /// For range/count/percentage: minimum value.
  final num? min;

  /// For range/count/percentage: maximum value.
  final num? max;

  /// For range: step increment.
  final num? step;

  /// For percentage: whether to use per-mille (0-1000) instead of percent.
  final bool perMille;

  /// Whether this option is required (cannot be left empty).
  final bool required;

  /// Whether this option is advanced (hidden by default).
  final bool advanced;

  /// Validation function (returns error message or null if valid).
  final String? Function(dynamic value)? validator;

  /// Callback when value changes.
  final void Function(dynamic value)? onChanged;

  /// Groups related options together in the UI.
  final String? group;

  /// Display order within the group (lower = first).
  final int order;

  /// Conditions that must be met for this option to be visible.
  /// Format: {"optionId": expectedValue}
  final Map<String, dynamic>? visibleWhen;

  BlockOption({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    required this.defaultValue,
    this.choices,
    this.min,
    this.max,
    this.step,
    this.perMille = false,
    this.required = false,
    this.advanced = false,
    this.validator,
    this.onChanged,
    this.group,
    this.order = 0,
    this.visibleWhen,
  }) : _value = defaultValue;

  /// Current value of the option.
  dynamic get value => _value;

  /// Set the value with validation.
  set value(dynamic newValue) {
    if (validator != null) {
      final error = validator!(newValue);
      if (error != null) {
        throw ArgumentError('Invalid value for $id: $error');
      }
    }
    _value = newValue;
    onChanged?.call(newValue);
  }

  /// Whether the current value differs from the default.
  bool get isModified => _value != defaultValue;

  /// Reset to default value.
  void reset() {
    _value = defaultValue;
    onChanged?.call(_value);
  }

  /// Validate the current value.
  String? validate() {
    if (required && _value == null) {
      return '$name is required';
    }
    if (validator != null) {
      return validator!(_value);
    }
    return null;
  }

  /// Create a copy with optionally modified properties.
  BlockOption copyWith({
    String? id,
    String? name,
    String? description,
    BlockOptionType? type,
    dynamic defaultValue,
    dynamic currentValue,
    List<OptionChoice>? choices,
    num? min,
    num? max,
    num? step,
    bool? perMille,
    bool? required,
    bool? advanced,
    String? Function(dynamic value)? validator,
    void Function(dynamic value)? onChanged,
    String? group,
    int? order,
    Map<String, dynamic>? visibleWhen,
  }) {
    final option = BlockOption(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      defaultValue: defaultValue ?? this.defaultValue,
      choices: choices ?? this.choices,
      min: min ?? this.min,
      max: max ?? this.max,
      step: step ?? this.step,
      perMille: perMille ?? this.perMille,
      required: required ?? this.required,
      advanced: advanced ?? this.advanced,
      validator: validator ?? this.validator,
      onChanged: onChanged ?? this.onChanged,
      group: group ?? this.group,
      order: order ?? this.order,
      visibleWhen: visibleWhen ?? this.visibleWhen,
    );
    option._value = currentValue ?? _value;
    return option;
  }

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        'type': type.name,
        'defaultValue': defaultValue,
        'value': _value,
        if (choices != null) 'choices': choices!.map((c) => c.toJson()).toList(),
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (step != null) 'step': step,
        if (perMille) 'perMille': perMille,
        if (required) 'required': required,
        if (advanced) 'advanced': advanced,
        if (group != null) 'group': group,
        'order': order,
        if (visibleWhen != null) 'visibleWhen': visibleWhen,
      };

  /// Deserialize from JSON.
  factory BlockOption.fromJson(Map<String, dynamic> json) {
    final option = BlockOption(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      type: BlockOptionType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => BlockOptionType.toggle,
      ),
      defaultValue: json['defaultValue'],
      choices: json['choices'] != null
          ? (json['choices'] as List)
              .map((c) => OptionChoice.fromJson(c as Map<String, dynamic>))
              .toList()
          : null,
      min: json['min'] as num?,
      max: json['max'] as num?,
      step: json['step'] as num?,
      perMille: json['perMille'] as bool? ?? false,
      required: json['required'] as bool? ?? false,
      advanced: json['advanced'] as bool? ?? false,
      group: json['group'] as String?,
      order: json['order'] as int? ?? 0,
      visibleWhen: json['visibleWhen'] as Map<String, dynamic>?,
    );
    if (json['value'] != null) {
      option._value = json['value'];
    }
    return option;
  }

  @override
  String toString() => 'BlockOption($id: $_value)';
}

/// A choice for dropdown or multi-select options.
class OptionChoice {
  /// The value to store when this choice is selected.
  final dynamic value;

  /// Human-readable label.
  final String label;

  /// Optional description/tooltip.
  final String? description;

  /// Optional icon name.
  final String? icon;

  /// Whether this choice is disabled.
  final bool disabled;

  /// Optional group for organizing choices.
  final String? group;

  const OptionChoice({
    required this.value,
    required this.label,
    this.description,
    this.icon,
    this.disabled = false,
    this.group,
  });

  Map<String, dynamic> toJson() => {
        'value': value,
        'label': label,
        if (description != null) 'description': description,
        if (icon != null) 'icon': icon,
        if (disabled) 'disabled': disabled,
        if (group != null) 'group': group,
      };

  factory OptionChoice.fromJson(Map<String, dynamic> json) => OptionChoice(
        value: json['value'],
        label: json['label'] as String,
        description: json['description'] as String?,
        icon: json['icon'] as String?,
        disabled: json['disabled'] as bool? ?? false,
        group: json['group'] as String?,
      );

  @override
  String toString() => 'OptionChoice($label)';
}

// ============================================================================
// Factory Methods for Common Option Types
// ============================================================================

/// Factory for creating common option types.
class BlockOptionFactory {
  BlockOptionFactory._();

  /// Create a toggle (boolean) option.
  static BlockOption toggle({
    required String id,
    required String name,
    String? description,
    bool defaultValue = false,
    String? group,
    int order = 0,
    Map<String, dynamic>? visibleWhen,
  }) =>
      BlockOption(
        id: id,
        name: name,
        description: description,
        type: BlockOptionType.toggle,
        defaultValue: defaultValue,
        group: group,
        order: order,
        visibleWhen: visibleWhen,
      );

  /// Create a dropdown (single select) option.
  static BlockOption dropdown({
    required String id,
    required String name,
    String? description,
    required List<OptionChoice> choices,
    required dynamic defaultValue,
    bool required = false,
    String? group,
    int order = 0,
    Map<String, dynamic>? visibleWhen,
  }) =>
      BlockOption(
        id: id,
        name: name,
        description: description,
        type: BlockOptionType.dropdown,
        defaultValue: defaultValue,
        choices: choices,
        required: required,
        group: group,
        order: order,
        visibleWhen: visibleWhen,
      );

  /// Create a range (numeric slider) option.
  static BlockOption range({
    required String id,
    required String name,
    String? description,
    required num min,
    required num max,
    num step = 1,
    required num defaultValue,
    String? group,
    int order = 0,
    Map<String, dynamic>? visibleWhen,
  }) =>
      BlockOption(
        id: id,
        name: name,
        description: description,
        type: BlockOptionType.range,
        defaultValue: defaultValue,
        min: min,
        max: max,
        step: step,
        group: group,
        order: order,
        visibleWhen: visibleWhen,
      );

  /// Create a count (integer stepper) option.
  static BlockOption count({
    required String id,
    required String name,
    String? description,
    required int min,
    required int max,
    required int defaultValue,
    String? group,
    int order = 0,
    Map<String, dynamic>? visibleWhen,
  }) =>
      BlockOption(
        id: id,
        name: name,
        description: description,
        type: BlockOptionType.count,
        defaultValue: defaultValue,
        min: min,
        max: max,
        step: 1,
        group: group,
        order: order,
        visibleWhen: visibleWhen,
      );

  /// Create a percentage option.
  static BlockOption percentage({
    required String id,
    required String name,
    String? description,
    required double defaultValue,
    bool perMille = false,
    String? group,
    int order = 0,
    Map<String, dynamic>? visibleWhen,
  }) =>
      BlockOption(
        id: id,
        name: name,
        description: description,
        type: BlockOptionType.percentage,
        defaultValue: defaultValue,
        min: 0,
        max: perMille ? 1000 : 100,
        step: perMille ? 1 : 0.1,
        perMille: perMille,
        group: group,
        order: order,
        visibleWhen: visibleWhen,
      );

  /// Create a multi-select option.
  static BlockOption multiSelect({
    required String id,
    required String name,
    String? description,
    required List<OptionChoice> choices,
    required List<dynamic> defaultValue,
    String? group,
    int order = 0,
    Map<String, dynamic>? visibleWhen,
  }) =>
      BlockOption(
        id: id,
        name: name,
        description: description,
        type: BlockOptionType.multiSelect,
        defaultValue: defaultValue,
        choices: choices,
        group: group,
        order: order,
        visibleWhen: visibleWhen,
      );

  /// Create a text input option.
  static BlockOption text({
    required String id,
    required String name,
    String? description,
    String defaultValue = '',
    bool required = false,
    String? group,
    int order = 0,
    Map<String, dynamic>? visibleWhen,
  }) =>
      BlockOption(
        id: id,
        name: name,
        description: description,
        type: BlockOptionType.text,
        defaultValue: defaultValue,
        required: required,
        group: group,
        order: order,
        visibleWhen: visibleWhen,
      );
}
