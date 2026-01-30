/// Tutorial Step Definitions
///
/// Defines all tutorial steps for onboarding flows:
/// - Basic workflow (5 steps)
/// - SlotLab workflow (5 steps)
///
/// Each step includes:
/// - Title and description
/// - Spotlight position and radius
/// - Tooltip position
/// - Step-by-step instructions
/// - Pro tips
library;

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// Arrow direction for tutorial pointer
enum ArrowDirection { up, down, left, right }

/// Tutorial step data model
class TutorialStep {
  final String title;
  final String description;
  final List<String> instructions;
  final List<String> tips;
  final IconData icon;
  final Color iconColor;
  final Rect? spotlightRect;
  final double spotlightRadius;
  final Offset tooltipPosition;
  final bool showArrow;
  final Offset arrowPosition;
  final ArrowDirection arrowDirection;

  const TutorialStep({
    required this.title,
    required this.description,
    this.instructions = const [],
    this.tips = const [],
    required this.icon,
    required this.iconColor,
    this.spotlightRect,
    this.spotlightRadius = 8.0,
    required this.tooltipPosition,
    this.showArrow = false,
    this.arrowPosition = Offset.zero,
    this.arrowDirection = ArrowDirection.down,
  });
}

/// All tutorial step definitions
class TutorialSteps {
  /// Basic workflow tutorial (Middleware section)
  static final List<TutorialStep> basicSteps = [
    // Step 1: Create Event
    TutorialStep(
      title: 'Create Your First Event',
      description:
          'Events are the building blocks of your audio system. They trigger sounds in response to game actions.',
      instructions: [
        'Click the "+" button in the Events Panel (right side)',
        'Give your event a descriptive name (e.g., "Spin Button Click")',
        'Select a target stage from the dropdown (e.g., SPIN_START)',
        'Click "Create" to add the event',
      ],
      tips: [
        'Event names should describe the game action, not the sound',
        'You can create multiple events for the same stage',
      ],
      icon: Icons.add_circle_outline,
      iconColor: FluxForgeTheme.successGreen,
      spotlightRect: const Rect.fromLTWH(1400, 100, 400, 600),
      spotlightRadius: 12,
      tooltipPosition: const Offset(900, 200),
      showArrow: true,
      arrowPosition: const Offset(1350, 300),
      arrowDirection: ArrowDirection.right,
    ),

    // Step 2: Assign Audio
    TutorialStep(
      title: 'Assign Audio to Event',
      description:
          'Add audio layers to your event. Each layer can have its own volume, pan, and timing offset.',
      instructions: [
        'Select your newly created event in the Events Panel',
        'Click "Add Layer" in the event inspector',
        'Browse and select an audio file (WAV, MP3, FLAC, or OGG)',
        'The audio file is now assigned to this event',
      ],
      tips: [
        'You can add multiple layers to create complex sounds',
        'Use the audio browser to preview files before adding',
        'Drag files directly from your OS file explorer',
      ],
      icon: Icons.audio_file,
      iconColor: FluxForgeTheme.accentBlue,
      spotlightRect: const Rect.fromLTWH(1400, 100, 400, 600),
      spotlightRadius: 12,
      tooltipPosition: const Offset(900, 200),
      showArrow: true,
      arrowPosition: const Offset(1350, 400),
      arrowDirection: ArrowDirection.right,
    ),

    // Step 3: Test Playback
    TutorialStep(
      title: 'Test Your Event',
      description:
          'Verify that your event plays correctly by triggering it manually.',
      instructions: [
        'With your event selected, click the "Preview" button',
        'Or: Use the keyboard shortcut (Space)',
        'Listen to confirm the audio plays as expected',
        'Check the Event Log (bottom panel) to see playback details',
      ],
      tips: [
        'The Event Log shows voice ID, bus routing, and latency',
        'Green checkmarks indicate successful playback',
        'Red warnings indicate missing audio or FFI issues',
      ],
      icon: Icons.play_circle_outline,
      iconColor: FluxForgeTheme.warningOrange,
      spotlightRect: const Rect.fromLTWH(1400, 100, 400, 600),
      spotlightRadius: 12,
      tooltipPosition: const Offset(900, 200),
      showArrow: true,
      arrowPosition: const Offset(1350, 500),
      arrowDirection: ArrowDirection.right,
    ),

    // Step 4: Adjust Timing
    TutorialStep(
      title: 'Fine-Tune Layer Timing',
      description:
          'Add delays and offsets to create complex, layered sounds that feel more natural.',
      instructions: [
        'Open the Layer Inspector by selecting a layer',
        'Use the "Delay" slider to add pre-delay (0-2000ms)',
        'Use the "Offset" slider to shift playback timing',
        'Adjust "Fade In" and "Fade Out" for smooth transitions',
        'Preview the event again to hear your changes',
      ],
      tips: [
        'Small delays (10-50ms) can make layers feel more natural',
        'Use offsets to create rhythmic patterns',
        'Fade times prevent clicks and pops',
      ],
      icon: Icons.tune,
      iconColor: FluxForgeTheme.accentCyan,
      spotlightRect: const Rect.fromLTWH(1400, 100, 400, 600),
      spotlightRadius: 12,
      tooltipPosition: const Offset(900, 200),
      showArrow: true,
      arrowPosition: const Offset(1350, 550),
      arrowDirection: ArrowDirection.right,
    ),

    // Step 5: Export
    TutorialStep(
      title: 'Export Your Work',
      description:
          'Export your audio configuration for use in your game engine.',
      instructions: [
        'Go to the Middleware section (top navigation)',
        'Click the "Export" button in the Deliver tab',
        'Choose your target platform (Unity, Unreal, Howler.js)',
        'Select an output folder',
        'Click "Export Package" to generate files',
      ],
      tips: [
        'Exported packages include all audio, events, and configurations',
        'Unity exports include C# scripts for easy integration',
        'Unreal exports include Blueprint-compatible components',
        'Howler.js exports are ready for web deployment',
      ],
      icon: Icons.download,
      iconColor: FluxForgeTheme.successGreen,
      spotlightRect: const Rect.fromLTWH(100, 50, 1200, 50),
      spotlightRadius: 8,
      tooltipPosition: const Offset(400, 200),
      showArrow: true,
      arrowPosition: const Offset(800, 150),
      arrowDirection: ArrowDirection.up,
    ),
  ];

