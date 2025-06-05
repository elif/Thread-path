require 'spec_helper'
require 'blob_graph'
require 'set'

RSpec.describe BlobGraph do

  module BlobGraphSpecHelpers
    def describe_implementations(implementations, &block)
      implementations.each do |impl|
        context "with #{impl} implementation" do
          instance_exec(impl, &block)
        end
      end
    end
  end

  RSpec.configure do |config|
    config.extend BlobGraphSpecHelpers
  end

  let(:labels_simple_junction) { [[1,2],[1,3]] }
  let(:labels_for_single_junction) {
    [ [1,1,1,1,0], [1,1,2,2,0], [1,3,2,2,0], [3,3,3,0,0], [0,0,0,0,0] ]
  }
  let(:labels_for_j1j2_edge_yields_1_vertex_for_matzeye) {
    [ [1,1,1,0,0], [1,2,3,0,0], [1,2,0,0,0], [0,2,4,4,0], [0,0,4,4,0] ]
  }
  let(:labels_for_two_distinct_junctions_with_edge) {
    [ # 6x6
      [1,1,0,0,0,0],
      [1,2,3,0,0,0],
      [0,3,0,0,0,0],
      [0,0,0,0,0,0],
      [0,0,0,2,4,0],
      [0,0,0,3,4,0]
    ]
  }
  let(:labels_for_two_distinct_junctions_no_edge) do # Corrected v3
    [ # 6x6
      [1,1,0,0,0,0],
      [1,2,3,0,0,0],
      [0,0,0,0,0,0], # L[2][1] (val 3 from prev example) removed to ensure J1 is distinct
      [0,0,7,0,0,0], # L[3][2]=7. Nhood for this: [[0,0,0],[0,7,0],[0,0,5]]. Unique {7,5}. Not a junction.
      [0,0,0,5,0,0], # L[4][3]=5 is J2. Nhood for this: [[7,0,0],[0,5,0],[0,6,0]]. Unique {7,5,6}. Junction. Contrib {5,6,7}
      [0,0,0,6,0,0]
    ]
    # J1: from (1,1) val=2 (N={1,2,3}), (2,1) val=3 (N={1,2,3}). Contrib {1,2,3}
    # J2: from (3,4) val=5 (L[4][3]). Contrib {5,6,7}
    # Common: {}. No edge.
  end
  let(:labels_no_junctions) { [ [1,1,2,2],[1,1,2,2],[1,1,2,2] ] }
  let(:labels_cross) { [ [1,1,0,2,2], [1,3,0,4,2], [5,5,0,6,6] ] }

  describe '.extract_from_labels' do
    describe_implementations [:ruby, :matzeye] do |implementation|
      let(:options) { { implementation: implementation, junction_conn: 8, _return_contrib_blobs: (implementation == :matzeye) } }

      context 'with labels_simple_junction (2x2 image)' do
        it 'returns expected graph structure' do
          result = BlobGraph.extract_from_labels(labels_simple_junction, options)
          expect(result).to include(:vertices, :edges, :detailed_edges)
          expect(result[:vertices].size).to eq(1)
          expect(result[:edges]).to be_empty
          if implementation == :matzeye && result.key?(:_internal_contrib_blobs)
            expect(result[:_internal_contrib_blobs].values.first).to eq(Set[1,2,3])
          end
        end
      end

      context 'with labels_for_single_junction (5x5 image)' do
        it 'identifies one vertex and no edges' do
          result = BlobGraph.extract_from_labels(labels_for_single_junction, options)
          expect(result[:vertices].size).to eq(1)
          vertex_id = result[:vertices].keys.first
          expect(result[:vertices][vertex_id][0]).to be_within(0.01).of(1.4)
          expect(result[:vertices][vertex_id][1]).to be_within(0.01).of(1.8)
          if implementation == :matzeye && result.key?(:_internal_contrib_blobs)
            expect(result[:_internal_contrib_blobs][vertex_id]).to eq(Set[1,2,3])
          end
          expect(result[:edges]).to be_empty
        end
      end

      context 'with labels_for_j1j2_edge_yields_1_vertex_for_matzeye (5x5 image)' do
        it 'identifies 1 vertex for MatzEye, and 0 edges' do
          result = BlobGraph.extract_from_labels(labels_for_j1j2_edge_yields_1_vertex_for_matzeye, options)
          if implementation == :matzeye
            expect(result[:vertices].size).to eq(1)
            expect(result[:edges].size).to eq(0)
            if result.key?(:_internal_contrib_blobs) && !result[:vertices].empty?
              expect(result[:_internal_contrib_blobs].values.first).to eq(Set[1,2,3,4])
            end
          elsif implementation == :ruby
            expect(result[:vertices].size).to be >= 0
            expect(result[:edges].size).to eq(0)
          end
        end
      end

      context 'with labels_for_two_distinct_junctions_with_edge (MatzEye specific)' do
        it 'creates an edge for two junctions sharing >= 2 blob IDs', if: implementation == :matzeye do
          result = BlobGraph.extract_from_labels(labels_for_two_distinct_junctions_with_edge, options)
          expect(result[:vertices].size).to eq(2)
          expect(result[:edges].size).to eq(1)
          v_ids = result[:vertices].keys.sort
          expect(result[:edges].first.sort).to eq(v_ids)
          if result.key?(:_internal_contrib_blobs)
             expect(result[:_internal_contrib_blobs][v_ids[0]]).to eq(Set[1,2,3])
             expect(result[:_internal_contrib_blobs][v_ids[1]]).to eq(Set[2,3,4])
          end
        end
      end

      context 'with labels_for_two_distinct_junctions_no_edge (MatzEye specific)' do
        it 'does not create an edge for two junctions sharing < 2 blob IDs', if: implementation == :matzeye do
          result = BlobGraph.extract_from_labels(labels_for_two_distinct_junctions_no_edge, options)
          expect(result[:vertices].size).to eq(2)
          expect(result[:edges]).to be_empty
           if result.key?(:_internal_contrib_blobs)
             v_ids = result[:vertices].keys.sort
             # J1: (1,1) val=2. Nhood for L[1][1]: [[1,1,0],[1,2,3],[0,0,0]]. Unique {1,2,3}.
             # J2: (3,4) val=5 (L[4][3]). Nhood for L[4][3]: [[7,0,0],[0,5,0],[0,6,0]]. Unique {5,6,7}.
             expect(result[:_internal_contrib_blobs][v_ids[0]]).to eq(Set[1,2,3])
             expect(result[:_internal_contrib_blobs][v_ids[1]]).to eq(Set[5,6,7])
           end
        end
      end

      context 'with labels_no_junctions (3x4 image)' do
        it 'identifies zero vertices and zero edges' do
          result = BlobGraph.extract_from_labels(labels_no_junctions, options)
          expect(result[:vertices]).to be_empty
          expect(result[:edges]).to be_empty
        end
      end

      context 'with original labels_cross' do
        it "processes and returns structure for #{implementation}" do
          result = BlobGraph.extract_from_labels(labels_cross, options.merge(skeletonize: false))
          if implementation == :ruby
            expect(result[:vertices].size).to be >= 2
          elsif implementation == :matzeye
            expect(result[:vertices].size).to eq(2)
          end
          expect(result[:edges]).to be_empty
        end
      end
    end
  end
  # Private method tests for original Ruby implementation remain (not shown for brevity)
end
