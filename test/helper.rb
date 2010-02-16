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
