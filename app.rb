require 'sinatra'
require 'securerandom'
require 'fileutils'
require_relative 'lib/impressionist'
require_relative 'lib/blob_graph'
require_relative 'lib/quilt_graph'

enable :sessions
set :bind, '0.0.0.0'
set :port, 4567

# Configuration for test environment
configure :test do
  set :protection, false
  set :static, false
  set :public_folder, File.expand_path('non_existent_public_folder_for_test', __dir__)
end

TMP_DIR = File.expand_path('tmp', __dir__)
FileUtils.mkdir_p(TMP_DIR)

helpers do

  private # Keep helpers private to the app routes

  def parse_step1_params(params)
    quant_interval = params[:quant_interval].to_i
    quant_interval = 1 if quant_interval < 1

    do_blur = params[:blur] == "on"

    blur_radius = params[:blur_radius].to_i
    blur_radius = 1 if blur_radius < 1

    connectivity = params[:connectivity].to_i
    connectivity = [4, 8].include?(connectivity) ? connectivity : 4

    min_blob_size = params[:min_blob_size].to_i
    min_blob_size = 0 if min_blob_size < 0

    {
      quant_interval: quant_interval,
      blur:           do_blur,
      blur_radius:    blur_radius,
      connectivity:   connectivity,
      min_blob_size:  min_blob_size
    }
  end

  def parse_step2_params(params)
    junction_conn = params[:junction_conn].to_i
    junction_conn = [4,8].include?(junction_conn) ? junction_conn : 8

    path_conn = params[:path_conn].to_i
    path_conn = [4,8].include?(path_conn) ? path_conn : 8

    skeletonize = params[:skeletonize] == 'on'

    simplify_tol = params[:simplify_tol].to_f
    simplify_tol = 0.0 if simplify_tol < 0.0

    {
      junction_conn: junction_conn,
      path_conn:     path_conn,
      skeletonize:   skeletonize,
      simplify_tol:  simplify_tol
    }
  end

  public # Make sure other helpers are public if used directly in routes/views

  # Create (or retrieve) a unique working directory for this session
  def session_dir
    if ENV['RACK_ENV'] == 'test'
      session[:uid] = "test_fixture_uid"
    else
      session[:uid] ||= SecureRandom.uuid
    end
    dir = File.join(TMP_DIR, session[:uid])
    FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
    dir
  end

  # Paths within session_dir
  def path_step1_png;        File.join(session_dir, 'step1.png');        end
  def path_labels_dat;       File.join(session_dir, 'labels.dat');       end
  def path_step2_svg;        File.join(session_dir, 'step2_graph.svg');  end
  def path_final_svg;        File.join(session_dir, 'final_quilt.svg');  end

  # Load dumped labels (from Marshal)
  def load_labels
    Marshal.load(File.binread(path_labels_dat))
  end

  # Save labels (2D Array) via Marshal
  def save_labels(lbls)
    File.open(path_labels_dat, 'wb') { |f| f.write(Marshal.dump(lbls)) }
  end

  # Render an SVG string inline (embed directly)
  def inline_svg_tag(svg_content)
    "<div style=\"width:100%;height:100%;\">#{svg_content}</div>"
  end
end

# ----------------------------------------------------------------------------
# Step 0: GET '/' – Show upload form and Step 1 options.
get '/' do
  session.clear
  <<~HTML
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8" />
      <title>Quilt Workflow – Step 1: Blob Recolor</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        label { display: block; margin-top: 10px; }
        input[type="number"] { width: 60px; }
      </style>
    </head>
    <body>
      <h2>Step 1: Upload PNG and Configure Blob Recolor</h2>
      <form action="/step1" method="POST" enctype="multipart/form-data">
        <label>
          Select PNG Image:
          <input type="file" name="image" accept="image/png" required>
        </label>
        <label>
          Quantization Interval:
          <input type="number" name="quant_interval" value="16" min="1">
        </label>
        <label>
          <input type="checkbox" name="blur" checked> Apply Box‐Blur
        </label>
        <label>
          Blur Radius:
          <input type="number" name="blur_radius" value="1" min="1">
        </label>
        <label>
          Connectivity:
          <select name="connectivity">
            <option value="4">4‐Connectivity</option>
            <option value="8" selected>8‐Connectivity</option>
          </select>
        </label>
        <label>
          Minimum Blob Size (pixels):
          <input type="number" name="min_blob_size" value="50" min="0">
        </label>
        <br>
        <button type="submit">Next: Recolor Image</button>
      </form>
    </body>
    </html>
  HTML
