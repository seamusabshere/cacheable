require 'helper'
require 'mocha'

class TestCacheableRegistry < Test::Unit::TestCase
  class Dummy
    def self.cache_key; 'Dummy'; end
    def cache_key; "Dummy/#{@name}"; end
    def initialize(name); @name = name; end
    extend Cacheable
    class << self
      def class_method_1; end
      cacheify :class_method_1
      def class_method_2(*args); end
      cacheify :class_method_2
    end
    def instance_method_1; end
    cacheify :instance_method_1
    def instance_method_2(*args); end
    cacheify :instance_method_2
  end
  
  should "register class methods" do
    assert Cacheable.registry[Dummy.metaclass].include?(:class_method_1)
  end
  
  should "register instance methods" do
    assert Cacheable.registry[Dummy].include?(:instance_method_1)
  end
  
  should "attempt to uncacheify **arbitrary** class methods" do
    Cacheable.repository.expects(:delete).with('Cacheable/Dummy/random')
    Dummy.uncacheify :random
  end
  
  should "attempt to uncacheify **arbitrary** instance methods" do
    Cacheable.repository.expects(:delete).with('Cacheable/Dummy/foobar/random')
    Dummy.new('foobar').uncacheify :random
  end
  
  should "attempt to uncacheify **matching** class methods" do
    Cacheable.repository.expects(:delete).with('Cacheable/Dummy/class_method_1')
    Cacheable.repository.expects(:delete).with('Cacheable/Dummy/class_method_2')
    Dummy.uncacheify /class_method/
  end
  
  should "attempt to uncacheify **matching** instance methods" do
    Cacheable.repository.expects(:delete).with('Cacheable/Dummy/foobar/instance_method_1')
    Cacheable.repository.expects(:delete).with('Cacheable/Dummy/foobar/instance_method_2')
    Dummy.new('foobar').uncacheify /instance_method/
  end
  
  should "attempt to uncacheify **all registered** class methods" do
    Cacheable.repository.expects(:delete).with('Cacheable/Dummy/class_method_1')
    Cacheable.repository.expects(:delete).with('Cacheable/Dummy/class_method_2')
    Dummy.uncacheify_all
  end
  
  should "attempt to uncacheify **all registered** instance methods" do
    Cacheable.repository.expects(:delete).with('Cacheable/Dummy/foobar/instance_method_1')
    Cacheable.repository.expects(:delete).with('Cacheable/Dummy/foobar/instance_method_2')
    Dummy.new('foobar').uncacheify_all
  end
end
