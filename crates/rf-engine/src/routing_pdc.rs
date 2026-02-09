//! Graph-Level Plugin Delay Compensation (PDC)
//!
//! Ensures phase-coherent parallel processing in complex audio routing graphs.
//!
//! # Problem
//! When parallel audio paths have different latencies (due to plugins),
//! they arrive at the mix point with phase misalignment, causing:
//! - Comb filtering
//! - Hollow sound
//! - Reduced bass response
//!
//! # Solution
//! 1. Build routing graph (tracks → buses → master)
//! 2. Topological sort (detect cycles, establish order)
//! 3. Calculate longest path latency for each node
//! 4. Identify mix points (nodes with 2+ inputs)
//! 5. Calculate per-input compensation at each mix point
//! 6. Propagate compensation requirements back to source nodes
//! 7. Result: All paths arrive phase-aligned
//!
//! # Algorithm (Pro Tools / Cubase Industry Standard)
//!
//! ## Phase 1: Forward Pass - Calculate Longest Paths
//! Using dynamic programming in topological order, calculate the cumulative
//! latency from source nodes to each node in the graph.
//!
//! ## Phase 2: Identify Mix Points
//! A mix point is any node with 2 or more incoming edges. At mix points,
//! signals from different paths are summed, requiring phase alignment.
//!
//! ## Phase 3: Calculate Per-Input Compensation at Mix Points
//! For each mix point:
//!   1. Calculate "arrival time" for each input = longest_path(source) + edge_latency
//!   2. Find max_arrival across all inputs
//!   3. compensation(input) = max_arrival - arrival_time(input)
//!
//! ## Phase 4: Propagate Compensation to Source Nodes
//! Each source node receives compensation equal to the maximum compensation
//! required by any path it feeds into.
//!
//! # Example
//! ```text
//! Track A → Bus 1 (insert: 100ms latency)
//!            ↓
//! Track B → Bus 1 (insert: 0ms latency)
//!            ↓
//!         Master
//!
//! Analysis:
//!   Mix point: Bus 1 (has 2 inputs: Track A and Track B)
//!   Arrival from Track A: longest_path(A)=0 + edge_latency=100 = 100ms
//!   Arrival from Track B: longest_path(B)=0 + edge_latency=0 = 0ms
//!   Max arrival: 100ms
//!
//!   Compensation at mix point:
//!     Input from A: 100 - 100 = 0ms (no compensation needed)
//!     Input from B: 100 - 0 = 100ms (needs 100ms delay)
//!
//!   Propagated to source nodes:
//!     Track A compensation: 0ms
//!     Track B compensation: 100ms
//!
//! Result: Track B gets +100ms delay, both arrive phase-aligned at Bus 1
//! ```
//!
//! # References
//! - Pro Tools HD: Graph-level PDC (industry standard)
//! - Cubase: Automatic Delay Compensation
//! - Reaper: Track delay compensation with parallel routing

use std::collections::{HashMap, HashSet, VecDeque};

/// Routing node ID (track, bus, or master)
pub type NodeId = u64;

/// Latency in samples
pub type LatencySamples = u64;

/// Audio routing graph node
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GraphNode {
    /// Audio track (id)
    Track(u64),
    /// Audio bus (id: 0=master, 1=music, 2=sfx, etc.)
    Bus(usize),
    /// Master output
    Master,
}

impl GraphNode {
    /// Convert to unique node ID for graph algorithms
    pub fn to_node_id(&self) -> NodeId {
        match self {
            GraphNode::Track(id) => *id,
            GraphNode::Bus(id) => 1_000_000 + (*id as u64),
            GraphNode::Master => 9_999_999,
        }
    }

    /// Convert from node ID
    pub fn from_node_id(id: NodeId) -> Option<Self> {
        if id == 9_999_999 {
            Some(GraphNode::Master)
        } else if id >= 1_000_000 {
            Some(GraphNode::Bus((id - 1_000_000) as usize))
        } else {
            Some(GraphNode::Track(id))
        }
    }
}

/// Audio routing edge (source → destination with latency)
#[derive(Debug, Clone)]
pub struct GraphEdge {
    /// Source node
    pub source: NodeId,
    /// Destination node
    pub destination: NodeId,
    /// Latency introduced by this connection (samples)
    /// Includes: insert chain latency + any routing delays
    pub latency: LatencySamples,
}

