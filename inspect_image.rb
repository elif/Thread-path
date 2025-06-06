require 'chunky_png'
begin
  image = ChunkyPNG::Image.from_file('spec/fixtures/fixture_distinct_colors.png')
  puts "Dimensions: #{image.width}x#{image.height}"

  if !image.palette.empty?
    puts "Color mode: Indexed (Paletted) - ChunkyPNG converts to RGBA pixels"
    # For paletted images, ChunkyPNG reads the palette and constructs full RGBA pixels.
    # The effective bit depth of these pixels is typically 24 (RGB) or 32 (RGBA).
  elsif image.pixels.all? { |p| ChunkyPNG::Color.grayscale?(p) }
    # This checks if all pixels are grayscale.
    # ChunkyPNG represents grayscale pixels also as full RGBA values (e.g., R=G=B).
    puts "Color mode: Grayscale (represented as RGBA by ChunkyPNG)"
  else
    # If not paletted and not purely grayscale, it's treated as RGB or RGBA.
    # ChunkyPNG pixels are integers representing combined RGBA values.
    puts "Color mode: Truecolor (RGB/RGBA)"
  end

  has_alpha = image.pixels.any? { |p| ChunkyPNG::Color.a(p) != 255 && p != ChunkyPNG::Color::TRANSPARENT } # Check for non-opaque pixels, excluding fully transparent black if it's special
  puts "Has alpha channel (excluding fully transparent black as background): #{has_alpha}"

  all_transparent_black = image.pixels.all? { |p| p == ChunkyPNG::Color::TRANSPARENT }
  puts "Is image entirely transparent black: #{all_transparent_black}"

  opaque_pixels = image.pixels.reject { |p| ChunkyPNG::Color.a(p) == 0 }
  if opaque_pixels.empty?
    puts "Image has no opaque pixels."
  else
    # Count unique colors among opaque pixels
    # Taking a sample if image is too large to avoid performance issues.
    sample_size = 10000
    pixel_sample = opaque_pixels.length > sample_size ? opaque_pixels.sample(sample_size) : opaque_pixels
    unique_colors = pixel_sample.uniq.length
    puts "Unique opaque colors in sample (#{pixel_sample.length} pixels): #{unique_colors}"

    if !image.palette.empty?
      puts "Palette size: #{image.palette.size}"
      unique_palette_colors = image.palette.uniq.length
      puts "Unique colors in palette: #{unique_palette_colors}"
    else
      puts "No palette."
    end
  end

  metadata = image.metadata
  if metadata.any?
    puts "Metadata:"
    metadata.each { |k,v| puts "  #{k}: #{v}"}
  else
    puts "No metadata."
  end
rescue ChunkyPNG::SignatureMismatch
  puts "Error: Not a valid PNG file (signature mismatch)."
rescue ChunkyPNG::NotSupported => e
  puts "Error: PNG format feature not supported by ChunkyPNG - #{e.message}"
rescue StandardError => e
  puts "Error loading or inspecting image: #{e.class.name} - #{e.message}"
  puts e.backtrace.join("\n  ") if e.backtrace
end
