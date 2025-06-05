require_relative '../../../lib/matzeye'
require 'chunky_png' # For converting test images if needed, and for color constants

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

  # Helper to convert a pixel_array to a ChunkyPNG image for easy comparison or saving
  def pixel_array_to_chunky(pixel_array, width, height)
    image = ChunkyPNG::Image.new(width, height)
    (0...height).each do |y|
      (0...width).each do |x|
        pixel = pixel_array[y][x]
        image[x,y] = ChunkyPNG::Color.rgba(pixel[0], pixel[1], pixel[2], pixel[3])
      end
    end
    image
  end

  describe '.box_blur' do
    it 'correctly blurs a simple 3x3 image with radius 1' do
      img = ChunkyPNG::Image.new(3, 3, ChunkyPNG::Color::TRANSPARENT) # RGBA(0,0,0,0)
      img[1,1] = ChunkyPNG::Color.rgba(90,90,90,255)

      pixel_array_input = chunky_to_pixel_array(img)

      # Expected manual calculation for center pixel (1,1) with radius 1:
      # R,G,B sums: 90 (from center) + 0*8 (from transparent black neighbors) = 90
      # Alpha sum: 255 (from center) + 0*8 (from transparent neighbors) = 255
      # Count = 9
      # Avg R,G,B = 90/9 = 10. Avg A = 255/9 = 28 (rounded)
      #
      # For corner (0,0):
      # R,G,B sums: 90 (from (1,1)) = 90
      # Alpha sum: 255 (from (1,1)) = 255
      # Count = 4
      # Avg R,G,B = 90/4 = 22.5 -> 23. Avg A = 255/4 = 63.75 -> 64
      #
      # For edge (1,0):
      # R,G,B sums: 90 (from (1,1)) = 90
      # Alpha sum: 255 (from (1,1)) = 255
      # Count = 6
      # Avg R,G,B = 90/6 = 15. Avg A = 255/6 = 42.5 -> 43

      blurred_pixel_array = MatzEye.box_blur(pixel_array_input, 3, 3, 1)

      expect(blurred_pixel_array[0][0]).to eq([23,23,23,64])
      expect(blurred_pixel_array[1][0]).to eq([15,15,15,43])
      expect(blurred_pixel_array[0][1]).to eq([15,15,15,43])
      expect(blurred_pixel_array[1][1]).to eq([10,10,10,28])
    end

    it 'handles radius 0 (effectively radius 1)' do
      img = ChunkyPNG::Image.new(2,2, ChunkyPNG::Color.rgba(100,100,100,255))
      img[0,0] = ChunkyPNG::Color.rgba(0,0,0,255)
      pixel_array_input = chunky_to_pixel_array(img)

      # (0,0) with radius 1: R,G,B sum = 0*1 + 100*3 = 300. Alpha sum = 255*4 = 1020. Count = 4
      # Avg R,G,B = 300/4 = 75. Avg A = 1020/4 = 255.

      blurred_array_r0 = MatzEye.box_blur(pixel_array_input, 2, 2, 0)
      blurred_array_r1 = MatzEye.box_blur(pixel_array_input, 2, 2, 1)

      expect(blurred_array_r0[0][0]).to eq([75,75,75,255])
      expect(blurred_array_r0).to eq(blurred_array_r1)
    end

    it 'handles image smaller than radius correctly' do
      img = ChunkyPNG::Image.new(2,2)
      img[0,0] = ChunkyPNG::Color.rgba(0,0,0,100)
      img[0,1] = ChunkyPNG::Color.rgba(50,50,50,150)
      img[1,0] = ChunkyPNG::Color.rgba(100,100,100,200)
      img[1,1] = ChunkyPNG::Color.rgba(200,200,200,250)
      pixel_array_input = chunky_to_pixel_array(img)

      # Avg R = (0+50+100+200)/4 = 350/4 = 87.5 -> 88
      # Avg G = (0+50+100+200)/4 = 88
      # Avg B = (0+50+100+200)/4 = 88
      # Avg A = (100+150+200+250)/4 = 700/4 = 175
      expected_pixel = [88,88,88,175]

      blurred_array = MatzEye.box_blur(pixel_array_input, 2, 2, 5)
      expect(blurred_array[0][0]).to eq(expected_pixel)
      expect(blurred_array[0][1]).to eq(expected_pixel)
      expect(blurred_array[1][0]).to eq(expected_pixel)
      expect(blurred_array[1][1]).to eq(expected_pixel)
    end
  end
end
