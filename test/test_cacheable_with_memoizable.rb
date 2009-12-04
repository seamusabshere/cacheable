require 'helper'

require 'vampire'

# in general, these tests are contrived in the sense that you wouldn't want to flush the cache without flushing the memoization, too
class TestCacheableWithMemoizable < Test::Unit::TestCase
  def setup
    Cacheable.repository.flush
  end
  
  class ElephantVampire < Vampire
    extend ActiveSupport::Memoizable

    memoize :name
  end

  should "not go out to the cache if memoized" do
    ed = ElephantVampire.new(:edward)
    assert_equal 0, ed.name_count
    flush_count = 0

    10.times do
      Cacheable.repository.flush
      flush_count += 1
      ed.name
      assert_equal 1, ed.name_count
    end
  end

  should "go out to the cache if necessary" do
    ed = ElephantVampire.new(:edward)
    assert_equal 0, ed.name_count
    flush_count = 0

    10.times do
      Cacheable.repository.flush
      ed.unmemoize_all
      flush_count += 1
      ed.name
      assert_equal flush_count, ed.name_count
    end
  end
end
