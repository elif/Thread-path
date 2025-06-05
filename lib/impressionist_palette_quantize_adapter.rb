require 'chunky_png'
require_relative 'palette_manager'
require_relative 'palette_quantizer'

module Impressionist
  module PaletteQuantizeAdapter
    def self.process_image(chunky_png_image, options = {})
      # 1. Validate inputs (basic)
      unless chunky_png_image.is_a?(ChunkyPNG::Image)
        raise ArgumentError, "Input must be a ChunkyPNG::Image"
      end

      palette_manager = options[:palette_object]
      unless palette_manager.is_a?(PaletteManager)
        # Allow nil palette_object if defaults handle it, but spec passes an instance.
        # The main Impressionist class might set a default PaletteManager if nil.
        # For this adapter, if it's provided, it must be a PaletteManager.
        # If not provided, then active_palette below would be an issue.
        # The impressionist_spec.rb always provides a mock_palette for :palette_quantize tests.
        raise ArgumentError, "Options must include a valid :palette_object of type PaletteManager" if palette_manager.nil?
      end

      active_palette = palette_manager.active_palette
      # PaletteQuantizer.quantize_to_palette handles nil or empty active_palette by returning original data.
      # PaletteQuantizer.remove_islands also handles nil or empty active_palette.

      island_depth = options.fetch(:island_depth, 0).to_i
      island_threshold = options.fetch(:island_threshold, 0).to_i

      # 2. Convert ChunkyPNG::Image to pixel_data (array of arrays of colors)
      height = chunky_png_image.height
      width = chunky_png_image.width

      # Handle 0-width or 0-height images to prevent errors later
      if width == 0 || height == 0
        return {
          image: ChunkyPNG::Image.new(width, height), # Return empty image of correct dimensions
          labels: Array.new(height) { Array.new(width, 0) },
          blob_count: 0
        }
      end

      pixel_data = Array.new(height) { |y|
        Array.new(width) { |x| chunky_png_image[x, y] }
      }

      # 3. Call PaletteQuantizer.quantize_to_palette
      quantized_pixel_data = PaletteQuantizer.quantize_to_palette(pixel_data, active_palette)

      # 4. Call PaletteQuantizer.remove_islands
      # Ensure active_palette is not nil if island removal is to be effective
      # (PaletteQuantizer.remove_islands checks for empty active_palette)
      final_pixel_data = PaletteQuantizer.remove_islands(quantized_pixel_data, island_depth, island_threshold, active_palette || [])


      # 5. Convert processed pixel_data back to a new ChunkyPNG::Image
      output_image = ChunkyPNG::Image.new(width, height)
      final_pixel_data.each_with_index do |row, y|
        row.each_with_index do |color, x|
          output_image[x, y] = color
        end
      end

      # 6. Determine :labels and :blob_count
      final_unique_colors = final_pixel_data.flatten.uniq

      # Create a mapping from color value to a label index for the final image
      # Ensure consistent labeling: sort unique colors before assigning indices
      # (e.g., by their integer value) to make tests more predictable if needed.
      color_to_label_idx = final_unique_colors.sort.each_with_index.to_h

      labels_array = final_pixel_data.map do |row|
        row.map { |color| color_to_label_idx[color] || 0 }
      end

      blob_count = final_unique_colors.size

      {
        image: output_image,
        labels: labels_array,
        blob_count: blob_count
      }
    end
  end
end