  /// SlotLab workflow tutorial
  static final List<TutorialStep> slotLabSteps = [
    // Step 1: Understanding the Slot Preview
    TutorialStep(
      title: 'Meet the Slot Simulator',
      description:
          'The slot preview is your audio testing playground. It simulates real slot machine behavior.',
      instructions: [
        'Press the SPIN button to start a spin',
        'Watch the reels animate and stop sequentially',
        'Observe the stage events in the Stage Trace (bottom)',
        'Listen for audio triggers at each stage',
      ],
      tips: [
        'Use F11 to enter fullscreen preview mode',
        'Press Space to spin or stop',
        'Press 1-7 to force specific outcomes (lose, small win, big win, etc.)',
      ],
      icon: Icons.casino,
      iconColor: FluxForgeTheme.accentBlue,
      spotlightRect: const Rect.fromLTWH(300, 100, 800, 600),
      spotlightRadius: 16,
      tooltipPosition: const Offset(100, 200),
      showArrow: true,
      arrowPosition: const Offset(550, 50),
      arrowDirection: ArrowDirection.down,
    ),

    // Step 2: Drop Zone Editing
    TutorialStep(
      title: 'Assign Audio via Drop Zones',
      description:
          'The fastest way to assign audio is by dragging files directly onto slot elements.',
      instructions: [
        'Click "Edit Mode" to activate drop zones',
        'Drag an audio file from the browser panel',
        'Drop it on a slot element (Spin button, reel, win overlay)',
        'A quick-sheet popup appears for confirmation',
        'Click "Commit" to create the event',
      ],
      tips: [
        'Drop zones are color-coded: Blue (UI), Purple (Reels), Gold (Wins)',
        'You can drop the same file on multiple targets',
        'Press Escape to exit Edit Mode',
      ],
      icon: Icons.touch_app,
      iconColor: FluxForgeTheme.successGreen,
      spotlightRect: const Rect.fromLTWH(300, 100, 800, 600),
      spotlightRadius: 16,
      tooltipPosition: const Offset(100, 200),
      showArrow: true,
      arrowPosition: const Offset(550, 50),
      arrowDirection: ArrowDirection.down,
    ),

    // Step 3: Stage Flow
    TutorialStep(
      title: 'Understand Stage Flow',
      description:
          'Slot games follow a predictable sequence of stages. Each stage can trigger audio events.',
      instructions: [
        'Spin the reels and watch the Stage Trace panel',
        'Observe the sequence: SPIN_START → REEL_STOP_0 → WIN_PRESENT',
        'Each stage is an audio trigger point',
        'Events are automatically matched to stages',
      ],
      tips: [
        'Stage flow varies based on game features (cascades, free spins, etc.)',
        'You can force specific outcomes to test rare stages',
        'The Event Log shows which events fired for each stage',
      ],
      icon: Icons.timeline,
      iconColor: FluxForgeTheme.warningOrange,
      spotlightRect: const Rect.fromLTWH(0, 700, 1920, 300),
      spotlightRadius: 12,
      tooltipPosition: const Offset(600, 500),
      showArrow: true,
      arrowPosition: const Offset(960, 650),
      arrowDirection: ArrowDirection.down,
    ),

    // Step 4: Testing Outcomes
    TutorialStep(
      title: 'Test Different Outcomes',
      description:
          'Use forced outcomes to test audio for rare events like big wins and jackpots.',
      instructions: [
        'Open the Forced Outcome panel (F tab in Lower Zone)',
        'Click "Big Win" to force a big win outcome',
        'Spin and listen to the full win presentation',
        'Try "Free Spins" to test feature trigger audio',
        'Use "Cascade" to test cascade audio sequences',
      ],
      tips: [
        'Keyboard shortcuts: 1=Lose, 2=Small Win, 3=Big Win, 4=Mega Win',
        'Big wins trigger rollup audio with tier-specific durations',
        'Free spins and bonus features have enter/exit audio stages',
      ],
      icon: Icons.science,
      iconColor: FluxForgeTheme.accentCyan,
      spotlightRect: const Rect.fromLTWH(0, 700, 1920, 300),
      spotlightRadius: 12,
      tooltipPosition: const Offset(600, 500),
      showArrow: true,
      arrowPosition: const Offset(960, 650),
      arrowDirection: ArrowDirection.down,
    ),

    // Step 5: Exporting for Production
    TutorialStep(
      title: 'Export for Your Game',
      description:
          'Once your audio is perfect, export it for integration into your slot game.',
      instructions: [
        'Navigate to the Middleware section',
        'Go to the Deliver tab in the Lower Zone',
        'Click "Validate" to check for missing audio',
        'Click "Bake All" to process audio (optional)',
        'Click "Package" to create the final export',
      ],
      tips: [
        'Validation ensures all stages have audio assigned',
        'Baking applies offline processing (normalization, compression)',
        'Package includes soundbanks, manifests, and integration scripts',
        'Choose your export format: Unity, Unreal, Howler.js, or Universal',
      ],
      icon: Icons.verified,
      iconColor: FluxForgeTheme.successGreen,
      spotlightRect: const Rect.fromLTWH(0, 700, 1920, 300),
      spotlightRadius: 12,
      tooltipPosition: const Offset(600, 500),
      showArrow: true,
      arrowPosition: const Offset(960, 650),
      arrowDirection: ArrowDirection.down,
    ),
  ];

  /// Get steps for a specific section
  static List<TutorialStep> stepsForSection(String section) {
    switch (section.toLowerCase()) {
      case 'slotlab':
      case 'slot_lab':
        return slotLabSteps;
      case 'middleware':
      case 'daw':
      default:
        return basicSteps;
    }
  }
}
