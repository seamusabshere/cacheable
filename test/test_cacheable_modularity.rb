require 'helper'

class Dummy
  def self.cache_key; 'Dummy'; end
  def cache_key; "Dummy/#{@name}"; end
  def initialize(name); @name = name; end
end

class TestCacheableModularity < Test::Unit::TestCase
  should "define cacheify so that it works for 'class' methods" do
    assert_nothing_raised do
      class Dummy1 < Dummy
        extend Cacheable
        class << self
          def class_method_1; end
          cacheify :class_method_1
        end
      end
    end
  end
  
  should "define cacheify so that it works for 'instance' methods" do
    assert_nothing_raised do
      class Dummy2 < Dummy
        extend Cacheable
        def instance_method_1; end
        cacheify :instance_method_1
      end
    end
  end
  
  should "define uncacheify on the 'class'" do
    assert_nothing_raised do
      class Dummy3 < Dummy
        extend Cacheable
        class << self
          def class_method_1; end
          cacheify :class_method_1
        end
      end
      Dummy3.uncacheify /.*/
    end
  end
  
  should "define uncacheify on 'instances'" do
    assert_nothing_raised do
      class Dummy4 < Dummy
        extend Cacheable
        def instance_method_1; end
        cacheify :instance_method_1
      end
      Dummy4.new('foo').uncacheify /.*/
    end
  end
  
  should "define cacheable_base on the 'class'" do
    assert_nothing_raised do
      class Dummy5 < Dummy
        extend Cacheable
        def instance_method_1; end
        cacheify :instance_method_1
      end
      Dummy5.cacheable_base
    end
  end
  
  should "define cacheable_base on 'instances'" do
    assert_nothing_raised do
      class Dummy6 < Dummy
        extend Cacheable
        def instance_method_1; end
        cacheify :instance_method_1
      end
      Dummy6.new('foo').cacheable_base
    end
  end
end