/// Audio routing graph for PDC calculation
#[derive(Debug, Clone)]
pub struct RoutingGraph {
    /// All nodes in the graph
    nodes: HashSet<NodeId>,
    /// Edges (connections with latency)
    edges: Vec<GraphEdge>,
    /// Adjacency list (node → [outgoing edge indices])
    adjacency: HashMap<NodeId, Vec<usize>>,
    /// Reverse adjacency list (node → [incoming edge indices])
    reverse_adjacency: HashMap<NodeId, Vec<usize>>,
}

impl RoutingGraph {
    /// Create empty routing graph
    pub fn new() -> Self {
        Self {
            nodes: HashSet::new(),
            edges: Vec::new(),
            adjacency: HashMap::new(),
            reverse_adjacency: HashMap::new(),
        }
    }

    /// Add node to graph
    pub fn add_node(&mut self, node: NodeId) {
        self.nodes.insert(node);
        self.adjacency.entry(node).or_default();
        self.reverse_adjacency.entry(node).or_default();
    }

    /// Add edge (connection with latency)
    pub fn add_edge(&mut self, source: NodeId, destination: NodeId, latency: LatencySamples) {
        // Ensure both nodes exist
        self.add_node(source);
        self.add_node(destination);

        // Add edge
        let edge_index = self.edges.len();
        self.edges.push(GraphEdge {
            source,
            destination,
            latency,
        });

        // Update adjacency lists (both directions)
        self.adjacency.entry(source).or_default().push(edge_index);
        self.reverse_adjacency
            .entry(destination)
            .or_default()
            .push(edge_index);
    }

    /// Get number of nodes
    pub fn node_count(&self) -> usize {
        self.nodes.len()
    }

    /// Get number of edges
    pub fn edge_count(&self) -> usize {
        self.edges.len()
    }

    /// Get all nodes
    pub fn nodes(&self) -> impl Iterator<Item = NodeId> + '_ {
        self.nodes.iter().copied()
    }

    /// Get outgoing edges from node
    pub fn outgoing_edges(&self, node: NodeId) -> impl Iterator<Item = &GraphEdge> + '_ {
        self.adjacency
            .get(&node)
            .map(|indices| indices.iter().map(move |&i| &self.edges[i]))
            .into_iter()
            .flatten()
    }

    /// Get incoming edges to node
    pub fn incoming_edges(&self, node: NodeId) -> impl Iterator<Item = &GraphEdge> + '_ {
        self.reverse_adjacency
            .get(&node)
            .map(|indices| indices.iter().map(move |&i| &self.edges[i]))
            .into_iter()
            .flatten()
    }

    /// Get number of incoming edges (in-degree)
    pub fn in_degree(&self, node: NodeId) -> usize {
        self.reverse_adjacency
            .get(&node)
            .map(|v| v.len())
            .unwrap_or(0)
    }

    /// Get edge by index
    pub fn get_edge(&self, index: usize) -> Option<&GraphEdge> {
        self.edges.get(index)
    }
}

impl Default for RoutingGraph {
    fn default() -> Self {
        Self::new()
    }
}

/// Information about a mix point in the routing graph
#[derive(Debug, Clone)]
pub struct MixPoint {
    /// The node where mixing occurs
    pub node: NodeId,
    /// Incoming edges (each represents a signal path being mixed)
    pub incoming_edge_indices: Vec<usize>,
    /// Maximum arrival time at this mix point (samples)
    pub max_arrival: LatencySamples,
    /// Per-input compensation required (edge_index → compensation)
    pub input_compensation: HashMap<usize, LatencySamples>,
}

/// PDC calculation result
#[derive(Debug, Clone)]
pub struct PDCResult {
    /// Longest path latency to each node (samples)
    /// This represents the cumulative latency from source nodes to each node.
    pub longest_paths: HashMap<NodeId, LatencySamples>,

    /// Required delay compensation per node (samples)
    /// This is the delay that must be applied at each source node to ensure
    /// all paths arrive phase-aligned at mix points.
    pub compensation: HashMap<NodeId, LatencySamples>,

    /// Maximum latency in the graph (samples)
    pub max_latency: LatencySamples,

    /// Whether graph has cycles (PDC not possible if true)
    pub has_cycles: bool,

