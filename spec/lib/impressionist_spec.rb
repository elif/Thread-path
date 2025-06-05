require 'spec_helper'
require 'chunky_png'
# require 'opencv' # Commented out as ruby-opencv is not installed
require 'impressionist' # Assuming lib is in $LOAD_PATH via spec_helper

# Helper to extend RSpec for describing implementations
module ImpressionistSpecHelpers
  def describe_implementations(implementations, &block)
    implementations.each do |impl|
      context "with #{impl} implementation" do
        instance_exec(impl, &block)
      end
    end
  end
end

RSpec.configure do |config|
  config.extend ImpressionistSpecHelpers
end

# Placeholder for PaletteManager if options require it
unless Object.const_defined?('PaletteManager')
  class ::PaletteManager
    attr_reader :active_palette
    def initialize(image_path = nil); @raw_palette = []; @active_palette = []; end
    # Simulate extraction for mock purposes
    def extract_palette_from_image(*args); @raw_palette = [ChunkyPNG::Color.rgb(255,0,0), ChunkyPNG::Color.rgb(0,0,255)]; @active_palette = @raw_palette.dup; end
    def add_to_active_palette(color); @active_palette << color unless @active_palette.include?(color); end
    def remove_from_active_palette(color); @active_palette.delete(color); end
    def clear_active_palette; @active_palette = []; end
    def activate_all_colors; @active_palette = @raw_palette.dup; end

  end
end

module Impressionist
  # Placeholder for PaletteQuantizeAdapter
  unless const_defined?('PaletteQuantizeAdapter')
    module PaletteQuantizeAdapter
      def self.process_image(image, options)
        # Mocked response for TDD
        processed_image = ChunkyPNG::Image.new(image.width, image.height, ChunkyPNG::Color::BLACK)
        mock_labels = Array.new(image.height) { Array.new(image.width, 0) }
        mock_blob_count = 0

        if options[:palette_object] && !options[:palette_object].active_palette.empty?
          # Simple mock: if red is in active palette, make first pixel red and count one blob.
          # This helps verify options are passed and have some effect.
          if options[:palette_object].active_palette.include?(ChunkyPNG::Color.rgb(255,0,0))
            processed_image[0,0] = ChunkyPNG::Color.rgb(255,0,0) if image.width > 0 && image.height > 0
            mock_labels[0][0] = 1 if image.height > 0 && image.width > 0
            mock_blob_count = 1 if image.height > 0 && image.width > 0
          end
        end
        { image: processed_image, labels: mock_labels, blob_count: mock_blob_count }
      end
    end
  end
end

