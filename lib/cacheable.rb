require 'active_support'
require 'active_support/version'
%w{
  active_support/core_ext/object
  active_support/core_ext/class
}.each do |active_support_3_requirement|
  require active_support_3_requirement
end if ActiveSupport::VERSION::MAJOR == 3

require 'set'
require 'zlib'

unless defined?(MEMCACHED_MAXIMUM_KEY_LENGTH)
  MEMCACHED_MAXIMUM_KEY_LENGTH = 250
end

if Object.respond_to? :singleton_class
  SINGLETON_CLASS_METHOD = :singleton_class
else
  SINGLETON_CLASS_METHOD = :metaclass
end

# There are three main "sections" in this code
# * repository: deals with storing actual values in the memcached server
# * registry: deals with keeping track of method names that have been cacheified
# * mixin: deals with adding methods like "cacheify" and "uncacheify" wherever this module is extended
# It might be nice to split these up into actual modules in different files.
module Cacheable
  def self.repository
    $cacheable_repository
  end

  # Expects an instance of Memcached.
  def self.repository=(memcached_instance)
    $cacheable_repository = memcached_instance
  end

  def self.registry
    $cacheable_registry ||= Hash.new
  end

  def self.shorten_key(key)
    key.length < MEMCACHED_MAXIMUM_KEY_LENGTH ? key : key[0..MEMCACHED_MAXIMUM_KEY_LENGTH-11] + Zlib.crc32(key).to_s
  end

  def self.cache_key(obj)
    if obj.respond_to? :cache_key
      obj.cache_key
    elsif obj.nil?
      'nil'
    elsif obj.is_a? String
      obj
    elsif obj.is_a? Symbol
      obj.to_s
    else
      # provided by ActiveSupport
      obj.to_param
    end.to_s.gsub /\s+/, '-'
  end
  
  def self.key_for(obj, symbol)
    shorten_key [ 'Cacheable', cache_key(obj), symbol.to_s.sub(/\?\Z/, '_query').sub(/!\Z/, '_bang') ].join('/')
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

  def self.cas(obj, symbol, ttl, &block)
    key = key_for obj, symbol
    
    retry_count = 3
    begin
      $stderr.puts "CACHEABLE: cas-cas (ttl #{ttl}) '#{key}'" if defined?(CACHEABLE_DEBUG)
      repository.cas key, ttl, &block
    rescue Memcached::NotFound
      $stderr.puts "CACHEABLE: retrying cas because not found (ttl #{ttl}) '#{key}'" if defined?(CACHEABLE_DEBUG)
      repository.set key, nil, ttl
      retry if (retry_count -= 1) > 0
    rescue Memcached::ConnectionDataExists
      $stderr.puts "CACHEABLE: retrying cas because exists (ttl #{ttl}) '#{key}'" if defined?(CACHEABLE_DEBUG)
      retry if (retry_count -= 1) > 0
    end
    $stderr.puts "CACHEABLE: cas-get '#{key}'" if defined?(CACHEABLE_DEBUG)
    repository.get key
  end
  
  def self.register(obj, symbol)
    self.registry[obj] ||= Set.new
    self.registry[obj] << symbol
  end

  # Adds: FooClass.cacheable_base
  def cacheable_base
    respond_to?(:base_class) ? base_class.send(SINGLETON_CLASS_METHOD) : send(SINGLETON_CLASS_METHOD)
  end

  # Adds: FooClass#cacheable_base (a)
  # Adds: FooClass.uncacheify and FooClass#uncacheify (b)
  # Adds: FooClass.cacheify (c)
  def self.extended(base)
    # (a)
    base.send :include, InstanceMethods

    # (b)
    base.extend ClassAndInstanceMethods
    base.send :include, ClassAndInstanceMethods

    # (c)
    base.send(SINGLETON_CLASS_METHOD).extend MetaclassAndClassMethods
    base.extend MetaclassAndClassMethods
  end
  
  module InstanceMethods
    def cacheable_base
      self.class.respond_to?(:base_class) ? self.class.base_class : self.class
    end
  end
  
  module ClassAndInstanceMethods
    def uncacheify(symbol_or_regexp)
      case symbol_or_regexp
      when Symbol, String
        symbols = [symbol_or_regexp.to_sym]
      when Regexp
        symbols = ::Cacheable.registry[cacheable_base].select { |x| x.to_s =~ symbol_or_regexp }
      end
      
      symbols.each do |symbol|
        key = ::Cacheable.key_for(self, symbol)
        begin
          $stderr.puts "CACHEABLE: uncacheify-delete '#{key}'" if defined?(CACHEABLE_DEBUG)
          ::Cacheable.repository.delete key
        rescue Memcached::NotFound
          # ignore
        end
      end
    end

    def uncacheify_all
      uncacheify /.*/
    end
  end

  module MetaclassAndClassMethods
    def cacheify(symbol, options = {})
      original_method = :"_uncacheified_#{symbol}"
      options[:ttl] ||= 60
    
      ::Cacheable.register self, symbol

      class_eval <<-EOS, __FILE__, __LINE__
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
            hash_args = ::Cacheable.key_for args
            
            result = ::Cacheable.cas(self, #{symbol.inspect}, #{options[:ttl]}) do |current_hash|
              current_hash = Hash.new unless current_hash.is_a?(Hash)
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
end
