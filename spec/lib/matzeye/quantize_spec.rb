require_relative '../../../lib/matzeye'
require 'chunky_png' # For color constants

RSpec.describe MatzEye do
  # Helper to convert a simple ChunkyPNG image to pixel_array for tests
  def chunky_to_pixel_array(image)
    Array.new(image.height) do |y|
      Array.new(image.width) do |x|
        color = image[x,y]
        [ChunkyPNG::Color.r(color), ChunkyPNG::Color.g(color), ChunkyPNG::Color.b(color), ChunkyPNG::Color.a(color)]
      end
    end
  end

  describe '.quantize_colors' do
    it 'quantizes colors correctly with a given interval' do
      # Input: 1x1 image, pixel [35, 67, 99, 128]
      pixel_array_input = [[[35, 67, 99, 128]]]
      width = 1
      height = 1
      # Interval 32:
      # R: (35/32)*32 = 1*32 = 32
      # G: (67/32)*32 = 2*32 = 64
      # B: (99/32)*32 = 3*32 = 96
      # A: 128 (preserved)
      quantized_array = MatzEye.quantize_colors(pixel_array_input, width, height, 32)
      expect(quantized_array[0][0]).to eq([32, 64, 96, 128])
    end

    it 'quantizes with interval 64' do
      pixel_array_input = [[[35, 67, 99, 255]]] # Alpha 255 (opaque)
      width = 1
      height = 1
      # Interval 64:
      # R: (35/64)*64 = 0*64 = 0
      # G: (67/64)*64 = 1*64 = 64
      # B: (99/64)*64 = 1*64 = 64
      # A: 255 (preserved)
      quantized_array = MatzEye.quantize_colors(pixel_array_input, width, height, 64)
      expect(quantized_array[0][0]).to eq([0, 64, 64, 255])
    end

    it 'quantizes with interval 1 (no change to RGB, alpha preserved)' do
      pixel_array_input = [[[35, 67, 99, 200]]]
      width = 1
      height = 1
      quantized_array = MatzEye.quantize_colors(pixel_array_input, width, height, 1)
      expect(quantized_array[0][0]).to eq([35, 67, 99, 200])
    end

    it 'raises an error if interval is less than 1' do
      pixel_array_input = [[[35, 67, 99, 200]]]
      width = 1
      height = 1
      expect { MatzEye.quantize_colors(pixel_array_input, width, height, 0) }.to raise_error(ArgumentError)
      expect { MatzEye.quantize_colors(pixel_array_input, width, height, -1) }.to raise_error(ArgumentError)
    end
  end
end
