# encoding: utf-8
require "mongoid/enum/enum_type"
require "mongoid/enum/invalid_key"
require "mongoid/enum/invalid_value"

module Mongoid # :nodoc:
  module Enum
    extend ActiveSupport::Concern

    included do
      class_attribute(:Ver)
      self.enums = {}
    end

    # :nodoc:
    module ClassMethods
      # Define enum field on the model. See description of Mongoid::Enum
      def enum(definitions)
        klass = self
        enum_prefix = definitions.delete(:_prefix)
        enum_suffix = definitions.delete(:_suffix)
        default_key = definitions.delete(:_default)
        pluralize   = definitions.delete(:_plural_scopes)

        definitions.each do |name, values|
          enum_values = ActiveSupport::HashWithIndifferentAccess.new
          name        = name.to_sym
          const_name  = name.to_s.pluralize.upcase

          if klass.const_defined?(const_name)
            fail ArgumentError, "Defining enum :#{name} on #{klass} would overwrite existing constant #{klass}::#{const_name}"
          end

          detect_enum_conflict!(name, name)
          detect_enum_conflict!(name, "#{name}=")

          if values.respond_to? :each_pair
            values.each_pair { |key, value| enum_values[key.to_s] = value }
          else
            values.each { |v| enum_values[v.to_s] = v.to_s }
          end

          enum_values.each do |key, value|
            key.freeze
            value.freeze
          end
          enum_values.freeze

          if default_key && !enum_values.key?(default_key)
            fail ArgumentError, "default key #{default_key} is not among enum options"
          end

          field name, type: EnumType.new(enum_values), default: default_key

          klass.const_set const_name, enum_values
          klass.validates name,
                          inclusion: {
                            in: enum_values.keys,
                            allow_nil: true,
                            message: "is invalid"
                          }

          _enum_methods_module.module_eval do
            enum_values.each do |key, value|
              if enum_prefix == true
                prefix = "#{name}_"
              elsif enum_prefix
                prefix = "#{enum_prefix}_"
              end
              if enum_suffix == true
                suffix = "_#{name}"
              elsif enum_suffix
                suffix = "_#{enum_suffix}"
              end

              value_method_name = "#{prefix}#{key}#{suffix}"
              scope_name = pluralize ? value_method_name.pluralize : value_method_name

              # def active?() status == 0 end
              klass.send(:detect_enum_conflict!, name, "#{value_method_name}?")
              define_method("#{value_method_name}?") { self[name] == value }

              # def active!() update! status: :active end
              klass.send(:detect_enum_conflict!, name, "#{value_method_name}!")
              define_method("#{value_method_name}!") { update! name => key }

              # scope :active, -> { where status: 0 }
              klass.send(:detect_enum_conflict!, name, scope_name, true)
              klass.scope scope_name, -> { klass.where name => key }
            end
          end

          # dup so children classes don't add their own enums to parent definitions
          self.enums = enums.dup

          enums[name] = enum_values
          enums.freeze
        end
      end

      private

      def _enum_methods_module
        @_enum_methods_module ||= begin
          mod = Module.new
          include mod
          mod
        end
      end

      # :nodoc:
      ENUM_CONFLICT_MESSAGE = "You tried to define an enum named \"%{enum}\" on the model \"%{klass}\", but this will generate %{type} method \"%{method}\", which is already defined."

      def detect_enum_conflict!(enum_name, method_name, class_method = false)
        method_name = method_name.to_sym

        if class_method
          if self.respond_to?(method_name, true)
            raise_conflict_error(enum_name, method_name, "class")
          end
        else
          if Mongoid.destructive_fields.include?(method_name) ||
             instance_methods.include?(method_name)
            raise_conflict_error(enum_name, method_name, "instance")
          end
        end
      end

      def raise_conflict_error(enum_name, method_name, type)
        fail ArgumentError, ENUM_CONFLICT_MESSAGE % {
          enum: enum_name,
          klass: name,
          type: type,
          method: method_name
        }
      end
    end
  end
end
