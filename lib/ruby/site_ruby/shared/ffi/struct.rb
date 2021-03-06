module FFI
  class Struct

    def size
      self.class.size
    end
    
    def alignment
      self.class.alignment
    end
    alias_method :align, :alignment

    def offset_of(name)
      self.class.offset_of(name)
    end

    def members
      self.class.members
    end

    def values
      members.map { |m| self[m] }
    end

    def offsets
      self.class.offsets
    end

    def clear
      pointer.clear
      self
    end

    def to_ptr
      pointer
    end

    def self.size
      defined?(@layout) ? @layout.size : defined?(@size) ? @size : 0
    end

    def self.size=(size)
      raise ArgumentError, "Size already set" if defined?(@size) || defined?(@layout)
      @size = size
    end

    def self.alignment
      @layout.alignment
    end

    def self.align
      @layout.alignment
    end

    def self.members
      @layout.members
    end

    def self.offsets
      @layout.offsets
    end

    def self.offset_of(name)
      @layout.offset_of(name)
    end

    def self.in
      :buffer_in
    end

    def self.out
      :buffer_out
    end

    def self.by_value
      ::FFI::StructByValue.new(self)
    end

    

    class << self
      public

      def layout(*spec)
        return @layout if spec.size == 0

        builder = FFI::StructLayoutBuilder.new
        builder.union = self < Union
        if spec[0].kind_of?(Hash)
          hash_layout(builder, spec)
        else
          array_layout(builder, spec)
        end
        builder.size = @size if defined?(@size) && @size > builder.size
        cspec = builder.build
        @layout = cspec unless self == FFI::Struct
        @size = cspec.size
        return cspec
      end


      protected

      def callback(params, ret)
        mod = enclosing_module
        FFI::CallbackInfo.new(find_type(ret, mod), params.map { |e| find_type(e, mod) })
      end

      
      def enclosing_module
        begin
          mod = self.name.split("::")[0..-2].inject(Object) { |obj, c| obj.const_get(c) }
          mod.respond_to?(:find_type) ? mod : nil
        rescue Exception => ex
          nil
        end
      end

      def find_type(type, mod = nil)
        if type.kind_of?(Class) && type < FFI::Struct
          FFI::Type::Struct.new(type)
        elsif type.is_a?(::Array)
          type
        elsif mod
          mod.find_type(type)
        end || FFI.find_type(type)
      end

      
      private

      def hash_layout(builder, spec)
        raise "Ruby version not supported" if RUBY_VERSION =~ /1.8.*/ && !(RUBY_PLATFORM =~ /java/)
        mod = enclosing_module
        spec[0].each do |name,type|
          if type.kind_of?(Class) && type < Struct
            builder.add_struct(name, type)
          elsif type.kind_of?(::Array)
            builder.add_array(name, find_type(type[0], mod), type[1])
          else
            builder.add_field(name, find_type(type, mod))
          end
        end
      end

      def array_layout(builder, spec)
        mod = enclosing_module
        i = 0
        while i < spec.size
          name, type = spec[i, 2]
          i += 2

          # If the next param is a Integer, it specifies the offset
          if spec[i].kind_of?(Integer)
            offset = spec[i]
            i += 1
          else
            offset = nil
          end
          if type.kind_of?(Class) && type < Struct
            builder.add_struct(name, type, offset)
          elsif type.kind_of?(::Array)
            builder.add_array(name, find_type(type[0], mod), type[1], offset)
          else
            builder.add_field(name, find_type(type, mod), offset)
          end
        end
      end

      #
      # FIXME This is here for backwards compat with rbx.  No idea if it
      # even works anymore, but left here for now.
      #
      protected
      def config(base, *fields)
        config = FFI::Config::CONFIG

        builder = FFI::StructLayoutBuilder.new

        fields.each do |field|
          offset = config["#{base}.#{field}.offset"]
          size   = config["#{base}.#{field}.size"]
          type   = config["#{base}.#{field}.type"]
          type   = type ? type.to_sym : FFI.size_to_type(size)

          code = FFI.find_type type
          if (code == NativeType::CHAR_ARRAY)
            builder.add_char_array(field.to_s, size, offset)
          else
            builder.add_field(field.to_s, code, offset)
          end
        end
        size = config["#{base}.sizeof"]
        builder.size = size if size > builder.size
        cspec = builder.build

        @layout = cspec
        @size = cspec.size

        return cspec
      end      
    end
  end


  class Union < Struct
    # Nothing to do here
  end
  
end
