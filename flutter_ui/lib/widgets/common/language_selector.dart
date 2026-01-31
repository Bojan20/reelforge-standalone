/// Language Selector Widget — P3-08
///
/// Dropdown for selecting application language.
/// Persists choice via LocalizationService.
///
/// Usage:
///   LanguageSelector()           // Full dropdown with flags
///   LanguageSelectorCompact()    // Icon button with popup
library;

import 'package:flutter/material.dart';
import '../../services/localization_service.dart';

/// Full language dropdown with flags and names
class LanguageSelector extends StatefulWidget {
  final bool showFlag;
  final bool showNativeName;
  final double? width;

  const LanguageSelector({
    super.key,
    this.showFlag = true,
    this.showNativeName = true,
    this.width,
  });

  @override
  State<LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends State<LanguageSelector> {
  @override
  void initState() {
    super.initState();
    LocalizationService.instance.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    LocalizationService.instance.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = LocalizationService.instance;
    final currentInfo = service.currentLocaleInfo;

    return Container(
      width: widget.width ?? 200,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentInfo.locale.languageCode,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1A20),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: kSupportedLocales.map((locale) {
            return DropdownMenuItem<String>(
              value: locale.locale.languageCode,
              child: Row(
                children: [
                  if (widget.showFlag) ...[
                    Text(locale.flag, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    widget.showNativeName ? locale.nativeName : locale.displayName,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (code) {
            if (code != null) {
              service.setLocaleByCode(code);
            }
          },
        ),
      ),
    );
  }
}

/// Compact language selector as icon button with popup
class LanguageSelectorCompact extends StatefulWidget {
  final double iconSize;
  final Color? iconColor;

  const LanguageSelectorCompact({
    super.key,
    this.iconSize = 20,
    this.iconColor,
  });

  @override
  State<LanguageSelectorCompact> createState() => _LanguageSelectorCompactState();
}

class _LanguageSelectorCompactState extends State<LanguageSelectorCompact> {
  @override
  void initState() {
    super.initState();
    LocalizationService.instance.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    LocalizationService.instance.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  void _showLanguageMenu(BuildContext context) {
    final service = LocalizationService.instance;
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + button.size.height,
        offset.dx + button.size.width,
        0,
      ),
      color: const Color(0xFF1A1A20),
      items: kSupportedLocales.map((locale) {
        final isSelected = locale.locale.languageCode ==
            service.currentLocale.languageCode;
        return PopupMenuItem<String>(
          value: locale.locale.languageCode,
          child: Row(
            children: [
              Text(locale.flag, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                locale.nativeName,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF4A9EFF) : Colors.white,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              const Spacer(),
              if (isSelected)
                const Icon(Icons.check, color: Color(0xFF4A9EFF), size: 16),
            ],
          ),
        );
      }).toList(),
    ).then((code) {
      if (code != null) {
        service.setLocaleByCode(code);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = LocalizationService.instance;
    final currentInfo = service.currentLocaleInfo;

    return Tooltip(
      message: 'Language: ${currentInfo.displayName}',
      child: InkWell(
        onTap: () => _showLanguageMenu(context),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(currentInfo.flag, style: TextStyle(fontSize: widget.iconSize)),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: widget.iconSize * 0.8,
                color: widget.iconColor ?? Colors.white54,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Language settings panel for Settings dialog
class LanguageSettingsPanel extends StatefulWidget {
  const LanguageSettingsPanel({super.key});

  @override
  State<LanguageSettingsPanel> createState() => _LanguageSettingsPanelState();
}

class _LanguageSettingsPanelState extends State<LanguageSettingsPanel> {
  @override
  void initState() {
    super.initState();
    LocalizationService.instance.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    LocalizationService.instance.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = LocalizationService.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Language / Jezik / Sprache',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        ...kSupportedLocales.map((locale) {
          final isSelected = locale.locale.languageCode ==
              service.currentLocale.languageCode;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => service.setLocale(locale.locale),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF4A9EFF).withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF4A9EFF)
                        : Colors.white12,
                  ),
                ),
                child: Row(
                  children: [
                    Text(locale.flag, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          locale.nativeName,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF4A9EFF)
                                : Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          locale.displayName,
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (isSelected)
                      const Icon(Icons.check_circle, color: Color(0xFF4A9EFF), size: 20),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
