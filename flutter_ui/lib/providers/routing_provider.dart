/// Routing Provider
///
/// Manages unified routing system:
/// - Dynamic channel creation/deletion
/// - Output routing (master, channel, none)
/// - Pre/post fader sends
/// - Channel properties (volume, pan, mute, solo)

import 'package:flutter/foundation.dart';
import '../src/rust/engine_api.dart' as api;

enum ChannelKind {
  audio(0),
  bus(1),
  aux(2),
  vca(3),
  master(4);

  final int value;
  const ChannelKind(this.value);
}

enum OutputDestType {
  master(0),
  channel(1),
  none(2);

  final int value;
  const OutputDestType(this.value);
}

class ChannelInfo {
  final int id;
  final ChannelKind kind;
  final String name;

  ChannelInfo({
    required this.id,
    required this.kind,
    required this.name,
  });
}

class RoutingProvider extends ChangeNotifier {
  final Map<int, ChannelInfo> _channels = {};
  final Map<int, int> _pendingCreations = {}; // callback_id -> expected_kind

  // Getters
  int get channelCount => _channels.length;
  List<ChannelInfo> get channels => _channels.values.toList();
  ChannelInfo? getChannel(int channelId) => _channels[channelId];

  /// Initialize routing system (called by PlaybackEngine)
  /// sender_ptr: Pointer to RoutingCommandSender (from Rust)
  Future<bool> initialize(int senderPtr) async {
    final result = api.routingInit(senderPtr);
    if (result == 1) {
      _updateChannelList();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Create new routing channel
  /// Returns callback_id for polling response (0 on failure)
  Future<int> createChannel(ChannelKind kind, String name) async {
    final callbackId = api.routingCreateChannel(kind.value, name);
    if (callbackId > 0) {
      _pendingCreations[callbackId] = kind.value;
    }
    return callbackId;
  }

  /// Poll for channel creation response
  /// Returns channel_id if ready, 0 if pending, -1 on error
  Future<int> pollChannelCreation(int callbackId) async {
    final channelId = api.routingPollResponse(callbackId);
    if (channelId > 0) {
      // Channel created successfully
      _pendingCreations.remove(callbackId);
      _updateChannelList();
      notifyListeners();
    } else if (channelId == -1) {
      // Error
      _pendingCreations.remove(callbackId);
    }
    return channelId;
  }

  /// Delete routing channel
  Future<bool> deleteChannel(int channelId) async {
    final result = api.routingDeleteChannel(channelId);
    if (result == 1) {
      _channels.remove(channelId);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Set channel output destination
  Future<bool> setOutput({
    required int channelId,
    required OutputDestType destType,
    int destChannelId = 0,
  }) async {
    final result = api.routingSetOutput(channelId, destType.value, destChannelId);
    if (result == 1) {
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Set channel to output to master
  Future<bool> setOutputToMaster(int channelId) async {
    return setOutput(
      channelId: channelId,
      destType: OutputDestType.master,
    );
  }

  /// Set channel to output to another channel
  Future<bool> setOutputToChannel(int fromId, int toId) async {
    return setOutput(
      channelId: fromId,
      destType: OutputDestType.channel,
      destChannelId: toId,
    );
  }

  /// Disable channel output
  Future<bool> disableOutput(int channelId) async {
    return setOutput(
      channelId: channelId,
      destType: OutputDestType.none,
    );
  }

  /// Add send from one channel to another
  Future<bool> addSend({
    required int fromChannel,
    required int toChannel,
    bool preFader = false,
  }) async {
    final result = api.routingAddSend(fromChannel, toChannel, preFader ? 1 : 0);
    if (result == 1) {
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Set channel volume (fader)
  Future<bool> setVolume(int channelId, double volumeDb) async {
    final result = api.routingSetVolume(channelId, volumeDb);
    return result == 1;
  }

  /// Set channel pan (-1.0 = left, 0.0 = center, 1.0 = right)
  Future<bool> setPan(int channelId, double pan) async {
    final result = api.routingSetPan(channelId, pan.clamp(-1.0, 1.0));
    return result == 1;
  }

  /// Set channel mute
  Future<bool> setMute(int channelId, bool mute) async {
    final result = api.routingSetMute(channelId, mute ? 1 : 0);
    if (result == 1) {
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Set channel solo
  Future<bool> setSolo(int channelId, bool solo) async {
    final result = api.routingSetSolo(channelId, solo ? 1 : 0);
    if (result == 1) {
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Update channel list from Rust
  void _updateChannelList() {
    final count = api.routingGetChannelCount();
    // TODO: Implement channel list query when FFI supports it
    // For now, just update count
  }

  /// Refresh routing state
  Future<void> refresh() async {
    _updateChannelList();

    // Process any pending channel creations
    final pending = List.from(_pendingCreations.keys);
    for (final callbackId in pending) {
      await pollChannelCreation(callbackId);
    }
  }

}
