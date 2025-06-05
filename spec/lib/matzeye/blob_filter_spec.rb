require_relative '../../../lib/matzeye'
# require 'chunky_png' # Not strictly needed as inputs/outputs are arrays/numbers

RSpec.describe MatzEye do
  describe '.filter_blobs_by_size' do
    it 'filters small blobs and relabels contiguously' do
      labels_array = [
        [1, 1, 0, 2, 2],
        [1, 1, 0, 3, 0],
        [0, 0, 0, 3, 3]
      ] # Blob 1 (size 4), Blob 2 (size 2), Blob 3 (size 3)

      filtered_labels, new_count = MatzEye.filter_blobs_by_size(labels_array, 5, 3, 3)

      expect(new_count).to eq(2)
      # Expected: Blob 2 (original label 2) removed. Blob 1 and 3 relabeled to 1 and 2.
      # Original 1 -> New 1 (or 2)
      # Original 3 -> New 2 (or 1)
      # Check pixel values:
      # Original 1s:
      expect(filtered_labels[0][0]).to satisfy { |x| x == 1 || x == 2 }
      expect(filtered_labels[0][1]).to eq(filtered_labels[0][0])
      expect(filtered_labels[1][0]).to eq(filtered_labels[0][0])
      expect(filtered_labels[1][1]).to eq(filtered_labels[0][0])
      # Original 2s (should be 0):
      expect(filtered_labels[0][3]).to eq(0)
      expect(filtered_labels[0][4]).to eq(0)
      # Original 3s:
      expect(filtered_labels[1][3]).to satisfy { |x| x == 1 || x == 2 }
      expect(filtered_labels[1][3]).not_to eq(filtered_labels[0][0]) # Must be different from blob 1's new label
      expect(filtered_labels[2][3]).to eq(filtered_labels[1][3])
      expect(filtered_labels[2][4]).to eq(filtered_labels[1][3])

      # Count non-zero pixels
      expect(filtered_labels.flatten.count { |p| p != 0 }).to eq(4 + 3) # Sizes of remaining blobs
    end

    it 'filters all blobs if they are too small' do
      labels_array = [
        [1, 0, 2, 2],
        [0, 0, 0, 2]
      ] # Blob 1 (size 1), Blob 2 (size 3)
      filtered_labels, new_count = MatzEye.filter_blobs_by_size(labels_array, 4, 2, 4)
      expect(new_count).to eq(0)
      expect(filtered_labels.flatten.all?(&:zero?)).to be true
    end

    it 'does not filter if min_size is 0 or 1 and relabels if needed' do
      labels_array = [
        [5, 5, 0], # Original labels are not contiguous
        [0, 2, 0]
      ] # Blob 5 (size 2), Blob 2 (size 1)
      filtered_labels, new_count = MatzEye.filter_blobs_by_size(labels_array, 3, 2, 1)
      expect(new_count).to eq(2)
      # Expect labels to be 1 and 2 (or vice versa)
      label_values = filtered_labels.flatten.reject(&:zero?).uniq.sort
      expect(label_values).to eq([1,2])

      # Ensure original 5s map to one new label, original 2s to another
      new_label_for_5 = filtered_labels[0][0]
      new_label_for_2 = filtered_labels[1][1]
      expect(new_label_for_5).not_to eq(0)
      expect(new_label_for_2).not_to eq(0)
      expect(new_label_for_5).not_to eq(new_label_for_2)

      expect(filtered_labels[0][1]).to eq(new_label_for_5)
    end

    it 'maintains contiguity if no blobs are filtered and labels are already contiguous' do
       labels_array = [
        [1, 1, 0],
        [0, 2, 0]
      ] # Blob 1 (size 2), Blob 2 (size 1) - already contiguous
      filtered_labels, new_count = MatzEye.filter_blobs_by_size(labels_array, 3, 2, 1)
      expect(new_count).to eq(2)
      expect(filtered_labels).to eq(labels_array)
    end

     it 'handles empty labels array' do
      labels_array = []
      filtered_labels, new_count = MatzEye.filter_blobs_by_size(labels_array, 0, 0, 5)
      expect(new_count).to eq(0)
      expect(filtered_labels).to be_empty
    end

    it 'handles labels array with only background' do
      labels_array = [[0,0,0],[0,0,0]]
      filtered_labels, new_count = MatzEye.filter_blobs_by_size(labels_array, 3, 2, 1)
      expect(new_count).to eq(0)
      expect(filtered_labels.flatten.all?(&:zero?)).to be true
    end
  end
end