end

# ----------------------------------------------------------------------------
# Step 1: POST '/step1' – Process impressionist recoloring, save labels, and show blob image + Step 2 options.
post '/step1' do
  unless params[:image] &&
         (tempfile = params[:image][:tempfile]) &&
         (filename = params[:image][:filename])
    halt 400, "No image uploaded"
  end

  orig_path = File.join(session_dir, 'original.png')
  FileUtils.copy_file(tempfile.path, orig_path)

  # Parse options using helper
  step1_options = parse_step1_params(params)

  # Call public Impressionist.process method
  impressionist_result = Impressionist.process(orig_path, step1_options)
  step1_img = impressionist_result[:image]
  labels = impressionist_result[:labels]
  # blob_count = impressionist_result[:blob_count] # Available if needed

  step1_img.save(path_step1_png)
  save_labels(labels)

  <<~HTML
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8" />
      <title>Step 2: Blob Graph Extraction</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        label { display: block; margin-top: 10px; }
        canvas#preview { border: 1px solid #ccc; max-width: 100%; }
      </style>
    </head>
    <body>
      <h2>Step 2: Blob‐Adjacency Graph Extraction</h2>
      <p>Below is the recolored “blob” image from Step 1:</p>
      <img src="/tmp/#{session[:uid]}/step1.png" style="max-width:100%;border:1px solid #ccc;">
      <h3>Configure Graph Extraction Options</h3>
      <form action="/step2" method="POST">
        <label>
          Junction Clustering Connectivity:
          <select name="junction_conn">
            <option value="4">4‐Connectivity</option>
            <option value="8" selected>8‐Connectivity</option>
          </select>
        </label>
        <label>
          Path BFS Connectivity:
          <select name="path_conn">
            <option value="4">4‐Connectivity</option>
            <option value="8" selected>8‐Connectivity</option>
          </select>
        </label>
        <label>
          <input type="checkbox" name="skeletonize" checked> Skeletonize Borders
        </label>
        <label>
          Simplification Tolerance:
          <input type="number" step="0.1" name="simplify_tol" value="2.0" min="0">
        </label>
        <br>
        <button type="submit">Next: Show Blob Graph</button>
      </form>
    </body>
    </html>
  HTML
end

