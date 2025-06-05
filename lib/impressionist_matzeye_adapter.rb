require_relative 'matzeye' # Corrected path
require 'chunky_png' # Ensure ChunkyPNG is available for this adapter

module Impressionist
  module MatzEyeAdapter # Renamed from MatzEye (which was previously OpenCV)
    class << self
      def process_image(chunky_png_image, options)
        width = chunky_png_image.width
        height = chunky_png_image.height

        # 1. Input Conversion: ChunkyPNG::Image to pixel_array [R,G,B,A]
        pixel_array_initial = Array.new(height) { Array.new(width) }
        (0...height).each do |y|
          (0...width).each do |x|
            color = chunky_png_image[x,y]
            pixel_array_initial[y][x] = [
              ChunkyPNG::Color.r(color),
              ChunkyPNG::Color.g(color),
              ChunkyPNG::Color.b(color),
              ChunkyPNG::Color.a(color)
            ]
          end
        end

        # 2. Call MatzEye Library for Processing Steps

        # Determine image to use for color averaging (before quantization)
        # If blur is applied, color averaging should use the blurred image's pixels.
        # Otherwise, it uses the original pixels.
        # The MatzEye.calculate_blob_average_colors expects original_pixel_array as its first argument.
        # This should be the state of the image *before* quantization.

        pixel_array_for_processing = pixel_array_initial
        pixel_array_for_color_avg = pixel_array_initial # Default to original

        if options[:blur]
          blur_radius = (options[:blur_radius] || 1).to_i
          blur_radius = 1 if blur_radius < 1
          # MatzEye.box_blur expects [R,G,B,A] and returns [R,G,B,A]
          pixel_array_for_processing = ::MatzEye.box_blur(pixel_array_initial, width, height, blur_radius)
          pixel_array_for_color_avg = pixel_array_for_processing # Use blurred for averaging if blur happened
        end

        quant_interval = (options[:quant_interval] || 16).to_i
        quant_interval = 1 if quant_interval < 1
        # MatzEye.quantize_colors expects [R,G,B,A] and returns [R,G,B,A]
        pixel_array_quantized_rgba = ::MatzEye.quantize_colors(pixel_array_for_processing, width, height, quant_interval)

        # Prepare data for CCL (packed RGB integers)
        quant_data_for_ccl = Array.new(height) { Array.new(width) }
        (0...height).each do |y|
          (0...width).each do |x|
            rgba_pixel = pixel_array_quantized_rgba[y][x]
            # Pack RGB, ignore A for CCL key if needed, or ensure MatzEye.connected_components handles it
            quant_data_for_ccl[y][x] = (rgba_pixel[0] << 16) | (rgba_pixel[1] << 8) | rgba_pixel[2]
          end
        end

        connectivity = (options[:connectivity] || 4).to_i
        connectivity = 4 unless [4,8].include?(connectivity)

        ccl_labels_array, ccl_blob_count = ::MatzEye.connected_components(quant_data_for_ccl, width, height, connectivity)

        min_blob_size_opt = (options[:min_blob_size] || 0).to_i
        min_blob_size_opt = 0 if min_blob_size_opt < 0

        current_labels, current_blob_count = if min_blob_size_opt > 0 && ccl_blob_count > 0
                                               ::MatzEye.filter_blobs_by_size(ccl_labels_array, width, height, min_blob_size_opt)
                                             else
                                               [ccl_labels_array, ccl_blob_count]
                                             end

        avg_colors_map = if current_blob_count > 0
                           # Use pixel_array_for_color_avg (post-blur, pre-quant) for color averaging
                           ::MatzEye.calculate_blob_average_colors(pixel_array_for_color_avg, width, height, current_labels, current_blob_count)
                         else
                           {}
                         end

        # MatzEye.build_image_from_labels expects avg_colors_map with [R,G,B,A] values
        # Our current calculate_blob_average_colors returns [R,G,B,A]
        final_pixel_array_rgba = ::MatzEye.build_image_from_labels(current_labels, width, height, avg_colors_map)

        # 3. Output Conversion: pixel_array [R,G,B,A] to ChunkyPNG::Image
        final_chunky_png_image = ChunkyPNG::Image.new(width, height)
        (0...height).each do |y|
          (0...width).each do |x|
            rgba_pixel = final_pixel_array_rgba[y][x]
            final_chunky_png_image[x,y] = ChunkyPNG::Color.rgba(rgba_pixel[0], rgba_pixel[1], rgba_pixel[2], rgba_pixel[3])
          end
        end

        # 4. Return
        {
          image: final_chunky_png_image,
          labels: current_labels,
          blob_count: current_blob_count
        }
      end # def process_image
    end # class << self
  end # module MatzEyeAdapter
end # module Impressionist
