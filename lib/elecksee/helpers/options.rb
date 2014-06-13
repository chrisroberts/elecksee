require 'elecksee'

class Lxc
  module Helpers
    # Helper methods for processing CLI options
    module Options
      class << self
        # Load option helper into included class
        #
        # @param klass [Class]
        # @return [TrueClass]
        def included(klass)
          klass.class_eval do
            class << self

              # @return [Hash] options
              attr_reader :options

              # Define option
              #
              # @param name [String] name of option
              # @param short [String] short flag
              # @param long [String] long flag
              # @param args [Hash]
              def option(name, short, type, args={})
                @options ||= {}
                @options[name] = args.merge(:short => short, :type => type)
                instance_eval do
                  attr_accessor name.to_sym
                end
              end
            end
          end
        end
      end

      private

      # Configure instance and validate options
      #
      # @param args [Array]
      def configure!(args)
        self.class.options.each do |name, opts|
          argv = args.detect{|k,v| (Array(opts[:aliases]) + Array(opts[:short]) + [name]).include?(k.to_sym)}
          argv = argv.last if argv
          argv ||= opts[:default]
          if(argv)
            check_type!(name, argv, opts[:type])
            self.send("#{name}=", argv)
          else
            if(opts[:required])
              raise ArgumentError.new "Missing required argument: #{name}"
            end
          end
        end
        if(ipaddress && gateway.nil?)
          self.gateway = ipaddress.sub(%r{\d+$}, '1')
        end
      end

      # Validate option type
      #
      # @param arg_name [String]
      # @param val [Object]
      # @param type [Symbol] expected type
      # @return [TrueClass]
      def check_type!(arg_name, val, type)
        valid = false
        case type
        when :string
          valid = val.is_a?(String)
        when :boolean
          valid = val.is_a?(TrueClass) || val.is_a?(FalseClass)
        when :integer
          valid = val.is_a?(Numeric)
        end
        unless(valid)
          raise ArgumentError.new "Invalid type provided for #{arg_name}. Expecting value type of: #{type.inspect} Got: #{val.class} -  #{val}"
        end
        true
      end
    end
  end
end
