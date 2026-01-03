/**
 * Runtime Stub - Test implementation for AudioBackend
 */

export { RuntimeStub, type RuntimeStubConfig } from "./runtimeStub";
export {
  getCommandsForEvent,
  getAllEvents,
  getRequiredAssets,
  type GameEvent,
} from "./eventMap";
export {
  LatencyMetrics,
  latencyMetrics,
  type LatencyMeasurement,
  type LatencyStats,
} from "./latencyMetrics";

// AudioBackend exports
export {
  type BusId,
  type AdapterCommand,
  type PlayCommand,
  type StopCommand,
  type StopAllCommand,
  type SetBusGainCommand,
  type AudioBackend,
  type AssetResolver,
  AudioEngineBackend,
} from "./audioBackend";
