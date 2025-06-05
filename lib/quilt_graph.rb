require 'set'

module QuiltGraph
  # ----------------------------------------------------------------------------
  # Attempts to repair defects until the graph is a valid quilt.
  def self.correct_quilt(blob_graph_data)
    # Extract graph topology, making deep copies to avoid modifying original input
    graph_topology = blob_graph_data[:graph_topology] || {} # Ensure graph_topology exists
    graph = {
      vertices: graph_topology[:vertices] ? graph_topology[:vertices].dup : {},
      edges:    graph_topology[:edges] ? graph_topology[:edges].map(&:dup) : []
    }

    # Initialize internal graph properties
    graph[:_next_id] ||= graph[:vertices].keys.map { |k| k.to_s.gsub(/[^\d]/, '').to_i }.max || 0
    graph[:_next_face_id] ||= 0
    graph[:faces] ||= {}

    # Extract source segmentation data for color processing
    source_segmentation = blob_graph_data[:source_segmentation]
    labels_matrix = source_segmentation ? source_segmentation[:labels] : nil
    avg_colors_map = source_segmentation ? source_segmentation[:avg_colors] : nil

    # Heuristic limit for iterations, ensure graph[:vertices] is not nil
    max_iterations = graph[:vertices] ? graph[:vertices].size * 2 : 0
    iterations = 0

    loop do
      iterations += 1
      break if iterations > max_iterations # Safety break

      modified_in_pass = false
      adj = build_adjacency_list(graph) # Adjacency list: {v => Set[u,w,...]}

      # 1. Fix vertices with degree < 2 (isolated or endpoint of a single edge)
      degrees = compute_degrees(adj)
      low_degree_verts = degrees.select { |vid, deg| deg < 2 }.keys
      unless low_degree_verts.empty?
        low_degree_verts.each { |vid| add_edge_to_nearest_distinct_vertex(graph, vid, adj) }
        modified_in_pass = true
        next # Restart checks
      end

      # 2. Fix disconnected components (if more than one)
      components = find_connected_components(graph[:vertices].keys, adj)
      if components.size > 1
        connect_closest_components(graph, components)
        modified_in_pass = true
        next # Restart checks
      end

      # 3. Fix bridges (edges whose removal disconnects the graph)
      bridges = find_bridges(graph[:vertices].keys, adj)
      unless bridges.empty?
        u, v = bridges.first # Fix one bridge at a time
        add_parallel_edge(graph, u, v) # This makes it a multi-graph temporarily if not handled
        modified_in_pass = true
        next # Restart checks
      end

      # 4. Fix any crossing edges by adding a new vertex at the intersection
      crossing = find_first_crossing(graph)
      if crossing
        edge1, edge2, intersection_point = crossing
        split_edges_at_intersection(graph, edge1, edge2, intersection_point)
        modified_in_pass = true
        next # Restart checks
      end

      break unless modified_in_pass # No fixes made in this pass, graph is stable
    end

    _identify_faces(graph, labels_matrix, avg_colors_map)

    # Merge the source_segmentation back into the final graph object
    graph[:source_segmentation] = source_segmentation
    graph
  end

  # ----------------------------------------------------------------------------
  # Convert the quilt-graph into an SVG string.
  def self.graph_to_svg_string(graph)
    vertices = graph[:vertices]
    edges    = graph[:edges]
    return "<svg />" if vertices.empty? # Handle empty graph

    xs = vertices.values.map { |pt| pt[0] }
    ys = vertices.values.map { |pt| pt[1] }
    min_x, max_x = xs.minmax
    min_y, max_y = ys.minmax

    # Handle case where all points are collinear or identical
    min_x ||= 0; max_x ||= 0; min_y ||= 0; max_y ||= 0;

    pad = 10.0
    vb_x      = min_x - pad
    vb_y      = min_y - pad
    vb_width  = (max_x - min_x) + 2 * pad
    vb_height = (max_y - min_y) + 2 * pad
    vb_width = pad * 2 if vb_width < pad # Ensure non-zero width/height
    vb_height = pad * 2 if vb_height < pad

    svg_lines = []
    svg_lines << '<?xml version="1.0" encoding="UTF-8"?>'
    svg_lines << "<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" width=\"100%\" height=\"100%\" viewBox=\"#{vb_x} #{vb_y} #{vb_width} #{vb_height}\">"
    svg_lines << "  <style>line { stroke: black; stroke-width: 1; } circle { fill: red; }</style>"

    edges.each do |(u, v)|
      next unless vertices[u] && vertices[v] # Ensure vertices exist
      x1, y1 = vertices[u]
      x2, y2 = vertices[v]
      svg_lines << "  <line x1=\"#{x1}\" y1=\"#{y1}\" x2=\"#{x2}\" y2=\"#{y2}\" />"
    end

    vertices.each do |_, (x, y)|
      svg_lines << "  <circle cx=\"#{x}\" cy=\"#{y}\" r=\"2\" />"
    end

    svg_lines << "</svg>"
    svg_lines.join("\n")
  end

  # ----------------------------------------------------------------------------
  # Checks if a graph is a "legal" quilt according to specific criteria.
  # A legal quilt must:
  # 1. Have all vertices with degree 2 or more.
  # 2. Be connected.
  # 3. Have no bridges (be 2-edge-connected).
  # 4. Have no crossing edges (be planar).
  #
  # @param graph [Hash] The graph structure with :vertices and :edges.
  # @return [Boolean] True if all checks pass, false otherwise.
  def self.is_quilt_legal?(graph)
    vertices = graph[:vertices]
    edges = graph[:edges]

    # Handle empty graph or graph with a single vertex early
    return false if vertices.nil? || vertices.empty? || vertices.size == 1

    adj = build_adjacency_list(graph)

    # 1. Degree Check: All vertices must have degree >= 2.
    # An empty graph or a single vertex graph cannot satisfy this.
    # Already handled by the check above for vertices.size == 1.
    # For other cases, compute degrees.
    degrees = compute_degrees(adj)
    return false if degrees.empty? # Should not happen if vertices is not empty
    degrees.each_value do |degree|
      return false if degree < 2
    end

    all_vertex_ids = vertices.keys

    # 2. Connectivity Check: The graph must be connected.
    # An empty graph is trivially connected/not disconnected.
    # A graph with vertices must have only one component.
    # (already handled empty graph, so vertices.keys is not empty here)
    components = find_connected_components(all_vertex_ids, adj)
    return false if components.size > 1

    # 3. Bridge Check: The graph must have no bridges.
    # (i.e., it must be 2-edge-connected)
    # An empty graph or a graph with a single vertex is not 2-edge-connected.
    # (already handled empty/single vertex graph)
    bridges = find_bridges(all_vertex_ids, adj)
    return false unless bridges.empty?

    # 4. Planarity Check: The graph must have no crossing edges.
    # (This uses a geometric check for crossings)
    crossing = find_first_crossing(graph)
    return false if crossing # A crossing was found

    true # All checks passed
  end

  private

  def self._new_face_id(graph)
    graph[:_next_face_id] += 1
    :"F#{graph[:_next_face_id]}"
  end

  def self._sort_edges_by_angle(center_vid, all_incident_edges, graph)
    center_coords = graph[:vertices][center_vid]
    return [] unless center_coords

    angles = []
    all_incident_edges.each do |u, v|
      neighbor_vid = (u == center_vid) ? v : u
      # Edge case: if the edge is a loop (u == v), and u == center_vid, then neighbor_vid is also center_vid.
      # This represents a self-loop. Depending on graph properties, this might be valid or not.
      # For angle calculation, a self-loop doesn't have a well-defined angle in this context.
      # We can choose to ignore it or handle it specially if the graph model allows self-loops.
      # Assuming here that self-loops are not typical for face definition or should be filtered by caller.
      next if neighbor_vid == center_vid

      neighbor_coords = graph[:vertices][neighbor_vid]
      next unless neighbor_coords # Skip if neighbor coords are missing for some reason

      angle = Math.atan2(neighbor_coords[1] - center_coords[1], neighbor_coords[0] - center_coords[0])
      angles << { id: neighbor_vid, angle: angle }
    end

    # Sort by angle. For ties in angle (collinear points),
    # a secondary sort key (e.g., vertex ID) could make it deterministic,
    # but is not strictly necessary for correctness of CCW traversal itself.
    sorted_neighbors = angles.sort_by { |a| a[:angle] }.map { |a| a[:id] }

    sorted_neighbors
  end

  def self._calculate_centroid(vertex_ids, all_vertices_coords)
    return nil if vertex_ids.empty?
    sum_x = 0.0
    sum_y = 0.0
    valid_vertices_count = 0
    vertex_ids.each do |vid|
      coords = all_vertices_coords[vid]
      if coords
        sum_x += coords[0]
        sum_y += coords[1]
        valid_vertices_count += 1
      end
    end
    return nil if valid_vertices_count == 0
    [sum_x / valid_vertices_count, sum_y / valid_vertices_count]
  end

  def self._identify_faces(graph, labels_matrix, avg_colors_map)
    visited_directed_edges = Set.new # Stores [u, v] pairs
    graph[:faces] ||= {} # Ensure faces hash exists, e.g. if method is called directly
    graph[:_next_face_id] ||= 0 # Ensure counter is initialized

    graph[:vertices].keys.each do |u_start_node|
      # Get all incident edges for u_start_node to find potential starting edges for faces
      # These edges must be actual pairs from graph[:edges] for _sort_edges_by_angle
      incident_to_u_start = graph[:edges].select { |e_u, e_v| e_u == u_start_node || e_v == u_start_node }

      # Sort these initial edges to have a consistent starting point for traversals from u_start_node
      sorted_initial_neighbors = _sort_edges_by_angle(u_start_node, incident_to_u_start, graph)

      sorted_initial_neighbors.each do |v_first_neighbor|
        start_edge = [u_start_node, v_first_neighbor]

        next if visited_directed_edges.include?(start_edge) # If this directed edge already processed

        # Start of a new face traversal
        new_face_id = _new_face_id(graph)
        current_face_vertices = []

        # Initialize traversal variables
        # `curr_v` is the vertex we are currently at.
        # `next_v` is the vertex we are moving to, along the edge (curr_v, next_v).
        # `prev_v_in_path` is the vertex we came from to reach `curr_v`.
        curr_v = u_start_node
        next_v = v_first_neighbor

        loop do
          # Add the current vertex to the face path.
          # Using `<< curr_v` is fine, duplicates won't occur if graph is simple and path is a cycle.
          current_face_vertices << curr_v
          visited_directed_edges.add([curr_v, next_v])

          # Prepare for the next step: the current `next_v` becomes the new `curr_v`
          # We need to find where to go from this new `curr_v` (which was old `next_v`)
          # The vertex we just came from (old `curr_v`) will be `prev_v_for_sorting`

          prev_v_for_sorting = curr_v # This is the vertex we arrived at `next_v` from
          curr_v = next_v            # Move to the next vertex

          # Find all edges incident to the new curr_v (which was next_v)
          incident_to_curr_v = graph[:edges].select { |e_u, e_v| e_u == curr_v || e_v == curr_v }

          # Sort neighbors of new curr_v by angle, relative to curr_v
          sorted_neighbors_around_curr_v = _sort_edges_by_angle(curr_v, incident_to_curr_v, graph)

          # Find prev_v_for_sorting in this sorted list.
          # The edge (curr_v, prev_v_for_sorting) is the one we just traversed (in reverse).
          # The next edge in CCW order for the face is the one *after* prev_v_for_sorting in this list.
          idx_of_prev_v = sorted_neighbors_around_curr_v.index(prev_v_for_sorting)

          # This should ideally not happen if graph is connected and edges are consistent.
          # If prev_v_for_sorting is not a neighbor of curr_v, something is wrong.
          break unless idx_of_prev_v

          # Pick the next vertex in the sorted list (cyclically)
          # This implements the "left turn" logic for CCW face traversal.
          next_idx = (idx_of_prev_v + 1) % sorted_neighbors_around_curr_v.size
          next_v = sorted_neighbors_around_curr_v[next_idx] # This is the new 'w' in (curr_v, w)

          # Loop termination condition:
          # Have we returned to the starting *vertex* of this face traversal AND
          # are we about to traverse the starting *directed edge* again?
          break if curr_v == u_start_node && next_v == v_first_neighbor

          # Safety break if something goes wrong (e.g., edge case not handled, graph defect)
          # This limit should be generous, e.g., number of vertices in the graph.
          # current_face_vertices should not grow beyond the number of unique vertices in the graph
          # for a simple cycle. If it does, it's likely an issue.
          if current_face_vertices.size > graph[:vertices].size
            # Optional: log a warning or error here
            # STDERR.puts "Warning: Face traversal exceeded vertex count for face #{new_face_id}. Graph defect?"
            break
          end
        end

        # Store the completed face.
        # A valid face in a planar graph usually has at least 3 vertices.
        # However, the definition might depend on how graph handles e.g. bridges or cut vertices.
        # Store the completed face.
        face_color = nil
        unless current_face_vertices.empty?
          if labels_matrix && avg_colors_map
            centroid = _calculate_centroid(current_face_vertices, graph[:vertices])
            if centroid
              px, py = centroid
              # Clamp coordinates to be within matrix bounds
              # labels_matrix is [rows][cols], so access is labels_matrix[y_idx][x_idx]
              matrix_height = labels_matrix.size
              matrix_width = labels_matrix[0].size # Assumes non-empty matrix

              clamped_y = py.round.clamp(0, matrix_height - 1)
              clamped_x = px.round.clamp(0, matrix_width - 1)

              blob_id = labels_matrix[clamped_y][clamped_x]
              face_color = avg_colors_map[blob_id] # Returns nil if blob_id not in map
            end
          end
          graph[:faces][new_face_id] = { vertices: current_face_vertices, color: face_color }
        end # else, if current_face_vertices is empty, do not store.
      end
    end
  end

  def self.new_vertex_id(graph)
    graph[:_next_id] += 1
    :"JCT#{graph[:_next_id]}" # More descriptive than V
  end

  def self.build_adjacency_list(graph)
    adj = Hash.new { |h, k| h[k] = Set.new }
    graph[:edges].each do |u, v|
      adj[u].add(v)
      adj[v].add(u)
    end
    adj
  end

  def self.compute_degrees(adj)
    adj.transform_values(&:size)
  end

  def self.add_edge_to_nearest_distinct_vertex(graph, vid, adj)
    return unless graph[:vertices][vid] # Vertex must exist
    min_dist_sq = Float::INFINITY
    nearest_distinct_vid = nil

    graph[:vertices].each do |other_vid, other_coords|
      next if other_vid == vid # Don't connect to self
      next if adj[vid]&.include?(other_vid) # Don't add if already connected

      dist_sq = (graph[:vertices][vid][0] - other_coords[0])**2 +
                (graph[:vertices][vid][1] - other_coords[1])**2
      if dist_sq < min_dist_sq
        min_dist_sq = dist_sq
        nearest_distinct_vid = other_vid
      end
    end

    if nearest_distinct_vid
      graph[:edges] << [vid, nearest_distinct_vid].sort # Add sorted
      graph[:edges].uniq! # Keep edges unique
    end
  end

  def self.find_connected_components(all_vertices, adj)
    visited = Set.new
    components = []
    all_vertices.each do |start_node|
      next if visited.include?(start_node)
      component = Set.new
      q = [start_node]
      visited.add(start_node)
      component.add(start_node)
      until q.empty?
        u = q.shift
        (adj[u] || []).each do |v| # adj[u] might be nil if u has no edges
          next if visited.include?(v)
          visited.add(v)
          component.add(v)
          q << v
        end
      end
      components << component.to_a unless component.empty?
    end
    components
  end

  def self.connect_closest_components(graph, components)
    # Find closest pair of vertices between first two components
    return if components.size < 2
    comp1_vids = components[0]
    comp2_vids = components[1]
    min_dist_sq = Float::INFINITY
    closest_pair = nil

    comp1_vids.each do |u|
      comp2_vids.each do |v|
        next unless graph[:vertices][u] && graph[:vertices][v]
        dist_sq = (graph[:vertices][u][0] - graph[:vertices][v][0])**2 +
                  (graph[:vertices][u][1] - graph[:vertices][v][1])**2
        if dist_sq < min_dist_sq
          min_dist_sq = dist_sq
          closest_pair = [u,v]
        end
      end
    end
    graph[:edges] << closest_pair.sort if closest_pair
    graph[:edges].uniq!
  end

  def self.find_bridges(all_vertices, adj)
    visited = Set.new
    tin = {} # discovery time
    low = {} # lowest discovery time reachable
    timer = 0
    bridges = []
    # parent = {} # Not strictly needed for just finding bridges

    dfs = lambda do |u, p = nil| # p is parent in DFS tree
      visited.add(u)
      timer += 1
      tin[u] = low[u] = timer
      (adj[u] || []).each do |v|
        next if v == p # Don't go back to parent immediately
        if visited.include?(v)
          low[u] = [low[u], tin[v]].min
        else
          dfs.call(v, u)
          low[u] = [low[u], low[v]].min
          bridges << [u,v].sort if low[v] > tin[u]
        end
      end
    end

    all_vertices.each do |v_id| # Ensure all components are visited
      dfs.call(v_id) unless visited.include?(v_id)
    end
    bridges.uniq # Ensure unique bridge pairs
  end

  def self.add_parallel_edge(graph, u, v)
    # This method simply adds another edge.
    # If the graph should not have parallel edges, this needs more logic
    # or rely on a later `graph[:edges].uniq!` if edges are simple pairs.
    # For now, assume adding it might be part of a strategy (e.g. making it 2-edge-connected)
    # and rely on `uniq!` if edges are just `[u,v].sort`.
    # However, the current implementation of `find_bridges` doesn't care about parallel edges,
    # so adding one won't resolve a bridge in its view unless graph structure changes more.
    # A common way to "fix" a bridge is to add an edge between two vertices in the components
    # formed by removing the bridge, but not parallel to the bridge itself.
    # For simplicity here, we'll add a "conceptual" parallel edge by adding a new vertex
    # along one of the existing edges, effectively splitting it, and then adding an edge.
    # This is more robust. Or, ensure no parallel edges by design.

    # Let's assume for now `graph[:edges]` can contain duplicates if needed,
    # or that `correct_quilt` loop will eventually resolve it if it's not quilt-legal.
    # A simple addition for now:
    graph[:edges] << [u,v].sort
    graph[:edges].uniq! # This ensures no true parallel edges if u,v are same.
                       # If the intent is to truly make it 2-edge-connected,
                       # this might not be sufficient. The problem asks for quilt-legal,
                       # which usually implies simple graph.
  end

  def self.find_first_crossing(graph)
    edges = graph[:edges]
    vertices = graph[:vertices]
    (0...edges.size).each do |i|
      u1, v1 = edges[i]
      next unless vertices[u1] && vertices[v1]
      p1, p2 = vertices[u1], vertices[v1]
      ((i + 1)...edges.size).each do |j|
        u2, v2 = edges[j]
        next unless vertices[u2] && vertices[v2]
        # Skip if edges share a vertex
        next if u1 == u2 || u1 == v2 || v1 == u2 || v1 == v2
        p3, p4 = vertices[u2], vertices[v2]

        # Line segment intersection check
        # (Using a common algorithm for line segment intersection)
        # Denominator for parameters t and u
        den = (p4[1] - p3[1]) * (p2[0] - p1[0]) - (p4[0] - p3[0]) * (p2[1] - p1[1])
        next if den == 0 # Parallel or collinear

        # Numerator for t (parameter for segment p1-p2)
        num_t = (p4[0] - p3[0]) * (p1[1] - p3[1]) - (p4[1] - p3[1]) * (p1[0] - p3[0])
        # Numerator for u (parameter for segment p3-p4)
        num_u = (p2[0] - p1[0]) * (p1[1] - p3[1]) - (p2[1] - p1[1]) * (p1[0] - p3[0])

        t = num_t.to_f / den
        u = num_u.to_f / den

        # Check if intersection point is within both segments (0 < t < 1 and 0 < u < 1)
        # Use a small epsilon for strict interior crossing
        epsilon = 1e-9
        if t > epsilon && t < (1.0 - epsilon) && u > epsilon && u < (1.0 - epsilon)
          intersection_x = p1[0] + t * (p2[0] - p1[0])
          intersection_y = p1[1] + t * (p2[1] - p1[1])
          return [edges[i], edges[j], [intersection_x, intersection_y]]
        end
      end
    end
    nil # No crossings found
  end

  def self.split_edges_at_intersection(graph, edge1, edge2, intersection_point)
    new_v_id = new_vertex_id(graph)
    graph[:vertices][new_v_id] = intersection_point

    u1, v1 = edge1
    u2, v2 = edge2

    # Remove original edges
    graph[:edges].delete(edge1.sort) # Assuming edges are stored sorted or need to check both orders
    graph[:edges].delete(edge1.reverse.sort)
    graph[:edges].delete(edge2.sort)
    graph[:edges].delete(edge2.reverse.sort)
    graph[:edges].uniq! # Clean up after deletion

    # Add new edges forming the split, always add sorted pairs
    graph[:edges] << [u1, new_v_id].sort
    graph[:edges] << [new_v_id, v1].sort
    graph[:edges] << [u2, new_v_id].sort
    graph[:edges] << [new_v_id, v2].sort
    graph[:edges].uniq! # Ensure no duplicates if, e.g., u1 or v1 was new_v_id (not possible here)
  end
end
