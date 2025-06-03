# lib/impressionist.rb
#
# A pure-Ruby library for “impressionist” blob detection and recoloring of PNG images,
# now with enhanced control over blob size and noise.
#
# Features:
#   • Optional box-blur to reduce noise.
#   • Fixed-interval color quantization.
#   • Two-pass connected-component labeling (4- or 8-connectivity).
#   • Optional filtering of small blobs (min_blob_size).
#   • Computes average RGB per blob and recolors entire blob to its average hue.
#   • Clean API: load, process, and save.
#
# Dependencies:
#   gem install chunky_png
#
# Usage Example:
#   require_relative 'lib/impressionist'
#
#   options = {
#     quant_interval: 16,   # Interval for uniform quantization (default: 16)
#     blur:           true, # Whether to apply box-blur before quantization
#     blur_radius:    1,    # Radius for box-blur (default: 1)
#     connectivity:   4,    # Pixel adjacency: 4 or 8 (default: 4)
#     min_blob_size:  50    # Merge any blob smaller than 50 pixels into nearest large neighbor
#   }
#
#   # Recolor input.png → output.png
#   Impressionist.recolor('input.png', 'output.png', options)
#
#   # Or get a ChunkyPNG::Image back instead of saving directly:
#   img = Impressionist.process('input.png', options)
#   img.save('out.png')
#

require 'chunky_png'
require 'set' # Added for Set operations