RSpec.describe Impressionist do
  let(:fixture_dir) { File.expand_path('../../fixtures', __FILE__) }
  let(:input_path) { File.join(fixture_dir, 'test_image.png') }
  let(:output_dir) { File.expand_path('../../../tmp/test_output', __FILE__) }
  let(:output_path) { File.join(output_dir, 'output_impressionist.png') }

  before(:all) do
    fixture_png_path = File.join(File.expand_path('../../fixtures', __FILE__), 'test_image.png')
    unless File.exist?(fixture_png_path)
      FileUtils.mkdir_p(File.dirname(fixture_png_path))
      File.open(fixture_png_path, 'wb') do |f|
        f.write(Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII='))
      end
    end
    sample_png_path = File.join(File.expand_path('../../fixtures', __FILE__), 'sample_image.png')
    unless File.exist?(sample_png_path)
      FileUtils.mkdir_p(File.dirname(sample_png_path))
      img = ChunkyPNG::Image.new(5, 5, ChunkyPNG::Color::WHITE)
      img[0,0] = ChunkyPNG::Color::BLACK
      img[1,1] = ChunkyPNG::Color.rgb(10,20,30)
      img[2,2] = ChunkyPNG::Color.rgb(30,20,10)
      img[3,3] = ChunkyPNG::Color.rgb(50,50,50)
      img[4,4] = ChunkyPNG::Color.rgb(100,100,100)
      img[0,4] = ChunkyPNG::Color.rgb(0,0,255)
      img.save(sample_png_path)
    end
  end

  before(:each) do
    FileUtils.mkdir_p(output_dir)
    FileUtils.rm_f(output_path)
  end

  after(:all) do
    FileUtils.rm_rf(File.expand_path('../../../tmp', __FILE__))
  end

  describe '.load_image' do
    it 'loads a PNG file' do
      expect { Impressionist.load_image(input_path) }.not_to raise_error
      img = Impressionist.load_image(input_path)
      expect(img).to be_a(ChunkyPNG::Image)
      expect(img.width).to eq(1)
      expect(img.height).to eq(1)
    end

    it 'raises an error if file not found' do
      expect { Impressionist.load_image('nonexistent.png') }.to raise_error(ArgumentError, /File not found/)
    end
  end

  describe '.save_image' do
    it 'saves a ChunkyPNG::Image to disk' do
      img = ChunkyPNG::Image.new(1, 1, ChunkyPNG::Color::BLACK)
      Impressionist.save_image(img, output_path)
      expect(File.exist?(output_path)).to be true
      loaded_img = ChunkyPNG::Image.from_file(output_path)
      expect(loaded_img[0,0]).to eq(ChunkyPNG::Color::BLACK)
    end
  end

  describe '.recolor' do
    it 'processes an image and saves it' do
      options = { quant_interval: 8 }
      expect(Impressionist.recolor(input_path, output_path, options)).to be true
      expect(File.exist?(output_path)).to be true
      expect(ChunkyPNG::Image.from_file(output_path)).to be_a(ChunkyPNG::Image)
    end
  end

  describe '.process' do
    let(:options) { { quant_interval: 8 } } # Default options for some tests
    let(:red_color) { ChunkyPNG::Color.rgb(255,0,0) }
    let(:blue_color) { ChunkyPNG::Color.rgb(0,0,255) }

    # Updated to include :palette_quantize
    describe_implementations [:chunky_png, :matzeye, :palette_quantize] do |implementation|
      it "processes an image and returns the expected structure for #{implementation}" do
        run_options = options.merge(implementation: implementation)

        # Special setup for palette_quantize if it's the current implementation
        if implementation == :palette_quantize
          mock_palette = PaletteManager.new
          # Ensure active_palette is not empty for the mock adapter to do something
          mock_palette.instance_variable_set(:@active_palette, [red_color])
          run_options[:palette_object] = mock_palette
          # Ensure other necessary options for palette_quantize are present if they don't have defaults in main code yet
          run_options[:island_depth] ||= 0
          run_options[:island_threshold] ||= 0
        end

        result = Impressionist.process(input_path, run_options)

        expect(result).to have_key(:image)
        expect(result).to have_key(:labels)
        expect(result).to have_key(:blob_count)

        expect(result[:image]).to be_a(ChunkyPNG::Image)
        expect(result[:image].width).to eq(1)
        expect(result[:image].height).to eq(1)

        expect(result[:labels]).to be_an(Array)
        expect(result[:labels].size).to eq(result[:image].height)
        expect(result[:labels].first.size).to eq(result[:image].width)
        expect(result[:blob_count]).to be_an(Integer)
        expect(result[:blob_count]).to be >= 0
      end
    end

    context "with default (chunky_png) implementation" do
      it 'processes an image and returns a ChunkyPNG::Image based result' do
        result = Impressionist.process(input_path, options)
        expect(result[:image]).to be_a(ChunkyPNG::Image)
      end
    end

    context "with :palette_quantize implementation" do
      let(:implementation_type) { :palette_quantize }
      let(:sample_input_image) { ChunkyPNG::Image.new(10, 10, ChunkyPNG::Color::WHITE) } # A bit larger for testing

      let(:mock_palette) do
        pm = PaletteManager.new
        pm.instance_variable_set(:@raw_palette, [red_color, blue_color])
        pm.instance_variable_set(:@active_palette, [red_color]) # Only red is active for this test case
        pm
      end

      let(:palette_options) do
        {
          implementation: implementation_type,
          palette_object: mock_palette,
          island_depth: 1,
          island_threshold: 5
        }
      end

      it 'processes an image and returns the expected structure' do
        # Allow the original method to be called but spy on its arguments and return value
        allow(Impressionist::PaletteQuantizeAdapter).to receive(:process_image).and_call_original.and_wrap_original do |original_method, image, opts|
          expect(opts).to include(:palette_object)
          expect(opts[:palette_object]).to be_a(PaletteManager)
          original_method.call(image, opts)
        end

        result = Impressionist.process(sample_input_image, palette_options)

        expect(result).to have_key(:image)
        expect(result[:image]).to be_a(ChunkyPNG::Image)
        expect(result[:image].width).to eq(sample_input_image.width)
        expect(result[:image].height).to eq(sample_input_image.height)

        # Based on the simple mock where image's first pixel turns red if red is in active_palette
        expect(result[:image][0,0]).to eq(red_color) if sample_input_image.width > 0 && sample_input_image.height > 0

        expect(result).to have_key(:labels)
        expect(result[:labels]).to be_an(Array)
        expect(result[:labels].size).to eq(sample_input_image.height)
        result[:labels].each { |row| expect(row.size).to eq(sample_input_image.width) } if sample_input_image.height > 0

        expect(result).to have_key(:blob_count)
        expect(result[:blob_count]).to be_an(Integer)
        # Based on mock (1 blob if red is active and image has size)
        expected_blob_count = (sample_input_image.width > 0 && sample_input_image.height > 0 && mock_palette.active_palette.include?(red_color)) ? 1 : 0
        expect(result[:blob_count]).to eq(expected_blob_count)
      end

      it 'ensures Impressionist.process calls the PaletteQuantizeAdapter with correct arguments' do
        expect(Impressionist::PaletteQuantizeAdapter).to receive(:process_image)
          .with(sample_input_image, hash_including(palette_options))
          .and_return({ image: ChunkyPNG::Image.new(1,1), labels: [[]], blob_count: 0 }) # minimal valid structure

        Impressionist.process(sample_input_image, palette_options)
      end

      it 'passes options like :island_depth and :island_threshold to the adapter' do
         options_with_specific_island_params = palette_options.merge(island_depth: 2, island_threshold: 10)
         expect(Impressionist::PaletteQuantizeAdapter).to receive(:process_image)
          .with(anything, hash_including(island_depth: 2, island_threshold: 10))
          .and_return({ image: ChunkyPNG::Image.new(1,1), labels: [[]], blob_count: 0 })

         Impressionist.process(sample_input_image, options_with_specific_island_params)
      end
    end
  end

  # Tests for the original pure Ruby implementation in Impressionist module
  describe 'Impressionist pure Ruby methods' do
    let(:quant_test_img) do
      img = ChunkyPNG::Image.new(2, 2)
      img[0,0] = ChunkyPNG::Color.rgb(10, 20, 30)
      img[1,0] = ChunkyPNG::Color.rgb(12, 22, 28)
      img[0,1] = ChunkyPNG::Color.rgb(8, 18, 25)
      img[1,1] = ChunkyPNG::Color.rgb(15, 25, 31)
      img
    end

    it 'Impressionist.process_image applies quantization and averages original colors' do
      opts = { quant_interval: 16, min_blob_size: 0, connectivity: 4 }
      result = Impressionist.process_image(quant_test_img, opts)
      expected_color = ChunkyPNG::Color.rgb(11, 21, 29)
      expect(result[:image][0,0]).to eq(expected_color)
    end

    it 'Impressionist.process_image applies box blur' do
      blur_test_img = ChunkyPNG::Image.new(3, 3, ChunkyPNG::Color::BLACK)
      blur_test_img[1,1] = ChunkyPNG::Color.rgb(90, 90, 90)
      opts = { blur: true, blur_radius: 1, quant_interval: 1, min_blob_size: 0 }
      result = Impressionist.process_image(blur_test_img, opts)
      expect(result[:image][1,1]).to eq(ChunkyPNG::Color.rgb(10,10,10))
    end
  end

  # Specific tests for the MatzEyeAdapter's integration via Impressionist
  describe Impressionist::MatzEyeAdapter do
    # let(:fixture_dir) { File.expand_path('../../fixtures', __FILE__) } # Already defined at top
    let(:larger_input_path) { File.join(fixture_dir, 'sample_image.png') }
    let(:larger_chunky_image) { ChunkyPNG::Image.from_file(larger_input_path) }

    def image_checksum(chunky_image)
      sum = 0
      chunky_image.pixels.each { |p| sum += p }
      sum
    end

    describe '.process_image' do
      it 'processes a basic image (blur only) and returns the correct structure' do
        opts = { blur: true, blur_radius: 1 }
        result = Impressionist::MatzEyeAdapter.process_image(larger_chunky_image, opts)

        expect(result).to be_a(Hash)
        expect(result).to have_key(:image); expect(result[:image]).to be_a(ChunkyPNG::Image)
        expect(result).to have_key(:labels); expect(result[:labels]).to be_an(Array)
        expect(result).to have_key(:blob_count); expect(result[:blob_count]).to be_an(Integer)

        original_checksum = image_checksum(larger_chunky_image)
        processed_checksum = image_checksum(result[:image])
        expect(processed_checksum).not_to eq(original_checksum)
      end

      it 'processes a basic image (no blur) and returns the correct structure' do
        opts = { blur: false, quant_interval: 16 }
        result = Impressionist::MatzEyeAdapter.process_image(larger_chunky_image, opts)

        expect(result).to be_a(Hash)
        expect(result[:image]).to be_a(ChunkyPNG::Image)
        expect(result[:image].width).to eq(larger_chunky_image.width)
        expect(result[:image].height).to eq(larger_chunky_image.height)
        expect(result[:image]).not_to be(larger_chunky_image)

        original_checksum = image_checksum(larger_chunky_image)
        processed_checksum = image_checksum(result[:image])
        expect(processed_checksum).not_to eq(original_checksum)
      end

      context 'with options' do
        it 'handles :min_blob_size correctly' do
          opts_no_filter = { min_blob_size: 0 }
          opts_with_filter = { min_blob_size: 26 }

          result_no_filter = Impressionist::MatzEyeAdapter.process_image(larger_chunky_image, opts_no_filter)
          result_with_filter = Impressionist::MatzEyeAdapter.process_image(larger_chunky_image, opts_with_filter)

          expect(result_no_filter[:blob_count]).to be > 0
          expect(result_with_filter[:blob_count]).to eq(0)
          is_all_white = true
          result_with_filter[:image].pixels.each do |pixel|
            is_all_white = false if pixel != ChunkyPNG::Color::WHITE
            break unless is_all_white
          end
          expect(is_all_white).to be true
        end

        it 'produces different images with different :quant_interval values' do
          opts_quant_low = { quant_interval: 8 }
          opts_quant_high = { quant_interval: 64 }

          result_quant_low = Impressionist::MatzEyeAdapter.process_image(larger_chunky_image, opts_quant_low)
          result_quant_high = Impressionist::MatzEyeAdapter.process_image(larger_chunky_image, opts_quant_high)

          checksum_low = image_checksum(result_quant_low[:image])
          checksum_high = image_checksum(result_quant_high[:image])
          expect(checksum_low).not_to eq(checksum_high)
        end
      end
    end
  end

  # Add tests for .available_implementations and .default_options related to palette_quantize
  describe '.available_implementations' do
    it 'includes :palette_quantize' do
      # This assumes Impressionist::PaletteQuantizeAdapter is defined and loaded.
      # Impressionist.rb should dynamically add :palette_quantize to its list.
      # For this spec, we will mock that behavior or assume it's present if adapter is defined.
      # If Impressionist.available_implementations is static, this test might need adjustment
      # or the main code needs to be changed to dynamically register adapters.
      # For now, let's assume it's added if the constant is defined.
      allow(Impressionist).to receive(:available_implementations).and_call_original # ensure we don't break other tests
      expect(Impressionist.available_implementations).to include(:palette_quantize)
    end
  end

  describe '.default_options' do
    it 'includes default values for :palette_quantize options' do
      # Assuming default options for palette_quantize will be added to Impressionist
      expected_defaults = {
        palette_object: nil,
        island_depth: 0,
        island_threshold: 0
        # Add other relevant defaults as they are defined
      }
      # This might require Impressionist.default_options to be updated in the main code
      # or we mock it here for the purpose of the test if it's dynamically generated.
      # For now, we expect it to be part of the returned hash.
      expect(Impressionist.default_options).to include(:palette_quantize)
      expect(Impressionist.default_options[:palette_quantize]).to eq(expected_defaults)
    end
  end
end
