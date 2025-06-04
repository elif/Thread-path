# No require 'cv' or 'opencv' here, as this module will use pure Ruby.
# The placeholder/conditional loading logic is removed.

module Impressionist
  module MatzEye
    # Simple UnionFind implementation for CCL
    class UnionFind
      def initialize
        @parent = {}
        @rank = {} # For union by rank/size optimization
      end

      def make_set(item)
        unless @parent.key?(item)
          @parent[item] = item
          @rank[item] = 0
        end
      end

      def find(item)
        # Path compression
        if @parent[item] != item
          @parent[item] = find(@parent[item])
        end
        @parent[item]
      end

      def union(item1, item2)
        root1 = find(item1)
        root2 = find(item2)

        return if root1 == root2 # Already in the same set

        # Union by rank
        if @rank[root1] < @rank[root2]
          @parent[root1] = root2
        elsif @rank[root1] > @rank[root2]
          @parent[root2] = root1
        else
          @parent[root2] = root1
          @rank[root1] += 1
        end
      end
    end # End UnionFind

    class << self
      def quantize_image(image, interval)
        raise ArgumentError, "Interval must be >= 1" if interval < 1
        width = image.width
        height = image.height
        output_image = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::TRANSPARENT)

        (0...height).each do |y|
          (0...width).each do |x|
            pixel = image[x,y]
            r = ChunkyPNG::Color.r(pixel)
            g = ChunkyPNG::Color.g(pixel)
            b = ChunkyPNG::Color.b(pixel)
            a = ChunkyPNG::Color.a(pixel)

            quant_r = (r / interval) * interval
            quant_g = (g / interval) * interval
            quant_b = (b / interval) * interval

            output_image[x,y] = ChunkyPNG::Color.rgba(quant_r, quant_g, quant_b, a)
          end
        end
        output_image
      end

      def box_blur(image, radius)
        radius = 1 if radius < 1 # Ensure radius is at least 1
        width = image.width
        height = image.height
        output_image = ChunkyPNG::Image.new(width, height)

        (0...height).each do |y|
          (0...width).each do |x|
            r_sum, g_sum, b_sum = 0, 0, 0
            pixel_count = 0

            y_start = [0, y - radius].max
            y_end = [height - 1, y + radius].min
            x_start = [0, x - radius].max
            x_end = [width - 1, x + radius].min

            (y_start..y_end).each do |ky|
              (x_start..x_end).each do |kx|
                pixel_value = image[kx, ky]
                r_sum += ChunkyPNG::Color.r(pixel_value)
                g_sum += ChunkyPNG::Color.g(pixel_value)
                b_sum += ChunkyPNG::Color.b(pixel_value)
                pixel_count += 1
              end
            end

            avg_r = (r_sum / pixel_count.to_f).round
            avg_g = (g_sum / pixel_count.to_f).round
            avg_b = (b_sum / pixel_count.to_f).round
            output_image[x,y] = ChunkyPNG::Color.rgb(avg_r, avg_g, avg_b)
          end
        end
        output_image
      end

      def process_image(chunky_png_image, options)
        width = chunky_png_image.width
        height = chunky_png_image.height

        # Apply blur if specified
        image_to_process = if options[:blur]
                             blur_radius = (options[:blur_radius] || 1).to_i
                             self.box_blur(chunky_png_image, blur_radius)
                           else
                             chunky_png_image.dup # Work on a copy
                           end

        # For now, other steps (quantization, CCL, etc.) are not implemented.
        # Apply blur if specified
        image_after_blur = if options[:blur]
                             blur_radius = (options[:blur_radius] || 1).to_i
                             self.box_blur(chunky_png_image, blur_radius)
                           else
                             chunky_png_image.dup # Work on a copy
                           end

        # Apply quantization
        quant_interval = (options[:quant_interval] || 16).to_i
        quant_interval = 1 if quant_interval < 1 # Ensure interval is at least 1
        quantized_image_obj = self.quantize_image(image_after_blur, quant_interval)

        # Apply blur if specified
        image_after_blur = if options[:blur]
                             blur_radius = (options[:blur_radius] || 1).to_i
                             self.box_blur(chunky_png_image, blur_radius)
                           else
                             chunky_png_image.dup # Work on a copy
                           end

        # Apply quantization
        quant_interval = (options[:quant_interval] || 16).to_i
        quant_interval = 1 if quant_interval < 1 # Ensure interval is at least 1
        quantized_image_obj = self.quantize_image(image_after_blur, quant_interval)

        # Prepare data for CCL
        quant_data_for_ccl = Array.new(height) { Array.new(width) }
        (0...height).each do |y|
          (0...width).each do |x|
            pixel = quantized_image_obj[x,y]
            r = ChunkyPNG::Color.r(pixel)
            g = ChunkyPNG::Color.g(pixel)
            b = ChunkyPNG::Color.b(pixel)
            # Assuming 0 might be a valid packed color if all r,g,b are 0.
            # The original code's CCL in BlobGraph ignored label 0 as background.
            # Here, the packed color 0 (black) is a valid color to be part of a blob.
            quant_data_for_ccl[y][x] = (r << 16) | (g << 8) | b
          end
        end

        connectivity = (options[:connectivity] || 4).to_i
        connectivity = 4 unless [4,8].include?(connectivity) # Default to 4 if invalid

        labels_array, actual_blob_count = self.perform_ccl(quant_data_for_ccl, width, height, connectivity)

        # For now, other steps (min_blob_size, averaging, etc.) are not implemented for MatzEye.
        # Return the quantized image, and the new labels/blob_count.
        {
          image: quantized_image_obj,
          labels: labels_array,
          blob_count: actual_blob_count
        }
      end # def process_image

      def perform_ccl(quantized_pixel_data, width, height, connectivity)
        labels = Array.new(height) { Array.new(width, 0) }
        uf = UnionFind.new
        next_label = 1

        # Define neighbor offsets based on connectivity for the first pass
        # For 4-connectivity: North (y-1, x), West (y, x-1)
        # For 8-connectivity: North (y-1, x), North-West (y-1, x-1), West (y, x-1), North-East (y-1, x+1)
        # These are chosen to only check pixels that would have already been processed in a raster scan.
        neighbors_def = if connectivity == 8
                          [[-1,0], [-1,-1], [0,-1], [-1,1]] # N, NW, W, NE
                        else # 4-connectivity (default)
                          [[-1,0], [0,-1]] # N, W
                        end

        # First pass: Assign initial labels and record equivalences
        (0...height).each do |y|
          (0...width).each do |x|
            current_color = quantized_pixel_data[y][x]
            # If 0 is used as a background marker in quantized_pixel_data, skip it.
            # The tests use 0 as background.
            next if current_color == 0

            neighbor_labels_of_same_color = []
            neighbors_def.each do |dy, dx|
              ny, nx = y + dy, x + dx
              next if ny < 0 || ny >= height || nx < 0 || nx >= width # Boundary check

              if quantized_pixel_data[ny][nx] == current_color && labels[ny][nx] != 0
                neighbor_labels_of_same_color << labels[ny][nx]
              end
            end

            if neighbor_labels_of_same_color.empty?
              # New component
              labels[y][x] = next_label
              uf.make_set(next_label)
              next_label += 1
            else
              # Smallest neighbor label found so far for this pixel
              min_label = neighbor_labels_of_same_color.min
              labels[y][x] = min_label
              # Union all found neighbor labels (that share the current_color) with this min_label
              neighbor_labels_of_same_color.each { |label| uf.union(min_label, label) }
            end
          end
        end

        # Second pass: Resolve equivalences and remap labels to be contiguous
        remap = {}
        blob_count = 0
        (0...height).each do |y|
          (0...width).each do |x|
            if labels[y][x] != 0 # If it's part of any blob
              root_label = uf.find(labels[y][x])
              unless remap.key?(root_label)
                blob_count += 1
                remap[root_label] = blob_count # Assign new contiguous label
              end
              labels[y][x] = remap[root_label]
            # Else, it remains 0 (background or uncolored)
            end
          end
        end
        [labels, blob_count]
      end # def perform_ccl

      def filter_and_relabel_blobs(labels_array, width, height, min_size)
        return [labels_array, 0] if labels_array.empty? || min_size <= 0 # No filtering or empty input

        blob_sizes = Hash.new(0)
        (0...height).each do |y|
          (0...width).each do |x|
            label = labels_array[y][x]
            blob_sizes[label] += 1 if label != 0
          end
        end

        small_blob_ids = Set.new
        blob_sizes.each do |label, size|
          small_blob_ids.add(label) if size < min_size
        end

        # Create new labels array, filtering out small blobs
        filtered_labels = Array.new(height) { Array.new(width, 0) }
        (0...height).each do |y|
          (0...width).each do |x|
            original_label = labels_array[y][x]
            unless original_label == 0 || small_blob_ids.include?(original_label)
              filtered_labels[y][x] = original_label # Keep it for now, relabel next
            end
          end
        end

        # Relabel remaining blobs to be contiguous
        # This is effectively another CCL pass on `filtered_labels` where pixel "color" is its current label
        # Or, more simply, map old valid labels to new ones.

        final_labels = Array.new(height) { Array.new(width, 0) }
        label_map = {}
        new_blob_count = 0

        (0...height).each do |y|
          (0...width).each do |x|
            current_filtered_label = filtered_labels[y][x]
            if current_filtered_label != 0
              unless label_map.key?(current_filtered_label)
                new_blob_count += 1
                label_map[current_filtered_label] = new_blob_count
              end
              final_labels[y][x] = label_map[current_filtered_label]
            end
          end
        end
        [final_labels, new_blob_count]
      end # def filter_and_relabel_blobs

      def calculate_average_colors(source_image, labels_array, width, height, blob_count)
        return {} if blob_count == 0

        blob_color_sums = Hash.new { |h, k| h[k] = {r: 0, g: 0, b: 0, count: 0} }

        (0...height).each do |y|
          (0...width).each do |x|
            label = labels_array[y][x]
            next if label == 0 # Skip background

            pixel = source_image[x,y] # Use original image for colors
            blob_color_sums[label][:r] += ChunkyPNG::Color.r(pixel)
            blob_color_sums[label][:g] += ChunkyPNG::Color.g(pixel)
            blob_color_sums[label][:b] += ChunkyPNG::Color.b(pixel)
            blob_color_sums[label][:count] += 1
          end
        end

        average_colors_map = {}
        (1..blob_count).each do |label| # Iterate through expected blob labels
          data = blob_color_sums[label]
          if data[:count] > 0
            avg_r = (data[:r] / data[:count].to_f).round
            avg_g = (data[:g] / data[:count].to_f).round
            avg_b = (data[:b] / data[:count].to_f).round
            average_colors_map[label] = [avg_r, avg_g, avg_b]
          else
            average_colors_map[label] = [0,0,0] # Default to black if blob has no pixels (should not happen if labels are correct)
          end
        end
        average_colors_map
      end # def calculate_average_colors

      def build_recolored_image(labels_array, average_colors_map, width, height)
        output_image = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::WHITE) # Default background white

        (0...height).each do |y|
          (0...width).each do |x|
            label_id = labels_array[y][x]
            if label_id > 0 && average_colors_map.key?(label_id)
              rgb_array = average_colors_map[label_id]
              output_image[x,y] = ChunkyPNG::Color.rgb(rgb_array[0], rgb_array[1], rgb_array[2])
            # else it remains background color (white)
            end
          end
        end
        output_image
      end # def build_recolored_image
    end # class << self
  end # module MatzEye
end # module Impressionist
