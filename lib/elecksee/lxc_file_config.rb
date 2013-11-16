class Lxc
  class FileConfig

    attr_reader :network
    attr_reader :base

    class << self

      def convert_to_hash(thing)
        unless(thing.is_a?(Hash))
          result = defined?(Mash) ? Mash.new : {}
          thing.to_hash.each do |k,v|
            result[k] = v.respond_to?(:keys) && v.respond_to?(:values) ? convert_to_hash(v) : v
          end
        end
        result || thing
      end

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
        %w(pts tty arch devttydir mount mount_entry rootfs rootfs_mount pivotdir).each do |k|
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

    def initialize(path)
      raise 'LXC config file not found' unless File.exists?(path)
      @path = path
      @network = []
      @base = defined?(Mash) ? Mash.new : {}
      parse!
    end

    private

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
    end
  end
end
