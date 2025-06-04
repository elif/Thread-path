require 'set'

module BlobGraph
  class << self
    # ------------------------------------------------------------------------
    # Public method to extract blob graph from a pre-labeled image.
    def extract_from_labels(labels, options = {})
      height = labels.size
      width  = labels.first.size

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

    # MODIFIED CONDITION:
    # A pixel is a candidate for a junction point if it's not background itself,
    # AND its 3x3 neighborhood contains pixels from at least three different non-background blobs.
    if current_pixel_label != 0 && neighbor_blob_ids.size >= 3
      junction_mask[y][x] = true
    else
      junction_mask[y][x] = false
    end
  end
end
      junction_labels, junction_count = ccl_binary(junction_mask, width, height, junction_conn)

      junction_coords = Hash.new { |h,k| h[k] = [0.0, 0.0, 0] }
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
      # border_pixels: key [b1,b2].sort => array of [x,y] on the seam
      border_pixels = Hash.new { |h,k| h[k] = Set.new } # Use Set for uniqueness

      height.times do |y|
        (0...width).each do |x|
          b1 = labels[y][x]
          next if b1 == 0
          # Check right and down neighbors
          [[0,1],[1,0]].each do |dy,dx| # dy, dx
            ny, nx = y + dy, x + dx
            next if ny >= height || nx >= width
            b2 = labels[ny][nx]
            next if b2 == 0 || b2 == b1
            key = [b1,b2].sort
            # Add the pixels forming the border
            border_pixels[key].add([x,y])
            border_pixels[key].add([nx,ny])
          end
        end
      end
      # Convert sets to arrays
      border_pixels.transform_values!(&:to_a)


      # 2.3 Map each border to touching junctions
      pixel_to_junc = {} # [x,y] => junction_id
      height.times do |y|
        (0...width).each do |x|
          ji = junction_labels[y][x]
          pixel_to_junc[[x,y]] = ji if ji != 0
        end
      end

      straight_edges = Set.new # Set of [j1, j2] pairs
      border_to_juncs = {}    # [b1,b2].sort => Set of junction_ids

      border_pixels.each do |(b1,b2), pix_list|
        key = [b1,b2].sort # Ensure consistent key
        current_border_juncs = Set.new
        pix_list.each do |px,py|
          # Check if the pixel itself is a junction pixel
          j_id = pixel_to_junc[[px,py]]
          current_border_juncs.add(j_id) if j_id

          # Also check 3x3 neighborhood of border pixel for junction_labels
          neighborhood_offsets.each do |dy_n, dx_n|
            ny_n, nx_n = py + dy_n, px + dx_n
            next if ny_n < 0 || ny_n >= height || nx_n < 0 || nx_n >= width
            j_id_neighbor = junction_labels[ny_n][nx_n]
            current_border_juncs.add(j_id_neighbor) if j_id_neighbor != 0
          end
        end
        current_border_juncs.delete(0) # Remove background junction label if any
        next if current_border_juncs.size < 2

        border_to_juncs[key] = current_border_juncs.dup
        # Add edges between all pairs of junctions touching this border
        current_border_juncs.to_a.combination(2).each do |j_pair|
          straight_edges.add(j_pair.sort) # Store sorted to ensure uniqueness
        end
      end
      edges = straight_edges.to_a

      detailed_edges = []
      if skeletonize && vertices.any? # Ensure vertices is not empty
        border_to_juncs.each do |border_key, touching_juncs|
          next if touching_juncs.size < 2
          touching_juncs.to_a.combination(2).each do |j1, j2|
            next unless vertices[j1] && vertices[j2] # Ensure junctions exist

            mask = Array.new(height) { Array.new(width, false) }
            border_pixels[border_key].each { |(px,py)| mask[py][px] = true }
            skel = zhang_suen_thin(mask, width, height)

            cx1, cy1 = vertices[j1]
            cx2, cy2 = vertices[j2]
            ep1 = nearest_skel_point(skel, cx1, cy1, width, height)
            ep2 = nearest_skel_point(skel, cx2, cy2, width, height)

            if ep1 && ep2 && ep1 != ep2
              path = shortest_path_on_skel(skel, ep1, ep2, width, height, path_conn)
              simplified = path.size > 1 ? rdp(path, simplify_tol) : path
              detailed_edges << { endpoints: [j1, j2].sort, polyline: simplified } if simplified.any?
            else
              # Fallback for non-skeletonizable or identical endpoints
              detailed_edges << { endpoints: [j1, j2].sort, polyline: [[cx1,cy1],[cx2,cy2]] }
            end
          end
        end
        # Remove duplicate detailed_edges (can happen if multiple borders share same two junctions)
        detailed_edges.uniq! { |de| de[:endpoints] }
      end


      {
        vertices:       vertices,
        edges:          edges,
        detailed_edges: detailed_edges.empty? && edges.any? ? # Provide basic detailed if empty
                        edges.map { |j1,j2| { endpoints: [j1,j2].sort, polyline: [vertices[j1], vertices[j2]] } } :
                        detailed_edges
      }
    end

    private

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

          # Assign a new label if not yet labeled
          if labels[y][x] == 0
            labels[y][x] = next_label
            uf.make_set(next_label)
            next_label += 1
          end
          current_label = labels[y][x]

          # Check neighbors
          neighbors_def.each do |dy, dx|
            ny, nx = y + dy, x + dx
            next if ny < 0 || ny >= height || nx < 0 || nx >= width # Bounds check
            next unless mask[ny][nx] # Neighbor must also be true in mask

            if labels[ny][nx] == 0 # Neighbor not yet labeled
              labels[ny][nx] = current_label
            else # Neighbor already labeled, union their sets
              uf.union(current_label, labels[ny][nx])
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
          provisional_label = labels[y][x]
          root = uf.find(provisional_label)
          unless remap.key?(root)
            count += 1
            remap[root] = count
          end
          labels[y][x] = remap[root]
        end
      end
      [labels, count]
    end

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
            next unless (!p[0] || !p[2] || !p[4]) # P2*P4*P6 == 0
            next unless (!p[2] || !p[4] || !p[6]) # P4*P6*P8 == 0
            to_remove_s1 << [x,y]
          end
        end
        unless to_remove_s1.empty?
          changing = true
          to_remove_s1.each { |(x,y)| thinned[y][x] = false }
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
          to_remove_s2.each { |(x,y)| thinned[y][x] = false }
        end
      end
      thinned
    end

    # Raw neighbors for Zhang-Suen: [P2,P3,P4,P5,P6,P7,P8,P9]
    # P2=arr[y-1][x], P3=arr[y-1][x+1] ... P9=arr[y-1][x-1]
    def neighbors8_raw(arr, x, y)
      [ arr[y-1][x], arr[y-1][x+1], arr[y][x+1], arr[y+1][x+1],
        arr[y+1][x], arr[y+1][x-1], arr[y][x-1], arr[y-1][x-1] ]
    end

    def transitions_raw(p_neighbors) # p_neighbors is [P2, ..., P9]
      count = 0
      (0..7).each do |i|
        v1 = p_neighbors[i] ? 1 : 0
        v2 = p_neighbors[(i+1)%8] ? 1 : 0
        count +=1 if v1 == 0 && v2 == 1
      end
      count
    end

    def nearest_skel_point(skel, cx, cy, width, height)
      best_pt = nil
      min_dist_sq = Float::INFINITY
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
    end

    def shortest_path_on_skel(skel, p1, p2, width, height, connectivity)
      return [] if p1.nil? || p2.nil? || !skel[p1[1]][p1[0]] || !skel[p2[1]][p2[0]]
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
    end

    def rdp(pts, tol)
      return [] if pts.nil? || pts.empty?
      return pts if pts.size < 2 # Or return pts if pts.size <= 2

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
        res1 = rdp(pts[0..index], tol)
        res2 = rdp(pts[index..pend], tol)
        # res1 will include pts[index], res2 starts with pts[index]
        # so remove duplicate pts[index]
        return res1[0...-1] + res2
      else
        return [pts[0], pts[pend]] # Return only endpoints
      end
    end

    def perpendicular_distance(p1, p2, p0)
      x1,y1 = p1
      x2,y2 = p2
      x0,y0 = p0
      num = ((y2-y1)*x0 - (x2-x1)*y0 + x2*y1 - y2*x1).abs
      den = Math.sqrt((y2-y1)**2 + (x2-x1)**2)
      return 0.0 if den == 0 # p1 and p2 are the same point
      num / den
    end

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
        @parent[x] = find(@parent[x]) if @parent[x] != x
        @parent[x]
      end
      def union(x,y)
        rx = find(x)
        ry = find(y)
        return if rx == ry
        if @rank[rx] < @rank[ry]
          @parent[rx] = ry
        elsif @rank[rx] > @rank[ry]
          @parent[ry] = rx
        else
          @parent[ry] = rx
          @rank[rx] += 1
        end
      end
    end
  end
end
