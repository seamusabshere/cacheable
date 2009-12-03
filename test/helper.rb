require 'rubygems'
require 'test/unit'
require 'shoulda'

CACHEABLE_TEST = true

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'cacheable'

class Test::Unit::TestCase
end

# my test stuff starts here

require 'memcached'

# expects a running memcached server at localhost:11211
Cacheable.repository = Memcached.new 'localhost:11211', :support_cas => true

class Vampire
  cattr_accessor :enemy_count
  @@enemy_count = 0

  class << self
    # Cacheable interface on classes
    def cache_key
      'Vampire'
    end
    extend Cacheable
    # end Cacheable interface

    def enemy
      self.enemy_count += 1
      'Children of the Moon'
    end
    cacheify :enemy
  end

  # Cacheable interface for instances
  def cache_key
    "Vampire/#{@id}"
  end
  extend Cacheable
  # end Cacheable interface

  attr_accessor :name_count, :frazzled_query_count, :pump_bang_count

  def initialize(shorthand)
    case shorthand
    when :edward
      @id = 1
      @name = 'Edward'
      @frazzled = true
      @pumped = false
    when :emmett
      @id = 2
      @name = 'Emmett'
      @frazzled = false
      @pumped = true
    end
    @name_count = 0
    @frazzled_query_count = 0
    @pump_bang_count = 0
  end

  def name
    self.name_count += 1
    @name
  end
  cacheify :name

  def frazzled?
    self.frazzled_query_count += 1
    @frazzled
  end
  cacheify :frazzled?

  def pump!
    self.pump_bang_count += 1
    @pumped = true
  end
  cacheify :pump!
end
