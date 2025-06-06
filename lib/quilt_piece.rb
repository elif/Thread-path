module QuiltGraph
  class QuiltPiece
    attr_reader :id, :vertices, :edges, :color

    def initialize(id:, vertices:, edges:, color:)
      @id = id
      @vertices = vertices
      @edges = edges
      @color = color
    end

    # Method to generate SVG for this piece
    # It will need access to the main graph's vertex coordinates
    def to_svg(all_graph_vertices)
      return "<svg />" if @vertices.empty? || @edges.empty?

      # Determine bounding box for this piece
      piece_coords = @vertices.map { |v_id| all_graph_vertices[v_id] }.compact
      return "<svg />" if piece_coords.empty?

      xs = piece_coords.map { |pt| pt[0] }
      ys = piece_coords.map { |pt| pt[1] }
      min_x, max_x = xs.minmax
      min_y, max_y = ys.minmax

      min_x ||= 0; max_x ||= 0; min_y ||= 0; max_y ||= 0;

      pad = 10.0
      vb_x      = min_x - pad
      vb_y      = min_y - pad
      vb_width  = (max_x - min_x) + 2 * pad
      vb_height = (max_y - min_y) + 2 * pad
      vb_width = pad * 2 if vb_width.abs < 1e-6 # Ensure non-zero width/height
      vb_height = pad * 2 if vb_height.abs < 1e-6


      svg_lines = []
      svg_lines << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      svg_lines << "<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" width=\"100%\" height=\"100%\" viewBox=\"#{vb_x} #{vb_y} #{vb_width} #{vb_height}\">"
      # Style for the piece, using its color
      # Convert color array [r,g,b] to "rgb(r,g,b)" string if necessary
      fill_color_string = @color.is_a?(Array) ? "rgb(#{@color.join(',')})" : "gray" # Default to gray if color format is unexpected
      svg_lines << "  <style>polygon { fill: #{fill_color_string}; stroke: black; stroke-width: 1; }</style>"

      # Create a polygon from the face's vertices
      points_str = piece_coords.map { |pt| "#{pt[0]},#{pt[1]}" }.join(" ")
      svg_lines << "  <polygon points=\"#{points_str}\" />"

      svg_lines << "</svg>"
      svg_lines.join("\n")
    end
  end
end
