# app.rb
#
# Sinatra application that guides the user through three steps:
#  1. Upload a PNG and apply “impressionist” blob recoloring (using Impressionist).
#  2. Extract a blob‐adjacency graph from the labeled image (using BlobGraph) and render it as SVG.
#  3. Smooth/validate the graph into a quilt‐legal planar graph (using QuiltGraph) and render final SVG.
#
# At each step, the user sees the result and can adjust options before proceeding.
#
# Directory structure:
#   tmp/   -- stores per‐session subfolders containing intermediate images, labels, and SVGs.
#
# Dependencies:
#   gem install sinatra chunky_png
#   (Ensure lib/impressionist.rb, lib/blob_graph.rb, lib/quilt_graph.rb are in the same folder)
#
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
  set :protection, false # From original TDD setup
  set :static, false     # Disable static file serving in test to isolate dynamic routes
  set :public_folder, File.expand_path('non_existent_public_folder_for_test', __dir__) # Ensure no static serving from project root
end

TMP_DIR = File.expand_path('tmp', __dir__)
FileUtils.mkdir_p(TMP_DIR)

helpers do
  # Create (or retrieve) a unique working directory for this session
  def session_dir
    if ENV['RACK_ENV'] == 'test'
      session[:uid] = "test_fixture_uid" # Always use this fixed, short ID in tests
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
  # Ensure an image was uploaded
  unless params[:image] &&
         (tempfile = params[:image][:tempfile]) &&
         (filename = params[:image][:filename])
    halt 400, "No image uploaded"
  end

  # Save uploaded file to session_dir as 'original.png'
  orig_path = File.join(session_dir, 'original.png')
  FileUtils.copy_file(tempfile.path, orig_path)

  # Parse options
  quant_interval = params[:quant_interval].to_i
  quant_interval = 1 if quant_interval < 1
  do_blur        = params[:blur] == "on"
  blur_radius    = params[:blur_radius].to_i
  blur_radius    = 1 if blur_radius < 1
  connectivity   = params[:connectivity].to_i
  connectivity   = [4,8].include?(connectivity) ? connectivity : 4
  min_blob_size  = params[:min_blob_size].to_i
  min_blob_size  = 0 if min_blob_size < 0

  # Load original via Impressionist, perform recolor, but also extract labels
  img = Impressionist.send(:load_image, orig_path)
  # If blur, apply
  work_img = do_blur ? Impressionist.send(:box_blur, img, blur_radius) : img

  # Quantize and label
  width  = work_img.width
  height = work_img.height
  quantized = Array.new(height) { Array.new(width, 0) }
  height.times do |y|
    (0...width).each do |x|
      pixel = work_img[x,y]
      r = ChunkyPNG::Color.r(pixel)
      g = ChunkyPNG::Color.g(pixel)
      b = ChunkyPNG::Color.b(pixel)
      rq = (r / quant_interval) * quant_interval
      gq = (g / quant_interval) * quant_interval
      bq = (b / quant_interval) * quant_interval
      quantized[y][x] = (rq << 16) | (gq << 8) | bq
    end
  end

  labels, blob_count = Impressionist.send(
    :connected_components,
    quantized, width, height, connectivity
  )

  # Merge small blobs if needed
  if min_blob_size > 0
    blob_sizes = Array.new(blob_count+1, 0)
    height.times { |y| (0...width).each { |x| blob_sizes[ labels[y][x] ] += 1 } }
    small_blobs = blob_sizes.each_index.select { |bid| bid != 0 && blob_sizes[bid] < min_blob_size }.to_set
    unless small_blobs.empty?
      labels = Impressionist.send(
        :merge_small_blobs,
        labels, quantized, width, height, small_blobs, connectivity
      )
    end
    # Relabel contiguous
    labels, blob_count = Impressionist.send(
      :relabel_contiguous,
      labels, width, height
    )
  end

  # Compute average colors and produce recolored image
  sums   = Array.new(blob_count + 1) { [0,0,0] }
  counts = Array.new(blob_count + 1, 0)
  height.times do |y|
    (0...width).each do |x|
      bid = labels[y][x]
      pixel = img[x,y] # Use original image for averaging colors
      sums[bid][0] += ChunkyPNG::Color.r(pixel)
      sums[bid][1] += ChunkyPNG::Color.g(pixel)
      sums[bid][2] += ChunkyPNG::Color.b(pixel)
      counts[bid] += 1
    end
  end

  avg_color = Array.new(blob_count + 1, 0)
  (1..blob_count).each do |bid|
    count = counts[bid]
    if count > 0
      r_avg = (sums[bid][0] / count.to_f).round
      g_avg = (sums[bid][1] / count.to_f).round
      b_avg = (sums[bid][2] / count.to_f).round
    else
      r_avg, g_avg, b_avg = 0, 0, 0 # Should not happen for valid bids
    end
    avg_color[bid] = ChunkyPNG::Color.rgba(r_avg, g_avg, b_avg, 255)
  end

  step1_img = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::WHITE)
  height.times do |y|
    (0...width).each do |x|
      bid = labels[y][x]
      step1_img[x,y] = avg_color[bid] # Use avg_color[0] for background if necessary
    end
  end

  # Save recolored image and labels
  step1_img.save(path_step1_png)
  save_labels(labels)

  # Render Step 2 page
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
  # Load labels
  labels = load_labels
  height = labels.size
  width  = labels.first.size

  # Parse options
  junction_conn = params[:junction_conn].to_i
  junction_conn = [4,8].include?(junction_conn) ? junction_conn : 8
  path_conn = params[:path_conn].to_i
  path_conn = [4,8].include?(path_conn) ? path_conn : 8
  skeletonize = params[:skeletonize] == 'on'
  simplify_tol = params[:simplify_tol].to_f

  # Extract graph
  result = BlobGraph.extract_from_labels(labels, {
    junction_conn:  junction_conn,
    path_conn:      path_conn,
    skeletonize:    skeletonize,
    simplify_tol:   simplify_tol
  })

  vertices = result[:vertices]
  edges    = result[:edges]
  detailed = result[:detailed_edges]

  step2_svg = ""
  if vertices.empty?
    step2_svg = '<svg width="100" height="100"><text x="10" y="20">No graph generated (no vertices).</text></svg>'
    # Also, ensure edges and detailed_edges are empty if vertices is empty, for consistency for QuiltGraph
    edges = []
    detailed = [] # Though not directly used by QuiltGraph, good to keep consistent
  else
    # Render straight-line graph as SVG
    # Compute viewBox from vertex coords
    xs = vertices.values.map { |(x,_)| x }
    ys = vertices.values.map { |(_,y)| y }
    min_x, max_x = xs.minmax
    min_y, max_y = ys.minmax
    pad = 10.0
    vb_x = min_x - pad
    vb_y = min_y - pad
    vb_w = (max_x.to_f - min_x.to_f) + 2*pad # Ensure float arithmetic
    vb_h = (max_y.to_f - min_y.to_f) + 2*pad # Ensure float arithmetic
    vb_w = pad * 2 if vb_w <= 0 # Handle cases with one or collinear points
    vb_h = pad * 2 if vb_h <= 0


    svg_lines = []
    svg_lines << '<?xml version="1.0" encoding="UTF-8"?>'
    svg_lines << "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"#{vb_x} #{vb_y} #{vb_w} #{vb_h}\" width=\"100%\" height=\"100%\">"
    # Draw edges (straight)
    edges.each do |(j1,j2)|
      # Ensure vertices for edges exist to prevent errors if graph is inconsistent
      next unless vertices[j1] && vertices[j2]
      x1,y1 = vertices[j1]
      x2,y2 = vertices[j2]
      svg_lines << "  <line x1=\"#{x1}\" y1=\"#{y1}\" x2=\"#{x2}\" y2=\"#{y2}\" stroke=\"blue\" stroke-width=\"0.5\" />"
    end
    # Draw vertices
    vertices.each do |j, (x,y)|
      svg_lines << "  <circle cx=\"#{x}\" cy=\"#{y}\" r=\"2\" fill=\"red\" />"
    end
    svg_lines << "</svg>"
    step2_svg = svg_lines.join("\n")
  end

  # Save SVG to file (even if it's the "No graph" message)
  File.write(path_step2_svg, step2_svg)

  # Store result (vertices & edges) in session for step3
  session[:vertices] = vertices
  session[:edges]    = edges
  session[:detailed] = detailed # Storing this though not used by QuiltGraph directly

  # Render Step 3 page
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
        <!-- No options exposed currently, using defaults for QuiltGraph -->
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
  # Load graph from session
  vertices = session[:vertices]
  edges    = session[:edges]
  # Detailed edges could be used for nicer rendering but we use straight-line here

  # Build QuiltGraph data structure: { vertices: {id=>[x,y]}, edges: [[u,v],...] }
  graph = { vertices: vertices, edges: edges }

  # Smooth and validate
  quilt_graph = QuiltGraph.correct_quilt(graph) # This modifies graph in-place

  # Export final quilt‐legal SVG
  final_svg = QuiltGraph.graph_to_svg_string(quilt_graph)
  File.write(path_final_svg, final_svg)

  # Render final page
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
# Serve tmp directory statically under /tmp
set :static, true
set :public_folder, File.dirname(__FILE__) # Serve from project root

