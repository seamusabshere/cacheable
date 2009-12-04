class Human
  attr_accessor :name
  def initialize(name)
    @name = name
  end
  
  def cache_key
    "Human:1/#{name}"
  end
  
  class << self
    def cache_key
      "Human:1"
    end
  end
end
