/// First Event Tutorial (M4)
///
/// Interactive tutorial that guides users through creating their first audio event.

import 'package:flutter/material.dart';
import '../../widgets/tutorial/tutorial_step.dart';

/// First Event tutorial definition
class FirstEventTutorial {
  static Tutorial get tutorial => Tutorial(
        id: 'first_event',
        name: 'Creating Your First Event',
        description: 'Learn the basics of creating and configuring audio events in FluxForge Studio.',
        estimatedMinutes: 5,
        category: TutorialCategory.events,
        difficulty: TutorialDifficulty.beginner,
        steps: [
          const TutorialStep(
            id: 'welcome',
            title: 'Welcome to FluxForge Studio',
            content: 'This tutorial will guide you through creating your first audio event. '
                'Audio events are the building blocks of slot game audio - they define '
                'what sounds play in response to game actions.',
            icon: Icons.waving_hand,
            tooltipPosition: TutorialTooltipPosition.center,
            showSpotlight: false,
            actions: [TutorialAction.skip, TutorialAction.next],
          ),
          const TutorialStep(
            id: 'events_folder',
            title: 'Events Folder',
            content: 'The Events Folder is where you organize all your audio events. '
                'You can create folders to group related events together '
                '(e.g., "Wins", "Spins", "Features").',
            icon: Icons.folder,
            tooltipPosition: TutorialTooltipPosition.bottom,
            actions: [TutorialAction.previous, TutorialAction.next],
          ),
          const TutorialStep(
            id: 'create_event',
            title: 'Create New Event',
            content: 'Click the + button to create a new event. '
                'Give it a descriptive name like "SPIN_START" or "WIN_SMALL". '
                'Event names should match your game\'s stage names.',
            icon: Icons.add_circle,
            tooltipPosition: TutorialTooltipPosition.right,
            actions: [TutorialAction.previous, TutorialAction.next],
          ),
          const TutorialStep(
            id: 'assign_stage',
            title: 'Assign Stage',
            content: 'Each event is triggered by a stage. '
                'Stages are game events like SPIN_START, REEL_STOP, WIN_PRESENT. '
                'Select the stage that should trigger this audio event.',
            icon: Icons.link,
            tooltipPosition: TutorialTooltipPosition.bottom,
            actions: [TutorialAction.previous, TutorialAction.next],
          ),
          const TutorialStep(
            id: 'add_layer',
            title: 'Add Audio Layer',
            content: 'Events can have multiple audio layers that play simultaneously. '
                'Click "Add Layer" to add your first audio file. '
                'Layers can have different volumes, delays, and bus routing.',
            icon: Icons.layers,
            tooltipPosition: TutorialTooltipPosition.right,
            actions: [TutorialAction.previous, TutorialAction.next],
          ),
          const TutorialStep(
            id: 'select_audio',
            title: 'Select Audio File',
            content: 'Browse to select an audio file (.wav, .mp3, .ogg). '
                'You can preview files by clicking on them. '
                'Quality WAV files (44.1kHz or 48kHz) are recommended.',
            icon: Icons.audiotrack,
            tooltipPosition: TutorialTooltipPosition.bottom,
            actions: [TutorialAction.previous, TutorialAction.next],
          ),
          const TutorialStep(
            id: 'configure_layer',
            title: 'Configure Layer',
            content: 'Adjust the layer properties:\n'
                '• Volume: -60dB to +12dB\n'
                '• Pan: Left (-1) to Right (+1)\n'
                '• Delay: Milliseconds before playback\n'
                '• Bus: Audio routing destination',
            icon: Icons.tune,
            tooltipPosition: TutorialTooltipPosition.left,
            actions: [TutorialAction.previous, TutorialAction.next],
          ),
          const TutorialStep(
            id: 'test_event',
            title: 'Test Your Event',
            content: 'Click the play button to preview your event. '
                'You can also test it in the Slot Lab by triggering the associated stage. '
                'Adjust volume and timing until it sounds right.',
            icon: Icons.play_circle,
            tooltipPosition: TutorialTooltipPosition.bottom,
            actions: [TutorialAction.previous, TutorialAction.next],
          ),
          const TutorialStep(
            id: 'complete',
            title: 'Congratulations!',
            content: 'You\'ve created your first audio event! '
                'Next steps:\n'
                '• Create more events for different stages\n'
                '• Explore RTPC for dynamic audio\n'
                '• Use containers for variation',
            icon: Icons.celebration,
            tooltipPosition: TutorialTooltipPosition.center,
            showSpotlight: false,
            actions: [TutorialAction.finish],
          ),
        ],
      );
}

