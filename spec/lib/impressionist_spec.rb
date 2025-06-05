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
    let(:options) { { quant_interval: 8 } }

    describe_implementations [:chunky_png, :matzeye] do |implementation|
      it "processes an image and returns the expected structure for #{implementation}" do
        run_options = options.merge(implementation: implementation)
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
    let(:fixture_dir) { File.expand_path('../../fixtures', __FILE__) }
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
end
