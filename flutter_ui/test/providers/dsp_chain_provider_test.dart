/// DspChainProvider Tests (P0.4)
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/dsp_chain_provider.dart';

void main() {
  group('DspChainProvider', () {
    test('addNode creates node in chain', () {
      final provider = DspChainProvider.instance;
      const trackId = 0;

      provider.addNode(trackId, DspNodeType.eq);

      final chain = provider.getChain(trackId);
      expect(chain.nodes.length, 1);
      expect(chain.nodes.first.type, DspNodeType.eq);
    });

    test('removeNode removes from chain', () {
      final provider = DspChainProvider.instance;
      const trackId = 1;

      provider.addNode(trackId, DspNodeType.compressor);
      final chain = provider.getChain(trackId);
      final nodeId = chain.nodes.first.id;

      provider.removeNode(trackId, nodeId);

      final updatedChain = provider.getChain(trackId);
      expect(updatedChain.nodes.length, 0);
    });

    test('swapNodes preserves parameters', () {
      final provider = DspChainProvider.instance;
      const trackId = 2;

      provider.addNode(trackId, DspNodeType.eq);
      provider.addNode(trackId, DspNodeType.compressor);

      final chain = provider.getChain(trackId);
      final nodeA = chain.nodes[0];
      final nodeB = chain.nodes[1];

      provider.swapNodes(trackId, nodeA.id, nodeB.id);

      final swappedChain = provider.getChain(trackId);
      expect(swappedChain.nodes[0].type, DspNodeType.compressor);
      expect(swappedChain.nodes[1].type, DspNodeType.eq);
    });

    test('toggleNodeBypass changes bypass state', () {
      final provider = DspChainProvider.instance;
      const trackId = 3;

      provider.addNode(trackId, DspNodeType.limiter);
      final chain = provider.getChain(trackId);
      final nodeId = chain.nodes.first.id;

      expect(chain.nodes.first.bypass, false);

      provider.toggleNodeBypass(trackId, nodeId);
      final updated = provider.getChain(trackId);
      expect(updated.nodes.first.bypass, true);
    });

    test('copyChain and pasteChain work', () {
      final provider = DspChainProvider.instance;
      const sourceTrack = 4;
      const targetTrack = 5;

      provider.addNode(sourceTrack, DspNodeType.eq);
      provider.addNode(sourceTrack, DspNodeType.compressor);

      provider.copyChain(sourceTrack);
      expect(provider.hasClipboard, true);

      provider.pasteChain(targetTrack);
      final targetChain = provider.getChain(targetTrack);
      expect(targetChain.nodes.length, 2);
    });
  });
}