    /// Topological order (if no cycles)
    pub topo_order: Vec<NodeId>,

    /// Identified mix points with per-input compensation details
    pub mix_points: Vec<MixPoint>,
}

impl PDCResult {
    /// Check if PDC calculation succeeded
    pub fn is_valid(&self) -> bool {
        !self.has_cycles
    }

    /// Get compensation delay for a node
    pub fn get_compensation(&self, node: NodeId) -> LatencySamples {
        self.compensation.get(&node).copied().unwrap_or(0)
    }

    /// Get longest path latency to a node
    pub fn get_longest_path(&self, node: NodeId) -> LatencySamples {
        self.longest_paths.get(&node).copied().unwrap_or(0)
    }
}

/// PDC calculator
pub struct PDCCalculator;

impl PDCCalculator {
    /// Calculate PDC for routing graph
    ///
    /// # Algorithm (Industry Standard - Pro Tools approach)
    ///
    /// 1. **Topological Sort**: Establish processing order, detect cycles
    /// 2. **Longest Paths**: Forward pass to calculate cumulative latency
    /// 3. **Identify Mix Points**: Find nodes with multiple inputs
    /// 4. **Per-Input Compensation**: Calculate delay needed at each mix point input
    /// 5. **Propagate to Sources**: Each source gets max compensation from its paths
    ///
    /// # Returns
    /// - Ok(PDCResult) if graph is acyclic
    /// - Err(String) if graph has cycles (PDC not possible)
    pub fn calculate(graph: &RoutingGraph) -> Result<PDCResult, String> {
        // Step 1: Topological sort (Kahn's algorithm)
        let topo_order = Self::topological_sort(graph)?;

        // Step 2: Calculate longest paths (forward pass)
        let longest_paths = Self::calculate_longest_paths(graph, &topo_order);

        // Step 3: Find maximum latency
        let max_latency = longest_paths.values().copied().max().unwrap_or(0);

        // Step 4: Identify mix points and calculate per-input compensation
        let mix_points = Self::identify_mix_points(graph, &longest_paths);

        // Step 5: Calculate compensation for each source node
        // Each source node gets the maximum compensation required by any
        // path it feeds into.
        let compensation = Self::calculate_source_compensation(graph, &mix_points, max_latency);

        Ok(PDCResult {
            longest_paths,
            compensation,
            max_latency,
            has_cycles: false,
            topo_order,
            mix_points,
        })
    }

    /// Identify mix points in the graph
    ///
    /// A mix point is any node with 2 or more incoming edges.
    /// For each mix point, we calculate the compensation needed for each input.
    ///
    /// # Algorithm
    /// For each mix point node:
    ///   1. Get all incoming edges
    ///   2. For each edge: arrival_time = longest_path(source) + edge.latency
    ///   3. max_arrival = max(all arrival times)
    ///   4. compensation(edge) = max_arrival - arrival_time(edge)
    pub fn identify_mix_points(
        graph: &RoutingGraph,
        longest_paths: &HashMap<NodeId, LatencySamples>,
    ) -> Vec<MixPoint> {
        let mut mix_points = Vec::new();

        for node in graph.nodes() {
            let in_degree = graph.in_degree(node);

            // A mix point has 2+ inputs
            if in_degree >= 2 {
                let incoming_edges: Vec<usize> = graph
                    .reverse_adjacency
                    .get(&node)
                    .map(|v| v.clone())
                    .unwrap_or_default();

                // Calculate arrival time for each input
                let mut arrivals: Vec<(usize, LatencySamples)> = Vec::new();

                for &edge_idx in &incoming_edges {
                    if let Some(edge) = graph.get_edge(edge_idx) {
                        let source_latency = longest_paths.get(&edge.source).copied().unwrap_or(0);
                        let arrival_time = source_latency + edge.latency;
                        arrivals.push((edge_idx, arrival_time));
                    }
                }

                // Find maximum arrival time
                let max_arrival = arrivals.iter().map(|(_, t)| *t).max().unwrap_or(0);

                // Calculate per-input compensation
                let mut input_compensation = HashMap::new();
                for (edge_idx, arrival_time) in &arrivals {
                    let comp = max_arrival.saturating_sub(*arrival_time);
                    input_compensation.insert(*edge_idx, comp);
                }

                mix_points.push(MixPoint {
                    node,
                    incoming_edge_indices: incoming_edges,
                    max_arrival,
                    input_compensation,
                });
            }
        }

        mix_points
    }