/// RTPC Setup tutorial definition
class RtpcSetupTutorial {
  static Tutorial get tutorial => Tutorial(
        id: 'rtpc_setup',
        name: 'Setting Up RTPC',
        description: 'Learn how to use Real-Time Parameter Control for dynamic audio.',
        estimatedMinutes: 7,
        category: TutorialCategory.rtpc,
        difficulty: TutorialDifficulty.intermediate,
        prerequisites: ['first_event'],
        steps: [
          const TutorialStep(
            id: 'intro',
            title: 'What is RTPC?',
            content: 'RTPC (Real-Time Parameter Control) lets you dynamically '
                'control audio parameters based on game values. '
                'For example, increase music intensity as wins get bigger.',
            icon: Icons.tune,
            tooltipPosition: TutorialTooltipPosition.center,
            showSpotlight: false,
            actions: [TutorialAction.skip, TutorialAction.next],
          ),
          const TutorialStep(
            id: 'create_rtpc',
            title: 'Create RTPC Parameter',
            content: 'Go to the RTPC panel and click "+ New RTPC". '
                'Name it something descriptive like "WinIntensity" or "FeatureProgress". '
                'Set the min/max range (typically 0-1 or 0-100).',
            icon: Icons.add,
            tooltipPosition: TutorialTooltipPosition.bottom,
            actions: [TutorialAction.previous, TutorialAction.next],
          ),
          const TutorialStep(
            id: 'define_curve',
            title: 'Define Response Curve',
            content: 'The curve determines how the parameter affects audio. '
                'Common curves:\n'
                '• Linear: Proportional response\n'
                '• Exponential: Subtle at low, dramatic at high\n'
                '• S-Curve: Gradual start and end',
            icon: Icons.show_chart,
            tooltipPosition: TutorialTooltipPosition.right,
            actions: [TutorialAction.previous, TutorialAction.next],
          ),
          const TutorialStep(
            id: 'bind_parameter',
            title: 'Bind to Audio Property',
            content: 'Connect the RTPC to an audio property:\n'
                '• Volume: Fade in/out based on value\n'
                '• Pitch: Change playback speed\n'
                '• Filter: Open/close frequency cutoff\n'
                '• Pan: Move sound in stereo field',
            icon: Icons.link,
            tooltipPosition: TutorialTooltipPosition.left,
            actions: [TutorialAction.previous, TutorialAction.next],
          ),
          const TutorialStep(
            id: 'test_rtpc',
            title: 'Test RTPC',
            content: 'Use the RTPC debugger to manually adjust the value '
                'and hear the effect in real-time. '
                'Fine-tune the curve until the response feels right.',
            icon: Icons.bug_report,
            tooltipPosition: TutorialTooltipPosition.bottom,
            actions: [TutorialAction.previous, TutorialAction.next],
          ),
          const TutorialStep(
            id: 'complete',
            title: 'RTPC Ready!',
            content: 'Your RTPC is set up and ready to use. '
                'The game engine will send RTPC values, and the audio will respond dynamically. '
                'Explore macros for controlling multiple parameters at once.',
            icon: Icons.check_circle,
            tooltipPosition: TutorialTooltipPosition.center,
            showSpotlight: false,
            actions: [TutorialAction.finish],
          ),
        ],
      );
}

/// All available tutorials
class BuiltInTutorials {
  static List<Tutorial> get all => [
        FirstEventTutorial.tutorial,
        RtpcSetupTutorial.tutorial,
      ];
}
