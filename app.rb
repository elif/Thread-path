require 'sinatra'
require 'securerandom'
require 'fileutils'
require 'json'
require_relative 'lib/impressionist'
require_relative 'lib/blob_graph'
require_relative 'lib/quilt_graph'
require_relative 'lib/palette_manager'

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

  def rgb_distance(color1, color2)
    return Float::INFINITY if color1.nil? || color2.nil? # Should not happen with proper checks

    r1 = ChunkyPNG::Color.r(color1)
    g1 = ChunkyPNG::Color.g(color1)
    b1 = ChunkyPNG::Color.b(color1)

    r2 = ChunkyPNG::Color.r(color2)
    g2 = ChunkyPNG::Color.g(color2)
    b2 = ChunkyPNG::Color.b(color2)

    Math.sqrt((r1 - r2)**2 + (g1 - g2)**2 + (b1 - b2)**2).to_f
  end
end

# ----------------------------------------------------------------------------
# POST '/palette_upload' – Upload palette image
post '/palette_upload' do
  content_type :json

  unless params[:palette_image] &&
         (tempfile = params[:palette_image][:tempfile])
    status 400
    return { status: 'error', message: 'No palette_image uploaded' }.to_json
  end

  s_dir = session_dir
  # Ensure session_dir itself doesn't make it into the publicly accessible path
  # if we decide to use part of s_dir in the response.
  # For now, we use the full path as per requirements, but this might be a security concern
  # if TMP_DIR is directly served. The /tmp/:sid/:file route seems to handle this safely.

  destination_filename = 'palette_source.png'
  destination_path = File.join(s_dir, destination_filename)

  begin
    FileUtils.copy_file(tempfile.path, destination_path)
    # The requirement is to return the full path, which includes the session ID.
    # Example: /tmp/session_id/palette_source.png
    # The actual TMP_DIR is not part of the URL directly, but the /tmp/:sid/:file route constructs it.
    # So, the image_path should align with how that route would serve it.
    image_path_for_client = "/tmp/#{session[:uid]}/#{destination_filename}"

    # Load the image with ChunkyPNG
    palette_image_obj = ChunkyPNG::Image.from_file(destination_path)

    # Process the image with Impressionist
    impressionist_options = {
      quant_interval: 32,
      blur: true,
      blur_radius: 1,
      min_blob_size: 20, # Lowered min_blob_size for Impressionist
      implementation: :chunky_png
    }
    impressionist_result = Impressionist.process(palette_image_obj, impressionist_options)

    # Refined Palette Extraction Logic
    raw_avg_colors = impressionist_result[:avg_colors] # 1-indexed, 0 is placeholder
    blob_sizes_map = impressionist_result[:blob_sizes] # 1-indexed
    blob_count = impressionist_result[:blob_count]

    max_palette_size = 10
    color_similarity_threshold = 50 # Max RGB distance to be considered "different"
    min_candidate_blob_size = 10    # Absolute minimum size for a blob to be considered

    candidates = []
    if raw_avg_colors && blob_sizes_map && blob_count > 0
      (1..blob_count).each do |blob_id|
        color = raw_avg_colors[blob_id]
        size = blob_sizes_map[blob_id]
        # Ensure color and size are valid, and color is not fully transparent
        if color && size && !(ChunkyPNG::Color.a(color) == 0 && color != ChunkyPNG::Color::TRANSPARENT) && color != ChunkyPNG::Color::TRANSPARENT
          candidates << { color: color, size: size, id: blob_id }
        end
      end
    end

    # Filter out initial tiny noise
    candidates.reject! { |c| c[:size] < min_candidate_blob_size }

    # Sort candidates: primarily by size (descending)
    candidates.sort_by! { |c| -c[:size] }

    # Build final palette by iterative selection based on similarity
    final_palette_chunky_colors = []
    candidates.each do |candidate|
      is_too_similar = final_palette_chunky_colors.any? do |existing_color|
        rgb_distance(candidate[:color], existing_color) < color_similarity_threshold
      end

      unless is_too_similar
        final_palette_chunky_colors << candidate[:color]
      end
      break if final_palette_chunky_colors.length >= max_palette_size
    end

    # Convert final palette to hex strings for JSON response
    output_hex_colors = final_palette_chunky_colors.map do |color|
      ChunkyPNG::Color.to_hex(color, false) # false for #RRGGBB
    end

    # Integrate with PaletteManager (using the new final hex colors)
    if output_hex_colors.any?
      palette_manager = PaletteManager.new
      output_hex_colors.each do |hex_string|
        color_object = ChunkyPNG::Color.from_hex(hex_string)
        palette_manager.add_to_active_palette(color_object)
      end
      # palette_manager instance is populated.
    end

    {
      status: 'success',
      message: 'Colors extracted',
      image_path: image_path_for_client,
      colors: output_hex_colors # Use the new refined list
    }.to_json
  rescue StandardError => e
    logger.error "Error in /palette_upload: #{e.message}\n#{e.backtrace.join("\n")}"
    status 500
    { status: 'error', message: "Failed to save or process image: #{e.message}" }.to_json
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
        /* Styles for Palette Tool */
        #paletteDropZone {
          border: 2px dashed #ccc;
          padding: 20px;
          margin-top: 20px;
          margin-bottom: 10px;
          text-align: center;
          background-color: #f9f9f9;
          cursor: pointer;
        }
        #paletteDropZone.dragover {
          background-color: #e9e9e9;
          border-color: #aaa;
        }
        #paletteSwatches {
          margin-top: 10px;
          display: flex;
          flex-wrap: wrap;
          min-height: 50px; /* So it's visible even when empty */
          padding: 5px;
          border: 1px solid #eee;
        }
        .swatch {
          width: 50px;
          height: 50px;
          margin: 5px;
          border: 1px solid #333;
          display: inline-block;
        }
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

      <hr style="margin-top: 30px; margin-bottom: 30px;">

      <h2>Palette Tool: Extract Colors from Image</h2>
      <div id="paletteDropZone">
        <p>Drag &amp; Drop an image here to extract its palette, or click to select file.</p>
        <input type="file" id="paletteFileInput" accept="image/*" style="display: none;">
      </div>
      <div id="paletteSwatches">
        <!-- Color swatches will be added here by JavaScript -->
      </div>

    <script>
      document.addEventListener('DOMContentLoaded', () => {
        const dropZone = document.getElementById('paletteDropZone');
        const swatchesDisplay = document.getElementById('paletteSwatches');
        const fileInput = document.getElementById('paletteFileInput');

        // Trigger hidden file input when drop zone is clicked
        dropZone.addEventListener('click', () => {
          fileInput.click();
        });

        fileInput.addEventListener('change', (event) => {
          const files = event.target.files;
          if (files.length > 0) {
            handleFile(files[0]);
          }
        });

        // Drag and Drop events
        dropZone.addEventListener('dragenter', (event) => {
          event.preventDefault();
          dropZone.classList.add('dragover');
        });

        dropZone.addEventListener('dragover', (event) => {
          event.preventDefault(); // Necessary to allow drop
          dropZone.classList.add('dragover');
        });

        dropZone.addEventListener('dragleave', (event) => {
          event.preventDefault();
          dropZone.classList.remove('dragover');
        });

        dropZone.addEventListener('dragend', (event) => { // Though 'dragleave' often suffices
          event.preventDefault();
          dropZone.classList.remove('dragover');
        });

        dropZone.addEventListener('drop', (event) => {
          event.preventDefault();
          dropZone.classList.remove('dragover');
          const files = event.dataTransfer.files;
          if (files.length > 0) {
            handleFile(files[0]);
          }
        });

        function handleFile(file) {
          if (!file.type.startsWith('image/')) {
            swatchesDisplay.innerHTML = '<p style="color: red;">Error: Only image files are allowed.</p>';
            return;
          }

          const formData = new FormData();
          formData.append('palette_image', file);

          swatchesDisplay.innerHTML = '<p>Loading colors...</p>';

          fetch('/palette_upload', {
            method: 'POST',
            body: formData
          })
          .then(response => {
            if (!response.ok) {
              // Try to get error message from JSON response if available
              return response.json().then(errData => {
                throw new Error(errData.message || `Server error: ${response.status}`);
              }).catch(() => { // Fallback if no JSON body or other parsing error
                throw new Error(`Server error: ${response.status} - ${response.statusText}`);
              });
            }
            return response.json();
          })
          .then(data => {
            swatchesDisplay.innerHTML = ''; // Clear loading message
            if (data.colors && data.colors.length > 0) {
              data.colors.forEach(hexColor => {
                const swatch = document.createElement('div');
                swatch.className = 'swatch';
                swatch.style.backgroundColor = hexColor;
                swatch.title = hexColor; // Show hex on hover
                swatchesDisplay.appendChild(swatch);
              });
            } else {
              swatchesDisplay.innerHTML = '<p>No colors extracted or found.</p>';
            }
          })
          .catch(error => {
            console.error('Error uploading or processing palette image:', error);
            swatchesDisplay.innerHTML = `<p style="color: red;">Error: ${error.message}</p>`;
          });
        }
      });
    </script>
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
