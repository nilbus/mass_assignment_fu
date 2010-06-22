# AttributeFu

# this lib file contains some methods that might be useful for active records

module AttributeFu
  def self.included(base)
    base.send :extend, ClassMethods
  end

  module ClassMethods
    def nested_attr_accessible_for(fieldset, fields)
      send :include, InstanceMethods
      cattr_accessor :naa_fieldsets
      self.naa_fieldsets ||= {}
      self.naa_fieldsets[fieldset.to_sym] = fields
    end

    def create_for(fieldset, attribute_hash)
      object = self.new
      return object.update_with_protected(fieldset, attribute_hash)
    end
    
    def create_for!(fieldset, attribute_hash)
      object = self.new
      return object.update_with_protected!(fieldset, attribute_hash)
    end
    
    
    def associated_class(association)
      begin
        return reflect_on_association(association).klass
      rescue
        return nil
      end
    end
    
    def new_associated_class(association)
      return associated_class.new
    end
  
  end

  module InstanceMethods
    def update_attributes_for(fieldset, attribute_hash)
      _update_with_protected(fieldset, attribute_hash)
      return self.save
    end
    
    def update_attributes_for!(fieldset, attribute_hash)
      _update_with_protected(fieldset, attribute_hash)
      return self.save!
    end


    
    protected

      def _update_with_protected(fieldset, updated_attributes)
        @naa_fieldset = nil
        # Look up a named fieldset, if it exists. Otherwise assume an array of attributes was passed in
        if self.class.naa_fieldsets[fieldset.to_sym]
          allowed_attribute_names = self.class.naa_fieldsets[fieldset.to_sym]
          @naa_fieldset = fieldset
        elsif fieldset.is_a? Array
          allowed_attribute_names = fieldset
        else
          allowed_attribute_names = []
          logger.warn "No nested_attr_accessible_for fieldset found with name '#{fieldset}' for #{self.class.name}"
        end
        updated_attributes = remove_disallowed_attributes_from_mass_assignment(updated_attributes, allowed_attribute_names.stringify)
        self.send(:attributes=, updated_attributes, false) # Turn off protected attributes since we removed the disallowed attributes
      end
      
  end
end

ActiveRecord::Base.send :include, AttributeFu
module ActiveRecord
  class Base
    def remove_disallowed_attributes_from_mass_assignment(attributes, allowed_attributes, nest_level = 0)
      return attributes if attributes.nil? or attributes.empty?
      allowed_attributes = allowed_attributes.to_a
      
      safe_attribute_names = Array.new # array version of the allowed attributes
      safe_attribute_hash = Hash.new # hash version of safe_attribute_names
      safe_attributes = Hash.new # A hash of all the attributes that pass and will be updated
      
      # Merge with attr_accessible and attr_protected specified in the model
      # Sets safe_attribute_names = accessile_attributes + allowed_attributes
      if self.class.accessible_attributes.nil? && self.class.protected_attributes.nil?
        safe_attribute_names = allowed_attributes
      elsif self.class.protected_attributes.nil? # accessible_attributes are set
        safe_attribute_names = (self.class.accessible_attributes + allowed_attributes)
      elsif self.class.accessible_attributes.nil? # protected_attributes are set
        safe_attribute_names = allowed_attributes
      else
        raise "Declare either attr_protected or attr_accessible for #{self.class}, but not both."
      end
      
      # Build a safe_attribute_hash out of safe_attribute_names
      # safe_attribute_names [:a, {:b => :c}] becomes safe_attribute_hash {:a => true, :b => :c}
      # Some attributes in safe_attribute_names may be hashes, and some arrays or symbols
      safe_attribute_names.each do |safe_attribute_name|
        if safe_attribute_name.is_a?(Hash)
          safe_attribute_name.each do |key, value|
            safe_attribute_hash.store(key, value)
          end
        else
          safe_attribute_hash.store(safe_attribute_name, true)
        end
      end

      # convert all keys and values to strings
      safe_attribute_hash = safe_attribute_hash.stringify
      
      # Scan through each of the attributes to update, and add the allowed ones to the safe list
      attributes.each do |key, value|
        associated_class = nil
        if key =~ /\w+_attributes/
          association_name = key.gsub("_attributes","").to_sym
          associated_class = associated_class(association_name)
        end
        
        # See if this attribute could be assignable
        if ((safe_attribute_hash.keys.include?(key.gsub(/\(.+/, "")) or key =~ /\d+/) and !attributes_protected_by_default.include?(key.gsub(/\(.+/, ""))) or (nest_level > 0 and key == "id")
          unless value.is_a?(Hash)
            safe_attributes.store(key, value)
          else # it is a hash
            if safe_attribute_hash[key] == "all" and associated_class
              # {:association => 'all'} includes all of association's properties but not its associations. It translates to
              # {:association => ['attr1', 'attr2', 'attrN', '_delete']}
              safe_attributes.store(key, associated_class.new.remove_disallowed_attributes_from_mass_assignment(value, associated_class.new.attributes.keys << '_delete', nest_level+1))
            elsif safe_attribute_hash[key] == true and associated_class
              # When one of the allowed_attributes was an associated_class but no fields are specified,
              # check the associated_class model's nested_attr_accessible_for, attr_accessible, and attr_protected.
              # If child attributes are not explicitly allowed by the model or nested_attr_accessible_for, they are not allowed.
              associated_class_safe_attributes = []
              associated_class_safe_attributes = associated_class.naa_fieldsets[@naa_fieldset] if @naa_fieldset && defined?(associated_class.naa_fieldsets) && associated_class.naa_fieldsets[@naa_fieldset]
              safe_attributes.store(key, associated_class.new.remove_disallowed_attributes_from_mass_assignment(value, associated_class_safe_attributes, nest_level+1))
            elsif key == "id"
              # Keep the ids of associated models - you don't need to specify 'id' as allowed
              safe_attributes.store(key, value)
            else
              if key =~ /\d+/
                # forms for has_many relationships may generate params like {:comments => {'1' => {:text => 'foo'}, '2' => {:text => 'bar'}}}
                # recurse with the same allowed_attributes as this level
                safe_attributes.store(key, remove_disallowed_attributes_from_mass_assignment(value, allowed_attributes, nest_level+1))
              elsif associated_class
                safe_attributes.store(key, associated_class.new.remove_disallowed_attributes_from_mass_assignment(value, safe_attribute_hash[key], nest_level+1))
              else
                safe_attributes.store(key, remove_disallowed_attributes_from_mass_assignment(value, safe_attribute_hash[key], nest_level+1))
              end
            end
          end
        else
          Rails.logger.debug "not updating #{key}; not in allowed set of attributes: #{safe_attribute_names}"
        end
      end

      removed_attributes = attributes.keys - safe_attributes.keys

      if removed_attributes.any?
        log_protected_attribute_removal(removed_attributes)
      end


      return safe_attributes
    end
    
    def associated_class(association)
      return self.class.associated_class(association)
    end
    
    def new_associated_class(association)
      return self.class.new_associated_class(association)
    end

  end
end
    

class Array
  def stringify
    new_array = []
    self.each do |item|
      new_array << (item.respond_to?(:stringify) ? item.stringify : item.to_s)
    end
    
    return new_array
  end
end

class Hash
  def stringify
    new_hash = {}
    self.each { |k, v| new_hash.store(k.to_s, (v.respond_to?(:stringify) ? v.stringify : v.to_s)) }
    return new_hash
  end
end
