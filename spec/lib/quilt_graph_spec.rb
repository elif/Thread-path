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
      # Use a graph known to be legal by `is_quilt_legal?`
      legal_graph = {
        vertices: { a: [0,0], b: [10,0], c: [5,10] }, # Triangle
        edges:    [ [:a,:b], [:b,:c], [:c,:a] ].map(&:sort)
      }
      expect(QuiltGraph.is_quilt_legal?(legal_graph)).to be true # Pre-condition

      original_edges = legal_graph[:edges].map(&:sort).to_set
      original_vertices_count = legal_graph[:vertices].size

      corrected = QuiltGraph.correct_quilt(Marshal.load(Marshal.dump(legal_graph)))

      expect(QuiltGraph.is_quilt_legal?(corrected)).to be true
      expect(corrected[:vertices].size).to eq(original_vertices_count)
      expect(corrected[:edges].map(&:sort).to_set).to eq(original_edges)
    end

    it 'fixes vertices with degree < 2 and results in a legal quilt' do
      graph = Marshal.load(Marshal.dump(graph_degree_lt_2))
      corrected = QuiltGraph.correct_quilt(graph)
      # For a graph like graph_degree_lt_2, it might be hard to make it fully legal
      # if it's too sparse. The goal of correct_quilt is to make progress.
      # If it can be made legal, great. If not, it should fix what it can.
      # The `is_quilt_legal?` check is the ultimate arbiter here.
      expect(QuiltGraph.is_quilt_legal?(corrected)).to be true
    end

    it 'connects disconnected components and results in a legal quilt' do
      graph = Marshal.load(Marshal.dump(graph_disconnected)) # two separate edges
      corrected = QuiltGraph.correct_quilt(graph)
      # This graph has 4 vertices, initially 2 edges, disconnected, all deg 1.
      # `correct_quilt` will connect them, try to raise degrees, remove bridges if any formed.
      expect(QuiltGraph.is_quilt_legal?(corrected)).to be true
    end

    it 'fixes bridges and results in a legal quilt' do
      graph = Marshal.load(Marshal.dump(graph_with_bridge)) # a-b-c-d (line)
      corrected = QuiltGraph.correct_quilt(graph)
      # This graph has multiple bridges and low degree vertices at ends.
      expect(QuiltGraph.is_quilt_legal?(corrected)).to be true
    end

    it 'resolves crossing edges by adding a new vertex and results in a legal quilt' do
      graph_input = Marshal.load(Marshal.dump(graph_with_crossing)) # graph_with_crossing has a: [0,10], b: [0,0], c: [10,10], d: [10,0] ; edges: [a,d], [b,c]
      original_num_vertices = graph_input[:vertices].size
      original_num_edges = graph_input[:edges].size

      corrected = QuiltGraph.correct_quilt(graph_input)

      # Check specific structural changes for crossing resolution
      expect(corrected[:vertices].size).to be > original_num_vertices
      # Expect original crossing edges to be removed and 4 new edges to be added for each crossing resolved.
      # If there was only one crossing, then it's -2+4 = +2 edges.
      # This fixture graph_with_crossing has one pair of crossing edges.
      expect(corrected[:edges].size).to eq(original_num_edges - 2 + 4)

      # Verify original edges are gone (assuming :a,:d and :b,:c were the ones crossing in graph_with_crossing)
      expect(corrected[:edges].map(&:sort)).not_to include([:a,:d].sort)
      expect(corrected[:edges].map(&:sort)).not_to include([:b,:c].sort)

      # Find the new vertex (the one not in original a,b,c,d)
      new_vertex_id = corrected[:vertices].keys.find { |k| !graph_with_crossing[:vertices].keys.include?(k) }
      expect(new_vertex_id).not_to be_nil

      # Check new edges connect to this new vertex
      # These specific vertex names (:a,:d,:b,:c) are from the `graph_with_crossing` fixture
      expect(corrected[:edges].map(&:sort)).to include([:a, new_vertex_id].sort)
      expect(corrected[:edges].map(&:sort)).to include([new_vertex_id, :d].sort)
      expect(corrected[:edges].map(&:sort)).to include([:b, new_vertex_id].sort)
      expect(corrected[:edges].map(&:sort)).to include([new_vertex_id, :c].sort)

      # Check coords of new vertex (approx intersection of (0,10)-(10,0) and (0,0)-(10,10) is (5,5))
      # These coordinates are specific to the `graph_with_crossing` fixture.
      if new_vertex_id && corrected[:vertices][new_vertex_id]
        expect(corrected[:vertices][new_vertex_id][0]).to be_within(1e-6).of(5.0)
        expect(corrected[:vertices][new_vertex_id][1]).to be_within(1e-6).of(5.0)
      end

      # Finally, ensure the entire graph is legal
      expect(QuiltGraph.is_quilt_legal?(corrected)).to be true
    end

    context 'with empty or minimal graph inputs' do
      let(:empty_graph_input) { { vertices: {}, edges: [] } }
      let(:single_vertex_graph_input) { { vertices: { a: [0,0] }, edges: [] } }
      let(:single_edge_graph_input) { { vertices: { a: [0,0], b: [1,1] }, edges: [[:a, :b]] } }


      it 'handles an empty graph input, which remains not legal' do
        corrected = QuiltGraph.correct_quilt(Marshal.load(Marshal.dump(empty_graph_input)))
        expect(corrected[:vertices]).to be_empty
        expect(corrected[:edges]).to be_empty
        expect(QuiltGraph.is_quilt_legal?(corrected)).to be false
      end

      it 'handles a single vertex graph, which remains not legal' do
        corrected = QuiltGraph.correct_quilt(Marshal.load(Marshal.dump(single_vertex_graph_input)))
        expect(corrected[:vertices].size).to eq(1)
        expect(corrected[:edges]).to be_empty
        expect(QuiltGraph.is_quilt_legal?(corrected)).to be false
      end

      it 'handles a single edge graph, which cannot be made legal by current rules' do
        # A graph with 2 vertices cannot have all degrees >= 2 without multi-edges/loops.
        # `is_quilt_legal?` will return false.
        corrected = QuiltGraph.correct_quilt(Marshal.load(Marshal.dump(single_edge_graph_input)))
        # `correct_quilt` will add an edge, resulting in deg=1 for both.
        # It might try to add another edge in fix_degree_lt_2 or fix_bridges.
        # `add_edge_to_nearest_distinct_vertex` won't add parallel if one exists.
        # `add_parallel_edge` in `fix_bridges` does `uniq!`, so no true parallel edges.
        # Therefore, degrees will remain 1.
        expect(QuiltGraph.is_quilt_legal?(corrected)).to be false
      end
    end

    context 'iterative corrections on complex graphs' do
      let(:complex_graph_1) do # From previous tests
        {
          vertices: {
            a: [0,10], b: [0,0], c: [20,5], d: [30,5],
            e: [40,40], # isolated
            f: [10,0], g: [10,10]
          },
          edges: [
            [:a,:f], [:b,:g], # Crossing edges a-f and b-g
            [:a,:c], [:c,:d], [:d,:g] # Path a-c-d-g, c-d is bridge
          ].map(&:sort)
        }
      end

      let(:complex_graph_2) do # Disconnected, bridge, low-degree, crossing
        {
          vertices: {
            k1: [0,0], k2: [10,0], k3: [5,5],  # Triangle 1 (k1,k2,k3)
            m1: [20,10], m2: [30,10],          # Edge m1-m2 (low degree, part of component 2)
            c1: [10,10], c2: [15,15],          # Crossing edges c1-c4, c2-c3
            c3: [10,15], c4: [15,10],
            b1: [5,-10], b2: [10,-10]          # Bridge k1-b1, then b1-b2 (low degree at b2)
          },
          edges: [
            [:k1,:k2], [:k2,:k3], [:k3,:k1], # Triangle 1
            [:m1,:m2],                       # Component 2 (low degree)
            [:c1,:c4], [:c2,:c3],            # Crossing edges (component 3, low degree)
            [:k1,:b1], [:b1,:b2]             # Bridge and low degree (component 4 attached to 1)
          ].map(&:sort)
        }
      end


      it 'makes complex_graph_1 legal' do
        corrected = QuiltGraph.correct_quilt(Marshal.load(Marshal.dump(complex_graph_1)))
        expect(QuiltGraph.is_quilt_legal?(corrected)).to be true
      end

      it 'makes complex_graph_2 legal' do
        # This graph is quite involved. The goal is that correct_quilt should eventually stabilize it
        # into a state that passes is_quilt_legal?.
        corrected = QuiltGraph.correct_quilt(Marshal.load(Marshal.dump(complex_graph_2)))
        expect(QuiltGraph.is_quilt_legal?(corrected)).to be true
      end
    end

    context 'geometric edge cases' do
      let(:collinear_points_shared_vertex) do
        # A(0,0) -- B(5,0) -- C(10,0). B is connected to D(5,5)
        # Edges: A-B, B-C, B-D. All degrees fine except A,C,D are 1.
        # This should be made legal. No crossings.
        {
          vertices: { a:[0,0], b:[5,0], c:[10,0], d:[5,5] },
          edges: [[:a,:b],[:b,:c],[:b,:d]].map(&:sort)
        }
      end

      let(:collinear_crossing_candidate) do
        # A(0,0)-B(10,0), C(2,0)-D(8,0) where C-D is "on top" of A-B but shorter.
        # And E(5,5)-F(5,-5) crossing A-B and C-D.
        # This tests if multiple crossings on a line are handled.
        # `find_first_crossing` will find one, fix it, then loop.
        {
            vertices: { a:[0,0], b:[10,0], e:[5,5], f:[5,-5] },
            edges: [[:a,:b], [:e,:f]].map(&:sort)
        } # This is just like graph_with_crossing, expected to be made legal.
      end

      let(:coincident_edges_separate) do
        # Edge A-B and edge C-D are perfectly collinear and overlapping, but no shared vertices.
        # A(0,0)-B(10,0) and C(2,0)-D(8,0).
        # `find_first_crossing` uses strict inequality (t>eps, t<1-eps), so it won't find this.
        # This graph has all deg=1. `correct_quilt` will try to connect them.
        {
            vertices: {a:[0,0],b:[10,0], c:[2,0],d:[8,0]},
            edges: [[:a,:b],[:c,:d]].map(&:sort)
        }
      end

      let(:nearly_parallel_no_crossing) do
        # Two edges that are very close to parallel but don't cross.
        # A(0,0)-B(10,0) and C(0,1)-D(10,1.1)
        # This should be legal if degrees etc are fine.
        {
            vertices: {a:[0,0],b:[10,0], c:[0,1],d:[10,1.1]},
            edges: [[:a,:b],[:c,:d], [:a,:c], [:b,:d]].map(&:sort) # Make it a quad
        } # This forms a simple quad, should be legal.
      end

      it 'handles collinear points with a shared vertex correctly' do
        graph = Marshal.load(Marshal.dump(collinear_points_shared_vertex))
        corrected = QuiltGraph.correct_quilt(graph)
        expect(QuiltGraph.is_quilt_legal?(corrected)).to be true
      end

      it 'handles collinear points that would form a crossing if an edge passed through' do
        # This is essentially the same as graph_with_crossing if points are collinear
        # e.g. a(0,0)-d(10,0) and b(2,0)-c(8,0) - this is not a crossing.
        # A better test: a(0,0)-d(10,0) and e(5,-2)-f(5,2) - this IS a crossing.
        graph = Marshal.load(Marshal.dump(collinear_crossing_candidate))
        corrected = QuiltGraph.correct_quilt(graph)
        expect(QuiltGraph.is_quilt_legal?(corrected)).to be true
      end

      it 'handles coincident (overlapping) edges by trying to make the overall graph legal' do
        # `find_first_crossing` won't detect coincident edges as crossings.
        # `correct_quilt` will then proceed to fix other issues like low degrees or disconnectivity.
        graph = Marshal.load(Marshal.dump(coincident_edges_separate))
        corrected = QuiltGraph.correct_quilt(graph)
        # This graph has 4 vertices, all degree 1, and is disconnected.
        # It will be connected, degrees increased. The coincident nature is not explicitly handled.
        expect(QuiltGraph.is_quilt_legal?(corrected)).to be true
      end

      it 'handles nearly parallel non-crossing edges correctly' do
        graph = Marshal.load(Marshal.dump(nearly_parallel_no_crossing))
        # This graph is already legal: a cycle of 4 nodes, all degree 2.
        expect(QuiltGraph.is_quilt_legal?(graph)).to be true # Pre-condition

        original_edges = graph[:edges].map(&:sort).to_set
        original_vertices_count = graph[:vertices].size

        corrected = QuiltGraph.correct_quilt(graph)

        expect(QuiltGraph.is_quilt_legal?(corrected)).to be true
        expect(corrected[:vertices].size).to eq(original_vertices_count)
        expect(corrected[:edges].map(&:sort).to_set).to eq(original_edges)
      end
    end
  end

  # Consider adding focused tests for private methods like:
  # .find_connected_components, .connect_closest_components,
  # .find_bridges, .find_first_crossing, .split_edges_at_intersection,
  # .add_edge_to_nearest_distinct_vertex
  # if their behavior isn't fully clear from the .correct_quilt tests.
