require 'active_support'
require 'set'
require 'zlib'

# There are three main "sections" in this code
# * repository: deals with storing actual values in the memcached server
# * registry: deals with keeping track of method names that have been cacheified
# * mixin: deals with adding methods like "cacheify" and "uncacheify" wherever this module is extended
# It might be nice to split these up into actual modules in different files.
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
  
  def self.sanitize_args(args)
    Array.wrap(args).map do |x|
      if x.nil?
        'nil'
      elsif x.is_a? String
        x
      elsif x.is_a? Symbol
        x.to_s
      elsif x.respond_to? :cache_key
        x.cache_key
      else
        x
      end
    end
  end

  def self.key_for(obj, symbol, shard_args = :cacheable_deadbeef)
    ary = [ 'Cacheable', obj.cache_key, symbol.to_s.sub(/\?\Z/, '_query').sub(/!\Z/, '_bang') ]
    ary += sanitize_args(shard_args) unless shard_args == :cacheable_deadbeef
    shorten_key ary.join('/')
  end

  def self.fetch(obj, symbol, ttl, &block)
    key = key_for obj, symbol
    begin
      $stderr.puts "CACHEABLE: fetch-get '#{key}'" if defined?(CACHEABLE_DEBUG)
      repository.get key
    rescue Memcached::NotFound
      v = block.call
      $stderr.puts "CACHEABLE: fetch-set (ttl #{ttl}) '#{key}'" if defined?(CACHEABLE_DEBUG)
      repository.set key, v, ttl
      v
    end
  end

  def self.cas(obj, symbol, shard_args, ttl, &block)
    key = key_for obj, symbol, shard_args
    begin
      $stderr.puts "CACHEABLE: cas-cas (ttl #{ttl}) '#{key}'" if defined?(CACHEABLE_DEBUG)
      repository.cas key, ttl, &block
    rescue Memcached::NotFound
      $stderr.puts "CACHEABLE: cas-set (ttl #{ttl}) '#{key}'" if defined?(CACHEABLE_DEBUG)
      repository.set key, block.call(nil), ttl
    end
    $stderr.puts "CACHEABLE: cas-get '#{key}'" if defined?(CACHEABLE_DEBUG)
    repository.get key
  end

  def self.registry
    Thread.current[:cacheable_registry] ||= Hash.new
  end
  
  def self.register(obj, symbol)
    self.registry[obj] ||= Set.new
    self.registry[obj] << symbol
  end
  
  def self.extended(base)
    base.extend SharedMethods
  end
  
  module SharedMethods
    def uncacheify(regexp, shard_args = :cacheable_deadbeef)
      regexp = Regexp.new(regexp.to_s) unless regexp.is_a?(Regexp)
      ::Cacheable.registry[cacheable_base].each do |symbol|
        next unless symbol.to_s =~ regexp
        key = ::Cacheable.key_for(self, symbol, shard_args)
        begin
          $stderr.puts "CACHEABLE: uncacheify-delete '#{key}'" if defined?(CACHEABLE_DEBUG)
          ::Cacheable.repository.delete key
        rescue Memcached::NotFound
          # ignore
        end
      end
    end

    # Note that this does not clear sharded things
    # For that you need, for example, uncacheify '.*', '14'
    def uncacheify_all
      uncacheify /.*/
    end
  end
  
  # This is called by "classes"
  # Note that I'm checking "base_class" to be nice to ActiveRecord STI
  def cacheable_base
    respond_to?(:base_class) ? base_class.metaclass : metaclass
  end
  
  module InstanceMethods
    # This is called by "instances"
    # Note that I'm checking "base_class" to be nice to ActiveRecord STI
    def cacheable_base
      self.class.respond_to?(:base_class) ? self.class.base_class : self.class
    end
    
    if defined?(CACHEABLE_TEST)
      def foobar
        # hi
      end
    end
  end

  def cacheify(symbol, options = {})
    original_method = :"_uncacheified_#{symbol}"
    options[:sharding] ||= 0
    options[:ttl] ||= 60
    
    ::Cacheable.register self, symbol

    class_eval <<-EOS, __FILE__, __LINE__
      # If there's a name, that probably means we're expected to handle "instances" of a class
      # In that case, make sure each instance responds to the uncacheify, etc.
      if self.name.present?
        include SharedMethods
        include InstanceMethods
      end
      
      if method_defined?(:#{original_method})
        raise "Already cacheified #{symbol}"
      end
      alias #{original_method} #{symbol}

      if instance_method(:#{symbol}).arity == 0
        def #{symbol}
          ::Cacheable.fetch(self, #{symbol.inspect}, #{options[:ttl]}) do
            #{original_method}
          end
        end
      else
        def #{symbol}(*args)
          sanitized_args = ::Cacheable.sanitize_args args
          shard_args = sanitized_args[0, #{options[:sharding]}]
          hash_args = sanitized_args[#{options[:sharding]}, sanitized_args.length]
          
          result = ::Cacheable.cas(self, #{symbol.inspect}, shard_args, #{options[:ttl]}) do |current_hash|
            current_hash ||= Hash.new
            if current_hash.has_key?(hash_args)
              current_hash[hash_args]
            else
              current_hash[hash_args] = #{original_method}(*args)
            end
            current_hash
          end
          
          result[hash_args]
        end
      end
    EOS
  end
end
