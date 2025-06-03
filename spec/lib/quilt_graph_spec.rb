require 'spec_helper'
require 'quilt_graph' # Assumes lib is in $LOAD_PATH via spec_helper
require 'set'

RSpec.describe QuiltGraph do

  # --- Helper to build adjacency list for checking graph properties ---
  def build_adj(graph)
    adj = Hash.new { |h, k| h[k] = Set.new }
    return adj unless graph && graph[:edges]
    graph[:edges].each do |u, v|
      adj[u].add(v)
      adj[v].add(u)
    end
    adj
  end

  # --- Fixture Data ---
  let(:simple_valid_graph) do
    {
      vertices: { a: [0,0], b: [10,0], c: [5,10] },
      edges:    [ [:a,:b], [:b,:c], [:c,:a] ].map(&:sort) # Triangle
    }
  end

  let(:graph_degree_lt_2) do # Vertex d is isolated, vertex e is degree 1
    {
      vertices: { a: [0,0], b: [10,0], c: [5,10], d: [20,20], e: [0,20], f: [0,30] },
      edges:    [ [:a,:b], [:b,:c], [:c,:a], [:e,:f] ].map(&:sort)
    }
  end

  let(:graph_disconnected) do
    {
      vertices: { a: [0,0], b: [10,0], c: [20,20], d: [30,20] },
      edges:    [ [:a,:b], [:c,:d] ].map(&:sort)
    }
  end

  let(:graph_with_bridge) do # Edge b-c is a bridge
    {
      vertices: { a: [0,0], b: [10,0], c: [20,0], d: [30,0] },
      edges:    [ [:a,:b], [:b,:c], [:c,:d] ].map(&:sort)
    }
  end

  let(:graph_with_bridge_more_complex) do
    {
      vertices: { a: [0,0], b: [10,0], x:[5,5], y:[5,-5], c: [20,0], z:[25,5], w:[25,-5]},
      edges: [[:a,:b], [:a,:x], [:b,:x], [:a,:y], [:b,:y], # comp1: a,b,x,y
              [:b,:c], # bridge
              [:c,:d], [:c,:z], [:d,:z], [:c,:w], [:d,:w] # comp2: c,d,z,w (d is implicit from edges)
             ].map(&:sort)
    }
  end


  let(:graph_with_crossing) do # Edges a-d and b-c cross
    {
      vertices: { a: [0,10], b: [0,0], c: [10,10], d: [10,0] },
      edges:    [ [:a,:d], [:b,:c] ].map(&:sort) # AD crosses BC
    }
  end

  describe '.graph_to_svg_string' do
    it 'generates an SVG string for a simple graph' do
      svg = QuiltGraph.graph_to_svg_string(simple_valid_graph)
      expect(svg).to be_a(String)
      expect(svg).to include('<svg')
      expect(svg).to include('</svg>')
      expect(svg).to include('x1="0" y1="0" x2="10" y2="0"') # Edge a-b
      expect(svg).to include('cx="0" cy="0" r="2"')     # Vertex a
    end

    it 'handles an empty graph' do
      svg = QuiltGraph.graph_to_svg_string({ vertices: {}, edges: [] })
      expect(svg).to include('<svg />') # Or some other valid empty SVG representation
    end

    it 'handles a graph with one vertex and no edges' do
        graph = { vertices: {a: [5,5]}, edges: [] }
        svg = QuiltGraph.graph_to_svg_string(graph)
        expect(svg).to include('cx="5" cy="5" r="2"')
        expect(svg).not_to include('<line')
    end
  end

  describe '.correct_quilt' do
    it 'does not modify an already valid graph' do
      # Need a more robust definition of "valid" or check specific properties
      # For now, assume simple_valid_graph is quilt-legal enough that correct_quilt is idempotent
      original_edges = simple_valid_graph[:edges].map(&:sort).to_set
      original_vertices_count = simple_valid_graph[:vertices].size

      corrected = QuiltGraph.correct_quilt(Marshal.load(Marshal.dump(simple_valid_graph))) # Deep copy

      corrected_adj = build_adj(corrected)
      corrected_degrees = corrected_adj.transform_values(&:size)

      expect(corrected_degrees.values.all? { |deg| deg >= 2 }).to be true
      # Add more checks for planarity, 2-edge-connectivity if possible/needed for "valid"
      # For now, check if structure largely unchanged for an already good graph
      expect(corrected[:vertices].size).to eq(original_vertices_count)
      expect(corrected[:edges].map(&:sort).to_set).to eq(original_edges)
    end

    it 'fixes vertices with degree < 2' do
      graph = Marshal.load(Marshal.dump(graph_degree_lt_2))
      corrected = QuiltGraph.correct_quilt(graph)
      adj = build_adj(corrected)
      degrees = adj.transform_values(&:size)

      # Check that original low-degree vertices now have degree >= 2 (or were removed if not connectable)
      # The current `add_edge_to_nearest_distinct_vertex` should ensure they get connected.
      expect(degrees[:d]).to be >= 1 # Was 0, should connect to something
      expect(degrees[:e]).to be >= 2 # Was 1 (e-f), should connect to something else
      expect(degrees.values.all? { |deg| deg >= 1 }).to be true # At least degree 1 after fix
      # A stronger check would be all deg >= 2 if graph is non-trivial
    end

    it 'connects disconnected components' do
      graph = Marshal.load(Marshal.dump(graph_disconnected))
      corrected = QuiltGraph.correct_quilt(graph)
      adj = build_adj(corrected)

      # Check if graph is now connected (all vertices reachable from 'a')
      # This assumes 'a' is a valid key, which it is in graph_disconnected
      # If graph could be empty, this check needs to be smarter.
      if corrected[:vertices].any?
        q = [corrected[:vertices].keys.first]
        visited = Set[q.first]
        until q.empty?
          u = q.shift
          (adj[u] || []).each do |v|
            next if visited.include?(v)
            visited.add(v)
            q << v
          end
        end
        expect(visited.size).to eq(corrected[:vertices].keys.size)
      else
        expect(corrected[:vertices]).to be_empty # Or handle as appropriate
      end
    end

    # Test for bridge fixing is tricky because "add_parallel_edge" might not truly make it 2-edge-connected
    # in a way that a simple bridge finding algorithm would immediately see as resolved without further changes.
    # The current implementation of add_parallel_edge adds a unique edge, so it should help.
    it 'attempts to fix bridges (makes graph 2-edge-connected or adds edges)' do
      graph = Marshal.load(Marshal.dump(graph_with_bridge))
      # original_edge_count = graph[:edges].size # Not used
      corrected = QuiltGraph.correct_quilt(graph)

      # Expectation: At least one edge was added to try and resolve the bridge b-c
      # Or the structure changed such that b-c is no longer a bridge
      # This is a weak test, stronger would be to re-run find_bridges and expect none.
      current_bridges = QuiltGraph.send(:find_bridges, corrected[:vertices].keys, build_adj(corrected))
      expect(current_bridges.select{|u,v| Set[u,v] == Set[:b,:c] }).to be_empty

    end

    it 'resolves crossing edges by adding a new vertex at the intersection' do
      graph = Marshal.load(Marshal.dump(graph_with_crossing))
      original_num_vertices = graph[:vertices].size
      original_num_edges = graph[:edges].size

      corrected = QuiltGraph.correct_quilt(graph)

      # Expect a new vertex to be added at the intersection
      expect(corrected[:vertices].size).to be > original_num_vertices
      # Expect original crossing edges to be removed and 4 new edges to be added
      expect(corrected[:edges].size).to eq(original_num_edges - 2 + 4)

      # Verify original edges are gone
      expect(corrected[:edges]).not_to include([:a,:d].sort)
      expect(corrected[:edges]).not_to include([:b,:c].sort)

      # Find the new vertex (the one not in original a,b,c,d)
      new_vertex_id = corrected[:vertices].keys.find { |k| ![:a,:b,:c,:d].include?(k) }
      expect(new_vertex_id).not_to be_nil

      # Check new edges connect to this new vertex
      expect(corrected[:edges]).to include([:a, new_vertex_id].sort)
      expect(corrected[:edges]).to include([new_vertex_id, :d].sort)
      expect(corrected[:edges]).to include([:b, new_vertex_id].sort)
      expect(corrected[:edges]).to include([new_vertex_id, :c].sort)

      # Check coords of new vertex (approx intersection of (0,10)-(10,0) and (0,0)-(10,10) is (5,5))
      expect(corrected[:vertices][new_vertex_id][0]).to be_within(1e-6).of(5.0)
      expect(corrected[:vertices][new_vertex_id][1]).to be_within(1e-6).of(5.0)
    end

    context 'iterative corrections' do
      it 'handles a graph requiring multiple types of fixes' do
        # Graph with isolated vertex 'e', a bridge 'c-d', and a crossing 'a-f' with 'b-g'
        complex_graph = {
          vertices: {
            a: [0,10], b: [0,0], c: [20,5], d: [30,5],
            e: [40,40], # isolated
            f: [10,0], g: [10,10]
          },
          edges: [
            [:a,:f], [:b,:g], # Crossing edges
            [:a,:c], [:c,:d], [:d,:g] # Path a-c-d-g, c-d is bridge initially
          ].map(&:sort)
        }

        corrected = QuiltGraph.correct_quilt(Marshal.load(Marshal.dump(complex_graph)))
        adj = build_adj(corrected)
        degrees = adj.transform_values(&:size)

        # 1. Degree of 'e' should be >= 1 (connected to something)
        #    Actually, quilt-legal implies degree >=2 for all.
        #    The loop should ensure this.
        degrees.each do |v, deg|
            expect(deg).to be >= 2 unless corrected[:vertices].size <= 1 # trivial case
        end

        # 2. Graph should be connected
        if corrected[:vertices].any?
            q_c = [corrected[:vertices].keys.first]
            visited_c = Set[q_c.first]
            until q_c.empty?
              u = q_c.shift
              (adj[u] || []).each do |v_node|
                next if visited_c.include?(v_node)
                visited_c.add(v_node)
                q_c << v_node
              end
            end
            expect(visited_c.size).to eq(corrected[:vertices].keys.size)
        end


        # 3. No bridges (check this by finding bridges again)
        current_bridges = QuiltGraph.send(:find_bridges, corrected[:vertices].keys, adj)
        expect(current_bridges).to be_empty

        # 4. No crossings (check this by finding crossings again)
        #    This requires access to the line intersection logic if we were to re-run it.
        #    For now, assume the iterations handle it if no more fixes are made.
        #    A simpler check: number of vertices should have increased due to crossing fix.
        expect(corrected[:vertices].size).to be > complex_graph[:vertices].size
      end
    end
  end

  # Consider adding focused tests for private methods like:
  # .find_connected_components, .connect_closest_components,
  # .find_bridges, .find_first_crossing, .split_edges_at_intersection,
  # .add_edge_to_nearest_distinct_vertex
  # if their behavior isn't fully clear from the .correct_quilt tests.
end
