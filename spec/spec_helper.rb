begin
  require File.dirname(__FILE__) + '/../../../../spec/spec_helper'
rescue LoadError
  puts "You need to install rspec in your base app"
  exit
end
require File.dirname(__FILE__) + '/../../../../vendor/plugins/lib/attribute_fu'

plugin_spec_dir = File.dirname(__FILE__)
ActiveRecord::Base.logger = Logger.new(plugin_spec_dir + "/debug.log")

class MockModel
  attr_accessor :attributes
  attr_accessor :accessible_attributes
end

class Student < MockModel
  include AttributeFu


end
