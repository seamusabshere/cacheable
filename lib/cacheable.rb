require 'active_support'
require 'set'
require 'zlib'

module Cacheable
  def self.repository
    Thread.current[:cacheable_repository]
  end

  # Expects an instance of Memcached.
  def self.repository=(memcached_instance)
    Thread.current[:cacheable_repository] = memcached_instance
  end

  def self.shorten_key(key)
    key.length < 250 ? key : key[0..239] + Zlib.crc32(key).to_s
  end

  def self.key_for(obj, symbol)
    shorten_key "#{obj.cache_key}/cacheable/#{symbol.to_s.sub(/\?\Z/, '_query').sub(/!\Z/, '_bang')}"
  end

  def self.fetch(obj, symbol, &block)
    key = key_for obj, symbol
    begin
      repository.get key
    rescue Memcached::NotFound
      v = block.call
      repository.set key, v
      v
    end
  end

  def self.cas(obj, symbol, &block)
    key = key_for obj, symbol
    begin
      repository.cas key, &block
    rescue Memcached::NotFound
      repository.set key, block.call(nil)
    end
    repository.get key
  end
  
  def self.delete(obj, symbol)
    repository.delete key_for(obj, symbol)
  end

  def self.registry
    Thread.current[:cacheable_registry] ||= Hash.new
  end
  
  def self.register(obj, symbol)
    self.registry[obj] ||= Set.new
    self.registry[obj] << symbol
  end
  
  def uncacheify(symbol)
    ::Cacheable.delete self, symbol
  rescue Memcached::NotFound
    # ignore
  end
  
  def uncacheify_all
    ::Cacheable.registry[metaclass].each do |symbol|
      uncacheify symbol
    end
  end
  
  module InstanceMethods
    def uncacheify(symbol)
      ::Cacheable.delete self, symbol
    rescue Memcached::NotFound
      # ignore
    end

    def uncacheify_all
      ::Cacheable.registry[self.class].each do |symbol|
        uncacheify symbol
      end
    end
    
    # This method intentionally commented out (see tests)
    # def foobar
    #   # hi
    # end
  end

  def cacheify(symbol)
    original_method = :"_uncacheified_#{symbol}"
    
    ::Cacheable.register self, symbol

    class_eval <<-EOS, __FILE__, __LINE__
      # Don't include InstanceMethods when this is called from the anonymous singleton (aka metaclass)
      if self.name.present?
        include InstanceMethods
      end
      
      if method_defined?(:#{original_method})
        raise "Already cacheified #{symbol}"
      end
      alias #{original_method} #{symbol}

      if instance_method(:#{symbol}).arity == 0
        def #{symbol}
          ::Cacheable.fetch(self, #{symbol.inspect}) do
            #{original_method}
          end
        end
      else
        def #{symbol}(*args)
          ::Cacheable.cas(self, #{symbol.inspect}) do |current_hash|
            current_hash ||= Hash.new
            if current_hash.has_key?(args)
              current_hash[args]
            else
              current_hash[args] = #{original_method}(*args)
            end
            current_hash
          end[args]
        end
      end
    EOS
  end
end
