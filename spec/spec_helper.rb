begin
  require File.dirname(__FILE__) + '/../../../../spec/spec_helper'
rescue LoadError
  puts "You need to install rspec in your base app"
  exit
end
require File.dirname(__FILE__) + '/../../../../vendor/plugins/attribute_fu/lib/attribute_fu'

plugin_spec_dir = File.dirname(__FILE__)
ActiveRecord::Base.logger = Logger.new(plugin_spec_dir + "/debug.log")

class MockModel
  cattr_accessor :accessible_attributes

  def attributes=(attr, check_accessible=nil)
    @attributes ||= {}
    @attributes.recursive_merge! attr if attr
  end

  def attributes
    @attributes
  end

  def save; end

  def attributes_protected_by_default; ['id']; end

  def log_protected_attribute_removal(filtered_attributes)
    @log ||= []
    @log << filtered_attributes
  end

  def self.reflect_on_association(association)
    $assoc = association.to_s.singularize.classify
    return self
  end

  def self.klass
    Object.const_get $assoc rescue nil
  end
end

class Student < MockModel
  include AttributeFu

  nested_attr_accessible_for :administrator, [:full_name, { :grades_attributes => [:override_letter_grade] }]
  nested_attr_accessible_for :student, [:preferred_name, { :profile_attributes => :all }]
  nested_attr_accessible_for :teacher, :grades_attributes

  def initial_attributes
    { 'full_name' => 'Jeff Fenworth', 'preferred_name' => 'Jef',
      'grades_attributes' => { '1' => Grade.new.initial_attributes },
      'profile_attributes' => Profile.new.initial_attributes }
  end

  def initialize
    self.attributes = initial_attributes
  end
end

class Grade < MockModel
  include AttributeFu

  def initial_attributes
    { 'letter_grade' => 'C', 'class_id' => '3857', 'override_letter_grade' => nil }
  end

  def initialize
    self.attributes = initial_attributes
  end

  def self.accessible_attributes
    ['class_id']
  end
end

class Profile < MockModel
  include AttributeFu

  def initial_attributes
    { 'favorite_sport' => 'quiddich' }
  end

  def initialize
    self.attributes = initial_attributes
  end
end

class Hash
  def recursive_merge!(h)
    self.merge!(h) {|key, _old, _new| if _old.class == Hash then _old.recursive_merge!(_new) else _new end  }
  end
end