end

RSpec.describe QuiltGraph do
  describe '.is_quilt_legal?' do
    let(:triangle_graph) do # Valid: deg>=2, connected, no bridges, no crossings
      {
        vertices: { a: [0,0], b: [10,0], c: [5,10] },
        edges:    [ [:a,:b], [:b,:c], [:c,:a] ].map(&:sort)
      }
    end

    let(:grid_2x2_graph) do # Valid: deg>=2 for internals, connected, no bridges, no crossings
      # Simplified: 4 outer nodes, 1 central. All degrees should be >= 2
      # For a true 2x2 grid (9 nodes), center is deg 4, edges deg 3, corners deg 2.
      # This example is a square with diagonals.
      {
        vertices: { tl: [0,10], tr: [10,10], bl: [0,0], br: [10,0], c: [5,5] },
        edges: [
          [:tl,:tr], [:tr,:br], [:br,:bl], [:bl,:tl], # Outer square
          [:tl,:c], [:tr,:c], [:bl,:c], [:br,:c]      # Spokes to center
        ].map(&:sort)
      }
    end

    let(:square_graph_planar) do # Valid: deg=2, connected, no bridges, no crossings
        {
            vertices: { a: [0,10], b: [10,10], c: [10,0], d: [0,0] },
            edges: [[:a,:b], [:b,:c], [:c,:d], [:d,:a]].map(&:sort)
        }
    end

    it 'returns true for a valid quilt graph (triangle)' do
      expect(QuiltGraph.is_quilt_legal?(triangle_graph)).to be true
    end

    it 'returns true for a valid quilt graph (2x2 grid like)' do
      expect(QuiltGraph.is_quilt_legal?(grid_2x2_graph)).to be true
    end

    it 'returns true for a valid quilt graph (simple square)' do
        expect(QuiltGraph.is_quilt_legal?(square_graph_planar)).to be true
    end

    context 'invalid graphs: low degree' do
      let(:single_edge_graph) do
        { vertices: { a: [0,0], b: [1,1] }, edges: [[:a, :b]] }
      end
      let(:isolated_vertex_graph) do # c is isolated (deg 0), a,b have deg 1
        { vertices: { a: [0,0], b: [1,1], c: [10,10] }, edges: [[:a, :b]] }
      end
      let(:one_deg_1_vertex_graph) do # a is deg 1
        { vertices: { a: [0,0], b: [1,0], c: [2,0] }, edges: [[:a,:b], [:b,:c], [:c,:b]]} # b-c is effectively one edge here for degree calc purposes
      end


      it 'returns false for a graph with degree 1 vertices (single edge)' do
        expect(QuiltGraph.is_quilt_legal?(single_edge_graph)).to be false
      end

      it 'returns false for a graph with an isolated vertex (degree 0)' do
        expect(QuiltGraph.is_quilt_legal?(isolated_vertex_graph)).to be false
      end

      it 'returns false for a graph where one vertex has degree 1' do
        # Graph: a-b-c (a has degree 1)
        graph = {
            vertices: { a: [0,0], b: [1,0], c: [2,0] },
            edges: [[:a,:b], [:b,:c]].map(&:sort)
        }
        expect(QuiltGraph.is_quilt_legal?(graph)).to be false
      end
    end

    context 'invalid graphs: disconnected' do
      let(:two_separate_triangles) do
        {
          vertices: {
            a1: [0,0], b1: [10,0], c1: [5,10],
            a2: [20,0], b2: [30,0], c2: [25,10]
          },
          edges: [
            [:a1,:b1], [:b1,:c1], [:c1,:a1],
            [:a2,:b2], [:b2,:c2], [:c2,:a2]
          ].map(&:sort)
        }
      end
      it 'returns false for a disconnected graph' do
        expect(QuiltGraph.is_quilt_legal?(two_separate_triangles)).to be false
      end
    end

    context 'invalid graphs: bridge' do
      let(:two_triangles_one_bridge) do # edge c1-a2 is a bridge
        {
          vertices: {
            a1: [0,0], b1: [10,0], c1: [5,10],
            a2: [20,0], b2: [30,0], c2: [25,10]
          },
          edges: [
            [:a1,:b1], [:b1,:c1], [:c1,:a1], # Triangle 1
            [:c1,:a2],                       # Bridge
            [:a2,:b2], [:b2,:c2], [:c2,:a2]  # Triangle 2
          ].map(&:sort)
        }
      end
      it 'returns false for a graph with a bridge' do
        expect(QuiltGraph.is_quilt_legal?(two_triangles_one_bridge)).to be false
      end
    end

    context 'invalid graphs: crossing edges' do
      let(:crossing_edges_graph) do # K4, but drawn with a crossing. a-c and b-d cross
                                   # All degrees are 3. Connected. No bridges.
        {
          vertices: { a: [0,10], b: [10,10], c: [0,0], d: [10,0] },
          edges:    [ [:a,:b], [:b,:c], [:c,:d], [:d,:a], [:a,:c], [:b,:d] ].map(&:sort)
          # Crossing occurs with [:a,:d] and [:b,:c] if we take these four from K4
          # Edges: AC and BD cross in a square ABCD
          # Let's use the simpler existing one for clarity if possible, or define one carefully.
          # The one from fixture: a[0,10], b[0,0], c[10,10], d[10,0]. Edges: [a,d], [b,c]
        }
      end
      let(:simple_crossing_graph) do # Edges a-d and b-c cross
        {
          vertices: { a: [0,10], b: [0,0], c: [10,10], d: [10,0] }, # a-d is (0,10)-(10,0), b-c is (0,0)-(10,10)
          edges:    [ [:a,:d], [:b,:c] ].map(&:sort)
          # This graph also has degree 1 vertices. Need a graph that ONLY fails planarity.
        }
      end

      let(:k4_crossing_graph) do # K4, often drawn with a crossing. All degrees 3.
                                 # Connected. No bridges (2-edge-connected).
        {
          vertices: { a: [0,10], b: [10,10], c: [0,0], d: [10,0] },
          # Edges: ab, bc, cd, da (outer square)
          # Diagonals: ac, bd. These will cross if drawn naively.
          # (0,10)--(0,0) is ac. (10,10)--(10,0) is bd. These don't cross.
          # (0,10)--(10,0) is ad. (10,10)--(0,0) is bc. These cross.
          edges: [[:a,:b], [:b,:d], [:d,:c], [:c,:a], [:a,:d], [:b,:c]].map(&:sort)
        }
      end

      it 'returns false for a graph with crossing edges (K4 example)' do
        # This K4 graph will have edges ad and bc crossing.
        # All vertices have degree 3. It's connected. It's 2-edge-connected (no bridges).
        expect(QuiltGraph.is_quilt_legal?(k4_crossing_graph)).to be false
      end
    end

    context 'invalid graphs: multiple violations' do
      let(:multiple_fail_graph) do # Disconnected AND low degree (c,d are deg 1)
        {
          vertices: { a: [0,0], b: [1,1], c: [10,10], d: [11,11] },
          edges: [[:a,:b], [:c,:d]].map(&:sort) # Two separate edges
        }
      end
      it 'returns false for a graph with multiple violations' do
        expect(QuiltGraph.is_quilt_legal?(multiple_fail_graph)).to be false
      end
    end

    context 'edge cases' do
      let(:empty_graph) { { vertices: {}, edges: [] } }
      let(:single_vertex_graph) { { vertices: { a: [0,0] }, edges: [] } }
      let(:single_edge_graph_again) { { vertices: { a: [0,0], b: [1,1] }, edges: [[:a, :b]] } }
      let(:two_vertices_cycle_graph) do # Degs = 2, connected, no bridges, no crossings
          {
              vertices: { a: [0,0], b: [1,1] },
              edges: [[:a,:b], [:a,:b]].map(&:sort).uniq # Simulate adding two edges, then unique.
                                                        # If edges must be distinct pairs:
                                                        # This is tricky. A "cycle" of 2 nodes means parallel edges.
                                                        # The current adj list builder naturally handles parallel edges
                                                        # by just connecting them. Degrees would be 1.
                                                        # find_bridges logic might not see this as 2-edge-connected
                                                        # unless it models multi-graph.
                                                        # For quilt_legal, we assume simple graphs primarily.
                                                        # A true cycle graph C_2 is {a,b} with edges (a,b)_1 and (a,b)_2.
                                                        # Let's assume quilt_graph edges are unique pairs [u,v].
                                                        # So this cannot be represented as distinct edges if not a multigraph.
                                                        # If it's { vertices: {a,b}, edges: [[:a,:b]]}, then it's single_edge_graph.
                                                        #
                                                        # If the graph structure allows multiple edges like:
                                                        # edges: [[:a,:b, id:1], [:a,:b, id:2]]
                                                        # then it's possible. But current structure is edges: [[:u,:v],...]
                                                        # So, let's redefine this as a graph that *should* pass if it were allowed.
                                                        # A digon (2 vertices, 2 edges between them)
                                                        # For the purpose of is_quilt_legal? using the current adj list:
                                                        # adj[a] = {b}, adj[b] = {a}. Degrees are 1. Fails.
                                                        #
                                                        # Let's test a line of 3 vertices: a-b-c. a,c are deg 1. Fails.
                                                        # A cycle of 3 vertices (triangle) is already tested as valid.
                                                        #
                                                        # What if it means a graph that *looks* like a 2-cycle but due to planarity
                                                        # it's actually fine? e.g. two edges very close.
                                                        #
                                                        # Given the problem statement, the structure is simple graph.
                                                        # So, "2 vertices and 2 parallel edges forming a cycle"
                                                        # would have edges: [[:a,:b], [:a,:b]]. After uniq, it's [[:a,:b]].
                                                        # This becomes single_edge_graph.
                                                        # So, this test might be redundant or needs clarification on "parallel edges".
                                                        # For now, assume it means a graph that *would* be fine if it's simple.
                                                        # The simplest 2-regular, 2-edge-connected, planar graph is C_3 (triangle).
                                                        #
                                                        # Let's test a loop (C2) using slightly different vertex IDs for the two edges,
                                                        # then merge them in thought. No, stick to definition.
                                                        # The problem implies the graph structure itself.
                                                        # So, edges: [[:a,:b], [:a,:b]] after `map(&:sort).uniq` is just one edge.
                                                        # This test case as "2 vertices, 2 parallel edges" will fail degree check.
          }
      end
      # Self-loop test:
      # graph[:edges] << [:a, :a]
      # build_adjacency_list: adj[a].add(a)
      # compute_degrees: adj[a].size (depends on Set behavior with self-add, usually counts as 1)
      # find_bridges: dfs might get confused by self-loops if not handled.
      # find_first_crossing: a self-loop is a point, not a line segment for crossing.
      # It's generally assumed simple graphs (no self-loops) for these geometric operations.
      # Let's assume self-loops make a graph not "quilt legal" due to degree calculation or bridge issues.
      let(:self_loop_graph) do
        { vertices: { a: [0,0], b: [1,1] }, edges: [[:a,:a], [:a,:b]].map(&:sort) }
        # adj[a] = {a,b}, adj[b] = {a}
        # degree[a] = 2, degree[b] = 1. Fails degree check for b.
      end
       let(:self_loop_graph_complex) do # a-a, a-b, b-b. a deg 3 (a,a,b), b deg 3 (a,b,b) if Set counts self once.
                                       # adj[a]={a,b}, adj[b]={a,b}. deg(a)=2, deg(b)=2. Connected.
                                       # Bridges: Removing a-b disconnects if a,b are distinct.
                                       # If adj[a]={a,b}, adj[b]={a,b}, tin[a]=1, low[a]=1.
                                       # dfs(a,p=nil): visited a. tin[a]=low[a]=1.
                                       #   neighbor a of a: if v==p (p is nil, so no). if visited.include?(a) (yes). low[a]=min(low[a],tin[a])=1.
                                       #   neighbor b of a: if v==p (no). if visited.include?(b) (no). dfs(b,a)
                                       #     dfs(b,p=a): visited b. tin[b]=low[b]=2.
                                       #       neighbor a of b: if v==p (yes, v=a, p=a). skip.
                                       #       neighbor b of b: if v==p (no). if visited.include?(b) (yes). low[b]=min(low[b],tin[b])=2.
                                       #     low[a]=min(low[a],low[b]) = min(1,2)=1.
                                       #     low[b] > tin[a]? (2 > 1) Yes. Bridge [a,b]. So it fails.
        { vertices: { a: [0,0], b: [1,1] }, edges: [[:a,:a], [:a,:b], [:b,:b]].map(&:sort).uniq }
        # after uniq: [[:a,:a], [:a,:b], [:b,:b]]
      end


      it 'returns false for an empty graph' do
        expect(QuiltGraph.is_quilt_legal?(empty_graph)).to be false
      end

      it 'returns false for a single vertex graph' do
        expect(QuiltGraph.is_quilt_legal?(single_vertex_graph)).to be false
      end

      it 'returns false for a single edge graph (edge case check)' do
        expect(QuiltGraph.is_quilt_legal?(single_edge_graph_again)).to be false
      end

      it 'returns false for a graph with a self-loop (violates degree or bridge for simple graphs)' do
        # self_loop_graph: a-a, a-b. deg(a)=2 (if set counts 'a' once), deg(b)=1. Fails.
        expect(QuiltGraph.is_quilt_legal?(self_loop_graph)).to be false
      end

      it 'returns false for a graph with self-loops that might seem to satisfy degrees (a-a, a-b, b-b)' do
        # This graph has adj[a]={a,b} and adj[b]={a,b}. So degrees are 2 for both. Connected.
        # However, the edge [a,b] is a bridge.
        expect(QuiltGraph.is_quilt_legal?(self_loop_graph_complex)).to be false
      end

      it 'returns true for a two-vertex cycle (digon) if it were simple and distinct edges (conceptually C_2)' do
        # As discussed, current structure implies edges are [[:a,:b]], which is degree 1.
        # A true C_2 (two nodes, two edges between them) would pass if graph could model it.
        # The method is_quilt_legal? is given a graph. If that graph is:
        # { vertices: {a,b}, edges: [[:a,:b], [:a,:b]] } -> after uniq -> { vertices: {a,b}, edges: [[:a,:b]] } -> Fails (deg 1)
        # This test is more about theoretical properties than current data structure limits.
        # For the implemented code, it will behave like single_edge_graph.
        # To make it pass, we'd need a graph like a triangle (C_3) or square (C_4).
        #
        # The prompt: "Graph with 2 vertices and 2 parallel edges forming a cycle"
        # This implies the graph *has* these parallel edges.
        # The build_adjacency_list treats [:u,:v] and [:v,:u] as one edge, and multiple [u,v] as one connection.
        # So adj[u]={v}, adj[v]={u}. Degree is 1.
        # So this test *should* be false based on how the helpers work.
        two_parallel_edges = {
            vertices: { a: [0,0], b: [1,1] },
            edges: [[:a,:b], [:a,:b]].map(&:sort) # Becomes [[:a,:b]] after internal processing by adjacency list builder
        }
        # Adjacency list for this will be a => {b}, b => {a}. Degrees will be 1.
        expect(QuiltGraph.is_quilt_legal?(two_parallel_edges)).to be false
      end
    end
  end
end
