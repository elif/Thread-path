require 'chunky_png'
require 'fileutils'

# 1. Define target directory
fixtures_dir = File.expand_path('spec/fixtures', Dir.pwd)
puts "Fixtures directory: #{fixtures_dir}"

# 2. Ensure this directory exists
FileUtils.mkdir_p(fixtures_dir)
puts "Ensured fixtures directory exists."

# Helper function to fill a rectangular area
def fill_rect(image, x1, y1, x2, y2, color)
  (y1..y2).each do |y|
    (x1..x2).each do |x|
      image[x, y] = color if x < image.width && y < image.height # Boundary check
    end
  end
end

# 3. Generate fixture_distinct_colors.png (250x50 pixels)
distinct_colors_png = ChunkyPNG::Image.new(250, 50, ChunkyPNG::Color::WHITE)
colors_distinct = [
  ChunkyPNG::Color.rgb(255, 0, 0),   # Red
  ChunkyPNG::Color.rgb(0, 255, 0),   # Green
  ChunkyPNG::Color.rgb(0, 0, 255),   # Blue
  ChunkyPNG::Color.rgb(255, 255, 0), # Yellow
  ChunkyPNG::Color.rgb(255, 0, 255)  # Magenta
]
block_width = 50
colors_distinct.each_with_index do |color, i|
  fill_rect(distinct_colors_png, i * block_width, 0, (i + 1) * block_width - 1, 49, color)
end
path_distinct = File.join(fixtures_dir, 'fixture_distinct_colors.png')
distinct_colors_png.save(path_distinct)
puts "Generated: #{path_distinct}"

# 4. Generate fixture_similar_hues.png (250x50 pixels)
similar_hues_png = ChunkyPNG::Image.new(250, 50, ChunkyPNG::Color::WHITE)
colors_similar = [
  ChunkyPNG::Color.rgb(0, 0, 100),    # Dark Blue
  ChunkyPNG::Color.rgb(0, 0, 180),    # Medium Blue
  ChunkyPNG::Color.rgb(100, 100, 255),# Light Blue
  ChunkyPNG::Color.rgb(0, 100, 0),    # Dark Green
  ChunkyPNG::Color.rgb(0, 180, 0)     # Medium Green
]
colors_similar.each_with_index do |color, i|
  fill_rect(similar_hues_png, i * block_width, 0, (i + 1) * block_width - 1, 49, color)
end
path_similar = File.join(fixtures_dir, 'fixture_similar_hues.png')
similar_hues_png.save(path_similar)
puts "Generated: #{path_similar}"

# 5. Generate fixture_many_colors.png (200x50 pixels)
# Using 10 distinct colors
many_colors_png = ChunkyPNG::Image.new(200, 50, ChunkyPNG::Color::WHITE)
ten_colors = [
  ChunkyPNG::Color.rgb(255,0,0),   # Red
  ChunkyPNG::Color.rgb(0,255,0),   # Green
  ChunkyPNG::Color.rgb(0,0,255),   # Blue
  ChunkyPNG::Color.rgb(255,255,0), # Yellow
  ChunkyPNG::Color.rgb(0,255,255), # Cyan
  ChunkyPNG::Color.rgb(255,0,255), # Magenta
  ChunkyPNG::Color.rgb(128,0,0),   # Maroon
  ChunkyPNG::Color.rgb(0,128,0),   # Dark Green
  ChunkyPNG::Color.rgb(0,0,128),   # Navy
  ChunkyPNG::Color.rgb(128,128,128) # Gray
]
small_block_width = 20
ten_colors.each_with_index do |color, i|
  fill_rect(many_colors_png, i * small_block_width, 0, (i + 1) * small_block_width - 1, 49, color)
end
path_many = File.join(fixtures_dir, 'fixture_many_colors.png')
many_colors_png.save(path_many)
puts "Generated: #{path_many}"

# 6. Generate fixture_gradient_and_spots.png (200x100 pixels)
gradient_spots_png = ChunkyPNG::Image.new(200, 100, ChunkyPNG::Color::WHITE)
# Background: Horizontal grayscale gradient
(0...gradient_spots_png.width).each do |x|
  gray_value = 200 - (150 * x / (gradient_spots_png.width - 1.0)).round # from 200 down to 50
  color = ChunkyPNG::Color.rgb(gray_value, gray_value, gray_value)
  (0...gradient_spots_png.height).each do |y|
    gradient_spots_png[x,y] = color
  end
end
# Spots
spot_color_red = ChunkyPNG::Color.rgb(220, 50, 50)
spot_color_blue = ChunkyPNG::Color.rgb(50, 50, 220)
spot_size = 10

# Red spot at (30,30)
fill_rect(gradient_spots_png, 30, 30, 30 + spot_size - 1, 30 + spot_size - 1, spot_color_red)
# Blue spot at (160,60)
fill_rect(gradient_spots_png, 160, 60, 160 + spot_size - 1, 60 + spot_size - 1, spot_color_blue)

path_gradient_spots = File.join(fixtures_dir, 'fixture_gradient_and_spots.png')
gradient_spots_png.save(path_gradient_spots)
puts "Generated: #{path_gradient_spots}"

puts "All fixture images generated successfully."
