require_relative '../../../lib/matzeye'
require 'set'

RSpec.describe MatzEye do
  describe '.identify_edges' do
    it 'creates an edge if two junctions share >= 2 blob IDs' do
      vertices = { 1 => [1.0,1.0], 2 => [5.0,5.0] }
      contrib_blobs = {
        1 => Set[1,2,3],
        2 => Set[2,3,4]
      } # Common: {2,3} (size 2)
      edges = MatzEye.identify_edges(vertices, contrib_blobs)
      expect(edges.size).to eq(1)
      expect(edges.first.sort).to eq([1,2])
    end

    it 'does not create an edge if junctions share < 2 blob IDs' do
      vertices = { 1 => [1.0,1.0], 2 => [5.0,5.0] }
      contrib_blobs = {
        1 => Set[1,2,3],
        2 => Set[3,4,5]
      } # Common: {3} (size 1)
      edges = MatzEye.identify_edges(vertices, contrib_blobs)
      expect(edges).to be_empty
    end

    it 'handles more than two junctions' do
      vertices = { 1 => [0,0], 2 => [1,1], 3 => [2,2], 4 => [3,3] }
      contrib_blobs = {
        1 => Set[1,2,3],    # J1
        2 => Set[2,3,4],    # J2 (edge with J1)
        3 => Set[3,4,5],    # J3 (edge with J2)
        4 => Set[1,5,6]     # J4 (edge with J1, J3)
      }
      # Expected edges:
      # (1,2) -> common {2,3}
      # (1,3) -> common {3} -> NO
      # (1,4) -> common {1,5} -> YES (if my {1,5,6} for J4 is correct for that)
      # (2,3) -> common {3,4}
      # (2,4) -> common {5} (if J4 is {1,5,6}) -> NO
      # (3,4) -> common {5}
      # Let's refine J4 for more predictable edges: J4 contrib {1,2,6}
      # Then:
      # (1,2) common {2,3} YES
      # (1,3) common {3} NO
      # (1,4) common {1,2} YES
      # (2,3) common {3,4} YES
      # (2,4) common {2} NO
      # (3,4) common {} NO
      contrib_blobs[4] = Set[1,2,6]
      edges = MatzEye.identify_edges(vertices, contrib_blobs)

      # Expected edges: [1,2], [1,4], [2,3]
      expect(edges.size).to eq(3)
      expect(edges).to include([1,2].sort)
      expect(edges).to include([1,4].sort)
      expect(edges).to include([2,3].sort)
    end

    it 'returns empty list if less than 2 vertices' do
      vertices1 = { 1 => [0,0] }
      contrib_blobs1 = { 1 => Set[1,2,3] }
      expect(MatzEye.identify_edges(vertices1, contrib_blobs1)).to be_empty

      vertices0 = {}
      contrib_blobs0 = {}
      expect(MatzEye.identify_edges(vertices0, contrib_blobs0)).to be_empty
    end
  end
end
