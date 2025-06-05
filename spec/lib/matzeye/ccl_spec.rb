require_relative '../../../lib/matzeye'
require 'chunky_png' # For color constants if used in test data setup

RSpec.describe MatzEye do
  describe '.connected_components' do
    # Helper to create packed RGB integer
    def pack_rgb(r,g,b)
      (r << 16) | (g << 8) | b
    end

    let(:color1) { pack_rgb(10,20,30) }
    let(:color2) { pack_rgb(50,60,70) }
    # let(:color3) { pack_rgb(100,110,120) } # Not used in these specific tests

    it 'labels a single blob image' do
      data = [
        [color1, color1, color1],
        [color1, color1, color1],
        [color1, color1, color1]
      ]
      # Assuming options[:process_zero_as_color] is false or not set by default in MatzEye.connected_components
      labels, count = MatzEye.connected_components(data, 3, 3, 4)
      expect(count).to eq(1)
      expect(labels.flatten.uniq).to eq([1])
    end

    it 'labels two distinct non-touching blobs (different colors)' do
      data = [
        [color1, color1, 0],
        [color1, color1, 0],
        [0,      0,      color2]
      ]
      labels, count = MatzEye.connected_components(data, 3, 3, 4)
      expect(count).to eq(2)
      expect(labels[0][0]).to eq(1)
      expect(labels[1][1]).to eq(1)
      expect(labels[2][2]).to eq(2)
    end

    it 'labels two distinct non-touching blobs (same color)' do
      data = [
        [color1, color1, 0],
        [color1, color1, 0],
        [0,      0,      color1]
      ]
      labels, count = MatzEye.connected_components(data, 3, 3, 4)
      expect(count).to eq(2)
      expect(labels[0][0]).to eq(1)
      expect(labels[2][2]).to eq(2)
    end

    it 'labels two touching blobs (same color) as one blob' do
      data = [
        [color1, color1, 0],
        [0,      color1, color1],
        [0,      0,      color1]
      ]
      labels, count = MatzEye.connected_components(data, 3, 3, 4)
      expect(count).to eq(1)
      expect(labels[0][0]).to eq(1)
      expect(labels[1][2]).to eq(1)
    end

    it 'labels two touching blobs (different colors) as two blobs' do
      data = [
        [color1, color1, 0],
        [0,      color1, color2],
        [0,      0,      color2]
      ]
      labels, count = MatzEye.connected_components(data, 3, 3, 4)
      expect(count).to eq(2)
      expect(labels[0][0]).to eq(1)
      expect(labels[1][1]).to eq(1)
      expect(labels[1][2]).to eq(2)
      expect(labels[2][2]).to eq(2)
    end

    it 'handles 4-connectivity for diagonal elements' do
      data = [
        [color1, 0,      0],
        [0,      color1, 0],
        [0,      0,      color1]
      ]
      labels, count = MatzEye.connected_components(data, 3, 3, 4)
      expect(count).to eq(3)
    end

    it 'handles 8-connectivity for diagonal elements' do
      data = [
        [color1, 0,      0],
        [0,      color1, 0],
        [0,      0,      color1]
      ]
      labels, count = MatzEye.connected_components(data, 3, 3, 8)
      expect(count).to eq(1)
      expect(labels[0][0]).to eq(1)
      expect(labels[1][1]).to eq(1)
      expect(labels[2][2]).to eq(1)
    end
  end

  describe MatzEye::UnionFind do
    subject { MatzEye::UnionFind.new }
    it 'correctly performs basic union-find operations' do
      subject.make_set(1)
      subject.make_set(2)
      subject.make_set(3)
      subject.union(1,2)
      expect(subject.find(1)).to eq(subject.find(2))
      expect(subject.find(1)).not_to eq(subject.find(3))
      subject.union(2,3)
      expect(subject.find(1)).to eq(subject.find(3))
    end
  end
end
