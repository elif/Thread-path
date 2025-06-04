# No require 'cv' or 'opencv' here, as this module will use pure Ruby.
require 'set'

module BlobGraph
  module MatzEye
    # UnionFind class (can be adapted from Impressionist::MatzEye::UnionFind or defined anew)
    class UnionFind
      def initialize
        @parent = {}
        @rank = {}
      end

      def make_set(item)
        unless @parent.key?(item)
          @parent[item] = item
          @rank[item] = 0
        end
      end

      def find(item)
        @parent[item] = find(@parent[item]) if @parent[item] != item
        @parent[item]
      end

      def union(item1, item2)
        root1 = find(item1)
        root2 = find(item2)
        return if root1 == root2
        if @rank[root1] < @rank[root2]
          @parent[root1] = root2
        elsif @rank[root1] > @rank[root2]
          @parent[root2] = root1
        else
          @parent[root2] = root1
          @rank[root1] += 1
        end
      end
    end # UnionFind

    class << self
      # Helper for binary CCL (mask contains 0 or 1)
      def perform_binary_ccl(mask, width, height, connectivity)
        labels = Array.new(height) { Array.new(width, 0) }
        uf = UnionFind.new
        next_label = 1

        neighbors_def = if connectivity == 8
                          [[-1,0], [-1,-1], [0,-1], [-1,1]] # N, NW, W, NE
                        else # 4-connectivity
                          [[-1,0], [0,-1]] # N, W
                        end

        (0...height).each do |y|
          (0...width).each do |x|
            next if mask[y][x] == 0 # Only process foreground pixels (marked as 1)

            neighbor_labels = []
            neighbors_def.each do |dy, dx|
              ny, nx = y + dy, x + dx
              next if ny < 0 || ny >= height || nx < 0 || nx >= width
              if mask[ny][nx] != 0 && labels[ny][nx] != 0
                neighbor_labels << labels[ny][nx]
              end
            end

            if neighbor_labels.empty?
              labels[y][x] = next_label
              uf.make_set(next_label)
              next_label += 1
            else
              min_label = neighbor_labels.min
              labels[y][x] = min_label
              neighbor_labels.each { |lbl| uf.union(min_label, lbl) }
            end
          end
        end

        remap = {}
        blob_count = 0
        (0...height).each do |y|
          (0...width).each do |x|
            if labels[y][x] != 0
              root = uf.find(labels[y][x])
              unless remap.key?(root)
                blob_count += 1
                remap[root] = blob_count
              end
              labels[y][x] = remap[root]
            end
          end
        end
        [labels, blob_count]
      end


      def extract_from_labels(labels_array, options)
        return { vertices: {}, edges: [], detailed_edges: [], _internal_contrib_blobs: {} } if labels_array.empty? || labels_array.first.empty?

        height = labels_array.size
        width = labels_array.first.size

        # 1. Detect Junction Pixels & Contributing Blobs
        junction_pixel_mask = Array.new(height) { Array.new(width, 0) } # 0 for non-junction, 1 for junction
        pixel_to_blob_sets = {}

        # Define full 3x3 neighborhood, excluding center for neighbor check
        neighborhood_offsets = [[-1,-1],[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0],[1,1]]
        # Simpler: define all 8 + center, then filter/handle center pixel within loop
        full_neighborhood_offsets = [[-1,-1],[-1,0],[-1,1],[0,-1],[0,0],[0,1],[1,-1],[1,0],[1,1]]


        (0...height).each do |y| # Iterate full range, handle borders for neighborhood
          (0...width).each do |x|
            current_pixel_label_val = labels_array[y][x]
            next if current_pixel_label_val == 0 # Junction pixel must be on a blob

            neighbor_blob_ids = Set.new
            full_neighborhood_offsets.each do |dy, dx|
              ny, nx = y + dy, x + dx
              if ny >= 0 && ny < height && nx >= 0 && nx < width && labels_array[ny][nx] != 0
                neighbor_blob_ids.add(labels_array[ny][nx])
              end
            end

            if neighbor_blob_ids.size >= 3
              junction_pixel_mask[y][x] = 1
              pixel_to_blob_sets[[x,y]] = neighbor_blob_ids.dup
            end
          end
        end

        # 2. Cluster Junction Pixels (Binary CCL)
        connectivity = options.fetch(:junction_conn, 8) == 8 ? 8 : 4
        j_labels_array, num_j_labels = perform_binary_ccl(junction_pixel_mask, width, height, connectivity)

        # 3. Calculate Centroids & Aggregate Contributing Blobs for each junction cluster
        junction_pixel_sums = Hash.new { |h,k| h[k] = { sum_x: 0.0, sum_y: 0.0, count: 0, contributing_blobs: Set.new } }

        (0...height).each do |r|
          (0...width).each do |c|
            j_id = j_labels_array[r][c] # This is the junction cluster ID
            if j_id > 0 # If this pixel is part of a junction cluster
              junction_pixel_sums[j_id][:sum_x] += c
              junction_pixel_sums[j_id][:sum_y] += r
              junction_pixel_sums[j_id][:count] += 1
              # Aggregate blob IDs from the original junction pixels that form this j_id component
              junction_pixel_sums[j_id][:contributing_blobs].merge(pixel_to_blob_sets[[c,r]]) if pixel_to_blob_sets[[c,r]]
            end
          end
        end

        vertices = {}
        junction_contributing_blobs_map = {}
        junction_pixel_sums.each do |j_id, data|
          if data[:count] > 0
            vertices[j_id] = [data[:sum_x] / data[:count], data[:sum_y] / data[:count]]
            junction_contributing_blobs_map[j_id] = data[:contributing_blobs]
          end
        end

        # 4. Edge Identification
        edges_set = Set.new
        j_ids = vertices.keys.to_a # Array of junction label IDs (already unique)

        j_ids.combination(2).each do |j_id1, j_id2|
          blobs1 = junction_contributing_blobs_map[j_id1]
          blobs2 = junction_contributing_blobs_map[j_id2]

          # Ensure blobs1 and blobs2 are not nil (though Hash.new default should prevent this for keys from `vertices`)
          if blobs1 && blobs2 && (blobs1 & blobs2).size >= 2
            edges_set.add([j_id1, j_id2].sort)
          end
        end
        final_edges_list = edges_set.to_a

        # 5. Create Basic Detailed Edges
        detailed_edges = final_edges_list.map do |j_id1, j_id2|
          v1_coords = vertices[j_id1]
          v2_coords = vertices[j_id2]
          # next unless v1_coords && v2_coords # Should be guaranteed if j_ids from vertices.keys
          { endpoints: [j_id1, j_id2].sort, polyline: [v1_coords, v2_coords] }
        end

        # Final Return Value
        {
          vertices: vertices,
          edges: final_edges_list,
          detailed_edges: detailed_edges
          # _internal_contrib_blobs is removed from final signature
        }
      end # def extract_from_labels
    end # class << self
  end # module MatzEye
end # module BlobGraph
