/// MixerProvider Tests (P0.4)
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/mixer_provider.dart';

void main() {
  group('MixerProvider', () {
    late MixerProvider provider;

    setUp(() {
      provider = MixerProvider();
    });

    test('createChannel creates new channel', () {
      final channel = provider.createChannel(name: 'Test Track');

      expect(channel.name, 'Test Track');
      expect(provider.channels.length, 1);
      expect(provider.channels.first.id, channel.id);
    });

    test('createChannel validates input', () {
      expect(
        () => provider.createChannel(name: '<script>alert</script>'),
        throwsArgumentError,
      );
    });

    test('setChannelVolume updates volume', () {
      final channel = provider.createChannel(name: 'Track 1');

      provider.setChannelVolume(channel.id, 0.8);

      final updated = provider.channels.firstWhere((c) => c.id == channel.id);
      expect(updated.volume, 0.8);
    });

    test('setChannelVolume clamps to safe range', () {
      final channel = provider.createChannel(name: 'Track 1');

      provider.setChannelVolume(channel.id, 10.0); // Out of range

      final updated = provider.channels.firstWhere((c) => c.id == channel.id);
      expect(updated.volume, lessThanOrEqualTo(4.0));
    });

    test('setChannelPan updates pan', () {
      final channel = provider.createChannel(name: 'Track 1');

      provider.setChannelPan(channel.id, -0.5);

      final updated = provider.channels.firstWhere((c) => c.id == channel.id);
      expect(updated.pan, -0.5);
    });

    test('toggleChannelMute changes mute state', () {
      final channel = provider.createChannel(name: 'Track 1');

      expect(channel.muted, false);

      provider.toggleChannelMute(channel.id);
      final updated = provider.channels.firstWhere((c) => c.id == channel.id);
      expect(updated.muted, true);
    });

    test('createBus creates bus channel', () {
      final bus = provider.createBus(name: 'Reverb Bus');

      expect(bus.name, 'Reverb Bus');
      expect(bus.type, ChannelType.bus);
      expect(provider.buses.length, 1);
    });

    test('createBus validates input', () {
      expect(
        () => provider.createBus(name: ''),
        throwsArgumentError,
      );
    });
  });
}
