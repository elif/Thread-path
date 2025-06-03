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
