require 'elecksee'
require 'attribute_struct'

class Lxc
  # Configuration file interface
  class FileConfig

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

    # @return [String] path to config file
    attr_reader :path
    # @return [AttrubuteStruct] config file contents
    attr_reader :state

    # Create new instance
    #
    # @param path [String]
    def initialize(path)
      raise 'LXC config file not found' unless File.exists?(path)
      @path = path
      parse!
    end

    # @return [Smash] hash like dump of state
    def state_hash
      state._dump.to_smash
    end

    # Overwrite the config file
    #
    # @return [Integer]
    def write!
      File.write(path, generate_content)
    end

    # Generate config file content from current value of state
    #
    # @return [String]
    def generate_content
      process_item(state_hash).flatten.join("\n")
    end

    private

    def process_item(item, parents=[])
      case item
      when Hash
        item.map do |k,v|
          process_item(v, parents + [k])
        end
      when Array
        item.map do |v|
          process_item(v, parents)
        end
      else
        "#{parents.join('.')} = #{item}"
      end
    end

    # Parse the configuration file
    #
    # @return [AttributeStruct]
    def parse!
      struct = LxcStruct.new
      struct._set_state(:value_collapse => true)
      File.read(path).split("\n").each do |line|
        parts = line.split('=').map(&:strip)
        parts.last.replace("'#{parts.last}'")
        struct.instance_eval(parts.join(' = '))
      end
      @state = struct
    end

  end
end

class LxcStruct < AttributeStruct

  def network(*args, &block)
    unless(self[:network])
      set!(:network, ::AttributeStruct::CollapseArray.new)
      self[:network].push(_klass_new)
    end
    if(self[:network].last._data[:type].is_a?(::AttributeStruct::CollapseArray))
      val = self[:network].last._data[:type].pop
      self[:network].push(_klass_new)
      self[:network].last.set!(:type, val)
    end
    self[:network].last
  end

  def _klass
    ::LxcStruct
  end

end
