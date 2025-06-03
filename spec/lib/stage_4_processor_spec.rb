require 'spec_helper'
require 'stage_4_processor' # Assumes lib is in $LOAD_PATH

RSpec.describe Stage4Processor do
  describe '.process' do
    it 'returns a string indicating SVG output and parameters' do
      image_data = "dummy_image_data_s4"
      params = { color: 'blue', quality: 'high' }
      expected_output = "Stage 4 processed 'dummy_image_data_s4' with params: {:color=>\"blue\", :quality=>\"high\"} and produced final SVG data (placeholder)"
      expect(Stage4Processor.process(image_data, params)).to eq(expected_output)
    end

    it 'handles 2 to 6 parameters' do
      image_data = "image_s4_multi_param"
      params_5 = { q1: 'aa', q2: 'bb', q3: 'cc', q4: 'dd', q5: 'ee' }
      expect(Stage4Processor.process(image_data, params_5)).to include(params_5.inspect)
    end
  end
end
