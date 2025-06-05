# Sinatra TDD Project

This is a simple Sinatra project set up for Test-Driven Development using RSpec.

## Project Overview

This Sinatra web application guides users through a three-step image processing workflow:

1.  **Upload and Recolor**: Users upload a PNG image, which is then processed to apply an "impressionist" blob recoloring effect.
2.  **Extract Blob Graph**: A blob-adjacency graph is extracted from the recolored image and rendered as an SVG.
3.  **Smooth and Validate Graph**: The graph is smoothed and validated to ensure it forms a quilt-legal planar graph, with the final result also rendered as an SVG.

At each step, users can view the intermediate visual result and adjust processing options before continuing to the next stage.

The core application logic is found in `app.rb`. During processing, intermediate files (images, label data, SVGs) are stored in per-session subfolders within a `tmp/` directory.

## Getting Started

### Ruby Version

- Ruby 3.1.2 (This version is managed by `.ruby-version` and `.tool-versions` files in the repository).

### Setup

1.  **Install Ruby:**
    Ensure Ruby 3.1.2 is installed. You can use a version manager like RVM or asdf:
    - RVM:
      ```bash
      rvm install 3.1.2 && rvm use 3.1.2
      ```
    - asdf:
      ```bash
      asdf install ruby 3.1.2 && asdf global ruby 3.1.2
      ```

2.  **Install Bundler:**
    If Bundler is not already installed:
    ```bash
    gem install bundler
    ```

3.  **Install Dependencies:**
    Navigate to the project directory and run:
    ```bash
    bundle install
    ```

### Running Tests

#### RSpec
To run all tests:
```bash
bundle exec rspec
```
Alternatively, using Rake:
```bash
bundle exec rake
```

#### Guard
To automatically run tests when files change:
```bash
bundle exec guard
```

## Libraries

### Impressionist

A pure-Ruby library for "impressionist" blob detection and recoloring of PNG images. It offers features such as:
- Noise reduction (optional box-blur).
- Fixed-interval color quantization.
- Two-pass connected-component labeling (4- or 8-connectivity).
- Optional filtering of small blobs.
- Calculation of average RGB per blob and recoloring of the entire blob to its average hue.

For more details, see `lib/impressionist.rb`.

### BlobGraph

A pure-Ruby library for extracting a blob-adjacency graph from a labeled image. Its key functions include:
- Detecting junction pixels (where three or more blobs meet) and clustering them into centroids.
- Building adjacency lists and border-pixel sets for each pair of adjacent blobs.
- Mapping each border to its touching junctions to create straight-line graph edges.
- Optionally, thinning borders (Zhang-Suen) and simplifying paths (Ramer–Douglas–Peucker).

For more details, see `lib/blob_graph.rb`.

### QuiltGraph

A Ruby module providing graph logic to:
- Parse an SVG into a quilt-graph structure.
- Correct the graph into a viable quilt diagram.
- Export the corrected graph back to an SVG format.

For more details, see `lib/quilt_graph.rb`.
