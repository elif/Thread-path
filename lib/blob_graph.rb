require 'set'
require_relative 'blob_graph_matzeye_adapter' # Changed from blob_graph_matzeye

module BlobGraph
  class << self
    # Public method to extract blob graph from a pre-labeled image.
    def extract_from_labels(segmentation_data, options = {})
      implementation = options.fetch(:implementation, :ruby) # Default to :ruby
      if implementation == :matzeye # Implementation key remains :matzeye
        BlobGraph::MatzEyeAdapter.extract_from_labels(segmentation_data, options) # Call the Adapter
      else # :ruby or any other value defaults to original
        _ruby_extract_from_labels(segmentation_data, options)
      end
    end

    private # All methods below this are private class methods

    def _ruby_extract_from_labels(segmentation_data, options = {})
      labels = segmentation_data[:labels]
      height = segmentation_data[:height] # or labels.size
      width  = segmentation_data[:width]  # or labels.first.size

      junction_conn  = options.fetch(:junction_conn, 8)
      junction_conn  = [4, 8].include?(junction_conn) ? junction_conn : 8
      path_conn      = options.fetch(:path_conn, 8)
      path_conn      = [4, 8].include?(path_conn) ? path_conn : 8
      skeletonize    = options.fetch(:skeletonize, true)
      simplify_tol   = options.fetch(:simplify_tol, 2.0).to_f

      # 2.1 Detect junction pixels (≥3 distinct blob IDs in its 3x3 neighborhood including self)
      junction_mask = Array.new(height) { Array.new(width, false) }
      neighborhood_offsets = [[-1,-1],[-1,0],[-1,1],[0,-1],[0,0],[0,1],[1,-1],[1,0],[1,1]]

      height.times do |y|
        (0...width).each do |x|
          current_pixel_label = labels[y][x]
          neighbor_blob_ids = Set.new
          neighborhood_offsets.each do |dy_offset, dx_offset|
            ny, nx = y + dy_offset, x + dx_offset
            next if ny < 0 || ny >= height || nx < 0 || nx >= width
            blob_id = labels[ny][nx]
            neighbor_blob_ids.add(blob_id) if blob_id != 0
          end
          if current_pixel_label != 0 && neighbor_blob_ids.size >= 3
            junction_mask[y][x] = true
          else
            junction_mask[y][x] = false
          end
        end
      end # End of height.times for junction_mask

      junction_labels, junction_count = ccl_binary(junction_mask, width, height, junction_conn)
      junction_coords = Hash.new { |h,k| h[k] = [0.0, 0.0, 0] } # Sum_x, Sum_y, Count
      height.times do |y|
        (0...width).each do |x|
          ji = junction_labels[y][x]
          next if ji == 0
          junction_coords[ji][0] += x
          junction_coords[ji][1] += y
          junction_coords[ji][2] += 1
        end
      end

      vertices = {} # j_id => [cx, cy]
      junction_coords.each do |ji, (sx, sy, count)|
        vertices[ji] = [sx / count.to_f, sy / count.to_f] if count > 0
      end

      # 2.2 Build blob adjacency and gather border pixels for each blob pair
      border_pixels = Hash.new { |h,k| h[k] = Set.new } # Key: [b1,b2].sort, Value: Set of [x,y]
      height.times do |y|
        (0...width).each do |x|
          b1 = labels[y][x]
          next if b1 == 0
          [[0,1],[1,0]].each do |dy,dx| # Check right (0,1) and down (1,0)
            ny, nx = y + dy, x + dx
            next if ny >= height || nx >= width
            b2 = labels[ny][nx]
            next if b2 == 0 || b2 == b1
            key = [b1,b2].sort
            border_pixels[key].add([x,y])
            border_pixels[key].add([nx,ny])
          end
        end
      end
      border_pixels.transform_values!(&:to_a) # Convert sets to arrays

      # 2.3 Map each border to touching junctions
      pixel_to_junc = {} # [x,y] => junction_id
      height.times do |y|
        (0...width).each do |x|
          ji = junction_labels[y][x]
          pixel_to_junc[[x,y]] = ji if ji != 0
        end
      end

      straight_edges = Set.new # Set of [j1, j2] pairs, sorted
      border_to_juncs = {}    # Key: [b1,b2].sort, Value: Set of junction_ids
      border_pixels.each do |border_pair_key, pix_list|
        current_border_juncs = Set.new
        pix_list.each do |px,py|
          j_id = pixel_to_junc[[px,py]] # Check if the border pixel itself is a junction
          current_border_juncs.add(j_id) if j_id && j_id != 0 # Ensure j_id is not nil or 0

          # Check 3x3 neighborhood of border pixel for junction_labels
          neighborhood_offsets.each do |dy_n, dx_n|
            ny_n, nx_n = py + dy_n, px + dx_n
            next if ny_n < 0 || ny_n >= height || nx_n < 0 || nx_n >= width
            j_id_neighbor = junction_labels[ny_n][nx_n] # Get junction label directly
            current_border_juncs.add(j_id_neighbor) if j_id_neighbor != 0
          end
        end
        current_border_juncs.delete(0) # Should be redundant if checks above are proper
        next if current_border_juncs.size < 2

        border_to_juncs[border_pair_key] = current_border_juncs.dup
        current_border_juncs.to_a.combination(2).each do |j_pair|
          straight_edges.add(j_pair.sort)
        end
      end
      edges = straight_edges.to_a

      detailed_edges = []
      if skeletonize && vertices.any? && !edges.empty? # Added !edges.empty? check
        border_to_juncs.each do |border_key, touching_juncs_set|
          next if touching_juncs_set.size < 2
          # Create edges only between junctions that are part of the 'edges' list
          # This avoids creating detailed_edges for junctions that might be near the same border pixels
          # but don't form a "primary" edge as detected by straight_edges logic.
          # However, the current straight_edges are formed from these same touching_juncs.
          # So, this iteration should align with the 'edges' list.
          touching_juncs_set.to_a.combination(2).each do |j1, j2|
            sorted_pair = [j1, j2].sort
            next unless edges.include?(sorted_pair) # Ensure this pair is a recognized edge
            next unless vertices[j1] && vertices[j2]

            mask = Array.new(height) { Array.new(width, false) }
            # Ensure border_pixels[border_key] is not nil, though it shouldn't be if border_to_juncs has the key
            (border_pixels[border_key] || []).each { |(px,py)| mask[py][px] = true }

            # Skip if mask is empty (no border pixels for this key somehow)
            next if mask.all? { |row| row.none? }

            skel = zhang_suen_thin(mask, width, height)
            cx1, cy1 = vertices[j1]
            cx2, cy2 = vertices[j2]
            ep1 = nearest_skel_point(skel, cx1, cy1, width, height)
            ep2 = nearest_skel_point(skel, cx2, cy2, width, height)

            path_polyline = []
            if ep1 && ep2 # && ep1 != ep2 (path can be single point if ep1==ep2 after snapping)
              path = shortest_path_on_skel(skel, ep1, ep2, width, height, path_conn)
              path_polyline = path.size > 1 ? rdp(path, simplify_tol) : path
              path_polyline = path if path_polyline.empty? && !path.empty? # rdp might return empty for 2 pts if tol too high
            end

            if path_polyline.any?
              detailed_edges << { endpoints: sorted_pair, polyline: path_polyline }
            else
              # Fallback: straight line if no path or empty path, but points exist
              detailed_edges << { endpoints: sorted_pair, polyline: [[cx1,cy1],[cx2,cy2]] }
            end
          end
        end
        # Remove duplicate detailed_edges (can happen if multiple borders share same two junctions,
        # or if logic above produces identical entries before uniq)
        detailed_edges.uniq! { |de| de[:endpoints] }
      end

      # If detailed_edges could not be computed but we have vertices and simple edges,
      # provide straight lines as polylines.
      if detailed_edges.empty? && edges.any? && vertices.any?
        detailed_edges = edges.map do |j1,j2|
          # Ensure vertices for j1 and j2 exist before trying to access them
          v1_coords = vertices[j1]
          v2_coords = vertices[j2]
          if v1_coords && v2_coords
            { endpoints: [j1,j2].sort, polyline: [v1_coords, v2_coords] }
          else
            nil # Or some other placeholder if vertices are missing for an edge
          end
        end.compact # Remove any nils if vertex data was missing
      end

      current_graph_output = {
        vertices:       vertices,
        edges:          edges,
        detailed_edges: detailed_edges
      }
      return {
        :graph_topology => current_graph_output,
        :source_segmentation => segmentation_data # Pass the original segmentation_data through
      }
    end # end _ruby_extract_from_labels

    def ccl_binary(mask, width, height, connectivity)
      labels = Array.new(height) { Array.new(width, 0) }
      uf = UnionFind.new
      next_label = 1
      neighbors_def = if connectivity == 8
        [[-1,0], [0,-1], [-1,-1], [1,-1]] # N, W, NW, NE
      else # 4-connectivity
        [[-1,0], [0,-1]] # N, W
      end

      height.times do |y|
        (0...width).each do |x|
          next unless mask[y][x] # Only process true pixels

          if labels[y][x] == 0 # Not yet labeled
            # Check neighbors for existing labels
            found_neighbor_label = 0
            neighbors_def.each do |dy, dx|
              ny, nx = y + dy, x + dx
              next if ny < 0 || ny >= height || nx < 0 || nx >= width
              if mask[ny][nx] && labels[ny][nx] != 0
                if found_neighbor_label == 0
                  found_neighbor_label = labels[ny][nx]
                else
                  uf.union(found_neighbor_label, labels[ny][nx])
                end
              end
            end
            if found_neighbor_label == 0
              labels[y][x] = next_label
              uf.make_set(next_label)
              next_label += 1
            else
              labels[y][x] = found_neighbor_label # Should be root after find, but uf.union handles it
            end
          end
          # Union with other neighbors if already labeled
          current_label_root = uf.find(labels[y][x]) # Ensure we use the root for union operations
          neighbors_def.each do |dy, dx|
            ny, nx = y + dy, x + dx
            next if ny < 0 || ny >= height || nx < 0 || nx >= width
            if mask[ny][nx] && labels[ny][nx] != 0
              uf.union(current_label_root, labels[ny][nx])
            # if mask[ny][nx] and labels[ny][nx] is 0, it will be processed when iteration reaches it.
            end
          end
        end
      end

      # Remap labels to be contiguous
      remap = {}
      count = 0
      height.times do |y|
        (0...width).each do |x|
          next unless mask[y][x] # Only process true pixels
          if labels[y][x] != 0
            root = uf.find(labels[y][x])
            unless remap.key?(root)
              count += 1
              remap[root] = count
            end
            labels[y][x] = remap[root]
          end
        end
      end
      [labels, count]
    end # end ccl_binary

    def zhang_suen_thin(mask, width, height)
      thinned = Array.new(height) { |y| mask[y].dup }
      changing = true
      while changing
        changing = false
        # Sub-iteration 1
        to_remove_s1 = []
        (1...height-1).each do |y| # Iterate excluding borders
          (1...width-1).each do |x|
            next unless thinned[y][x]
            p = neighbors8_raw(thinned, x, y) # p[0]=p2, p[1]=p3 ... p[7]=p9
            bp = p.count(true)
            next unless bp.between?(2,6)
            ap = transitions_raw(p)
            next unless ap == 1
            next unless (!p[0] || !p[2] || !p[4]) # P2*P4*P6 == 0 (at least one is false)
            next unless (!p[2] || !p[4] || !p[6]) # P4*P6*P8 == 0 (at least one is false)
            to_remove_s1 << [x,y]
          end
        end
        unless to_remove_s1.empty?
          changing = true
          to_remove_s1.each { |(px,py)| thinned[py][px] = false }
        end

        # Sub-iteration 2
        to_remove_s2 = []
        (1...height-1).each do |y|
          (1...width-1).each do |x|
            next unless thinned[y][x]
            p = neighbors8_raw(thinned, x, y)
            bp = p.count(true)
            next unless bp.between?(2,6)
            ap = transitions_raw(p)
            next unless ap == 1
            next unless (!p[0] || !p[2] || !p[6]) # P2*P4*P8 == 0
            next unless (!p[0] || !p[4] || !p[6]) # P2*P6*P8 == 0
            to_remove_s2 << [x,y]
          end
        end
        unless to_remove_s2.empty?
          changing = true
          to_remove_s2.each { |(px,py)| thinned[py][px] = false }
        end
      end
      thinned
    end # end zhang_suen_thin

    def neighbors8_raw(arr, x, y)
      [ arr[y-1][x], arr[y-1][x+1], arr[y][x+1], arr[y+1][x+1],
        arr[y+1][x], arr[y+1][x-1], arr[y][x-1], arr[y-1][x-1] ]
    end # end neighbors8_raw

    def transitions_raw(p_neighbors) # p_neighbors is [P2, ..., P9]
      count = 0
      (0..7).each do |i|
        v1 = p_neighbors[i] # true or false
        v2 = p_neighbors[(i+1)%8] # true or false
        count +=1 if !v1 && v2 # from false to true (0 to 1 transition)
      end
      count
    end # end transitions_raw

    def nearest_skel_point(skel, cx, cy, width, height)
      best_pt = nil
      min_dist_sq = Float::INFINITY
      # If skeleton is empty, return nil early
      is_skel_empty = skel.all? { |row| row.none? }
      return nil if is_skel_empty

      height.times do |y|
        (0...width).each do |x|
          if skel[y][x]
            dist_sq = (x-cx)**2 + (y-cy)**2
            if dist_sq < min_dist_sq
              min_dist_sq = dist_sq
              best_pt = [x,y]
            end
          end
        end
      end
      best_pt
    end # end nearest_skel_point

    def shortest_path_on_skel(skel, p1, p2, width, height, connectivity)
      return [] if p1.nil? || p2.nil?
      # Check if p1 or p2 are outside bounds or not on skeleton
      return [] if p1[1] < 0 || p1[1] >= height || p1[0] < 0 || p1[0] >= width || !skel[p1[1]][p1[0]]
      return [] if p2[1] < 0 || p2[1] >= height || p2[0] < 0 || p2[0] >= width || !skel[p2[1]][p2[0]]
      return [p1] if p1 == p2


      q = [[p1, [p1]]] # Queue stores [current_node, path_to_current_node]
      visited = { p1 => true }

      dirs = if connectivity == 8
        [[-1,0],[1,0],[0,-1],[0,1],[-1,-1],[-1,1],[1,-1],[1,1]]
      else # 4-connectivity
        [[-1,0],[1,0],[0,-1],[0,1]]
      end

      until q.empty?
        curr, path = q.shift
        return path if curr == p2

        dirs.each do |dy, dx|
          ny, nx = curr[1] + dy, curr[0] + dx
          next_node = [nx, ny]
          next if ny < 0 || ny >= height || nx < 0 || nx >= width
          next unless skel[ny][nx]
          next if visited[next_node]

          visited[next_node] = true
          q << [next_node, path + [next_node]]
        end
      end
      [] # Path not found
    end # end shortest_path_on_skel

    def rdp(pts, tol)
      return [] if pts.nil? || pts.empty?
      return pts if pts.size <= 2 # Return points if 2 or less, no simplification possible

      dmax = 0.0
      index = 0
      pend = pts.size - 1

      (1...pend).each do |i|
        d = perpendicular_distance(pts[0], pts[pend], pts[i])
        if d > dmax
          index = i
          dmax = d
        end
      end

      if dmax > tol
        # Recursive calls
        res1 = rdp(pts[0..index], tol)
        res2 = rdp(pts[index..pend], tol)
        # Concatenate results, removing duplicate point at 'index'
        return res1[0...-1] + res2
      else
        # If max distance is not greater than tolerance, simplify to start and end points
        return [pts[0], pts[pend]]
      end
    end # end rdp

    def perpendicular_distance(p1, p2, p0)
      x1,y1 = p1; x2,y2 = p2; x0,y0 = p0
      # Area = |(y2-y1)*x0 - (x2-x1)*y0 + x2*y1 - y2*x1| / 2
      # Base = sqrt((y2-y1)^2 + (x2-x1)^2)
      # Height (distance) = 2 * Area / Base
      num = ((y2-y1)*x0 - (x2-x1)*y0 + x2*y1 - y2*x1).abs
      den = Math.sqrt((y2-y1)**2 + (x2-x1)**2)
      return 0.0 if den == 0 # p1 and p2 are the same point
      num / den
    end # end perpendicular_distance

    class UnionFind
      def initialize
        @parent = {}
        @rank = {}
      end
      def make_set(x)
        unless @parent.key?(x)
          @parent[x] = x
          @rank[x] = 0
        end
      end
      def find(x)
        # Path compression
        @parent[x] = find(@parent[x]) if @parent[x] != x
        @parent[x]
      end
      def union(x,y)
        root_x = find(x)
        root_y = find(y)
        return if root_x == root_y # Already in the same set

        # Union by rank
        if @rank[root_x] < @rank[root_y]
          @parent[root_x] = root_y
        elsif @rank[root_x] > @rank[root_y]
          @parent[root_y] = root_x
        else
          @parent[root_y] = root_x
          @rank[root_x] += 1
        end
      end
    end # end UnionFind
  end # End of class << self
end # End of module BlobGraph
