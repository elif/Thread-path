require 'chunky_png'
require 'set'
require 'fileutils' # Added for FileUtils.mkdir_p
require_relative 'impressionist_matzeye_adapter'
require_relative 'impressionist_palette_quantize_adapter'

module Impressionist
  VERSION = '1.1.0'

  class << self
    def recolor(input_path, output_path, options = {})
      img_obj = load_image(input_path)
      # Call the chunky_png specific implementation (process_image, not the dispatcher process)
      result_hash = process_image(img_obj, options)
      recolored_image = result_hash[:processed_image] # Corrected key
      save_image(recolored_image, output_path)
      true
    end

    def process(input_or_path, options = {})
      img = if input_or_path.is_a?(ChunkyPNG::Image)
              input_or_path
            else
              load_image(input_or_path)
            end

      implementation = options.fetch(:implementation, :chunky_png).to_sym

      case implementation
      when :matzeye
        Impressionist::MatzEyeAdapter.process_image(img, options)
      when :palette_quantize
        Impressionist::PaletteQuantizeAdapter.process_image(img, options)
      when :chunky_png
        process_image(img, options)
      else
        raise ArgumentError, "Unsupported implementation: #{implementation}. Supported are :chunky_png, :matzeye, :palette_quantize."
      end
    end

    def load_image(path)
      raise ArgumentError, "Input path must be a string." unless path.is_a?(String)
      raise ArgumentError, "File not found: #{path}" unless File.exist?(path)
      ChunkyPNG::Image.from_file(path)
    end

    def save_image(img, path)
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      img.save(path) # This line can cause error if img is nil
    end


    def _apply_blur(image, do_blur, blur_radius)
      return image unless do_blur
      box_blur(image, blur_radius)
    end
    def _quantize_image(image, quant_interval)
      width = image.width
      height = image.height
      quantized = Array.new(height) { Array.new(width, 0) }
      height.times do |y|
        (0...width).each do |x|
          pixel = image[x, y]
          r = ChunkyPNG::Color.r(pixel)
          g = ChunkyPNG::Color.g(pixel)
          b = ChunkyPNG::Color.b(pixel)
          rq = (r / quant_interval) * quant_interval
          gq = (g / quant_interval) * quant_interval
          bq = (b / quant_interval) * quant_interval
          quantized[y][x] = (rq << 16) | (gq << 8) | bq
        end
      end
      quantized
    end

    def _calculate_labels(quantized_image, width, height, connectivity, min_blob_size)
      labels, blob_count = connected_components(quantized_image, width, height, connectivity)

      if min_blob_size > 0
        blob_sizes_intermediate = Array.new(blob_count + 1, 0)
        height.times do |y|
          (0...width).each do |x|
            bid = labels[y][x]
            blob_sizes_intermediate[bid] += 1 if bid > 0
          end
        end

        small_blobs = blob_sizes_intermediate.each_index.select { |bid| bid != 0 && blob_sizes_intermediate[bid] > 0 && blob_sizes_intermediate[bid] < min_blob_size }.to_set

        if !small_blobs.empty?
          labels = merge_small_blobs(labels, quantized_image, width, height, small_blobs, connectivity)
          labels, blob_count = relabel_contiguous(labels, width, height)
        end
      end

      final_blob_sizes = Array.new(blob_count + 1, 0)
      height.times do |y|
        (0...width).each do |x|
          bid = labels[y][x]
          final_blob_sizes[bid] += 1 if bid > 0
        end
      end

      { labels: labels, blob_count: blob_count, blob_sizes: final_blob_sizes }
    end

    def _calculate_average_colors(original_image, labels, blob_count)
      width = original_image.width
      height = original_image.height
      sums   = Array.new(blob_count + 1) { [0, 0, 0] }
      counts = Array.new(blob_count + 1, 0)

      height.times do |y|
        (0...width).each do |x|
          bid = labels[y][x]
          next if bid == 0
          pixel = original_image[x, y]
          sums[bid][0] += ChunkyPNG::Color.r(pixel)
          sums[bid][1] += ChunkyPNG::Color.g(pixel)
          sums[bid][2] += ChunkyPNG::Color.b(pixel)
          counts[bid] += 1
        end
      end

      avg_color = Array.new(blob_count + 1, ChunkyPNG::Color::TRANSPARENT)
      (1..blob_count).each do |bid|
        count = counts[bid]
        if count > 0
          r_avg = (sums[bid][0] / count.to_f).round
          g_avg = (sums[bid][1] / count.to_f).round
          b_avg = (sums[bid][2] / count.to_f).round
          avg_color[bid] = ChunkyPNG::Color.rgba(r_avg, g_avg, b_avg, 255)
        else
          # This case should ideally not happen if blob_count is accurate
          # and labels only contain bids up to blob_count.
          # Assigning black, but could be an error or logged.
          avg_color[bid] = ChunkyPNG::Color::BLACK
        end
      end
      avg_color
    end

    def _build_recolored_image(width, height, labels, average_colors)
      out_img = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::WHITE)
      height.times do |y|
        (0...width).each do |x|
          bid = labels[y][x]
          out_img[x, y] = average_colors[bid] # average_colors should have an entry for bid=0 (background)
        end
      end
      out_img
    end

    def process_image(img, options = {})
      quant_interval = (options[:quant_interval] || 16).to_i
      quant_interval = 1 if quant_interval < 1
      do_blur        = options[:blur]        || false
      blur_radius    = (options[:blur_radius] || 1).to_i
      blur_radius    = 1 if blur_radius < 1
      connectivity   = (options[:connectivity] || 4).to_i
      connectivity   = [4, 8].include?(connectivity) ? connectivity : 4
      min_blob_size  = (options[:min_blob_size] || 0).to_i
      min_blob_size  = 0 if min_blob_size < 0

      width  = img.width
      height = img.height

      blurred_img = _apply_blur(img, do_blur, blur_radius)
      quantized_data = _quantize_image(blurred_img, quant_interval)

      labeling_result = _calculate_labels(quantized_data, width, height, connectivity, min_blob_size)
      labels = labeling_result[:labels]
      blob_count = labeling_result[:blob_count]
      blob_sizes_map = labeling_result[:blob_sizes]

      avg_colors_map = _calculate_average_colors(img, labels, blob_count)

      output_image = _build_recolored_image(width, height, labels, avg_colors_map)

      {
        :processed_image    => output_image,
        :image_attributes   => {
          :width  => width,
          :height => height
        },
        :segmentation_result => {
          :labels       => labels,
          :avg_colors   => avg_colors_map,
          :blob_count   => blob_count,
          :blob_sizes   => blob_sizes_map,
          :width        => width,
          :height       => height
        }
      }
    end

    def merge_small_blobs(labels, quantized, width, height, small_blobs, connectivity)
      new_labels = Array.new(height) { |y| labels[y].dup }
      if connectivity == 8
        neigh = [[-1,0],[1,0],[0,-1],[0,1],[-1,-1],[-1,1],[1,-1],[1,1]]
      else
        neigh = [[-1,0],[1,0],[0,-1],[0,1]]
      end

      height.times do |y|
        (0...width).each do |x|
          bid = labels[y][x]
          next unless small_blobs.include?(bid)
          neighbor_counts = Hash.new(0)
          neigh.each do |dx,dy|
            nx, ny = x+dx, y+dy
            next if nx < 0 || nx >= width || ny < 0 || ny >= height
            nbid = labels[ny][nx]
            if nbid > 0 && !small_blobs.include?(nbid)
              neighbor_counts[nbid] += 1
            end
          end
          if neighbor_counts.any?
            best = neighbor_counts.max_by { |_, count| count }[0]
            new_labels[y][x] = best
          else
            # If a small blob has no non-small neighbors, it might become 0 (background)
            # or remain, depending on desired behavior. Here it becomes 0.
            new_labels[y][x] = 0
          end
        end
      end
      new_labels
    end

    def relabel_contiguous(labels, width, height)
      final_labels = Array.new(height) { Array.new(width, 0) }
      uf = UnionFind.new
      next_label = 1
      neigh = [[-1,0],[0,-1]] # Only need to check backwards/upwards due to scan order

      height.times do |y|
        (0...width).each do |x|
          current_original_label = labels[y][x] # This is the label from after merge_small_blobs
          next if current_original_label == 0 # Skip background pixels assigned in merge_small_blobs

          # For any non-zero pixel, it needs a label in final_labels
          # Check neighbors for same original label to connect components
          # This logic might be overly complex for simple relabeling;
          # connected_components algorithm is usually more direct for this.
          # However, this is about ensuring labels are 1..N_final.

          # Simplified relabeling: use connected_components again on the *merged* labels
          # but only considering same-labeled regions.
          # The existing UF approach is okay if current_original_label is used carefully.
          # The main goal of relabel_contiguous is to make blob IDs dense from 1 to N.

          # Sticking to existing logic structure for minimal invasive change:
          # This part seems to try to assign a *new* set of labels (final_labels)
          # based on contiguity of *original* labels (from the 'labels' input array).

          # If a pixel hasn't been assigned a new label yet in final_labels
          if final_labels[y][x] == 0
            final_labels[y][x] = next_label
            uf.make_set(next_label)
            # Propagate this new label to contiguous pixels with the same original_label
            # This requires a flood fill or similar scan from this point.
            # The current neighbor check only looks back, which is part of typical CCA.
            # Let's assume this is intended to work with the UnionFind structure.
            next_label += 1
          end
          provisional_label_for_current_pixel = final_labels[y][x]

          neigh.each do |dx, dy| # Check left and up
            nx, ny = x + dx, y + dy
            next if nx < 0 || ny < 0 # Boundary checks

            # If neighbor had same original label (from after merge_small_blobs)
            if labels[ny][nx] == current_original_label
              if final_labels[ny][nx] == 0 # Should not happen if scan order is top-to-bottom, left-to-right
                 final_labels[ny][nx] = provisional_label_for_current_pixel
              else
                 # Union the current pixel's component with the neighbor's component
                 uf.union(provisional_label_for_current_pixel, final_labels[ny][nx])
              end
            end
          end
        end
      end

      remap = {}
      final_blob_count = 0
      height.times do |y|
        (0...width).each do |x|
          # This provisional_label is from the new set of labels being built in final_labels
          provisional_label = final_labels[y][x]
          next if provisional_label == 0 # Skip background

          root = uf.find(provisional_label)
          unless remap.key?(root)
            final_blob_count += 1
            remap[root] = final_blob_count
          end
          final_labels[y][x] = remap[root]
        end
      end
      [final_labels, final_blob_count]
    end

    private # box_blur and connected_components were implicitly private by not being self.method

    def box_blur(img, radius)
      width  = img.width
      height = img.height
      out = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::WHITE)
      radius = [1, radius.to_i].max # Ensure radius is at least 1

      height.times do |y|
        (0...width).each do |x|
          r_sum = g_sum = b_sum = 0
          count = 0
          ((y - radius)..(y + radius)).each do |yy|
            yy_clamp = yy.clamp(0, height - 1)
            ((x - radius)..(x + radius)).each do |xx|
              xx_clamp = xx.clamp(0, width - 1)
              pix = img[xx_clamp, yy_clamp]
              r_sum += ChunkyPNG::Color.r(pix)
              g_sum += ChunkyPNG::Color.g(pix)
              b_sum += ChunkyPNG::Color.b(pix)
              count += 1
            end
          end
          out[x, y] = ChunkyPNG::Color.rgba((r_sum / count.to_f).round,
                                            (g_sum / count.to_f).round,
                                            (b_sum / count.to_f).round,
                                            ChunkyPNG::Color.a(img[x,y]))
        end
      end
      out
    end

    def connected_components(quantized, width, height, connectivity)
      labels = Array.new(height) { Array.new(width, 0) }
      uf = UnionFind.new
      next_label = 1 # Labels are 1-based

      # Define neighbors for 4-way or 8-way connectivity
      # Only need to check neighbors that could have already been labeled (e.g. left, up-left, up, up-right for 8-way)
      # Classic CCA uses:
      # For N4: (x-1, y) and (x, y-1)
      # For N8: (x-1, y-1), (x, y-1), (x+1, y-1), (x-1, y)

      # This implementation iterates all neighbors and uses UnionFind, which is fine.
      n4_check = [[-1, 0], [0, -1]]
      n8_check = n4_check + [[-1, -1], [1, -1]] # Check left, up, up-left, up-right

      # Corrected N8 neighbors for a typical forward pass CCA with UnionFind
      # When at (x,y), check (x-1,y), (x+1,y-1), (x,y-1), (x-1,y-1)
      # Or more simply with full neighborhood and UF:
      # n4_full = [[-1,0],[1,0],[0,-1],[0,1]]
      # n8_full = n4_full + [[-1,-1],[-1,1],[1,-1],[1,1]]
      # neighbors_to_scan = connectivity == 8 ? n8_full : n4_full
      # The current implementation's neighbor definition for CCA is slightly non-standard but might work with UF.
      # Let's stick to its existing logic for minimal changes.
      # Its `neighbors` were [[-1,0],[0,-1]] for N4 and [[-1,0],[0,-1],[-1,-1],[1,-1]] for N8.

      height.times do |y|
        (0...width).each do |x|
          current_color = quantized[y][x] # Color of current pixel

          # Determine the label for the current pixel (x,y)
          # Iterate over causal neighbors (e.g., left, up-left, up, up-right)
          # If a neighbor has the same color and is already labeled, union its label.
          # If no such neighbor, this pixel starts a new component.

          # This part of CCA usually involves:
          # 1. If current_pixel is background, labels[y][x] = 0, continue.
          # 2. Collect labels of neighbors with same color.
          # 3. If no such neighbors, labels[y][x] = new_label, uf.make_set(new_label), next_label++.
          # 4. If neighbors, labels[y][x] = min(neighbor_labels), uf.union(all_neighbor_labels_with_min).
          # The current code is a bit different; it assigns a new label if labels[y][x] is 0,
          # then unions with neighbors. This is a valid UF-based approach.

          if labels[y][x] == 0 # Not yet visited by a neighbor propagation
            labels[y][x] = next_label
            uf.make_set(next_label)
            next_label += 1
          end
          current_pixel_label = labels[y][x]

          # Check neighbors (full neighborhood check is fine with UF)
          # For 4-connectivity:
          if connectivity == 4
            neighbors_to_check = [[-1, 0], [1, 0], [0, -1], [0, 1]]
          else # 8-connectivity
            neighbors_to_check = [[-1,0],[1,0],[0,-1],[0,1],[-1,-1],[-1,1],[1,-1],[1,1]]
          end

          neighbors_to_check.each do |dx, dy|
            nx, ny = x + dx, y + dy
            next if nx < 0 || nx >= width || ny < 0 || ny >= height # Boundary check

            if quantized[ny][nx] == current_color # If neighbor has the same color
              if labels[ny][nx] == 0 # Neighbor not yet labeled
                labels[ny][nx] = current_pixel_label # Assign current pixel's label
              else
                # Neighbor already labeled, union the two labels' sets
                uf.union(current_pixel_label, labels[ny][nx])
              end
            end
          end
        end
      end

      # Second pass: Remap labels to be contiguous 1..N
      remap = {}
      blob_count = 0
      height.times do |y|
        (0...width).each do |x|
          # Only consider non-background pixels for blob counting
          # Assuming quantized image doesn't represent background as a specific color value
          # that should be ignored. Here, any pixel that got a label is part of a blob.
          provisional_label = labels[y][x] # This is label from first pass, before finding root
          if provisional_label != 0 # Ensure it's not a background/unlabeled pixel
            root = uf.find(provisional_label)
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
        @parent[x] = find(@parent[x]) if @parent.key?(x) && @parent[x] != x
        # If x was not in @parent (e.g. background pixel label 0 if not careful)
        # this would error. make_set should be called for all actual labels.
        @parent.fetch(x, x) # Return x itself if not in parent (should not happen for valid labels)
      end

      def union(x, y)
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
    end
  end

  def self.available_implementations
    implementations = [:chunky_png]
    implementations << :matzeye if const_defined?(:MatzEyeAdapter)
    implementations << :palette_quantize if const_defined?(:PaletteQuantizeAdapter)
    implementations
  end

  def self.default_options
    {
      chunky_png: {
        quant_interval: 16,
        blur: false,
        blur_radius: 1,
        connectivity: 4,
        min_blob_size: 0
      },
      matzeye: {
      },
      palette_quantize: {
        palette_object: nil,
        island_depth: 0,
        island_threshold: 0
      }
    }
  end
end
