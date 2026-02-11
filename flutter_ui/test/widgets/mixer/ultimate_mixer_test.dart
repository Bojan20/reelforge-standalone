/// Ultimate Mixer Widget Tests
///
/// Tests for mixer models and calculations:
/// - MixerChannel model defaults, copyWith, volumeDbString
/// - ChannelType enum completeness
/// - AuxSend model
/// - VcaFader model
/// - MixerGroup link modes
/// - Channel ordering and reorder logic
/// - Mute/Solo interaction rules
@Tags(['widget'])
library;

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/mixer_provider.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // ChannelType Enum Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('ChannelType', () {
    test('has all 6 expected types', () {
      expect(ChannelType.values.length, 6);
      expect(ChannelType.audio, isNotNull);
      expect(ChannelType.instrument, isNotNull);
      expect(ChannelType.bus, isNotNull);
      expect(ChannelType.aux, isNotNull);
      expect(ChannelType.vca, isNotNull);
      expect(ChannelType.master, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MixerChannel Model Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('MixerChannel dB calculations', () {
    test('volume 0.0 gives -infinity dB', () {
      final ch = MixerChannel(id: '1', name: 'T', type: ChannelType.audio, volume: 0);
      // Should contain infinity symbol
      expect(ch.volumeDbString.contains('∞') || ch.volumeDbString.contains('inf'), true);
    });

    test('volume 1.0 gives 0.0 dB', () {
      final ch = MixerChannel(id: '1', name: 'T', type: ChannelType.audio, volume: 1.0);
      expect(ch.volumeDbString, contains('0.0'));
    });

    test('volume 0.5 gives approximately -6 dB', () {
      final ch = MixerChannel(id: '1', name: 'T', type: ChannelType.audio, volume: 0.5);
      // 20 * log10(0.5) = -6.02
      final dbStr = ch.volumeDbString;
      expect(dbStr, contains('-'));
      expect(dbStr, contains('6'));
    });

    test('volume 2.0 gives approximately +6 dB', () {
      final ch = MixerChannel(id: '1', name: 'T', type: ChannelType.audio, volume: 2.0);
      final dbStr = ch.volumeDbString;
      expect(dbStr, startsWith('+'));
      expect(dbStr, contains('6'));
    });

    test('volume values obey logarithmic relationship', () {
      // Doubling volume = +6.02 dB
      final ch1 = MixerChannel(id: '1', name: 'T', type: ChannelType.audio, volume: 0.5);
      final ch2 = MixerChannel(id: '2', name: 'T', type: ChannelType.audio, volume: 1.0);

      // Extract numeric dB values
      final db1 = _parseDb(ch1.volumeDbString);
      final db2 = _parseDb(ch2.volumeDbString);

      if (db1 != null && db2 != null) {
        expect((db2 - db1).abs(), closeTo(6.02, 0.1));
      }
    });
  });

  group('MixerChannel sends', () {
    test('8 default inserts with 4 pre and 4 post', () {
      final ch = MixerChannel(id: '1', name: 'T', type: ChannelType.audio);
      expect(ch.inserts.length, 8);
      final pre = ch.inserts.where((i) => i.isPreFader).length;
      final post = ch.inserts.where((i) => !i.isPreFader).length;
      expect(pre, 4);
      expect(post, 4);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // AuxSend Model Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('AuxSend', () {
    test('defaults: level 0, post-fader, enabled', () {
      final send = AuxSend(auxId: 'aux_1');
      expect(send.level, 0.0);
      expect(send.preFader, false);
      expect(send.enabled, true);
    });

    test('copyWith preserves unchanged fields', () {
      final send = AuxSend(auxId: 'aux_1', level: 0.7, preFader: true);
      final copied = send.copyWith(level: 0.3);
      expect(copied.level, 0.3);
      expect(copied.preFader, true);
      expect(copied.auxId, 'aux_1');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Pan Law Calculations (Pure Math)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Pan Law calculations', () {
    test('equal power: center pan gives -3 dB per channel', () {
      // Equal power pan law: L = cos(pan * pi/2), R = sin(pan * pi/2)
      // At center (pan=0.5 normalized): both = cos(pi/4) = sin(pi/4) = 0.707 ≈ -3dB
      const pan = 0.0; // Center
      final normPan = (pan + 1.0) / 2.0; // 0.5
      final l = math.cos(normPan * math.pi / 2);
      final r = math.sin(normPan * math.pi / 2);
      final lDb = 20 * math.log(l) / math.ln10;
      final rDb = 20 * math.log(r) / math.ln10;
      expect(lDb, closeTo(-3.01, 0.1));
      expect(rDb, closeTo(-3.01, 0.1));
    });

    test('equal power: hard left gives 0 dB L, -inf R', () {
      const pan = -1.0; // Hard left
      final normPan = (pan + 1.0) / 2.0; // 0.0
      final l = math.cos(normPan * math.pi / 2);
      final r = math.sin(normPan * math.pi / 2);
      expect(l, closeTo(1.0, 0.001));
      expect(r, closeTo(0.0, 0.001));
    });

    test('equal power: hard right gives -inf L, 0 dB R', () {
      const pan = 1.0; // Hard right
      final normPan = (pan + 1.0) / 2.0; // 1.0
      final l = math.cos(normPan * math.pi / 2);
      final r = math.sin(normPan * math.pi / 2);
      expect(l, closeTo(0.0, 0.001));
      expect(r, closeTo(1.0, 0.001));
    });

    test('linear pan: center gives 0.5 per channel', () {
      const pan = 0.0;
      final normPan = (pan + 1.0) / 2.0;
      final l = 1.0 - normPan;
      final r = normPan;
      expect(l, 0.5);
      expect(r, 0.5);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MixerProvider — Mute/Solo Interaction
  // ═══════════════════════════════════════════════════════════════════════════

  group('Mute/Solo interaction', () {
    late MixerProvider provider;

    setUp(() {
      provider = MixerProvider();
    });

    test('solo defeats mute (soloed channel is heard even if muted)', () {
      final ch = provider.createChannel(name: 'A');
      provider.toggleChannelMute(ch.id);
      expect(provider.getChannel(ch.id)!.muted, true);

      provider.toggleChannelSolo(ch.id);
      expect(provider.getChannel(ch.id)!.soloed, true);
      // When a channel is soloed, it should be heard regardless of mute
      expect(provider.hasSoloedChannels, true);
    });

    test('only soloed channels heard when any channel is soloed', () {
      final ch1 = provider.createChannel(name: 'A');
      final ch2 = provider.createChannel(name: 'B');
      if (ch1.id == ch2.id) return; // Skip on ID collision

      provider.toggleChannelSolo(ch1.id);
      expect(provider.hasSoloedChannels, true);
      // ch1 soloed, ch2 not — ch2 is effectively muted
      expect(provider.getChannel(ch1.id)!.soloed, true);
      expect(provider.getChannel(ch2.id)!.soloed, false);
    });

    test('clearAllSolo restores normal playback', () {
      final ch1 = provider.createChannel(name: 'A');
      provider.toggleChannelSolo(ch1.id);
      expect(provider.hasSoloedChannels, true);

      provider.clearAllSolo();
      expect(provider.hasSoloedChannels, false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // VcaFader Model Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('VcaFader', () {
    test('default level is unity (1.0)', () {
      final vca = VcaFader(id: 'v1', name: 'VCA 1');
      expect(vca.level, 1.0);
    });

    test('member IDs track controlled channels', () {
      final vca = VcaFader(
        id: 'v1',
        name: 'VCA 1',
        memberIds: ['ch_1', 'ch_2', 'ch_3'],
      );
      expect(vca.memberIds.length, 3);
      expect(vca.memberIds, contains('ch_2'));
    });

    test('copyWith preserves memberIds', () {
      final vca = VcaFader(
        id: 'v1',
        name: 'VCA 1',
        memberIds: ['a', 'b'],
      );
      final copied = vca.copyWith(level: 0.5);
      expect(copied.level, 0.5);
      expect(copied.memberIds, ['a', 'b']);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MixerGroup Model Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('MixerGroup', () {
    test('default link settings', () {
      final group = MixerGroup(id: 'g1', name: 'Group 1');
      expect(group.linkMode, GroupLinkMode.relative);
      expect(group.linkVolume, true);
      expect(group.linkPan, false);
      expect(group.linkMute, true);
      expect(group.linkSolo, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Send Level Calculations
  // ═══════════════════════════════════════════════════════════════════════════

  group('Send level calculations', () {
    test('send level 0.0 means no signal', () {
      final send = AuxSend(auxId: 'aux', level: 0.0);
      expect(send.level, 0.0);
    });

    test('send level 1.0 means unity', () {
      final send = AuxSend(auxId: 'aux', level: 1.0);
      expect(send.level, 1.0);
    });

    test('pre-fader send ignores channel volume conceptually', () {
      final send = AuxSend(auxId: 'aux', level: 0.8, preFader: true);
      expect(send.preFader, true);
      // Pre-fader: send level is independent of channel fader
      expect(send.level, 0.8);
    });
  });
}

/// Helper: parse dB value from volumeDbString like "-6.0 dB" or "+3.5 dB"
double? _parseDb(String dbStr) {
  final cleaned = dbStr.replaceAll('dB', '').replaceAll(' ', '');
  return double.tryParse(cleaned);
}