    /// Calculate compensation for each source node
    ///
    /// # Algorithm
    ///
    /// This uses a **backward propagation** approach:
    ///
    /// 1. First, calculate the compensation required for each edge at mix points
    /// 2. Then, propagate compensation backward through the graph:
    ///    - Each node gets the max compensation of its outgoing edges
    ///    - Plus any compensation from downstream nodes (chain propagation)
    ///
    /// ## Edge Compensation at Mix Points
    /// At each mix point, we know which edges need delay compensation.
    /// An edge with lower arrival time needs more compensation.
    ///
    /// ## Backward Propagation
    /// If Node A → Node B and Node B needs X compensation at a mix point,
    /// then Node A also needs X compensation (the delay propagates backward).
    ///
    /// ## Terminal Nodes
    /// Terminal nodes (like Master output) have outgoing edges but don't feed
    /// into mix points, so they get 0 compensation.
    ///
    /// ## Orphaned Nodes
    /// Nodes with NO incoming and NO outgoing edges (truly orphaned) get
    /// max_latency compensation to stay aligned with the longest path.
    fn calculate_source_compensation(
        graph: &RoutingGraph,
        mix_points: &[MixPoint],
        max_latency: LatencySamples,
    ) -> HashMap<NodeId, LatencySamples> {
        // Build a quick lookup: edge_index → compensation required at mix point
        let mut edge_compensation: HashMap<usize, LatencySamples> = HashMap::new();
        for mp in mix_points {
            for (edge_idx, comp) in &mp.input_compensation {
                let entry = edge_compensation.entry(*edge_idx).or_insert(0);
                *entry = (*entry).max(*comp);
            }
        }

        // Initialize all nodes to 0 compensation
        let mut compensation: HashMap<NodeId, LatencySamples> =
            graph.nodes().map(|n| (n, 0)).collect();

        // Process in reverse topological order to propagate compensation backward
        // We need to calculate topo order again (could cache this, but it's fast)
        let topo_order = match Self::topological_sort(graph) {
            Ok(order) => order,
            Err(_) => return compensation, // Cycles detected, return zeros
        };

        // Reverse order: process downstream nodes first, then propagate backward
        for &node in topo_order.iter().rev() {
            let outgoing_indices: Vec<usize> = graph
                .adjacency
                .get(&node)
                .map(|v| v.clone())
                .unwrap_or_default();

            // Find max compensation required:
            // 1. Direct edge compensation (if edge goes to a mix point)
            // 2. Downstream node compensation (propagate back from children)
            let mut max_comp: LatencySamples = 0;

            for edge_idx in &outgoing_indices {
                // Direct edge compensation at mix point
                if let Some(&comp) = edge_compensation.get(edge_idx) {
                    max_comp = max_comp.max(comp);
                }

                // Propagate compensation from destination node
                if let Some(edge) = graph.get_edge(*edge_idx) {
                    let dest_comp = compensation.get(&edge.destination).copied().unwrap_or(0);
                    max_comp = max_comp.max(dest_comp);
                }
            }

            compensation.insert(node, max_comp);
        }

        // Handle truly orphaned nodes (no incoming AND no outgoing edges)
        // These nodes are disconnected from the routing graph entirely.
        // They get max_latency compensation to stay aligned.
        for node in graph.nodes() {
            let in_degree = graph.in_degree(node);
            let out_degree = graph.adjacency.get(&node).map(|v| v.len()).unwrap_or(0);

            if in_degree == 0 && out_degree == 0 {
                // Truly orphaned node
                compensation.insert(node, max_latency);
            }
        }

        compensation
    }

