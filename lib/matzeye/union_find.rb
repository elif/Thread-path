module MatzEye
  class UnionFind
    def initialize
      @parent = {}
      @rank = {} # For union by rank/size optimization
    end

    def make_set(item)
      unless @parent.key?(item)
        @parent[item] = item
        @rank[item] = 0
      end
    end

    def find(item)
      # Path compression
      if @parent[item] != item
        @parent[item] = find(@parent[item])
      end
      @parent[item]
    end

    def union(item1, item2)
      root1 = find(item1)
      root2 = find(item2)

      return if root1 == root2 # Already in the same set

      # Union by rank
      if @rank[root1] < @rank[root2]
        @parent[root1] = root2
      elsif @rank[root1] > @rank[root2]
        @parent[root2] = root1
      else
        @parent[root2] = root1
        @rank[root1] += 1
      end
    end
  end # End UnionFind
end # Module MatzEye
