require 'sinatra'

# Add lib to load path for the application itself
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), 'lib')) unless $LOAD_PATH.include?(File.join(File.dirname(__FILE__), 'lib'))

require 'stage_1_processor'
require 'stage_2_processor'
require 'stage_3_processor'
require 'stage_4_processor'

configure :test do
  set :protection, false
end

get '/' do
  'Hello World!'
end

post '/upload' do
  if params[:image] && params[:image][:tempfile]
    # Placeholder for where actual image data would be read
    image_data = params[:image][:filename] # Using filename as placeholder for image data content

    # Define placeholder parameters for each stage
    # These would eventually come from user input (params) or be configured
    stage1_params = { p1_1: params['s1p1'], p1_2: params['s1p2'] }
    stage2_params = { p2_1: params['s2p1'], p2_2: params['s2p2'] }
    stage3_params = { p3_1: params['s3p1'], p3_2: params['s3p2'] }
    stage4_params = { p4_1: params['s4p1'], p4_2: params['s4p2'] }

    # Pipeline execution
    processed_data_s1 = Stage1Processor.process(image_data, stage1_params)
    processed_data_s2 = Stage2Processor.process(processed_data_s1, stage2_params)
    processed_data_s3 = Stage3Processor.process(processed_data_s2, stage3_params)
    final_output = Stage4Processor.process(processed_data_s3, stage4_params)

    status 200
    # Return the final output from Stage 4
    body final_output
  else
    status 400
    body "No file uploaded"
  end
end
