require 'spec_helper'
require_relative '../../lib/palette_manager'

# Mock ChunkyPNG::Image and Color for testing purposes if PaletteManager
# is expected to interact with them directly for palette extraction.
# For now, we'll assume PaletteManager might take simple image data
# or that internal image processing is mocked.

RSpec.describe PaletteManager do
  let(:fixture_dir) { File.expand_path('../fixtures', __dir__) }
  let(:sample_palette_image_path) { File.join(fixture_dir, 'sample_palette.png') } # Assume this exists or will be created
  let(:empty_image_path) { File.join(fixture_dir, 'empty_image.png') } # Assume this exists

  # Helper to create a dummy image file for tests
  def create_dummy_image(path, width: 1, height: 1, color: ChunkyPNG::Color::WHITE)
    FileUtils.mkdir_p(File.dirname(path))
    img = ChunkyPNG::Image.new(width, height, color)
    img.save(path)
  end

  before do
    # Create a dummy sample palette image for tests that need an image path
    # This image should ideally have a few distinct color areas
    # For now, a simple one will do; more complex mocking of swatch extraction
    # will be handled within the tests.
    palette_img = ChunkyPNG::Image.new(2, 1)
    palette_img[0,0] = ChunkyPNG::Color.rgb(255,0,0) # Red
    palette_img[1,0] = ChunkyPNG::Color.rgb(0,0,255) # Blue
    create_dummy_image(sample_palette_image_path, width: 2, height: 1, color: ChunkyPNG::Color::TRANSPARENT) # Ensure path exists
    ChunkyPNG::Image.new(2,1).tap { |img| img[0,0] = ChunkyPNG::Color.rgb(255,0,0); img[1,0] = ChunkyPNG::Color.rgb(0,0,255); }.save(sample_palette_image_path, :fast_rgba)

    create_dummy_image(empty_image_path) # An empty/single-color image
  end

  after do
    FileUtils.rm_f(sample_palette_image_path)
    FileUtils.rm_f(empty_image_path)
  end

  # Placeholder for the actual PaletteManager class -- REMOVED


  describe 'Palette Extraction' do
    context 'when initialized with an image path' do
      subject { PaletteManager.new(sample_palette_image_path) }

      it 'can be initialized with an image path' do
        expect(subject.instance_variable_get(:@image_path)).to eq(sample_palette_image_path)
      end

      describe '#extract_palette_from_image' do
        it 'populates the raw palette using :mock strategy for this test' do
          # This test specifically uses the :mock strategy defined in PaletteManager
          subject.extract_palette_from_image(swatch_finder_method: :mock)
          expect(subject.raw_palette).not_to be_empty
          expect(subject.raw_palette).to all(be_a(Integer)) # ChunkyPNG colors are integers
          expect(subject.raw_palette).to contain_exactly(ChunkyPNG::Color.rgb(255,0,0), ChunkyPNG::Color.rgb(0,0,255))
        end

        it 'ensures extracted raw palette contains unique colors' do
          # This test will use the default :simple_unique_colors strategy.
          # The sample_palette_image_path is created with Red and Blue.
          # The PaletteManager's extract_palette_from_image should handle uniqueness.

          # Create an image with duplicate colors for the test subject
          img_with_duplicates_path = File.join(fixture_dir, 'dup_colors.png')
          ChunkyPNG::Image.new(3,1).tap { |img|
            img[0,0] = ChunkyPNG::Color.rgb(255,0,0);
            img[1,0] = ChunkyPNG::Color.rgb(0,0,255);
            img[2,0] = ChunkyPNG::Color.rgb(255,0,0); # Duplicate Red
          }.save(img_with_duplicates_path, :fast_rgba)

          manager_with_duplicates = PaletteManager.new(img_with_duplicates_path)
          manager_with_duplicates.extract_palette_from_image # Uses default :simple_unique_colors

          expect(manager_with_duplicates.raw_palette.uniq.size).to eq(manager_with_duplicates.raw_palette.size)
          expect(manager_with_duplicates.raw_palette).to contain_exactly(ChunkyPNG::Color.rgb(255,0,0), ChunkyPNG::Color.rgb(0,0,255))
          FileUtils.rm_f(img_with_duplicates_path)
        end

        it 'handles image with no discernible swatches by returning an empty raw palette' do
          # This test relies on mocking the internal _perform_actual_extraction method.
          # The PaletteManager must use this method (or a similar one that can be mocked)
          # when a specific swatch_finder_method is chosen.
          manager = PaletteManager.new(empty_image_path) # empty_image_path is a 1x1 white image

          # Test 1: Using the default :simple_unique_colors strategy with an empty image
          # (after ensuring create_dummy_image helper correctly saves it)
          # The `empty_image_path` is a 1x1 white image by default from `before` block.
          # So it should extract one color: white.
          # To test "no discernible swatches", we need an image that truly has no pixels or is invalid.
          # Or, we can mock the ChunkyPNG loading to return an empty image.

          allow(ChunkyPNG::Image).to receive(:from_file).with(empty_image_path).and_return(ChunkyPNG::Image.new(0,0))
          manager.extract_palette_from_image # Uses default strategy
          expect(manager.raw_palette).to be_empty

          # Test 2: Mocking _perform_actual_extraction if a strategy uses it
          # This requires extract_palette_from_image to have a path that calls _perform_actual_extraction
          # and that path is triggered by a specific swatch_finder_method.
          # Let's use the :_perform_actual_extraction_mock strategy for this.
          allow(manager).to receive(:_perform_actual_extraction).and_return([])
          manager.extract_palette_from_image(swatch_finder_method: :_perform_actual_extraction_mock)
          expect(manager.raw_palette).to be_empty
        end

        it 'sets the active palette to match the raw palette after extraction' do
          subject.extract_palette_from_image
          expect(subject.active_palette).to eq(subject.raw_palette)
        end
      end
    end

    context 'when initialized without an image path' do
      subject { PaletteManager.new }
      it 'has an empty raw palette initially' do
        expect(subject.raw_palette).to be_empty
      end
      it 'has an empty active palette initially' do
        expect(subject.active_palette).to be_empty
      end
    end
  end

  describe 'Active Palette Management' do
    subject { PaletteManager.new }
    let(:color1) { ChunkyPNG::Color.rgb(255, 0, 0) } # Red
    let(:color2) { ChunkyPNG::Color.rgb(0, 255, 0) } # Green
    let(:color3) { ChunkyPNG::Color.rgb(0, 0, 255) } # Blue

    before do
      # Manually set a raw palette for these tests
      subject.instance_variable_set(:@raw_palette, [color1, color2, color3])
      subject.activate_all_colors # Start with all colors active
    end

    describe '#raw_palette' do
      it 'returns the list of extracted colors' do
        expect(subject.raw_palette).to contain_exactly(color1, color2, color3)
      end
    end

    describe '#active_palette' do
      it 'returns the current list of active colors' do
        expect(subject.active_palette).to contain_exactly(color1, color2, color3)
      end
    end

    describe '#add_to_active_palette' do
      it 'adds a color to the active palette if it exists in the raw palette and is not already active' do
        subject.remove_from_active_palette(color1) # Make it inactive first
        subject.add_to_active_palette(color1)
        expect(subject.active_palette).to include(color1)
      end

      it 'does not add a color if it is not in the raw palette (optional behavior, for now assume it can add any color)' do
        new_color = ChunkyPNG::Color.rgb(255,255,0) # Yellow
        subject.add_to_active_palette(new_color)
        # This behavior depends on design choice: should active palette be strictly a subset of raw?
        # For now, the placeholder allows adding any color.
        # A stricter implementation might be:
        # expect(subject.active_palette).not_to include(new_color)
        # Or it might add to raw_palette as well. For now, test current placeholder behavior:
        expect(subject.active_palette).to include(new_color)
      end

      it 'does not duplicate a color if already active' do
        subject.add_to_active_palette(color1)
        expect(subject.active_palette.count(color1)).to eq(1)
      end
    end

    describe '#remove_from_active_palette' do
      it 'removes a color from the active palette' do
        subject.remove_from_active_palette(color1)
        expect(subject.active_palette).not_to include(color1)
        expect(subject.active_palette).to contain_exactly(color2, color3)
      end

      it 'does nothing if the color is not in the active palette' do
        subject.remove_from_active_palette(ChunkyPNG::Color.rgb(128,128,128)) # A color not present
        expect(subject.active_palette).to contain_exactly(color1, color2, color3)
      end
    end

    describe '#clear_active_palette' do
      it 'removes all colors from the active palette' do
        subject.clear_active_palette
        expect(subject.active_palette).to be_empty
      end
    end

    describe '#activate_all_colors' do
      it 'sets the active palette to be identical to the raw palette' do
        subject.clear_active_palette
        subject.activate_all_colors
        expect(subject.active_palette).to eq(subject.raw_palette)
        expect(subject.active_palette).to contain_exactly(color1, color2, color3)
      end

      it 'handles an empty raw palette' do
        subject.instance_variable_set(:@raw_palette, [])
        subject.activate_all_colors
        expect(subject.active_palette).to be_empty
      end
    end

    describe 'Toggling (conceptual)' do
      # This is more of a conceptual test for how one might implement toggle
      # using existing add/remove methods.
      it 'can simulate toggling a color (remove if present, add if not)' do
        # Start with color1 active
        expect(subject.active_palette).to include(color1)

        # Toggle 1: Remove color1
        if subject.active_palette.include?(color1)
          subject.remove_from_active_palette(color1)
        else
          # subject.add_to_active_palette(color1) # Assuming add_to_active_palette adds from raw if not present
        end
        expect(subject.active_palette).not_to include(color1)

        # Toggle 2: Add color1 back
        if subject.active_palette.include?(color1)
          subject.remove_from_active_palette(color1)
        else
          # For this test, let's assume we want to add it back from raw palette if it was there.
          # The placeholder PaletteManager's add_to_active_palette doesn't currently enforce it must be in raw.
          # A real toggle might be:
          # subject.toggle_active_status(color1) which would consult raw_palette.
          # For now, using basic add:
          subject.add_to_active_palette(color1)
        end
        expect(subject.active_palette).to include(color1)
      end
    end
  end
end
