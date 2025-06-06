require 'spec_helper'
require 'quilt_piece' # Assuming this is how QuiltPiece is loaded by spec_helper or directly

RSpec.describe QuiltGraph::QuiltPiece do
  describe '#initialize' do
    it 'assigns id, vertices, edges, and color' do
      vertices = [:V1, :V2, :V3]
      edges = [[:V1, :V2], [:V2, :V3], [:V3, :V1]]
      color = [255, 0, 0] # Red
      piece = QuiltGraph::QuiltPiece.new(id: :F1, vertices: vertices, edges: edges, color: color)

      expect(piece.id).to eq(:F1)
      expect(piece.vertices).to eq(vertices)
      expect(piece.edges).to eq(edges)
      expect(piece.color).to eq(color)
    end
  end

  describe '#to_svg' do
    let(:all_graph_vertices) do
      {
        V1: [0, 0],
        V2: [100, 0],
        V3: [50, 50],
        V4: [100, 100], # For a potential quad
        V5: [0, 100]  # For a potential quad
      }
    end

    context 'with a triangular piece' do
      let(:tri_vertices) { [:V1, :V2, :V3] }
      # Edges for a piece are typically derived and ordered, e.g. from a walk around the face
      let(:tri_edges) { [[:V1, :V2], [:V2, :V3], [:V3, :V1]] }
      let(:tri_color) { [0, 255, 0] } # Green
      let(:triangle_piece) do
        QuiltGraph::QuiltPiece.new(id: :F2, vertices: tri_vertices, edges: tri_edges, color: tri_color)
      end

      it 'generates a valid SVG string' do
        svg = triangle_piece.to_svg(all_graph_vertices)
        expect(svg).to include('<svg')
        expect(svg).to include('</svg>')
        expect(svg).to include('<?xml version="1.0" encoding="UTF-8"?>')
        expect(svg).to include('xmlns="http://www.w3.org/2000/svg"')
      end

      it 'contains a polygon with correct points' do
        svg = triangle_piece.to_svg(all_graph_vertices)
        # Order of points should match the order in tri_vertices
        expect(svg).to include('<polygon points="0,0 100,0 50,50"')
      end

      it 'sets the correct fill color' do
        svg = triangle_piece.to_svg(all_graph_vertices)
        expect(svg).to include('fill: rgb(0,255,0);')
      end

      it 'includes style for polygon' do
        svg = triangle_piece.to_svg(all_graph_vertices)
        expect(svg).to include('<style>polygon { fill: rgb(0,255,0); stroke: black; stroke-width: 1; }</style>')
      end

      it 'calculates viewBox correctly' do
        svg = triangle_piece.to_svg(all_graph_vertices)
        # min_x=0, max_x=100, min_y=0, max_y=50. pad=10
        # vb_x = 0-10 = -10
        # vb_y = 0-10 = -10
        # vb_width = (100-0) + 2*10 = 120
        # vb_height = (50-0) + 2*10 = 70
        expect(svg).to include('viewBox="-10.0 -10.0 120.0 70.0"')
      end
    end

    context 'with a rectangular piece' do
      let(:rect_vertices) { [:V1, :V2, :V4, :V5] } # 0,0 -> 100,0 -> 100,100 -> 0,100
      let(:rect_edges) { [[:V1,:V2], [:V2,:V4], [:V4,:V5], [:V5,:V1]] }
      let(:rect_color) { "blue" } # Test with string color
      let(:rectangle_piece) do
        QuiltGraph::QuiltPiece.new(id: :F3, vertices: rect_vertices, edges: rect_edges, color: rect_color)
      end

      it 'generates a valid SVG string' do
        svg = rectangle_piece.to_svg(all_graph_vertices)
        expect(svg).to include('<svg')
        expect(svg).to include('</svg>')
      end

      it 'contains a polygon with correct points' do
        svg = rectangle_piece.to_svg(all_graph_vertices)
        expect(svg).to include('<polygon points="0,0 100,0 100,100 0,100"')
      end

      it 'sets the correct fill color when color is a string' do
        svg = rectangle_piece.to_svg(all_graph_vertices)
        # The QuiltPiece code defaults to "gray" if color is not an array.
        # This test should reflect the actual behavior.
        # Let's assume the desired behavior for a string color is to use it directly if it's a valid SVG color name.
        # The current implementation defaults to gray for non-array.
        # We should adjust the test if QuiltPiece is updated to handle string colors directly.
        # For now, based on current QuiltPiece:
        expect(svg).to include('fill: gray;') # or expect(svg).to include('fill: blue;') if QuiltPiece handles it.
                                                # Based on current code: @color.is_a?(Array) ? "rgb(#{@color.join(',')})" : "gray"
                                                # So, if 'blue' (a string) is passed, it will result in gray.
                                                # This highlights a potential point of improvement in QuiltPiece or a clarification in requirements.
                                                # For this test, I will stick to the current implementation detail.
      end
    end

    context 'with empty vertices' do
      let(:empty_piece) { QuiltGraph::QuiltPiece.new(id: :F4, vertices: [], edges: [], color: [0,0,0]) }
      it 'returns a simple svg tag' do
        expect(empty_piece.to_svg(all_graph_vertices)).to eq("<svg />")
      end
    end

    context 'with empty edges (but present vertices)' do
      let(:no_edges_piece) { QuiltGraph::QuiltPiece.new(id: :F5, vertices: [:V1, :V2], edges: [], color: [0,0,0]) }
      it 'returns a simple svg tag' do
        # Current implementation of to_svg checks @vertices.empty? || @edges.empty?
        expect(no_edges_piece.to_svg(all_graph_vertices)).to eq("<svg />")
      end
    end

    context 'with vertices not in all_graph_vertices' do
      # Only V6 is not in all_graph_vertices, V1 is.
      let(:some_invalid_piece) { QuiltGraph::QuiltPiece.new(id: :F6, vertices: [:V1, :V6], edges: [[:V1, :V6]], color: [0,0,0])}
      it 'generates SVG using only valid vertices' do
        svg = some_invalid_piece.to_svg(all_graph_vertices)
        # piece_coords will be [[0,0]] for V1. V6 will be nil and compacted out.
        # This will result in a polygon with one point.
        expect(svg).to include('<polygon points="0,0"')
        # xs=[0], ys=[0]. min_x=0, max_x=0, min_y=0, max_y=0.
        # vb_width and vb_height would be 2*pad = 20 if not for the min_x||=0 etc.
        # Since min/max are same, width/height are 0, then forced to 2*pad.
        # vb_x = 0 - 10 = -10
        # vb_y = 0 - 10 = -10
        # vb_width = 20
        # vb_height = 20
        expect(svg).to include('viewBox="-10.0 -10.0 20.0 20.0"')
      end
    end

    context 'with all vertices not in all_graph_vertices' do
      let(:all_invalid_piece) { QuiltGraph::QuiltPiece.new(id: :F7, vertices: [:V6, :V7], edges: [[:V6, :V7]], color: [0,0,0])}
      it 'returns a simple svg tag due to empty piece_coords' do
        # piece_coords will be empty after map and compact.
        expect(all_invalid_piece.to_svg(all_graph_vertices)).to eq("<svg />")
      end
    end

    context 'when color is nil' do
      let(:nil_color_piece) do
        QuiltGraph::QuiltPiece.new(id: :F8, vertices: [:V1, :V2, :V3], edges: [[:V1,:V2],[:V2,:V3],[:V3,:V1]], color: nil)
      end
      it 'defaults to gray fill color' do
        svg = nil_color_piece.to_svg(all_graph_vertices)
        expect(svg).to include('fill: gray;')
      end
    end

  end
end
