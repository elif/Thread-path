require_relative 'matzeye' # Corrected path
require 'set'            # For Set data structure if used in adapter logic

module BlobGraph
  module MatzEyeAdapter # Renamed from MatzEye (which was previously OpenCV)
    class << self
      def extract_from_labels(labels_array, options)
        # Input: labels_array (2D Array of Integers from Impressionist)
        # Output: Hash { vertices: vertices_hash, edges: edges_list, detailed_edges: detailed_edges_list }

        return { vertices: {}, edges: [], detailed_edges: [] } if labels_array.empty? || labels_array.first.empty?

        height = labels_array.size
        width = labels_array.first.size

        # 1. Detect Junction Pixels & Get Contributing Blob Sets
        junction_pixel_mask_array, pixel_to_blob_sets_hash =
          ::MatzEye.detect_junction_pixels(labels_array, width, height)

        # 2. Cluster Junction Pixels
        connectivity = options.fetch(:junction_conn, 8) == 8 ? 8 : 4
        cluster_labels_array, num_clusters =
          ::MatzEye.cluster_junction_pixels(junction_pixel_mask_array, width, height, connectivity)

        # 3. Calculate Centroids & Aggregate Contributing Blobs for each cluster
        vertices_hash, junction_contrib_blobs_hash =
          ::MatzEye.calculate_junction_centroids_and_contrib_blobs(
            cluster_labels_array, width, height, pixel_to_blob_sets_hash, num_clusters
          )

        # 4. Identify Edges
        edges_list = ::MatzEye.identify_edges(vertices_hash, junction_contrib_blobs_hash)

        # 5. Create Basic Detailed Edges (straight lines for now)
        detailed_edges_list = edges_list.map do |v_id1, v_id2|
          # Ensure vertices exist, though identify_edges should only return valid pairs
          if vertices_hash[v_id1] && vertices_hash[v_id2]
            { endpoints: [v_id1, v_id2].sort, polyline: [vertices_hash[v_id1], vertices_hash[v_id2]] }
          else
            nil # Should ideally not happen
          end
        end.compact

        # Return final structure
        {
          vertices: vertices_hash,
          edges: edges_list,
          detailed_edges: detailed_edges_list
        }
      end # def extract_from_labels
    end # class << self
  end # module MatzEyeAdapter
end # module BlobGraph
