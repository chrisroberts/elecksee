require 'elecksee'

class Lxc
  # Configuration file interface
  class FileConfig

    # @return [Array]
    attr_reader :network
    # @return [String] path to configuration file
    attr_reader :base

    class << self

      # Convert object to Hash if possible
      #
      # @param thing [Object]
      # @return [Hash]
      # @note used mostly for the lxc resource within chef
      def convert_to_hash(thing)
        if(defined?(Chef) && thing.is_a?(Chef::Resource))
          result = Hash[*(
              (thing.methods - Chef::Resource.instance_methods).map{ |key|
                unless(key.to_s.start_with?('_') || thing.send(key).nil?)
                  [key, thing.send(key)]
                end
              }.compact.flatten(1)
          )]
        else
          unless(thing.is_a?(Hash))
            result = defined?(Mash) ? Mash.new : {}
            thing.to_hash.each do |k,v|
              result[k] = v.respond_to?(:keys) && v.respond_to?(:values) ? convert_to_hash(v) : v
            end
          end
        end
        result || thing
      end

      # Symbolize keys within hash
      #
      # @param thing [Hashish]
      # @return [Hash]
      def symbolize_hash(thing)
        if(defined?(Mash))
          Mash.new(thing)
        else
          result = {}
          thing.each do |k,v|
            result[k.to_sym] = v.is_a?(Hash) ? symbolize_hash(v) : v
          end
          result
        end
      end

      # Generate configuration file contents
      #
      # @param resource [Hashish]
      # @return [String]
      def generate_config(resource)
        resource = symbolize_hash(convert_to_hash(resource))
        config = []
        config << "lxc.utsname = #{resource[:utsname]}"
        if(resource[:aa_profile])
          config << "lxc.aa_profile = #{resource[:aa_profile]}"
        end
        [resource[:network]].flatten.each do |net_hash|
          nhsh = Mash.new(net_hash)
          flags = nhsh.delete(:flags)
          %w(type link).each do |k|
            config << "lxc.network.#{k} = #{nhsh.delete(k)}" if nhsh[k]
          end
          nhsh.each_pair do |k,v|
            config << "lxc.network.#{k} = #{v}"
          end
          if(flags)
            config << "lxc.network.flags = #{flags}"
          end
        end
        if(resource[:cap_drop])
          config << "lxc.cap.drop = #{Array(resource[:cap_drop]).join(' ')}"
        end
        %w(include pts tty arch devttydir mount mount_entry rootfs rootfs_mount pivotdir).each do |k|
          config << "lxc.#{k.sub('_', '.')} = #{resource[k.to_sym]}" if resource[k.to_sym]
        end
        prefix = 'lxc.cgroup'
        resource[:cgroup].each_pair do |key, value|
          if(value.is_a?(Array))
            value.each do |val|
              config << "#{prefix}.#{key} = #{val}"
            end
          else
            config << "#{prefix}.#{key} = #{value}"
          end
        end
        config.join("\n") + "\n"
      end

    end

    # Create new instance
    #
    # @param path [String]
    def initialize(path)
      raise 'LXC config file not found' unless File.exists?(path)
      @path = path
      @network = []
      @base = defined?(Mash) ? Mash.new : {}
      parse!
    end

    private

    # Parse the configuration file
    #
    # @return [TrueClass]
    def parse!
      cur_net = nil
      File.readlines(@path).each do |line|
        if(line.start_with?('lxc.network'))
          parts = line.split('=')
          name = parts.first.split('.').last.strip
          if(name.to_sym == :type)
            @network << cur_net if cur_net
            cur_net = Mash.new
          end
          if(cur_net)
            cur_net[name] = parts.last.strip
          else
            raise "Expecting 'lxc.network.type' to start network config block. Found: 'lxc.network.#{name}'"
          end
        else
          parts = line.split('=')
          name = parts.first.sub('lxc.', '').strip
          if(@base[name])
            @base[name] = [@base[name], parts.last.strip].flatten
          else
            @base[name] = parts.last
          end
        end
      end
      @network << cur_net if cur_net
      true
    end

  end
end
