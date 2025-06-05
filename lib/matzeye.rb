module MatzEye
  require_relative 'matzeye/union_find'

  # Image Processing Methods (from Impressionist::MatzEye)
  def self.box_blur(pixel_array, width, height, radius)
    radius = 1 if radius < 1
    output_pixel_array = Array.new(height) { Array.new(width) }
    (0...height).each do |y|
      (0...width).each do |x|
        r_sum, g_sum, b_sum, a_sum = 0, 0, 0, 0
        pixel_count = 0
        y_start = [0, y - radius].max
        y_end = [height - 1, y + radius].min
        x_start = [0, x - radius].max
        x_end = [width - 1, x + radius].min
        (y_start..y_end).each do |ky|
          (x_start..x_end).each do |kx|
            pixel = pixel_array[ky][kx]
            r_sum += pixel[0]; g_sum += pixel[1]; b_sum += pixel[2];
            a_sum += pixel[3] if pixel.size == 4
            pixel_count += 1
          end
        end
        avg_r = (r_sum / pixel_count.to_f).round
        avg_g = (g_sum / pixel_count.to_f).round
        avg_b = (b_sum / pixel_count.to_f).round
        # Handle alpha: if original pixel had alpha, average it, else default to opaque
        original_pixel_alpha = pixel_array[y][x].size == 4 ? pixel_array[y][x][3] : 255
        avg_a = (pixel_array[y][x].size == 4 && pixel_count > 0) ? (a_sum / pixel_count.to_f).round : original_pixel_alpha
        avg_a = 255 if pixel_count == 0 # Should not happen with valid inputs

        output_pixel_array[y][x] = [avg_r, avg_g, avg_b, avg_a]
      end
    end
    output_pixel_array
  end

  def self.quantize_colors(pixel_array, width, height, interval)
    raise ArgumentError, "Interval must be >= 1" if interval < 1
    output_pixel_array = Array.new(height) { Array.new(width) }
    (0...height).each do |y|
      (0...width).each do |x|
        pixel = pixel_array[y][x]
        r, g, b = pixel[0], pixel[1], pixel[2]
        a = pixel.size == 4 ? pixel[3] : 255 # Preserve alpha or default to opaque
        quant_r = (r / interval) * interval
        quant_g = (g / interval) * interval
        quant_b = (b / interval) * interval
        output_pixel_array[y][x] = [quant_r, quant_g, quant_b, a]
      end
    end
    output_pixel_array
  end

  def self.connected_components(quantized_pixel_data, width, height, connectivity, options = {})
    labels = Array.new(height) { Array.new(width, 0) }
    uf = UnionFind.new
    next_label = 1
    neighbors_def = if connectivity == 8
                      [[-1,0], [-1,-1], [0,-1], [-1,1]]
                    else
                      [[-1,0], [0,-1]]
                    end
    (0...height).each do |y|
      (0...width).each do |x|
        current_color = quantized_pixel_data[y][x]
        # Allow processing of packed color 0, unless explicitly told not to by options
        is_background_skip = (current_color == 0 && !options.fetch(:process_zero_as_color, false))
        next if is_background_skip

        neighbor_labels_of_same_color = []
        neighbors_def.each do |dy, dx|
          ny, nx = y + dy, x + dx
          next if ny < 0 || ny >= height || nx < 0 || nx >= width
          if quantized_pixel_data[ny][nx] == current_color && labels[ny][nx] != 0
            neighbor_labels_of_same_color << labels[ny][nx]
          end
        end
        if neighbor_labels_of_same_color.empty?
          labels[y][x] = next_label
          uf.make_set(next_label)
          next_label += 1
        else
          min_label = neighbor_labels_of_same_color.min
          labels[y][x] = min_label
          neighbor_labels_of_same_color.each { |label| uf.union(min_label, label) }
        end
      end
    end
    remap = {}
    blob_count = 0
    (0...height).each do |y|
      (0...width).each do |x|
        if labels[y][x] != 0
          root_label = uf.find(labels[y][x])
          unless remap.key?(root_label)
            blob_count += 1
            remap[root_label] = blob_count
          end
          labels[y][x] = remap[root_label]
        end
      end
    end
    [labels, blob_count]
  end

  def self.filter_blobs_by_size(labels_array, width, height, min_size)
    # Calculate current blob count based on max label_id in labels_array
    current_max_label = 0
    labels_array.each { |row| row.each { |label| current_max_label = [current_max_label, label].max } }
    return [labels_array, current_max_label] if min_size <= 0

    blob_sizes = Hash.new(0)
    (0...height).each do |y| (0...width).each do |x|
        label = labels_array[y][x]
        blob_sizes[label] += 1 if label != 0
    end end
    small_blob_ids = Set.new
    blob_sizes.each { |label, size| small_blob_ids.add(label) if label != 0 && size < min_size }

    filtered_labels = Array.new(height) { Array.new(width, 0) }
    (0...height).each do |y| (0...width).each do |x|
        original_label = labels_array[y][x]
        filtered_labels[y][x] = original_label unless original_label == 0 || small_blob_ids.include?(original_label)
    end end

    final_labels = Array.new(height) { Array.new(width, 0) }
    label_map = {}; new_blob_count = 0
    (0...height).each do |y| (0...width).each do |x|
        current_filtered_label = filtered_labels[y][x]
        if current_filtered_label != 0
          unless label_map.key?(current_filtered_label)
            new_blob_count += 1
            label_map[current_filtered_label] = new_blob_count
          end
          final_labels[y][x] = label_map[current_filtered_label]
        end
    end end
    [final_labels, new_blob_count]
  end

  def self.calculate_blob_average_colors(original_pixel_array, width, height, labels_array, blob_count)
    return {} if blob_count == 0
    blob_color_sums = Hash.new { |h, k| h[k] = {r: 0, g: 0, b: 0, a:0, count: 0} }
    (0...height).each do |y| (0...width).each do |x|
        label = labels_array[y][x]
        next if label == 0
        pixel = original_pixel_array[y][x] # Expects [R,G,B,A] or [R,G,B]
        blob_color_sums[label][:r] += pixel[0]; blob_color_sums[label][:g] += pixel[1];
        blob_color_sums[label][:b] += pixel[2];
        blob_color_sums[label][:a] += (pixel.size == 4 ? pixel[3] : 255); # Default alpha to 255 if not present
        blob_color_sums[label][:count] += 1
    end end
    average_colors_map = {}
    (1..blob_count).each do |label|
      data = blob_color_sums[label]
      if data[:count] > 0
        avg_r = (data[:r] / data[:count].to_f).round; avg_g = (data[:g] / data[:count].to_f).round;
        avg_b = (data[:b] / data[:count].to_f).round; avg_a = (data[:a] / data[:count].to_f).round;
        average_colors_map[label] = [avg_r, avg_g, avg_b, avg_a]
      else
        average_colors_map[label] = [0,0,0,255]
      end
    end
    average_colors_map
  end

  def self.build_image_from_labels(labels_array, width, height, avg_colors_map)
    output_pixel_array = Array.new(height) { Array.new(width) }
    white_pixel = [255,255,255,255]
    (0...height).each do |y| (0...width).each do |x|
        label_id = labels_array[y][x]
        output_pixel_array[y][x] = (label_id > 0 && avg_colors_map.key?(label_id)) ? avg_colors_map[label_id] : white_pixel
    end end
    output_pixel_array
  end

  # Blob Graph Extraction Methods (from BlobGraph::MatzEye)
  def self.detect_junction_pixels(labels_array, width, height)
    junction_pixel_mask = Array.new(height) { Array.new(width, 0) }
    pixel_to_blob_sets = {}
    full_neighborhood_offsets = [[-1,-1],[-1,0],[-1,1],[0,-1],[0,0],[0,1],[1,-1],[1,0],[1,1]]
    (0...height).each do |y|
      (0...width).each do |x|
        current_pixel_label_val = labels_array[y][x]
        next if current_pixel_label_val == 0
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
    [junction_pixel_mask, pixel_to_blob_sets]
  end

  def self.cluster_junction_pixels(junction_pixel_mask_array, width, height, connectivity)
    labels = Array.new(height) { Array.new(width, 0) }
    uf = UnionFind.new
    next_label = 1
    neighbors_def = if connectivity == 8
                      [[-1,0], [-1,-1], [0,-1], [-1,1]]
                    else
                      [[-1,0], [0,-1]]
                    end
    (0...height).each do |y|
      (0...width).each do |x|
        next if junction_pixel_mask_array[y][x] == 0
        neighbor_labels = []
        neighbors_def.each do |dy, dx|
          ny, nx = y + dy, x + dx
          next if ny < 0 || ny >= height || nx < 0 || nx >= width
          if junction_pixel_mask_array[ny][nx] != 0 && labels[ny][nx] != 0
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
    cluster_count = 0
    (0...height).each do |y|
      (0...width).each do |x|
        if labels[y][x] != 0
          root = uf.find(labels[y][x])
          unless remap.key?(root)
            cluster_count += 1
            remap[root] = cluster_count
          end
          labels[y][x] = remap[root]
        end
      end
    end
    [labels, cluster_count]
  end

  def self.calculate_junction_centroids_and_contrib_blobs(cluster_labels_array, width, height, pixel_to_blob_sets_hash, num_clusters)
    junction_pixel_sums = Hash.new { |h,k| h[k] = { sum_x: 0.0, sum_y: 0.0, count: 0, contributing_blobs: Set.new } }
    (0...height).each do |r|
      (0...width).each do |c|
        j_id = cluster_labels_array[r][c]
        if j_id > 0
          junction_pixel_sums[j_id][:sum_x] += c
          junction_pixel_sums[j_id][:sum_y] += r
          junction_pixel_sums[j_id][:count] += 1
          junction_pixel_sums[j_id][:contributing_blobs].merge(pixel_to_blob_sets_hash[[c,r]]) if pixel_to_blob_sets_hash[[c,r]]
        end
      end
    end
    vertices_hash = {}
    junction_contrib_blobs_hash = {}
    junction_pixel_sums.each do |j_id, data|
      if data[:count] > 0
        vertices_hash[j_id] = [data[:sum_x] / data[:count], data[:sum_y] / data[:count]]
        junction_contrib_blobs_hash[j_id] = data[:contributing_blobs]
      end
    end
    [vertices_hash, junction_contrib_blobs_hash]
  end

  def self.identify_edges(vertices_hash, junction_contrib_blobs_hash)
    edges_set = Set.new
    j_ids = vertices_hash.keys.to_a
    j_ids.combination(2).each do |j_id1, j_id2|
      blobs1 = junction_contrib_blobs_hash[j_id1]
      blobs2 = junction_contrib_blobs_hash[j_id2]
      if blobs1 && blobs2 && (blobs1 & blobs2).size >= 2
        edges_set.add([j_id1, j_id2].sort)
      end
    end
    edges_set.to_a
  end
end
