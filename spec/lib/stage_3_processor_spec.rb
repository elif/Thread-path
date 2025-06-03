require 'spec_helper'
require 'stage_3_processor' # Assumes lib is in $LOAD_PATH

RSpec.describe Stage3Processor do
  describe '.process' do
    it 'returns a string indicating processing and parameters' do
      image_data = "dummy_image_data_s3"
      params = { settingX: true, settingY: false }
      expected_output = "Stage 3 processed 'dummy_image_data_s3' with params: {:settingX=>true, :settingY=>false}"
      expect(Stage3Processor.process(image_data, params)).to eq(expected_output)
    end

    it 'handles 2 to 6 parameters' do
      image_data = "image_s3_multi_param"
      params_4 = { s1: 0, s2: 1, s3: 2, s4: 3 }
      expect(Stage3Processor.process(image_data, params_4)).to include(params_4.inspect)
    end
  end
end
