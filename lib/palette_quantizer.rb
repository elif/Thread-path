require 'chunky_png' # For ChunkyPNG::Color utilities
require 'set'      # Useful for collections of unique items

module PaletteQuantizer
  # Calculate squared Euclidean distance between two ChunkyPNG::Color values
  def self.color_distance_squared(c1, c2)
    r1, g1, b1 = ChunkyPNG::Color.r(c1), ChunkyPNG::Color.g(c1), ChunkyPNG::Color.b(c1)
    r2, g2, b2 = ChunkyPNG::Color.r(c2), ChunkyPNG::Color.g(c2), ChunkyPNG::Color.b(c2)
    # Consider alpha if relevant, though typically quantization is on RGB
    # a1 = ChunkyPNG::Color.a(c1)
    # a2 = ChunkyPNG::Color.a(c2)
    # ((r1 - r2)**2) + ((g1 - g2)**2) + ((b1 - b2)**2) + ((a1 - a2)**2)
    ((r1 - r2)**2) + ((g1 - g2)**2) + ((b1 - b2)**2)
  end

  def self.quantize_to_palette(pixel_data, active_palette)
    # Handle edge cases as per passing tests
    return pixel_data if active_palette.nil? || active_palette.empty?
    return pixel_data if pixel_data.nil? || pixel_data.empty? || pixel_data[0].empty?

    pixel_data.map do |row|
      row.map do |pixel_color|
        # If the pixel_color is already in the active_palette, keep it.
        # This check is important if active_palette might not contain all possible pixel colors.
        # The placeholder in the spec used `active_palette.include?(pixel_color)`
        # However, min_by will correctly return the color itself if it's in the palette
        # because its distance to itself will be 0.
        # For clarity and to exactly match spec's placeholder behavior if needed:
        # next pixel_color if active_palette.include?(pixel_color) # This was in spec's placeholder

        active_palette.min_by { |palette_color| color_distance_squared(pixel_color, palette_color) }
      end
    end
  end

  # --- Island Removal Logic ---
  # Helper: Get valid neighbors of a pixel
  def self.get_neighbors(y, x, height, width, connectivity = 4) # Default to 4-connectivity
    neighbors = []
    potential = []

    # 4-connectivity (N, S, E, W)
    potential << [y - 1, x] if y > 0
    potential << [y + 1, x] if y < height - 1
    potential << [y, x - 1] if x > 0
    potential << [y, x + 1] if x < width - 1

    if connectivity == 8
      # 8-connectivity (includes diagonals)
      potential << [y - 1, x - 1] if y > 0 && x > 0
      potential << [y - 1, x + 1] if y > 0 && x < width - 1
      potential << [y + 1, x - 1] if y < height - 1 && x > 0
      potential << [y + 1, x + 1] if y < height - 1 && x < width - 1
    end
    # The previous version of get_neighbors was simpler and directly added valid ones.
    # This one is more explicit.
    potential.each do |ny, nx| # This was implicit in the previous version
        neighbors << [ny,nx] # if ny >= 0 && ny < height && nx >= 0 && nx < width (already handled by conditions)
    end
    neighbors
  end


  # Helper: Perform a BFS to find all pixels in a connected island of same color
  def self.find_island(start_y, start_x, pixel_data, visited_mask, target_color, height, width)
    island_pixels = []
    q = [[start_y, start_x]] # Queue for BFS

    # Check if already visited before marking (should not happen if called correctly)
    return island_pixels if visited_mask[start_y][start_x]

    visited_mask[start_y][start_x] = true

    head = 0
    while head < q.size # Efficient queue using array index
      curr_y, curr_x = q[head]
      head += 1

      island_pixels << [curr_y, curr_x]

      get_neighbors(curr_y, curr_x, height, width).each do |ny, nx|
        if !visited_mask[ny][nx] && pixel_data[ny][nx] == target_color
          visited_mask[ny][nx] = true
          q.push([ny, nx])
        end
      end
    end
    island_pixels
  end

  def self.remove_islands(input_pixel_data, island_depth, island_threshold, active_palette)
    return input_pixel_data if island_depth == 0 || island_threshold == 0
    return input_pixel_data if active_palette.nil? || active_palette.empty?
    return input_pixel_data if input_pixel_data.nil? || input_pixel_data.empty? || input_pixel_data[0].empty?

    height = input_pixel_data.size
    width = input_pixel_data[0].size

    # Make a mutable copy for processing. Use deep copy for rows.
    current_pixel_data = input_pixel_data.map(&:dup)

    island_depth.times do |_iteration|
      visited_mask = Array.new(height) { Array.new(width, false) }
      islands_changed_in_pass = false

      # Create a temporary structure to apply changes after full analysis of this pass
      # to avoid cascading changes within a single pass affecting later island analysis in same pass.
      next_pixel_data = current_pixel_data.map(&:dup)

      (0...height).each do |y|
        (0...width).each do |x|
          next if visited_mask[y][x] # Already processed as part of another island or visited

          target_color = current_pixel_data[y][x]
          # Find all connected pixels of the same color (the island)
          island_coords = find_island(y, x, current_pixel_data, visited_mask, target_color, height, width)

          next if island_coords.empty? # Should not happen if logic is correct

          # Check if island size is within threshold for removal
          if island_coords.size <= island_threshold
            neighbor_colors_count = Hash.new(0)

            # For each pixel in the island, find its neighbors that are NOT part of the island
            island_coords.each do |iy, ix|
              get_neighbors(iy, ix, height, width).each do |ny, nx|
                # Check if neighbor is outside the current island
                # This check is tricky: find_island already identified all island pixels.
                # So, if current_pixel_data[ny][nx] != target_color, it's an external neighbor.
                neighbor_color = current_pixel_data[ny][nx]
                if neighbor_color != target_color
                  neighbor_colors_count[neighbor_color] += 1
                end
              end
            end

            next if neighbor_colors_count.empty? # Island is isolated or surrounded by itself (shouldn't happen)

            # Select the most frequent_neighbor color that is in the active_palette
            best_replacement_color = nil
            max_freq = -1 # Start with -1 to ensure any valid color is chosen

            # Sort by frequency, then by color value (for stable results if frequencies tie)
            sorted_neighbors = neighbor_colors_count.sort_by { |color, count| [-count, color] }

            sorted_neighbors.each do |color, _count|
              if active_palette.include?(color)
                best_replacement_color = color
                break
              end
            end

            # If a valid replacement color is found, apply it to the island in next_pixel_data
            if best_replacement_color
              island_coords.each do |r_y, r_x|
                next_pixel_data[r_y][r_x] = best_replacement_color
              end
              islands_changed_in_pass = true
            end
          end
        end
      end # end of pass (y,x scan)

      current_pixel_data = next_pixel_data # Apply all changes from this pass
      break unless islands_changed_in_pass # If no islands were changed, further depth iterations won't help.
    end # end island_depth.times

    current_pixel_data
  end
end
