require_relative '../../../lib/matzeye'
# require 'chunky_png' # Not strictly needed as inputs/outputs are pixel_arrays

RSpec.describe MatzEye do
  describe '.build_image_from_labels' do
    it 'constructs the output pixel_array from labels and average colors' do
      labels = [
        [1, 1, 0],
        [0, 2, 2]
      ]
      # avg_colors_map stores [R,G,B,A]
      avg_colors = {
        1 => [255,0,0,255], # Red
        2 => [0,0,255,255]  # Blue
      }
      width = 3
      height = 2

      output_pixel_array = MatzEye.build_image_from_labels(labels, width, height, avg_colors)

      expect(output_pixel_array.size).to eq(height)
      expect(output_pixel_array[0].size).to eq(width)

      expect(output_pixel_array[0][0]).to eq([255,0,0,255]) # Red
      expect(output_pixel_array[0][1]).to eq([255,0,0,255]) # Red
      expect(output_pixel_array[0][2]).to eq([255,255,255,255]) # Background (White, Opaque)
      expect(output_pixel_array[1][0]).to eq([255,255,255,255]) # Background
      expect(output_pixel_array[1][1]).to eq([0,0,255,255])   # Blue
      expect(output_pixel_array[1][2]).to eq([0,0,255,255])   # Blue
    end

    it 'handles labels not present in average_colors_map by using background' do
      labels = [[1,2]] # Label 2 has no avg color defined
      avg_colors = { 1 => [100,100,100,255] }
      output_pixel_array = MatzEye.build_image_from_labels(labels, 2, 1, avg_colors)
      expect(output_pixel_array[0][0]).to eq([100,100,100,255])
      expect(output_pixel_array[0][1]).to eq([255,255,255,255]) # Background
    end

    it 'handles empty labels array' do
      output_pixel_array = MatzEye.build_image_from_labels([], 0, 0, {})
      expect(output_pixel_array).to be_empty
    end

    it 'handles labels array with only background' do
      labels = [[0,0],[0,0]]
      output_pixel_array = MatzEye.build_image_from_labels(labels, 2, 2, { 1 => [10,20,30,255]})
      expect(output_pixel_array[0][0]).to eq([255,255,255,255])
      expect(output_pixel_array[1][1]).to eq([255,255,255,255])
    end
  end
end
