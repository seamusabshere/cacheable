require 'helper'

class TestCacheable < Test::Unit::TestCase
  def setup
    Cacheable.repository.flush
    @flush_count = 1
    Vampire.enemy_count = 0
  end

  should "keep track of the Memcached object it's talking to" do
    assert Cacheable.repository.is_a?(Memcached)
  end

  should "keep track of where it's caching the results of a method call" do
    assert_equal 'Vampire/cacheable/a', Cacheable.key_for(Vampire, :a)
    assert_equal 'Vampire/1/cacheable/b', Cacheable.key_for(Vampire.new(:edward), :b)
    assert_equal 'Vampire/2/cacheable/c', Cacheable.key_for(Vampire.new(:emmett), :c)
  end

  should "be able to fetch from its cache" do
    Cacheable.repository.set Cacheable.key_for(Vampire, :already_there), 'existing_value'
    assert_equal 'existing_value', Cacheable.fetch(Vampire, :already_there) { 'new_value' }
    assert_equal 'new_value', Cacheable.fetch(Vampire, :totally_new) { 'new_value'}
  end

  should "be able to compare and swap from its cache" do
    existing_value_hash = { :existing => 'value' }
    new_value_hash = { :new => 'value' }
    Cacheable.repository.set Cacheable.key_for(Vampire, :already_there), existing_value_hash

    assert_equal existing_value_hash.merge(new_value_hash), Cacheable.cas(Vampire, :already_there) { |current| current.merge new_value_hash }

    assert_equal new_value_hash, Cacheable.cas(Vampire, :totally_new) { |current| new_value_hash }
  end

  should "cacheify a class method" do
    assert_equal 0, Vampire.enemy_count

    10.times do
      Vampire.enemy
      assert_equal 1, Vampire.enemy_count
    end
  end

  should "cacheify an instance method" do
    ed = Vampire.new(:edward)
    assert_equal 0, ed.name_count

    10.times do
      ed.name
      assert_equal 1, ed.name_count
    end
  end

  should "not have problems with queries in method names" do
    ed = Vampire.new(:edward)
    assert_equal 0, ed.frazzled_query_count

    10.times do
      ed.frazzled?
      assert_equal 1, ed.frazzled_query_count
    end
  end

  should "not have problems with bangs in method names" do
    ed = Vampire.new(:edward)
    assert_equal 0, ed.pump_bang_count
    assert !ed.instance_variable_get(:@pumped)

    10.times do
      ed.pump!
      assert ed.instance_variable_get(:@pumped)
      assert_equal 1, ed.pump_bang_count
    end
  end

  should "regenerate the cache if the cache is flushed" do
    ed = Vampire.new(:edward)
    assert_equal 0, ed.name_count

    10.times do
      ed.name
      assert_equal @flush_count, ed.name_count
      Cacheable.repository.flush
      @flush_count += 1
    end
  end

  should "regenerate the cache on class methods if uncacheify_all is called" do
    assert_equal 0, Vampire.enemy_count

    10.times do
      Vampire.enemy
      assert_equal @flush_count, Vampire.enemy_count
      Vampire.uncacheify_all
      @flush_count += 1
    end
  end

  should "regenerate the cache on **instance** methods if uncacheify_all is called" do
    ed = Vampire.new(:edward)
    assert_equal 0, ed.name_count

    10.times do
      ed.name
      assert_equal @flush_count, ed.name_count
      ed.uncacheify_all
      @flush_count += 1
    end
  end
  
  should "only define methods where they're expected" do
    assert !Object.respond_to?(:cacheify)
    assert Vampire.metaclass.respond_to?(:cacheify)
    assert Vampire.respond_to?(:cacheify)
    
    assert !Object.respond_to?(:uncacheify)
    assert Vampire.metaclass.respond_to?(:uncacheify)
    assert Vampire.respond_to?(:uncacheify)
    
    # These tests intentionally commented out (see lib/cacheable.rb)
    # assert !Object.instance_methods.include?('foobar')
    # assert !Vampire.metaclass.instance_methods.include?('foobar')
    # assert Vampire.instance_methods.include?('foobar')
  end
  
  should "take regexp arguments to uncacheify class methods" do
    assert_equal 0, Vampire.enemy_count

    # miss...
    10.times do
      Vampire.enemy
      assert_equal 1, Vampire.enemy_count
      Vampire.uncacheify /frazz.*/
    end
    
    # hit...
    10.times do
      Vampire.enemy
      assert_equal @flush_count, Vampire.enemy_count
      Vampire.uncacheify /enem.*/
      @flush_count += 1
    end
  end
  
  should "take regexp arguments to uncacheify instance methods" do
    ed = Vampire.new(:edward)
    assert_equal 0, ed.name_count

    # miss...
    10.times do
      ed.name
      assert_equal 1, ed.name_count
      ed.uncacheify /frazz.*/
    end
    
    # hit...
    10.times do
      ed.name
      assert_equal @flush_count, ed.name_count
      ed.uncacheify /nam.*/
      @flush_count += 1
    end
  end
end