# ----------------------------------------------------------------------------
# Step 2: POST '/step2' – Extract blob graph, save SVG, and show graph + Step 3 options.
post '/step2' do
  labels = load_labels
  # height = labels.size # Not directly used, but good for context
  # width  = labels.first.size # Not directly used

  step2_parsed_options = parse_step2_params(params)

  result = BlobGraph.extract_from_labels(labels, step2_parsed_options)

  vertices = result[:vertices]
  edges    = result[:edges]
  detailed = result[:detailed_edges]

  step2_svg = ""
  if vertices.empty?
    step2_svg = '<svg width="100" height="100"><text x="10" y="20">No graph generated (no vertices).</text></svg>'
    edges = []
  else
    xs = vertices.values.map { |(x,_)| x }
    ys = vertices.values.map { |(_,y)| y }
    min_x, max_x = xs.minmax
    min_y, max_y = ys.minmax
    pad = 10.0
    vb_x = min_x - pad
    vb_y = min_y - pad
    vb_w = (max_x.to_f - min_x.to_f) + 2*pad
    vb_h = (max_y.to_f - min_y.to_f) + 2*pad
    vb_w = pad * 2 if vb_w <= 0
    vb_h = pad * 2 if vb_h <= 0

    svg_lines = []
    svg_lines << '<?xml version="1.0" encoding="UTF-8"?>'
    svg_lines << "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"#{vb_x} #{vb_y} #{vb_w} #{vb_h}\" width=\"100%\" height=\"100%\">"
    edges.each do |(j1,j2)|
      next unless vertices[j1] && vertices[j2]
      x1,y1 = vertices[j1]
      x2,y2 = vertices[j2]
      svg_lines << "  <line x1=\"#{x1}\" y1=\"#{y1}\" x2=\"#{x2}\" y2=\"#{y2}\" stroke=\"blue\" stroke-width=\"0.5\" />"
    end
    vertices.each do |j, (x,y)|
      svg_lines << "  <circle cx=\"#{x}\" cy=\"#{y}\" r=\"2\" fill=\"red\" />"
    end
    svg_lines << "</svg>"
    step2_svg = svg_lines.join("\n")
  end

  File.write(path_step2_svg, step2_svg)

  session[:vertices] = vertices
  session[:edges]    = edges
  session[:detailed_edges] = detailed

  <<~HTML
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8" />
      <title>Step 3: Quilt Smoothing & Validation</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        label { display: block; margin-top: 10px; }
      </style>
    </head>
    <body>
      <h2>Step 2 Result: Blob Graph</h2>
      <p>Below is the straight-line blob graph:</p>
      #{inline_svg_tag(step2_svg)}
      <h3>Configure Quilt Smoothing Options</h3>
      <form action="/step3" method="POST">
        <p>(Using default smoothing/validation settings.)</p>
        <button type="submit">Next: Generate Quilt‐Legal SVG</button>
      </form>
    </body>
    </html>
  HTML
end

# ----------------------------------------------------------------------------
# Step 3: POST '/step3' – Smooth/validate graph and show final quilt‐legal SVG.
post '/step3' do
  vertices = session[:vertices]
  edges    = session[:edges]

  graph_input = { vertices: vertices, edges: edges }
  quilt_graph_result = QuiltGraph.correct_quilt(graph_input)

  final_svg = QuiltGraph.graph_to_svg_string(quilt_graph_result)
  File.write(path_final_svg, final_svg)

  <<~HTML
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8" />
      <title>Final Quilt‐Legal SVG</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
      </style>
    </head>
    <body>
      <h2>Final Quilt‐Legal SVG</h2>
      <p>The final smoothed and validated quilt diagram:</p>
      #{inline_svg_tag(final_svg)}
      <p><a href="/download_final">Download SVG</a></p>
    </body>
    </html>
  HTML
end

# ----------------------------------------------------------------------------
# Route to download final SVG file
get '/download_final' do
  send_file path_final_svg, filename: "quilt_legal.svg", type: "image/svg+xml"
end

# ----------------------------------------------------------------------------
set :static, true
set :public_folder, File.dirname(__FILE__)

get '/tmp/:sid/:file' do |sid, file|
  safe_sid = sid.gsub(/[^a-zA-Z0-9_-]/, "")
  if file.include?('..') || file.start_with?('/')
    error 404, "Invalid path due to '..' or leading '/'."
  end
  safe_file = file.gsub(/[^a-zA-Z0-9_.-]/, "")
  halt 404, "Invalid characters in path" if safe_sid != sid || safe_file != file
  path = File.join(TMP_DIR, safe_sid, safe_file)
  begin
    halt 404, "Invalid path components" if safe_sid.empty? || safe_file.empty?
    if File.exist?(path) && File.realpath(path).start_with?(File.realpath(TMP_DIR))
      send_file path
    else
      halt 404, "File not found or access denied"
    end
  rescue Errno::ENOENT
    halt 404, "File not found during path resolution"
  end
end
