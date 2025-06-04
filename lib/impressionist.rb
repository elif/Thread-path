require 'chunky_png'
require 'set'
require 'fileutils' # Added for FileUtils.mkdir_p

module Impressionist
  VERSION = '1.1.0'

  class << self
    def recolor(input_path, output_path, options = {})
      img_obj = load_image(input_path) # Renamed to avoid conflict with result[:image]
      result_hash = process_image(img_obj, options) # process_image now returns hash
      recolored_image = result_hash[:image]
      save_image(recolored_image, output_path)
      true
    end

    def process(input_path, options = {})
      img = load_image(input_path)
      process_image(img, options) # process_image returns hash, .process will now also return hash
    end

    def load_image(path)
      raise ArgumentError, "File not found: #{path}" unless File.exist?(path)
      ChunkyPNG::Image.from_file(path)
    end

    def save_image(img, path)
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      img.save(path)
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
        blob_sizes = Array.new(blob_count + 1, 0)
        height.times do |y|
          (0...width).each do |x|
            bid = labels[y][x]
            blob_sizes[bid] += 1 if bid > 0
          end
        end
        small_blobs = blob_sizes.each_index.select { |bid| bid != 0 && blob_sizes[bid] > 0 && blob_sizes[bid] < min_blob_size }.to_set

        unless small_blobs.empty?
          labels = merge_small_blobs(labels, quantized_image, width, height, small_blobs, connectivity)
          labels, blob_count = relabel_contiguous(labels, width, height)
        end
      end
      { labels: labels, blob_count: blob_count }
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
          out_img[x, y] = average_colors[bid]
        end
      end
      out_img
    end
def process_image(img, options = {})
  # Parse and normalize options
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

  avg_colors_map = _calculate_average_colors(img, labels, blob_count) # Use original img for color averaging

  output_image = _build_recolored_image(width, height, labels, avg_colors_map)

  { image: output_image, labels: labels, blob_count: blob_count }
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
      neigh = [[-1,0],[0,-1]]

      height.times do |y|
        (0...width).each do |x|
          current_original_label = labels[y][x]
          next if current_original_label == 0

          if final_labels[y][x] == 0
            final_labels[y][x] = next_label
            uf.make_set(next_label)
            next_label += 1
          end
          provisional_label = final_labels[y][x]

          neigh.each do |dx, dy|
            nx, ny = x + dx, y + dy
            next if nx < 0 || ny < 0
            if labels[ny][nx] == current_original_label
              if final_labels[ny][nx] == 0
                 final_labels[ny][nx] = provisional_label
              else
                 uf.union(provisional_label, final_labels[ny][nx])
              end
            end
          end
        end
      end

      remap = {}
      final_blob_count = 0
      height.times do |y|
        (0...width).each do |x|
          provisional_label = final_labels[y][x]
          next if provisional_label == 0
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

    private
    def box_blur(img, radius)
      width  = img.width
      height = img.height
      out = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::WHITE)
      radius = [1, radius.to_i].max

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
      next_label = 1

      n4 = [[-1, 0], [0, -1]]
      n8 = n4 + [[-1, -1], [1, -1]]
      neighbors = connectivity == 8 ? n8 : n4

      height.times do |y|
        (0...width).each do |x|
          if labels[y][x] == 0
            labels[y][x] = next_label
            uf.make_set(next_label)
            next_label += 1
          end
          current_label = labels[y][x]
          current_color = quantized[y][x]

          neighbors.each do |dx, dy|
            nx, ny = x + dx, y + dy
            next if nx < 0 || nx >= width || ny < 0 || ny >= height
            if quantized[ny][nx] == current_color
              if labels[ny][nx] == 0
                labels[ny][nx] = current_label
              else
                uf.union(current_label, labels[ny][nx])
              end
            end
          end
        end
      end

      remap = {}
      blob_count = 0
      height.times do |y|
        (0...width).each do |x|
          provisional_label = labels[y][x]
          root = uf.find(provisional_label)
          unless remap.key?(root)
            blob_count += 1
            remap[root] = blob_count
          end
          labels[y][x] = remap[root]
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
        @parent[x] = find(@parent[x]) if @parent[x] != x
        @parent[x]
      end

      def union(x, y)
        root_x = find(x)
        root_y = find(y)
        return if root_x == root_y

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
end
