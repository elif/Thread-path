module QuiltGraph
  class QuiltPiece
    attr_reader :id, :vertices, :edges, :color

    def initialize(id:, vertices:, edges:, color:)
      @id = id
      @vertices = vertices
      @edges = edges
      @color = color
    end

    # Method to generate SVG elements (polygon and lines) for this piece
    # It will need access to the main graph's vertex coordinates
    def to_svg(all_graph_vertices)
      return "" if @vertices.empty? # No vertices, no piece

      piece_coords = @vertices.map { |v_id| all_graph_vertices[v_id] }.compact
      return "" if piece_coords.empty? || piece_coords.length < 3 # Not enough points for a polygon

      svg_elements = []

      # Convert color array [r,g,b] to "rgb(r,g,b)" string if necessary
      fill_color_string = @color.is_a?(Array) ? "rgb(#{@color.join(',')})" : "gray" # Default to gray

      # Create a polygon from the face's vertices
      # Style for fill is applied inline; stroke and stroke-width will be handled by parent SVG style
      points_str = piece_coords.map { |pt| "#{pt[0]},#{pt[1]}" }.join(" ")
      svg_elements << "  <polygon points=\"#{points_str}\" fill=\"#{fill_color_string}\" />"

      # Add edges as lines
      # Stroke and stroke-width will be handled by parent SVG style for 'line'
      @edges.each do |v1_id, v2_id|
        pt1 = all_graph_vertices[v1_id]
        pt2 = all_graph_vertices[v2_id]

        if pt1 && pt2
          # Ensure points are numbers before creating line, protects against nil or non-numeric coords
          if pt1.all? { |c| c.is_a?(Numeric) } && pt2.all? { |c| c.is_a?(Numeric) }
            svg_elements << "  <line x1=\"#{pt1[0]}\" y1=\"#{pt1[1]}\" x2=\"#{pt2[0]}\" y2=\"#{pt2[1]}\" />"
          else
            # Optionally log or handle malformed point data
            # $stderr.puts "Warning: Skipping edge due to invalid coordinate data for piece #{@id}"
          end
        else
          # Optionally log or handle missing vertex data
          # $stderr.puts "Warning: Skipping edge due to missing vertex data for piece #{@id}"
        end
      end

      svg_elements.join("\n")
    end
  end
end
