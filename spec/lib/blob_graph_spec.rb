require 'spec_helper'
require 'blob_graph'
require 'set'

RSpec.describe BlobGraph do

  let(:labels_simple_junction) do
    [
      [1,2],
      [1,3]
    ]
  end

  let(:labels_cross) do
    [
      [1,1,0,2,2],
      [1,3,0,4,2],
      [5,5,0,6,6]
    ]
  end

  describe '.extract_from_labels' do
    context 'with simple_junction case' do
      it 'returns a hash with vertices, edges, and detailed_edges' do
        result = BlobGraph.extract_from_labels(labels_simple_junction)
        expect(result).to be_a(Hash)
        expect(result).to have_key(:vertices)
        expect(result).to have_key(:edges)
        expect(result).to have_key(:detailed_edges)
      end

      it 'identifies one junction for the simple_junction case' do
        result = BlobGraph.extract_from_labels(labels_simple_junction)
        expect(result[:vertices].size).to eq(1)
        expect(result[:vertices][1]).to eq([0.5, 0.5]) if result[:vertices].key?(1)
      end

      it 'produces no straight edges if only one junction is found' do
         result = BlobGraph.extract_from_labels(labels_simple_junction)
         expect(result[:edges]).to be_empty
      end
    end

    context 'with labels_cross (designed for multiple junctions)' do
      it 'processes it and expects multiple distinct junctions (vertices)' do
        result = BlobGraph.extract_from_labels(labels_cross, skeletonize: false)
        expect(result[:vertices].size).to be >= 2
        expect(result[:edges].size).to be >= 1
        result[:edges].each do |u,v|
          expect(result[:vertices]).to have_key(u)
          expect(result[:vertices]).to have_key(v)
        end
      end

      it 'produces detailed_edges when skeletonize is true and multiple junctions exist' do
        result_skel = BlobGraph.extract_from_labels(labels_cross, skeletonize: true, simplify_tol: 1.0)
        expect(result_skel[:detailed_edges]).not_to be_empty
        result_skel[:detailed_edges].each do |de|
          expect(de).to have_key(:endpoints)
          expect(de).to have_key(:polyline)
          expect(de[:endpoints].size).to eq(2)
          expect(de[:polyline].size).to be >= 2
          expect(result_skel[:vertices]).to have_key(de[:endpoints][0])
          expect(result_skel[:vertices]).to have_key(de[:endpoints][1])
        end
      end
    end
  end

  describe '.ccl_binary (private)' do
    let(:mask_2x2_all_true) { [[true, true], [true, true]] }
    let(:mask_2x2_diagonal) { [[true, false], [false, true]] } # T F
                                                              # F T
    let(:mask_disconnected_corners) { [[true, false, true], [false,true,false], [true,false,true]]}


    it 'labels a fully connected mask as one component (8-conn)' do
      labels, count = BlobGraph.send(:ccl_binary, mask_2x2_all_true, 2, 2, 8)
      expect(count).to eq(1)
      expect(labels).to eq([[1,1],[1,1]])
    end

    it 'labels a fully connected mask as one component (4-conn)' do
      labels, count = BlobGraph.send(:ccl_binary, mask_2x2_all_true, 2, 2, 4)
      expect(count).to eq(1)
      expect(labels).to eq([[1,1],[1,1]])
    end

    it 'labels a diagonal mask (TF,FT) as two components with 4-connectivity' do
      labels, count = BlobGraph.send(:ccl_binary, mask_2x2_diagonal, 2, 2, 4)
      expect(count).to eq(2)
      expect(labels[0][0]).not_to eq(0)
      expect(labels[1][1]).not_to eq(0)
      expect(labels[0][0]).not_to eq(labels[1][1])
      expect(labels[0][1]).to eq(0)
      expect(labels[1][0]).to eq(0)
    end

    it 'labels a diagonal mask (TF,FT) as ONE component with 8-connectivity' do # Corrected expectation
      labels, count = BlobGraph.send(:ccl_binary, mask_2x2_diagonal, 2, 2, 8)
      # With 8-connectivity, the two 'true' pixels in [[T,F],[F,T]] ARE connected through their corners
      # by the raster scan logic of typical CCL.
      # (0,0) is T. (1,1) is T. When processing (1,1), its NW neighbor (0,0) is T, so they are unioned.
      expect(count).to eq(1) # Changed from 2 to 1
      expect(labels[0][0]).not_to eq(0)
      expect(labels[1][1]).not_to eq(0)
      expect(labels[0][0]).to eq(labels[1][1]) # They should now have the same label
      expect(labels[0][1]).to eq(0)
      expect(labels[1][0]).to eq(0)
    end
  end

  describe '.zhang_suen_thin (private)' do
    it 'does not thin a 4x4 solid square (as expected for ZS)' do
      mask_4x4 = Array.new(4) { Array.new(4, true) }
      thinned = BlobGraph.send(:zhang_suen_thin, mask_4x4, 4, 4)
      original_true_count = mask_4x4.flatten.count(true)
      thinned_true_count = thinned.flatten.count(true)
      expect(thinned_true_count).to eq(original_true_count)
    end

    it 'produces a known skeleton for a simple line' do
        mask_3row_line = [
            [false,false,false,false],
            [false,true,true,false],
            [false,false,false,false]
        ]
        thinned_3row = BlobGraph.send(:zhang_suen_thin, mask_3row_line, 4, 3)
        expect(thinned_3row[1][1]).to be true
        expect(thinned_3row[1][2]).to be true
        expect(thinned_3row.flatten.count(true)).to eq(2)
    end
  end

  describe '.rdp (private)' do
    it 'does not simplify a straight line if tolerance is high' do
      points = [[0,0], [1,1], [2,2], [3,3]]
      simplified = BlobGraph.send(:rdp, points, 1.0)
      expect(simplified).to eq([[0,0], [3,3]])
    end

    it 'simplifies a slightly bent line' do
      points = [[0,0], [1,0.1], [2,0], [3,0]]
      simplified = BlobGraph.send(:rdp, points, 0.05)
      expect(simplified).to eq([[0,0], [1,0.1], [3,0]])
    end

    it 'returns endpoints if all points are within tolerance' do
      points = [[0,0], [1,0.01], [2, -0.01], [3,0]]
      simplified = BlobGraph.send(:rdp, points, 0.1)
      expect(simplified).to eq([[0,0], [3,0]])
    end

    it 'handles an empty list of points' do
      expect(BlobGraph.send(:rdp, [], 1.0)).to eq([])
    end

    it 'handles a list with one point' do
      expect(BlobGraph.send(:rdp, [[0,0]], 1.0)).to eq([[0,0]])
    end

    it 'handles a list with two points' do
      expect(BlobGraph.send(:rdp, [[0,0],[1,1]], 1.0)).to eq([[0,0],[1,1]])
    end
  end

  describe '.perpendicular_distance (private)' do
    it 'calculates distance from point to line segment' do
      dist = BlobGraph.send(:perpendicular_distance, [0,0], [2,0], [1,1])
      expect(dist).to be_within(1e-9).of(1.0)
      dist2 = BlobGraph.send(:perpendicular_distance, [0,0], [1,1], [0.5,0.5])
      expect(dist2).to be_within(1e-9).of(0.0)
      dist3 = BlobGraph.send(:perpendicular_distance, [0,0],[2,2],[0,1])
      expect(dist3).to be_within(1e-9).of(1.0/Math.sqrt(2))
    end

    it 'handles distance to a zero-length segment (p1=p2)' do
      dist = BlobGraph.send(:perpendicular_distance, [0,0], [0,0], [1,1])
      expect(dist).to eq(0.0)
    end
  end

  describe '.shortest_path_on_skel (private)' do
    let(:skel_3x3_line) do
      [
        [false, false, false],
        [true,  true,  true],
        [false, false, false]
      ]
    end
    it 'finds a straight path' do
      path = BlobGraph.send(:shortest_path_on_skel, skel_3x3_line, [0,1], [2,1], 3, 3, 4)
      expect(path).to eq([[0,1],[1,1],[2,1]])
    end

    it 'returns empty if no path (disconnected)' do
      skel_disconnected = [ [true, false, true] ]
      path = BlobGraph.send(:shortest_path_on_skel, skel_disconnected, [0,0], [2,0], 3, 1, 4)
      expect(path).to be_empty
    end

    it 'returns path of single point if start equals end' do
        path = BlobGraph.send(:shortest_path_on_skel, skel_3x3_line, [1,1], [1,1], 3,3,4)
        expect(path).to eq([[1,1]])
    end

    it 'returns empty if start or end point is not on skeleton' do
        path1 = BlobGraph.send(:shortest_path_on_skel, skel_3x3_line, [0,0], [2,1], 3,3,4)
        expect(path1).to be_empty
        path2 = BlobGraph.send(:shortest_path_on_skel, skel_3x3_line, [0,1], [2,2], 3,3,4)
        expect(path2).to be_empty
    end
  end
end
