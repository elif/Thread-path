# Load necessary files
require_relative './lib/quilt_graph'
require_relative './lib/quilt_piece'

puts "Script starting..."

# 1. Define vertices
vertices = {
  v1: [10.0, 10.0],
  v2: [110.0, 10.0],
  v3: [110.0, 110.0],
  v4: [10.0, 110.0],
  v5: [160.0, 60.0] # Another vertex, perhaps for a second piece or as a standalone vertex
}
puts "Vertices defined."

# 2. Define faces (QuiltPiece objects)
# A square piece
piece1_edges = [[:v1, :v2], [:v2, :v3], [:v3, :v4], [:v4, :v1]]
face1_piece = QuiltGraph::QuiltPiece.new(
  id: :F1,
  vertices: [:v1, :v2, :v3, :v4], # Ordered vertices for polygon
  edges: piece1_edges.map { |e| e.sort }, # Edges for this piece, sorted for consistency
  color: [255, 0, 0] # Red
)
puts "Piece 1 defined."

# A triangular piece
piece2_edges = [[:v2, :v5], [:v5, :v3], [:v3, :v2]]
face2_piece = QuiltGraph::QuiltPiece.new(
  id: :F2,
  vertices: [:v2, :v5, :v3], # Ordered vertices for polygon
  edges: piece2_edges.map { |e| e.sort },
  color: [0, 255, 0] # Green
)
puts "Piece 2 defined."

# Collect all unique edges for the global graph[:edges] list if needed by any function
# For graph_to_svg_string, it primarily uses graph[:faces] and graph[:vertices]
# The direct drawing of edges from graph[:edges] was removed, so this might not be strictly necessary
# for the current version of graph_to_svg_string, but good for completeness.
all_edges = (piece1_edges + piece2_edges).map { |e| e.sort }.uniq
puts "All edges collected."

graph_data = {
  vertices: vertices,
  edges: all_edges, # Global edge list
  faces: {
    F1: face1_piece,
    F2: face2_piece
  }
  # No need for _next_id, _next_face_id, source_segmentation for this direct SVG test
}
puts "Graph data constructed."

# 3. Generate SVG
begin
  puts "Generating SVG string..."
  svg_string = QuiltGraph.graph_to_svg_string(graph_data)
  puts "SVG string generated."
  # 4. Print SVG
  puts "\nSVG OUTPUT START\n"
  puts svg_string
  puts "\nSVG OUTPUT END\n"
rescue => e
  puts "Error during SVG generation or script execution: #{e.message}"
  puts e.backtrace.join("\n")
end

puts "Script finished."
