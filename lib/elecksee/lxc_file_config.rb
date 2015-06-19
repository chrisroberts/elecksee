require 'elecksee'
require 'attribute_struct'

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

class Lxc
  # Configuration file interface
  class FileConfig

    # @return [String] path to config file
    attr_reader :path
    # @return [AttrubuteStruct] config file contents
    attr_accessor :state

    # Create new instance
    #
    # @param path [String]
    def initialize(path)
      @path = path
      if(File.exists?(path))
        parse!
      else
        @state = LxcStruct.new
      end
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

    # Convert item to configuration file line
    #
    # @param item [Object]
    # @param parents [Array<String>] parent hash keys
    # @return [Array<String>]
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
        ["#{parents.join('.')} = #{item}"]
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
