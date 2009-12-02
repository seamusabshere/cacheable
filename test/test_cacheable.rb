require 'helper'

class TestCacheable < Test::Unit::TestCase
  def setup
    Cacheable.repository.flush
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

  should "go out to the cache if necessary" do
    ed = Vampire.new(:edward)
    assert_equal 0, ed.name_count
    flush_count = 0

    10.times do
      Cacheable.repository.flush
      flush_count += 1
      ed.name
      assert_equal flush_count, ed.name_count
    end
  end

  should "not have problems with queries" do
    ed = Vampire.new(:edward)
    assert_equal 0, ed.frazzled_query_count

    10.times do
      ed.frazzled?
      assert_equal 1, ed.frazzled_query_count
    end
  end

  should "not have problems with bangs" do
    ed = Vampire.new(:edward)
    assert_equal 0, ed.pump_bang_count
    assert !ed.instance_variable_get(:@pumped)

    10.times do
      ed.pump!
      assert ed.instance_variable_get(:@pumped)
      assert_equal 1, ed.pump_bang_count
    end
  end
end