# Because we saved intermediate files in TMP_DIR/session_id,
# we create a route to serve them under /tmp/<session_id>/*
# This allows <img src="/tmp/..."> to work
get '/tmp/:sid/:file' do |sid, file|
  # Basic sanitization first
  safe_sid = sid.gsub(/[^a-zA-Z0-9_-]/, "")

  # Check for malicious patterns in 'file' parameter early
  # If 'file' contains '..' or starts with '/', it's suspicious.
  if file.include?('..') || file.start_with?('/')
    error 404, "Invalid path due to '..' or leading '/'." # Changed halt to error
  end

  # Further sanitize 'file' after the '..' check
  safe_file = file.gsub(/[^a-zA-Z0-9_.-]/, "")

  # If sanitization changed anything (e.g. removed other bad chars), halt.
  # This also catches cases where `file` was different from `safe_file` due to `../` being stripped by earlier logic if we kept it.
  halt 404, "Invalid characters in path" if safe_sid != sid || safe_file != file

  path = File.join(TMP_DIR, safe_sid, safe_file)

  # Final security check: ensure the real path is still within TMP_DIR
  # File.realpath resolves symlinks and '..'
  begin
    # Ensure path is not empty and components are reasonable
    halt 404, "Invalid path components" if safe_sid.empty? || safe_file.empty?

    # Check existence and that the real path is within TMP_DIR
    if File.exist?(path) && File.realpath(path).start_with?(File.realpath(TMP_DIR))
      send_file path
    else
      halt 404, "File not found or access denied"
    end
  rescue Errno::ENOENT # Can be raised by File.realpath if path is bad during resolution
    halt 404, "File not found during path resolution"
  end
end
