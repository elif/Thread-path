# Sinatra TDD Project

This is a simple Sinatra project set up for Test-Driven Development using RSpec.

## Ruby Version

- Ruby 3.1.2 (Managed by `.ruby-version` and `.tool-versions`)

## Setup

1.  **Install Ruby:**
    Make sure you have Ruby 3.1.2 installed. You can use a version manager like RVM or asdf:
    - RVM: `rvm install 3.1.2 && rvm use 3.1.2`
    - asdf: `asdf install ruby 3.1.2 && asdf global ruby 3.1.2`

2.  **Install Bundler:**
    If you don't have Bundler installed:
    `gem install bundler`

3.  **Install Dependencies:**
    Navigate to the project directory and run:
    `bundle install`

## Running Tests

### RSpec
To run all tests:
`bundle exec rspec`

Or using Rake:
`bundle exec rake`

### Guard
To automatically run tests when files change:
`bundle exec guard`

## Application
The main application file is `app.rb`.

The Sinatra web application guides the user through the following process:
1.  **Upload PNG and Recolor**: Upload a PNG image and apply “impressionist” blob recoloring using the `Impressionist` library.
2.  **Extract Blob Graph**: Extract a blob-adjacency graph from the labeled image using the `BlobGraph` library and render it as an SVG.
3.  **Smooth and Validate Graph**: Smooth and validate the graph into a quilt-legal planar graph using the `QuiltGraph` library and render the final SVG.

At each step, the user can see the intermediate result and adjust options before proceeding to the next stage.

The application uses a `tmp/` directory to store per-session subfolders. These subfolders contain intermediate files generated during the process, such as images, label data, and SVGs.

## Image Processing Pipeline

The application includes a multi-stage image processing pipeline accessible via the `POST /upload` endpoint.

### Data Flow

1.  An image file is uploaded to `POST /upload` along with parameters for each processing stage (e.g., `s1p1`, `s1p2`, `s2p1`, etc.).
2.  The initial image data (currently represented by its filename) is passed to `Stage1Processor`.
3.  The output of `Stage1Processor` is passed as input to `Stage2Processor`, and so on, through `Stage3Processor` and `Stage4Processor`.
4.  Each stage processor (`lib/stage_N_processor.rb`) currently contains placeholder logic that acknowledges the data and parameters it received.
5.  The final output from `Stage4Processor` (which will eventually be SVG data) is returned as the HTTP response.

### Processing Modules

The pipeline consists of the following placeholder modules found in the `lib/` directory:

-   `stage_1_processor.rb`: Placeholder for the first stage of image processing.
-   `stage_2_processor.rb`: Placeholder for the second stage.
-   `stage_3_processor.rb`: Placeholder for the third stage.
-   `stage_4_processor.rb`: Placeholder for the fourth stage, intended to produce the final SVG output.

Each module's behavior and interactions are tested via RSpec tests in `spec/lib/` and `spec/upload_spec.rb`.

### Image Processing Library: Impressionist
# lib/impressionist.rb
#
# A pure-Ruby library for “impressionist” blob detection and recoloring of PNG images,
# now with enhanced control over blob size and noise.
#
# Features:
#   • Optional box-blur to reduce noise.
#   • Fixed-interval color quantization.
#   • Two-pass connected-component labeling (4- or 8-connectivity).
#   • Optional filtering of small blobs (min_blob_size).
#   • Computes average RGB per blob and recolors entire blob to its average hue.
#   • Clean API: load, process, and save.
#
# Dependencies:
#   gem install chunky_png
#
# Usage Example:
```ruby
#   require_relative 'lib/impressionist'
#
#   options = {
#     quant_interval: 16,
#     blur:           true,
#     blur_radius:    1,
#     connectivity:   4,
#     min_blob_size:  50
#   }
#
#   # Recolor input.png → output.png
#   Impressionist.recolor('input.png', 'output.png', options)
#
#   # Or get a Hash {image:, labels:, blob_count:} back instead of saving directly:
#   result = Impressionist.process('input.png', options)
#   result[:image].save('out.png')
```

### Graph Extraction Library: BlobGraph
# lib/blob_graph.rb
#
# A pure-Ruby library for extracting a blob-adjacency graph from a labeled image,
# designed to integrate smoothly with the Sinatra quilting app and avoid redundant work.
#
# Assumptions:
#  • You have already run a connected-component labeling (from Impressionist) to get a 2D labels array.
#  • labels[y][x] is an integer blob ID (1..N) or 0 for background.
#
# Features:
#   2.1 Detect junction pixels (where ≥3 blobs meet) and cluster them into junction centroids.
#   2.2 Build adjacency lists and border-pixel sets for each pair of adjacent blobs.
#   2.3 Map each border to its touching junctions to create straight-line edges (j1→j2).
#   2.4 Optionally run Zhang-Suen thinning on each border, extract shortest path between junctions,
#       and simplify via Ramer–Douglas–Peucker.
#
# Public API:
#   BlobGraph.extract_from_labels(labels, options) ⇒ { vertices:, edges:, detailed_edges: }
#
#   • labels:  2D Array [height][width] of integer blob IDs (0 = background).
#   • options: Hash (all optional):
#       :junction_conn   (4 or 8; default: 8)  # connectivity when clustering junction pixels
#       :path_conn       (4 or 8; default: 8)  # connectivity when BFS on skeleton
#       :skeletonize     (Boolean; default: true)
#       :simplify_tol    (Float; default: 2.0)  # tolerance for RDP simplification
#
# Returns:
#   {
#     vertices:       { j_id => [cx, cy], ... },
#     edges:          [ [j1, j2], ... ],               # straight-line connectivity
#     detailed_edges: [ { endpoints: [j1, j2], polyline: [[x,y],...] }, ... ]
#   }
#
# Dependencies: None beyond Ruby stdlib.
#
# Example Usage:
```ruby
#   require_relative 'lib/blob_graph'
#
#   # Suppose `labels` is produced by Impressionist.connected_components
#   result = BlobGraph.extract_from_labels(labels, {
#     junction_conn: 8,
#     path_conn:     8,
#     skeletonize:   true,
#     simplify_tol:  2.0
#   })
#
#   vertices       = result[:vertices]        # { j_id => [cx,cy], ... }
#   edges          = result[:edges]           # [ [j1,j2], ... ]
#   detailed_edges = result[:detailed_edges]  # [ { endpoints:[j1,j2], polyline:[[x,y],...] }, ... ]
```

### Quilt Graph Library: QuiltGraph
# lib/quilt_graph.rb
#
# Module containing all graph logic for parsing an SVG into a quilt-graph,
# correcting it into a viable quilt diagram, and exporting back to SVG.
#
# Since the Sinatra app already has a planar graph (vertices & edges),
# we only need correct_quilt and graph_to_svg_string here.
#
# Dependencies: None beyond Ruby stdlib.
#
