require 'sinatra'

configure :test do
  set :protection, false
end

get '/' do
  'Hello World!'
end