module Impressionist
  VERSION = '1.1.0'

  class << self
    # Public API: Load a PNG, perform impressionist recoloring, and save to output_path.
    #
    # input_path  - String path to input PNG file.
    # output_path - String path to write recolored PNG.
    # options     - Hash of optional settings:
    #               :quant_interval (Integer, default: 16)
    #               :blur           (Boolean, default: false)
    #               :blur_radius    (Integer, default: 1)
    #               :connectivity   (Integer: 4 or 8, default: 4)
    #               :min_blob_size  (Integer, default: 0)
    #
    # Returns: true if saved successfully.
    def recolor(input_path, output_path, options = {})
      img = load_image(input_path)
      recolored = process_image(img, options)
      save_image(recolored, output_path)
      true
    end

    # Public API: Load a PNG, perform impressionist recoloring, and return a ChunkyPNG::Image.
    #
    # input_path - String path to input PNG file.
    # options    - Same as recolor.
    #
    # Returns: ChunkyPNG::Image (recolored).
    def process(input_path, options = {})
      img = load_image(input_path)
      process_image(img, options)
    end

    # Making these methods public for app.rb direct use (indicated by .send usage)
    public

    # Internal: Load a PNG from disk into a ChunkyPNG::Image.
    def load_image(path)
      raise ArgumentError, "File not found: #{path}" unless File.exist?(path)
      ChunkyPNG::Image.from_file(path)
    end

    # Internal: Save a ChunkyPNG::Image to disk.
    def save_image(img, path)
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir) # Ensure FileUtils is available or require it
      img.save(path)
    end

    # Core processing: given a ChunkyPNG::Image and options, produce a new recolored image.
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

      # Step 1: (Optional) Box-blur to remove single-pixel noise
      work_img = img
      if do_blur
        work_img = box_blur(img, blur_radius)
      end

      # Step 2: Uniform color quantization → 2D array of “flat_color” integers
      quantized = Array.new(height) { Array.new(width, 0) }
      height.times do |y|
        (0...width).each do |x|
          pixel = work_img[x, y]
          r = ChunkyPNG::Color.r(pixel)
          g = ChunkyPNG::Color.g(pixel)
          b = ChunkyPNG::Color.b(pixel)
          rq = (r / quant_interval) * quant_interval
          gq = (g / quant_interval) * quant_interval
          bq = (b / quant_interval) * quant_interval
          quantized[y][x] = (rq << 16) | (gq << 8) | bq
        end
      end

      # Step 3: Two-pass connected-component labeling on quantized[][]
      labels, blob_count = connected_components(quantized, width, height, connectivity)

      # Step 4: Compute blob sizes and identify small blobs
      if min_blob_size > 0 # Only do this work if necessary
        blob_sizes = Array.new(blob_count + 1, 0)
        height.times do |y|
          (0...width).each do |x|
            bid = labels[y][x]
            blob_sizes[bid] += 1 if bid > 0 # Ensure bid is valid
          end
        end
        small_blobs = blob_sizes.each_index.select { |bid| bid != 0 && blob_sizes[bid] > 0 && blob_sizes[bid] < min_blob_size }.to_set
        unless small_blobs.empty?
          labels = merge_small_blobs(labels, quantized, width, height, small_blobs, connectivity)
          # After merging, recompute final blob IDs and sizes
          labels, blob_count = relabel_contiguous(labels, width, height)
        end
      end


      # Step 5: Compute sum & count of original colors per blob
      sums   = Array.new(blob_count + 1) { [0, 0, 0] }
      counts = Array.new(blob_count + 1, 0)

      height.times do |y|
        (0...width).each do |x|
          bid = labels[y][x]
          next if bid == 0 # Skip background/unlabeled pixels
          pixel = img[x, y] # Use original image for color averaging
          r = ChunkyPNG::Color.r(pixel)
          g = ChunkyPNG::Color.g(pixel)
          b = ChunkyPNG::Color.b(pixel)
          sums[bid][0] += r
          sums[bid][1] += g
          sums[bid][2] += b
          counts[bid] += 1
        end
      end

      # Step 6: Compute average color per blob
      avg_color = Array.new(blob_count + 1, ChunkyPNG::Color::TRANSPARENT) # Default for unassigned
      (1..blob_count).each do |bid|
        count = counts[bid]
        if count > 0
          r_avg = (sums[bid][0] / count.to_f).round
          g_avg = (sums[bid][1] / count.to_f).round
          b_avg = (sums[bid][2] / count.to_f).round
          avg_color[bid] = ChunkyPNG::Color.rgba(r_avg, g_avg, b_avg, 255)
        else
          # This case (bid > 0 but count == 0) should ideally not happen if labels are clean.
          # If it does, assign a default color (e.g., black or transparent)
          avg_color[bid] = ChunkyPNG::Color::BLACK # Or some other indicator
        end
      end

      # Step 7: Recolor entire image by blob average
      out_img = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::WHITE) # Default background
      height.times do |y|
        (0...width).each do |x|
          bid = labels[y][x]
          out_img[x, y] = avg_color[bid] # avg_color[0] is TRANSPARENT if bid is 0
        end
      end

      out_img
    end

    # Merge pixels of small blobs (in `small_blobs` set) into nearest large neighbor.
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
            nbid = labels[ny][nx] # Use original labels for neighbor check
            if nbid > 0 && !small_blobs.include?(nbid)
              neighbor_counts[nbid] += 1
            end
          end
          if neighbor_counts.any?
            best = neighbor_counts.max_by { |_, count| count }[0]
            new_labels[y][x] = best
          else
            new_labels[y][x] = 0 # Mark for potential background absorption
          end
        end
      end
      new_labels
    end

    # After merging small blobs, relabel contiguously.
    def relabel_contiguous(labels, width, height)
      # This relabeling assumes labels[y][x] == 0 are holes,
      # and non-zero values are parts of some (possibly disconnected) blob region.
      # It finds connected components of non-zero regions.
      final_labels = Array.new(height) { Array.new(width, 0) }
      uf = UnionFind.new
      next_label = 1

      # For relabeling, always use 4-connectivity to define "same region"
      # This is simpler and ensures that pixels that *should* be the same blob
      # (because they have the same label value from merge_small_blobs)
      # end up with the same final label.
      neigh = [[-1,0],[0,-1]] # Check up and left

      height.times do |y|
        (0...width).each do |x|
          current_original_label = labels[y][x]
          next if current_original_label == 0 # Skip background/holes

          # Assign a new provisional label if not yet seen in final_labels
          if final_labels[y][x] == 0
            final_labels[y][x] = next_label
            uf.make_set(next_label)
            next_label += 1
          end
          provisional_label = final_labels[y][x]

          neigh.each do |dx, dy|
            nx, ny = x + dx, y + dy
            next if nx < 0 || ny < 0 # Bounds check for up/left
            # Only union if the original labels were the same (meaning they are part of the same blob region)
            if labels[ny][nx] == current_original_label
              if final_labels[ny][nx] == 0 # Not yet provisionally labeled
                 final_labels[ny][nx] = provisional_label
              else # Already provisionally labeled, union their sets
                 uf.union(provisional_label, final_labels[ny][nx])
              end
            end
          end
        end
      end

      # Second pass: flatten and remap to contiguous final IDs
      remap = {}
      final_blob_count = 0
      height.times do |y|
        (0...width).each do |x|
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


    # Perform a simple box-blur on a ChunkyPNG::Image.
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
            yy_clamp = yy.clamp(0, height - 1) # Clamp coordinates to image bounds
            ((x - radius)..(x + radius)).each do |xx|
              xx_clamp = xx.clamp(0, width - 1) # Clamp coordinates to image bounds
              pix = img[xx_clamp, yy_clamp]
              r_sum += ChunkyPNG::Color.r(pix)
              g_sum += ChunkyPNG::Color.g(pix)
              b_sum += ChunkyPNG::Color.b(pix)
              count += 1
            end
          end
          out[x, y] = ChunkyPNG::Color.rgba((r_sum / count.to_f).round, # Use .to_f for division
                                            (g_sum / count.to_f).round,
                                            (b_sum / count.to_f).round,
                                            ChunkyPNG::Color.a(img[x,y])) # Preserve original alpha
        end
      end
      out
    end

    # Two-pass connected-component labeling on quantized color map.
    def connected_components(quantized, width, height, connectivity)
      labels = Array.new(height) { Array.new(width, 0) }
      uf = UnionFind.new
      next_label = 1

      n4 = [[-1, 0], [0, -1]]
      n8 = n4 + [[-1, -1], [1, -1]] # Relative to current: (x-1,y), (x,y-1), (x-1,y-1), (x+1,y-1)
      neighbors = connectivity == 8 ? n8 : n4

      height.times do |y|
        (0...width).each do |x|
          # Labels[y][x] must be part of a component, so assign a new one if it's 0.
          if labels[y][x] == 0
            labels[y][x] = next_label
            uf.make_set(next_label)
            next_label += 1
          end
          current_label = labels[y][x]
          current_color = quantized[y][x]

          neighbors.each do |dx, dy|
            nx, ny = x + dx, y + dy
            next if nx < 0 || nx >= width || ny < 0 || ny >= height # Bounds check
            if quantized[ny][nx] == current_color # Same color region
              if labels[ny][nx] == 0 # Neighbor not yet labeled
                labels[ny][nx] = current_label
              else # Neighbor already labeled, union their sets
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
          # Find the root of the set this provisional label belongs to
          root = uf.find(provisional_label)
          # If this root hasn't been mapped to a final blob ID yet, assign one
          unless remap.key?(root)
            blob_count += 1
            remap[root] = blob_count
          end
          # Assign the final, contiguous blob ID
          labels[y][x] = remap[root]
        end
      end
      [labels, blob_count]
    end

    # Union-Find (Disjoint Set) implementation
    class UnionFind
      def initialize
        @parent = {}
        @rank = {} # For union by rank optimization
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

      def union(x, y)
        # Union by rank
        root_x = find(x)
        root_y = find(y)
        return if root_x == root_y # Already in the same set

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
