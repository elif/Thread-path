require 'spec_helper'
require 'stage_1_processor' # Assumes lib is in $LOAD_PATH

RSpec.describe Stage1Processor do
  describe '.process' do
    it 'returns a string indicating processing and parameters' do
      image_data = "dummy_image_data_s1"
      params = { param1: 'val1', param2: 'val2' }
      # Note: Ruby's Hash#inspect typically uses => for key-value pairs.
      # And symbol keys are represented as :key.
      expected_output = "Stage 1 processed 'dummy_image_data_s1' with params: {:param1=>\"val1\", :param2=>\"val2\"}"
      expect(Stage1Processor.process(image_data, params)).to eq(expected_output)
    end

    it 'handles 2 to 6 parameters' do
      image_data = "image_s1_multi_param"
      params_2 = { p1: 'a', p2: 'b' }
      params_6 = { p1: 'a', p2: 'b', p3: 'c', p4: 'd', p5: 'e', p6: 'f' }

      expect(Stage1Processor.process(image_data, params_2)).to include(params_2.inspect)
      expect(Stage1Processor.process(image_data, params_6)).to include(params_6.inspect)
    end
  end
end