    /// Topological sort using Kahn's algorithm
    ///
    /// Returns topological order if graph is acyclic, error if cycles detected.
    fn topological_sort(graph: &RoutingGraph) -> Result<Vec<NodeId>, String> {
        // Calculate in-degree for each node
        let mut in_degree: HashMap<NodeId, usize> = graph.nodes().map(|n| (n, 0)).collect();

        for edge in &graph.edges {
            *in_degree.entry(edge.destination).or_insert(0) += 1;
        }

        // Queue of nodes with in-degree 0
        let mut queue: VecDeque<NodeId> = in_degree
            .iter()
            .filter(|(_, degree)| **degree == 0)
            .map(|(&node, _)| node)
            .collect();

        let mut topo_order = Vec::new();

        while let Some(node) = queue.pop_front() {
            topo_order.push(node);

            // For each outgoing edge, decrement in-degree
            for edge in graph.outgoing_edges(node) {
                let dest_degree = in_degree.get_mut(&edge.destination).unwrap();
                *dest_degree -= 1;

                if *dest_degree == 0 {
                    queue.push_back(edge.destination);
                }
            }
        }

        // If topo_order doesn't contain all nodes, graph has cycles
        if topo_order.len() != graph.node_count() {
            return Err(format!(
                "Routing graph has cycles (processed {}/{} nodes). PDC cannot be calculated.",
                topo_order.len(),
                graph.node_count()
            ));
        }

        Ok(topo_order)
    }

    /// Calculate longest path latency to each node
    ///
    /// Uses dynamic programming with topological order.
    /// For each node, longest_path = max(longest_path(source) + edge.latency)
    /// across all incoming edges.
    fn calculate_longest_paths(
        graph: &RoutingGraph,
        topo_order: &[NodeId],
    ) -> HashMap<NodeId, LatencySamples> {
        let mut longest: HashMap<NodeId, LatencySamples> = graph.nodes().map(|n| (n, 0)).collect();

        // Process nodes in topological order
        for &node in topo_order {
            let current_latency = longest[&node];

            // Update all successors
            for edge in graph.outgoing_edges(node) {
                let new_latency = current_latency + edge.latency;
                let dest_latency = longest.get_mut(&edge.destination).unwrap();

                // Take maximum (longest path)
                if new_latency > *dest_latency {
                    *dest_latency = new_latency;
                }
            }
        }

        longest
    }

    /// Detect cycles in graph (DFS-based)
    ///
    /// Returns true if graph has cycles, false otherwise.
    pub fn has_cycles(graph: &RoutingGraph) -> bool {
        let mut visited = HashSet::new();
        let mut rec_stack = HashSet::new();

        for node in graph.nodes() {
            if !visited.contains(&node) {
                if Self::has_cycles_dfs(graph, node, &mut visited, &mut rec_stack) {
                    return true;
                }
            }
        }

        false
    }

    /// DFS helper for cycle detection
    fn has_cycles_dfs(
        graph: &RoutingGraph,
        node: NodeId,
        visited: &mut HashSet<NodeId>,
        rec_stack: &mut HashSet<NodeId>,
    ) -> bool {
        visited.insert(node);
        rec_stack.insert(node);

        for edge in graph.outgoing_edges(node) {
            if !visited.contains(&edge.destination) {
                if Self::has_cycles_dfs(graph, edge.destination, visited, rec_stack) {
                    return true;
                }
            } else if rec_stack.contains(&edge.destination) {
                // Back edge detected (cycle)
                return true;
            }
        }

        rec_stack.remove(&node);
        false
    }
}

