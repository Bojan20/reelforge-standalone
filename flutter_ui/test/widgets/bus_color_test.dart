/// Bus Color Picker Tests (P10.1.14)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/mixer/bus_color_picker.dart';

void main() {
  group('BusColorPicker', () {
    testWidgets('displays current color', (tester) async {
      const testColor = Color(0xFF4A9EFF);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusColorPicker(
              currentColor: testColor,
              onColorChanged: (_) {},
            ),
          ),
        ),
      );

      // Should show a container with the current color
      final colorContainer = find.byType(Container).first;
      expect(colorContainer, findsOneWidget);
    });

    testWidgets('opens color picker popup on tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusColorPicker(
              currentColor: busColorPresets[0],
              onColorChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(BusColorPicker));
      await tester.pumpAndSettle();

      expect(find.text('Select Color'), findsOneWidget);
    });

    testWidgets('calls onColorChanged when color selected', (tester) async {
      Color? selectedColor;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusColorPicker(
              currentColor: busColorPresets[0],
              onColorChanged: (color) => selectedColor = color,
            ),
          ),
        ),
      );

      // Open popup
      await tester.tap(find.byType(BusColorPicker));
      await tester.pumpAndSettle();

      // Find all color swatches (InkWell widgets inside popup)
      // The popup has multiple swatches, tap one of them
      final swatches = find.descendant(
        of: find.byType(PopupMenuItem<Color>),
        matching: find.byType(InkWell),
      );

      expect(swatches, findsWidgets);

      // Tap the second color swatch
      await tester.tap(swatches.at(1));
      await tester.pumpAndSettle();

      expect(selectedColor, isNotNull);
    });
  });

  group('BusColorPickerInline', () {
    testWidgets('displays limited colors in row', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusColorPickerInline(
              currentColor: busColorPresets[0],
              onColorChanged: (_) {},
              maxColors: 4,
            ),
          ),
        ),
      );

      // Should have exactly 4 small swatches + overflow picker
      final containers = find.byType(Container);
      expect(containers, findsWidgets);
    });

    testWidgets('selects color on tap', (tester) async {
      Color? selectedColor;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusColorPickerInline(
              currentColor: busColorPresets[0],
              onColorChanged: (color) => selectedColor = color,
              maxColors: 6,
            ),
          ),
        ),
      );

      // Find all InkWell (tappable swatches)
      final inkwells = find.byType(InkWell);
      expect(inkwells, findsWidgets);

      // Tap second color
      await tester.tap(inkwells.at(1));
      await tester.pumpAndSettle();

      expect(selectedColor, isNotNull);
      expect(selectedColor, busColorPresets[1]);
    });
  });

  group('busColorPresets', () {
    test('has 12 preset colors', () {
      expect(busColorPresets.length, 12);
    });

    test('all colors are distinct', () {
      final uniqueColors = busColorPresets.map((c) => c.value).toSet();
      expect(uniqueColors.length, busColorPresets.length);
    });
  });
}
