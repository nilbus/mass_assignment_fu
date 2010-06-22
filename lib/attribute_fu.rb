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

    def remove_disallowed_attributes_from_mass_assignment(assigned_attributes, explicitly_allowed_attributes, nest_level = 0)
      return assigned_attributes if assigned_attributes.nil? or assigned_attributes.empty?

      # Start with what was specified in nested_attr_accessible_for
      safe_attributes = explicitly_allowed_attributes.to_a.flatten
      # Add anything marked attr_accessible in the model
      safe_attributes += self.class.accessible_attributes unless self.class.accessible_attributes.nil?
      safe_attributes = safe_attributes.hashify.stringify

      kept_attributes = updatable_attributes(assigned_attributes, safe_attributes, explicitly_allowed_attributes, nest_level)
      filtered_attributes = assigned_attributes.keys - kept_attributes.keys
      log_protected_attribute_removal(filtered_attributes) if filtered_attributes.any?

      return kept_attributes
    end
    
    def self.find_associated_class(association)
      begin
        return reflect_on_association(association).klass
      rescue
        return nil
      end
    end
    
    def self.new_associated_class(association)
      return find_associated_class.new
    end
  
    def find_associated_class(association)
      return self.class.find_associated_class(association)
    end
    
    def new_associated_class(association)
      return self.class.new_associated_class(association)
    end

    private
      # Scan through each of the assigned_attributes, and add the allowed ones to the safe list
      def updatable_attributes(assigned_attributes, safe_attributes, explicitly_allowed_attributes, nest_level)
        kept_attributes = {}

        assigned_attributes.each do |key, value|
          associated_class = nil
          if key =~ /\w+_attributes/
            association_name = key.gsub("_attributes","").to_sym
            associated_class = find_associated_class(association_name)
          end
          
          # See if this attribute could be assignable
          if ((safe_attributes.keys.include?(key.gsub(/\(.+/, "")) or key =~ /\d+/) and !attributes_protected_by_default.include?(key.gsub(/\(.+/, ""))) or (nest_level > 0 and key == "id")
            unless value.is_a?(Hash)
              kept_attributes.store(key, value)
            else # it is a hash
              if safe_attributes[key] == "all" and associated_class
                # {:association => 'all'} includes all of association's properties but not its associations. It translates to
                # {:association => ['attr1', 'attr2', 'attrN', '_delete']}
                kept_attributes.store(key, associated_class.new.remove_disallowed_attributes_from_mass_assignment(value, associated_class.new.attributes.keys << '_delete', nest_level+1))
              elsif safe_attributes[key] == "true" and associated_class
                # When one of the allowed_attributes was an associated_class but no fields are specified,
                # check the associated_class model's nested_attr_accessible_for, attr_accessible, and attr_protected.
                # If child attributes are not explicitly allowed by the model or nested_attr_accessible_for, they are not allowed.
                associated_class_safe_attributes = []
                associated_class_safe_attributes = associated_class.naa_fieldsets[@naa_fieldset] if @naa_fieldset && defined?(associated_class.naa_fieldsets) && associated_class.naa_fieldsets[@naa_fieldset]
                kept_attributes.store(key, associated_class.new.remove_disallowed_attributes_from_mass_assignment(value, associated_class_safe_attributes, nest_level+1))
              elsif key == "id"
                # Keep the ids of associated models - you don't need to specify 'id' as allowed
                kept_attributes.store(key, value)
              else
                if key =~ /\d+/
                  # forms for has_many relationships may generate params like {:comments => {'1' => {:text => 'foo'}, '2' => {:text => 'bar'}}}
                  # recurse with the same explicitly_allowed_attributes as this level
                  kept_attributes.store(key, remove_disallowed_attributes_from_mass_assignment(value, explicitly_allowed_attributes, nest_level+1))
                elsif associated_class
                  kept_attributes.store(key, associated_class.new.remove_disallowed_attributes_from_mass_assignment(value, safe_attributes[key], nest_level+1))
                else
                  kept_attributes.store(key, remove_disallowed_attributes_from_mass_assignment(value, safe_attributes[key], nest_level+1))
                end
              end
            end
          else
            Rails.logger.debug "not updating #{key}; not in allowed set of attributes: #{safe_attributes.keys}"
          end
        end
        return kept_attributes
      end

  end
end
    

class Array
  # convert all keys and values to strings
  def stringify
    new_array = []
    self.each do |item|
      new_array << (item.respond_to?(:stringify) ? item.stringify : item.to_s)
    end
    
    return new_array
  end

  # [:a, {:b => :c}] becomes {:a => true, :b => :c}
  def hashify
    hash = {}
    each do |item|
      if item.is_a?(Hash)
        item.each do |key, value|
          hash.store(key, value)
        end
      else
        hash.store(item, true)
      end
    end
    return hash
  end

end

class Hash
  # convert all keys and values to strings
  def stringify
    new_hash = {}
    self.each { |k, v| new_hash.store(k.to_s, (v.respond_to?(:stringify) ? v.stringify : v.to_s)) }
    return new_hash
  end
end
