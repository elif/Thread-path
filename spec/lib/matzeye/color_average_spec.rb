require_relative '../../../lib/matzeye'
# require 'chunky_png' # Not strictly needed as inputs are pixel_arrays

RSpec.describe MatzEye do
  describe '.calculate_blob_average_colors' do
    let(:source_pixel_array_2x2) do
      # R, G, B, A
      [
        [[10,20,30,255], [50,60,70,255]],
        [[100,0,0,255],  [0,100,0,255]]
      ]
    end

    it 'calculates average for a single blob covering whole image' do
      labels = [[1,1],[1,1]]
      # R_avg = (10+50+100+0)/4 = 160/4 = 40
      # G_avg = (20+60+0+100)/4 = 180/4 = 45
      # B_avg = (30+70+0+0)/4 = 100/4 = 25
      # A_avg = (255*4)/4 = 255
      avg_map = MatzEye.calculate_blob_average_colors(source_pixel_array_2x2, 2, 2, labels, 1)
      expect(avg_map[1]).to eq([40,45,25,255])
    end

    it 'calculates averages for multiple distinct blobs' do
      labels = [[1,1],[0,2]] # Blob 1: (0,0), (1,0). Blob 2: (1,1) (coords y,x for array)
      # Blob 1: P(0,0)=[10,20,30,255], P(0,1)=[50,60,70,255]
      # R=(10+50)/2=30, G=(20+60)/2=40, B=(30+70)/2=50, A=(255*2)/2=255
      # Blob 2: P(1,1)=[0,100,0,255]
      # R=0, G=100, B=0, A=255
      avg_map = MatzEye.calculate_blob_average_colors(source_pixel_array_2x2, 2, 2, labels, 2)
      expect(avg_map[1]).to eq([30,40,50,255])
      expect(avg_map[2]).to eq([0,100,0,255])
    end

    it 'handles blob_count correctly if a label ID has no pixels' do
      labels = [[1,1],[0,0]] # Blob 1 exists, Blob 2 (implied by blob_count=2) does not
      avg_map = MatzEye.calculate_blob_average_colors(source_pixel_array_2x2, 2, 2, labels, 2)
      # Blob 1 is pixels (0,0) and (0,1) from source_pixel_array_2x2
      # R=(10+50)/2=30, G=(20+60)/2=40, B=(30+70)/2=50, A=255
      expect(avg_map[1]).to eq([30,40,50,255])
      expect(avg_map[2]).to eq([0,0,0,255])   # Default for blob with no pixels (opaque black)
    end

    it 'returns an empty map if blob_count is 0' do
      labels = [[0,0],[0,0]]
      avg_map = MatzEye.calculate_blob_average_colors(source_pixel_array_2x2, 2, 2, labels, 0)
      expect(avg_map).to be_empty
    end

    it 'handles pixels with no alpha (assumes opaque)' do
      pixel_array_no_alpha = [
        [[10,20,30], [50,60,70]]
      ]
      labels = [[1,1]]
      avg_map = MatzEye.calculate_blob_average_colors(pixel_array_no_alpha, 2, 1, labels, 1)
      # R=(10+50)/2=30, G=(20+60)/2=40, B=(30+70)/2=50, A=255 (default)
      expect(avg_map[1]).to eq([30,40,50,255])
    end
  end
end
