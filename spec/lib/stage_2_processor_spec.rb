require 'spec_helper'
require 'stage_2_processor' # Assumes lib is in $LOAD_PATH

RSpec.describe Stage2Processor do
  describe '.process' do
    it 'returns a string indicating processing and parameters' do
      image_data = "dummy_image_data_s2"
      params = { paramA: 'valA', paramB: 'valB' }
      expected_output = "Stage 2 processed 'dummy_image_data_s2' with params: {:paramA=>\"valA\", :paramB=>\"valB\"}"
      expect(Stage2Processor.process(image_data, params)).to eq(expected_output)
    end

    it 'handles 2 to 6 parameters' do
      image_data = "image_s2_multi_param"
      params_3 = { px: 1, py: 2, pz: 3 }
      expect(Stage2Processor.process(image_data, params_3)).to include(params_3.inspect)
    end
  end
end
