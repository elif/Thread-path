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
