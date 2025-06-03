require 'spec_helper'
require 'rack/test'
# app.rb is already required by spec_helper

# Explicitly require processors for mocking, even if app loads them.
# This ensures they are defined when RSpec compiles the spec file.
require 'stage_1_processor'
require 'stage_2_processor'
require 'stage_3_processor'
require 'stage_4_processor'


RSpec.describe 'Image Upload Feature' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  let(:image_file) { Rack::Test::UploadedFile.new(File.join(File.dirname(__FILE__), 'fixtures', 'test_image.png'), 'image/png') }

  # Ensure fixture file is created (idempotently)
  before(:all) do
    fixtures_dir = File.join(File.dirname(__FILE__), 'fixtures')
    FileUtils.mkdir_p(fixtures_dir)
    # Create the file only if it doesn't exist to avoid issues with multiple runs or before(:all) subtleties
    fixture_file_path = File.join(fixtures_dir, 'test_image.png')
    File.open(fixture_file_path, 'w') { |f| f.write("fake image data") } unless File.exist?(fixture_file_path)
  end

  context "POST /upload with pipeline orchestration" do
    # Define expected parameters for each stage, these should match what app.rb prepares
    let(:s1_params) { { p1_1: 'val_s1p1', p1_2: 'val_s1p2' } }
    let(:s2_params) { { p2_1: 'val_s2p1', p2_2: 'val_s2p2' } }
    let(:s3_params) { { p3_1: 'val_s3p1', p3_2: 'val_s3p2' } }
    let(:s4_params) { { p4_1: 'val_s4p1', p4_2: 'val_s4p2' } }

    # All parameters sent in the POST request
    let(:all_upload_params) do
      {
        image: image_file,
        s1p1: 'val_s1p1', s1p2: 'val_s1p2',
        s2p1: 'val_s2p1', s2p2: 'val_s2p2',
        s3p1: 'val_s3p1', s3p2: 'val_s3p2',
        s4p1: 'val_s4p1', s4p2: 'val_s4p2'
      }
    end

    it 'calls each stage processor in sequence and returns final output' do
      # Mock the processors
      # Note: image_data in app.rb is currently params[:image][:filename] which is "test_image.png"
      # The output of one stage is the input to the next.
      expect(Stage1Processor).to receive(:process).with("test_image.png", s1_params).ordered.and_return("output_s1")
      expect(Stage2Processor).to receive(:process).with("output_s1", s2_params).ordered.and_return("output_s2")
      expect(Stage3Processor).to receive(:process).with("output_s2", s3_params).ordered.and_return("output_s3")
      expect(Stage4Processor).to receive(:process).with("output_s3", s4_params).ordered.and_return("final_svg_placeholder_output")

      post '/upload', all_upload_params

      expect(last_response).to be_ok
      expect(last_response.body).to eq("final_svg_placeholder_output")
    end

    it 'still returns 400 if no file is uploaded' do
      # No need to mock processors here as the route should return early
      post '/upload', { s1p1: 'val_s1p1' } # Missing image
      expect(last_response).to be_bad_request
      expect(last_response.body).to include("No file uploaded")
    end
  end
end
