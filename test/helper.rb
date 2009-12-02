require 'rubygems'
require 'test/unit'
require 'shoulda'

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
  extend Cacheable

  # needed by the cacheable interface
  def self.cache_key
    'Vampire'
  end
  def cache_key
    "#{self.class.cache_key}/#{id}"
  end

  attr_accessor :name_count, :id_count, :frazzled_query_count, :pump_bang_count

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
    @id_count = 0
    @frazzled_query_count = 0
    @pump_bang_count = 0
  end

  def id
    self.id_count += 1
    @id
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

  cattr_accessor :enemy_count
  @@enemy_count = 0

  class << self
    extend Cacheable
    def enemy
      self.enemy_count += 1
      'Children of the Moon'
    end
    cacheify :enemy
  end
end
