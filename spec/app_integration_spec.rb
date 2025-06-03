require 'spec_helper' # Should require 'app.rb' and set RACK_ENV='test'
require 'rack/test'
require 'fileutils' # For cleaning up tmp session dirs

RSpec.describe 'Application Integration Workflow' do
  include Rack::Test::Methods

  TMP_DIR_BASE = File.expand_path('../../tmp', __FILE__) # Path to project's tmp directory

  def app
    Sinatra::Application
  end

  # Clean up any session directories in tmp before and after tests
  # Also prepare global fixtures here
  before(:all) do
    FileUtils.rm_rf(Dir.glob("#{TMP_DIR_BASE}/*")) # Clean tmp

    # Ensure spec/fixtures directory exists
    fixtures_dir = File.join(File.dirname(__FILE__), 'fixtures')
    FileUtils.mkdir_p(fixtures_dir)

    # Always create/overwrite with a valid 1x1 PNG to ensure consistency
    fixture_file_path = File.join(fixtures_dir, 'test_image.png')
    File.open(fixture_file_path, 'wb') do |f| # Use 'wb' for binary write
      f.write(Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII='))
    end
  end
  after(:all) do
    FileUtils.rm_rf(Dir.glob("#{TMP_DIR_BASE}/*")) # Clean tmp
  end

  # Helper to get the current session ID from the cookie
  def current_session_id
    # rack_mock_session.cookie_jar["rack.session"] can be nil if no session cookie yet
    # It can also be just the session_id without a semicolon (e.g. after session.clear then a new request)
    # Or it can be "session_id; path=/; HttpOnly"
    cookie_value = rack_mock_session.cookie_jar["rack.session"]
    return nil unless cookie_value
    cookie_value.split(';').first
  end

  describe "GET /" do
    it "loads the initial upload form" do
      get '/'
      expect(last_response).to be_ok
      expect(last_response.body).to include("<h2>Step 1: Upload PNG and Configure Blob Recolor</h2>")
      expect(last_response.body).to include("<form action=\"/step1\" method=\"POST\" enctype=\"multipart/form-data\">")
    end

    it "clears the session" do
      # Set some dummy session data by starting a workflow
      post '/step1', image: Rack::Test::UploadedFile.new(File.expand_path('../fixtures/test_image.png', __FILE__), 'image/png', true)
      expect(current_session_id).not_to be_nil
      first_sid = current_session_id

      get '/' # This should clear the session
      expect(last_response).to be_ok

      # After session.clear, the next request that tries to establish a session will create a new one.
      # So, we make another request that would initiate a session to check if the ID is different.
      post '/step1', image: Rack::Test::UploadedFile.new(File.expand_path('../fixtures/test_image.png', __FILE__), 'image/png', true)
      new_sid = current_session_id
      expect(new_sid).not_to be_nil
      expect(new_sid).not_to eq(first_sid)
    end
  end

  describe "Full Workflow Simulation" do
    # fixture_image_path is now consistently created in before(:all)
    let(:fixture_image_path) { File.join(File.dirname(__FILE__), 'fixtures', 'test_image.png') }
    let(:uploaded_file) { Rack::Test::UploadedFile.new(fixture_image_path, 'image/png', true) } # binary mode true

    it "successfully completes the 3-step workflow and download" do
      # Step 0: Get initial form (and initialize session)
      get '/'
      expect(last_response).to be_ok
      initial_sid = current_session_id # Capture session ID after first request
      expect(initial_sid).not_to be_nil # A session should be created or cleared/recreated

      # Step 1: POST /step1
      step1_params = {
        image: uploaded_file,
        quant_interval: "8",
        blur: "on",
        blur_radius: "1",
        connectivity: "8",
        min_blob_size: "0" # For a 1x1 png, min_blob_size > 1 would remove it. Set to 0 or 1.
      }
      post '/step1', step1_params
      expect(last_response).to be_ok
      expect(last_response.body).to include("<h2>Step 2: Blob‐Adjacency Graph Extraction</h2>")

      # Verify files for step 1
      # In test env, app.rb now forces session[:uid] to "test_fixture_uid"
      expected_test_sid = "test_fixture_uid"
      session_path = File.join(TMP_DIR_BASE, expected_test_sid)
      expect(File).to exist(File.join(session_path, 'original.png')), "original.png not found in #{session_path}"
      expect(File).to exist(File.join(session_path, 'step1.png')), "step1.png not found in #{session_path}"
      expect(File).to exist(File.join(session_path, 'labels.dat')), "labels.dat not found in #{session_path}"
      expect(last_response.body).to include("/tmp/#{expected_test_sid}/step1.png") # App should use this SID in response

      # Step 2: POST /step2
      step2_params = {
        junction_conn: "8",
        path_conn: "8",
        skeletonize: "on", # Test with skeletonization
        simplify_tol: "1.5"
      }
      post '/step2', step2_params
      expect(last_response).to be_ok
      # The page title for step 3 form is "Step 3: Quilt Smoothing & Validation"
      # but the H2 for the graph from step 2 is "Step 2 Result: Blob Graph"
      expect(last_response.body).to include("<h2>Step 2 Result: Blob Graph</h2>")
      expect(last_response.body).to include("<svg") # Check for embedded SVG
      expect(last_response.body).to include("<h3>Configure Quilt Smoothing Options</h3>")

      # Verify files for step 2
      expect(File).to exist(File.join(session_path, 'step2_graph.svg')), "step2_graph.svg not found in #{session_path}"

      # Step 3: POST /step3
      post '/step3' # No params for step3 in current app.rb
      expect(last_response).to be_ok
      expect(last_response.body).to include("<h2>Final Quilt‐Legal SVG</h2>")
      expect(last_response.body).to include("<svg") # Check for final embedded SVG
      expect(last_response.body).to include("<a href=\"/download_final\">Download SVG</a>")

      # Verify files for step 3
      expect(File).to exist(File.join(session_path, 'final_quilt.svg')), "final_quilt.svg not found in #{session_path}"

      # Download final SVG
      get '/download_final'
      expect(last_response).to be_ok
      expect(last_response.headers['Content-Type']).to eq('image/svg+xml')
      # Note: Rack::Test often downcases header names
      disposition_header = last_response.headers['content-disposition'] || last_response.headers['Content-Disposition']
      expect(disposition_header).to include("filename=\"quilt_legal.svg\"")
      expect(last_response.body).to include("<svg") # Basic check it's an SVG
    end

    it "handles image upload failure in /step1" do
      post '/step1' # No image param
      expect(last_response).to be_bad_request
      expect(last_response.body).to include("No image uploaded")
    end
  end

  describe "Static File Serving for /tmp files" do
    it "serves a file from a session directory" do
      # Use a short, predictable SID for this test's setup
      test_sid = "testingsid123"
      # 1. Create a dummy file in a path that mimics a session directory
      session_specific_tmp_dir = File.join(TMP_DIR_BASE, test_sid)
      FileUtils.mkdir_p(session_specific_tmp_dir) # Ensure dir exists
      File.write(File.join(session_specific_tmp_dir, "test_file.txt"), "Hello Jules!")

      # 2. Request the file using the same predictable SID
      get "/tmp/#{test_sid}/test_file.txt"
      expect(last_response).to be_ok
      expect(last_response.body).to eq("Hello Jules!")
      # Default content type for .txt by Sinatra might vary, could be text/plain or application/octet-stream
      # Let's be flexible or check for a common part. For now, checking it's not HTML.
      expect(last_response.headers['Content-Type']).not_to include('text/html')
    end

    it "returns 404 for non-existent file in /tmp" do
      get '/tmp/non_existent_sid/non_existent_file.txt'
      expect(last_response).to be_not_found
    end

    it "returns 404 for path traversal attempts" do
      get '/tmp/fakesid/../../Gemfile' # This path will be sanitized
      # Debug: Print status and relevant headers
      # puts "Path Traversal Response Status: #{last_response.status}"
      # puts "Path Traversal Response Location: #{last_response.headers['Location']}"
      expect(last_response.status).to eq(404)
    end
  end
end