// =============================================================================
// UNIT TESTS
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    /// Test: Simple linear chain (no mix points)
    ///
    /// ```text
    /// Track 1 → Bus 1 (50ms) → Master (0ms)
    /// ```
    ///
    /// Expected: No compensation needed (no parallel paths)
    #[test]
    fn test_simple_chain() {
        let mut graph = RoutingGraph::new();
        let track1 = 1;
        let bus1 = 1_000_001; // Bus 1
        let master = 9_999_999;

        graph.add_edge(track1, bus1, 50);
        graph.add_edge(bus1, master, 0);

        let result = PDCCalculator::calculate(&graph).unwrap();

        assert!(!result.has_cycles);
        assert_eq!(result.max_latency, 50);

        // No mix points → no compensation needed
        assert_eq!(result.get_compensation(track1), 0);
        assert_eq!(result.get_compensation(bus1), 0);
        assert_eq!(result.get_compensation(master), 0);
    }

    /// Test: Parallel paths merging at Bus 1
    ///
    /// ```text
    /// Track A → Bus 1 (100ms edge) ↘
    ///                               → Master
    /// Track B → Bus 1 (0ms edge)   ↗
    /// ```
    ///
    /// Expected:
    /// - Track A: 0ms compensation (longest path)
    /// - Track B: 100ms compensation (needs delay to match Track A)
    #[test]
    fn test_parallel_paths() {
        let mut graph = RoutingGraph::new();
        let track_a = 1;
        let track_b = 2;
        let bus1 = 1_000_001;
        let master = 9_999_999;

        graph.add_edge(track_a, bus1, 100); // 100ms plugin latency
        graph.add_edge(track_b, bus1, 0); // No plugin
        graph.add_edge(bus1, master, 0);

        let result = PDCCalculator::calculate(&graph).unwrap();

        assert!(!result.has_cycles);
        assert_eq!(result.max_latency, 100);

        // Bus 1 is a mix point (2 inputs)
        assert_eq!(result.mix_points.len(), 1);
        assert_eq!(result.mix_points[0].node, bus1);

        // Verify longest paths
        assert_eq!(result.get_longest_path(track_a), 0);
        assert_eq!(result.get_longest_path(track_b), 0);
        assert_eq!(result.get_longest_path(bus1), 100); // Max of inputs

        // Track A: longest path through its edge (100ms), no comp needed
        assert_eq!(result.get_compensation(track_a), 0);

        // Track B: shorter path (0ms), needs 100ms comp to align
        assert_eq!(result.get_compensation(track_b), 100);

        // Bus 1: receives signals, no source compensation needed
        assert_eq!(result.get_compensation(bus1), 0);
    }

    /// Test: Multi-stage cumulative latency
    ///
    /// ```text
    /// Track 1 → Bus 1 (50ms) → Bus 2 (30ms) → Master
    /// ```
    ///
    /// Expected: longest_path(Bus 2) = 50 + 30 = 80ms
    #[test]
    fn test_multi_stage_latency() {
        let mut graph = RoutingGraph::new();
        let track1 = 1;
        let bus1 = 1_000_001;
        let bus2 = 1_000_002;
        let master = 9_999_999;

        graph.add_edge(track1, bus1, 50);
        graph.add_edge(bus1, bus2, 30);
        graph.add_edge(bus2, master, 0);

        let result = PDCCalculator::calculate(&graph).unwrap();

        assert!(!result.has_cycles);
        assert_eq!(result.max_latency, 80); // 50 + 30

        // Longest path: track1 → bus1 (50) → bus2 (30) = 80
        assert_eq!(result.get_longest_path(bus2), 80);
    }

    /// Test: Cycle detection returns error
    ///
    /// ```text
    /// Track 1 → Bus 1 → Bus 2 → Bus 1 (cycle!)
    /// ```
    #[test]
    fn test_cycle_detection() {
        let mut graph = RoutingGraph::new();
        let track1 = 1;
        let bus1 = 1_000_001;
        let bus2 = 1_000_002;

        graph.add_edge(track1, bus1, 10);
        graph.add_edge(bus1, bus2, 10);
        graph.add_edge(bus2, bus1, 10); // Creates cycle

        let result = PDCCalculator::calculate(&graph);

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("cycles"));
    }

    /// Test: DFS cycle detection
    #[test]
    fn test_has_cycles_dfs() {
        let mut graph = RoutingGraph::new();
        graph.add_edge(1, 2, 10);
        graph.add_edge(2, 3, 10);
        graph.add_edge(3, 1, 10); // Cycle

        assert!(PDCCalculator::has_cycles(&graph));
    }

    /// Test: Linear graph has no cycles
    #[test]
    fn test_no_cycles_linear() {
        let mut graph = RoutingGraph::new();
        graph.add_edge(1, 2, 10);
        graph.add_edge(2, 3, 10);
        graph.add_edge(3, 4, 10);

        assert!(!PDCCalculator::has_cycles(&graph));
    }

    /// Test: Diamond pattern (classic PDC scenario)
    ///
    /// ```text
    /// Track 1 → Bus A (100ms) ↘
    ///                          → Bus C (50ms) → Master
    /// Track 2 → Bus B (0ms)   ↗
    /// ```
    ///
    /// Analysis:
    /// - Mix point: Bus C
    /// - Arrival from Bus A: longest_path(Bus A)=100 + edge=50 = 150ms
    /// - Arrival from Bus B: longest_path(Bus B)=0 + edge=50 = 50ms
    /// - Max arrival: 150ms
    ///
    /// Compensation at Bus C mix point:
    /// - Input from Bus A: 150 - 150 = 0ms
    /// - Input from Bus B: 150 - 50 = 100ms
    ///
    /// Propagated to sources:
    /// - Track 1 → Bus A → Bus C (0ms comp path) → Track 1 gets 0ms
    /// - Track 2 → Bus B → Bus C (100ms comp path) → Track 2 gets 100ms
    #[test]
    fn test_diamond_pattern() {
        let mut graph = RoutingGraph::new();
        let track1 = 1;
        let track2 = 2;
        let bus_a = 1_000_001;
        let bus_b = 1_000_002;
        let bus_c = 1_000_003;
        let master = 9_999_999;

        graph.add_edge(track1, bus_a, 100);
        graph.add_edge(track2, bus_b, 0);
        graph.add_edge(bus_a, bus_c, 50);
        graph.add_edge(bus_b, bus_c, 50);
        graph.add_edge(bus_c, master, 0);

        let result = PDCCalculator::calculate(&graph).unwrap();

        assert!(!result.has_cycles);

        // Longest path: track1 → bus_a (100) → bus_c (50) = 150
        assert_eq!(result.max_latency, 150);

        // Verify longest paths
        assert_eq!(result.get_longest_path(track1), 0);
        assert_eq!(result.get_longest_path(track2), 0);
        assert_eq!(result.get_longest_path(bus_a), 100);
        assert_eq!(result.get_longest_path(bus_b), 0);
        assert_eq!(result.get_longest_path(bus_c), 150);

        // Bus C is the mix point
        assert!(!result.mix_points.is_empty());
        let bus_c_mix = result.mix_points.iter().find(|mp| mp.node == bus_c);
        assert!(bus_c_mix.is_some());
        assert_eq!(bus_c_mix.unwrap().max_arrival, 150);

        // Track 1: Path through Bus A has no comp needed (longest path)
        assert_eq!(result.get_compensation(track1), 0);

        // Track 2: Path through Bus B needs 100ms comp to align with Track 1
        // At Bus C: arrival from Bus B = 0 + 50 = 50, needs 150 - 50 = 100
        assert_eq!(result.get_compensation(track2), 100);

        // Bus B: Its edge to Bus C needs 100ms comp, propagates back
        assert_eq!(result.get_compensation(bus_b), 100);
    }

    /// Test: Empty graph
    #[test]
    fn test_empty_graph() {
        let graph = RoutingGraph::new();

        let result = PDCCalculator::calculate(&graph).unwrap();

        assert!(!result.has_cycles);
        assert_eq!(result.max_latency, 0);
        assert_eq!(result.topo_order.len(), 0);
    }

    /// Test: Single node (no edges)
    #[test]
    fn test_single_node() {
        let mut graph = RoutingGraph::new();
        graph.add_node(1);

        let result = PDCCalculator::calculate(&graph).unwrap();

        assert!(!result.has_cycles);
        assert_eq!(result.max_latency, 0);
        assert_eq!(result.get_compensation(1), 0);
    }

    /// Test: Orphaned node gets max compensation
    ///
    /// ```text
    /// Track 1 → Bus 1 (50ms) → Master
    /// Track 2 (orphaned, no connections)
    /// ```
    ///
    /// Expected: Track 2 gets max_latency compensation (50ms)
    /// This ensures orphaned tracks stay aligned with the main routing graph.
    #[test]
    fn test_orphaned_nodes() {
        let mut graph = RoutingGraph::new();
        graph.add_edge(1, 1_000_001, 50);
        graph.add_edge(1_000_001, 9_999_999, 0);
        graph.add_node(2); // Orphaned

        let result = PDCCalculator::calculate(&graph).unwrap();

        assert!(!result.has_cycles);

        // Orphaned node gets max_latency compensation
        assert_eq!(result.get_compensation(2), 50);
    }

    /// Test: Complex multi-bus routing
    ///
    /// ```text
    ///                    ┌→ Bus SFX (10ms) ─┐
    /// Track 1 (0ms) ─────┤                   ├→ Bus Master (0ms) → Master
    ///                    └→ Bus Music (50ms)─┘
    ///
    /// Track 2 (0ms) ───→ Bus Voice (0ms) ───→ Bus Master
    /// ```
    ///
    /// Mix point: Bus Master (3 inputs)
    /// - From SFX: 0 + 10 = 10ms arrival
    /// - From Music: 0 + 50 = 50ms arrival
    /// - From Voice: 0 + 0 = 0ms arrival
    /// Max arrival: 50ms
    ///
    /// Compensation:
    /// - Track 1's SFX path: 50 - 10 = 40ms
    /// - Track 1's Music path: 50 - 50 = 0ms
    /// - Track 2's Voice path: 50 - 0 = 50ms
    #[test]
    fn test_complex_multi_bus() {
        let mut graph = RoutingGraph::new();
        let track1 = 1;
        let track2 = 2;
        let bus_sfx = 1_000_001;
        let bus_music = 1_000_002;
        let bus_voice = 1_000_003;
        let bus_master = 1_000_000; // Bus 0
        let master = 9_999_999;

        // Track 1 splits to SFX and Music
        graph.add_edge(track1, bus_sfx, 10);
        graph.add_edge(track1, bus_music, 50);

        // Track 2 goes to Voice
        graph.add_edge(track2, bus_voice, 0);

        // All buses merge at Bus Master
        graph.add_edge(bus_sfx, bus_master, 0);
        graph.add_edge(bus_music, bus_master, 0);
        graph.add_edge(bus_voice, bus_master, 0);

        // Bus Master to Master output
        graph.add_edge(bus_master, master, 0);

        let result = PDCCalculator::calculate(&graph).unwrap();

        assert!(!result.has_cycles);
        assert_eq!(result.max_latency, 50);

        // Bus Master is a mix point with 3 inputs
        let master_mix = result.mix_points.iter().find(|mp| mp.node == bus_master);
        assert!(master_mix.is_some());
        assert_eq!(master_mix.unwrap().max_arrival, 50);

        // Track 1: Has two paths, takes max compensation needed (40ms for SFX path)
        // SFX path needs: 50 - 10 = 40ms
        // Music path needs: 50 - 50 = 0ms
        // Track 1 gets max(40, 0) = 40ms
        assert_eq!(result.get_compensation(track1), 40);

        // Track 2: Voice path needs 50ms comp
        assert_eq!(result.get_compensation(track2), 50);

        // Bus Voice needs 50ms comp (passes through to Track 2)
        assert_eq!(result.get_compensation(bus_voice), 50);

        // Bus SFX needs 40ms comp
        assert_eq!(result.get_compensation(bus_sfx), 40);

        // Bus Music: on critical path, no comp needed
        assert_eq!(result.get_compensation(bus_music), 0);
    }

    /// Test: identify_mix_points helper function
    #[test]
    fn test_identify_mix_points() {
        let mut graph = RoutingGraph::new();
        let track_a = 1;
        let track_b = 2;
        let bus1 = 1_000_001;
        let master = 9_999_999;

        graph.add_edge(track_a, bus1, 100);
        graph.add_edge(track_b, bus1, 0);
        graph.add_edge(bus1, master, 0);

        let longest_paths = {
            let topo = PDCCalculator::topological_sort(&graph).unwrap();
            PDCCalculator::calculate_longest_paths(&graph, &topo)
        };

        let mix_points = PDCCalculator::identify_mix_points(&graph, &longest_paths);

        // Only Bus 1 is a mix point
        assert_eq!(mix_points.len(), 1);
        assert_eq!(mix_points[0].node, bus1);
        assert_eq!(mix_points[0].max_arrival, 100);
        assert_eq!(mix_points[0].incoming_edge_indices.len(), 2);

        // Verify per-input compensation
        // Edge 0: track_a → bus1 (100ms) → arrival = 0 + 100 = 100 → comp = 0
        // Edge 1: track_b → bus1 (0ms) → arrival = 0 + 0 = 0 → comp = 100
        for (&edge_idx, &comp) in &mix_points[0].input_compensation {
            let edge = graph.get_edge(edge_idx).unwrap();
            if edge.source == track_a {
                assert_eq!(comp, 0, "Track A edge should have 0 compensation");
            } else if edge.source == track_b {
                assert_eq!(comp, 100, "Track B edge should have 100 compensation");
            }
        }
    }
}
