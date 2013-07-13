class Lxc
  module Helpers

    module Options
      class << self
        def included(klass)
          klass.class_eval do
            attr_reader :options
            
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

      private

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
        raise ArgumentError.new "Invalid type provided for #{arg_name}. Expecting value type of: #{type.inspect} Got: #{val.class} -  #{val}" unless valid
      end
    end
  end
end
