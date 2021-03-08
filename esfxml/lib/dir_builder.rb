# Allocate file names for the entire directory
class DirBuilder
  attr_reader :xml_printer
  # Semanitc names extras
  attr_accessor :faction_name
  attr_accessor :region_data_num
  
  def initialize(out_dir)
    @out_dir = out_dir
    @path_allocator = Hash.new
    @xml_printer = nil
    FileUtils.mkdir_p @out_dir
    @semantic_names_stack = []
    @region_data_num = 0
  end

  def save_binfile(base_name, semantic_name, ext, data)
    path, rel_path = alloc_new_path(base_name, semantic_name, ext)
    File.open(path, 'wb'){|fh| fh.write data}
    rel_path
  end
  
  def open_xml(new_xml_printer)
    @xml_printer.flush! if @xml_printer
    prev_printer = @xml_printer
    @xml_printer = new_xml_printer
    @xml_printer.out!("<?xml version=\"1.0\"?>")
    yield
    @xml_printer.close
    @xml_printer = prev_printer
    new_xml_printer.rel_path
  end
  
  def open_main_xml(&blk)
    open_xml(XMLPrinter.new(File.join(@out_dir, 'esf.xml'), 'esf.xml'), &blk)
  end

  def open_nested_xml(base_name, semantic_name, &blk)
    @semantic_names_stack << semantic_name
    use_semantic_name = @semantic_names_stack.compact[-1]
    rv = open_xml(XMLPrinter.new(*alloc_new_path(base_name, use_semantic_name, ".xml")), &blk)
    @semantic_names_stack.pop
    rv
  end

  def alloc_new_path(base_name, semantic_name, ext)
    semantic_name = semantic_name.gsub(/[:\/\/]/, "-") if semantic_name
    alloc_key = [base_name, semantic_name, @faction_name, @region_data_num, ext]
    name = base_name
    name = name.gsub("%R", @region_data_num.to_s)
    if name =~ /%f/
      fn = @faction_name || ""
      if fn == ""
        # Delete - after %f if %f is empty
        name = name.sub(/%f-?/, "")
      else
        name = name.sub("%f", fn)
      end
    end
    if name =~ /%s/
      sn = semantic_name || ""
      if sn == ""
        # Delete - after %s if %s is empty
        name = name.sub(/%s-?/, "")
      else
        name = name.sub("%s", sn)
      end
    elsif semantic_name
      name += "-" unless name =~ /[-\/]\z/
      name += "#{semantic_name}"
    end
    while true
      rel_path = name
      i = (@path_allocator[alloc_key] ||= (name =~ /%d|\/\z/ ? 1 : 0))
      @path_allocator[alloc_key] += 1
      ix = "%04d" % i
      if name =~ /%d/
        rel_path = rel_path.sub("%d", ix)
      elsif name =~ /%D/
          rel_path = rel_path.sub("%D", ix)
      elsif i > 0
        rel_path += "-" unless rel_path =~ /[-\/]\z/
        rel_path += ix
      elsif rel_path =~ /[-\/]\z/
        rel_path += ix
      end
      rel_path += ext
      path = File.join(@out_dir, rel_path)
      unless File.exist?(path)
        dirname = File.dirname(path)
        FileUtils.mkdir_p dirname unless File.exist?(dirname)
        return [path, rel_path]
      end
    end
  end
end

# Printer for a single XML output
class XMLPrinter
  attr_reader :out_buf, :rel_path
  def initialize(out_path, rel_path)
    @rel_path = rel_path
    @out_fh   = File.open(out_path, 'wb')
    # @out_fh.sync = true # for easier debugging
    @out_buf  = ""
    @stack    = []
    @indent   = Hash.new{|ht,k| ht[k]=" "*k}
  end
  def flush!
    @out_fh.write @out_buf
    @out_buf = ""
  end
  def close
    flush!
    @out_fh.close
  end
  def tag!(name, attrs=nil)
    attrs = attrs_to_s(attrs) if attrs
    if block_given?
      out! "<#{name}#{attrs}>"
      @stack << name
      yield
      @stack.pop
      out! "</#{name}>"
    else
      out! "<#{name}#{attrs}/>"
    end
  end
  def out!(str)
    @out_buf << @indent[@stack.size] << str << "\n"
    flush! if @out_buf.size > 1_000_000
    # flush! # for easier debugging
  end
  def out_ary!(tag, attrs, data)
    if data.empty?
      out! "<#{tag}#{attrs}/>"
    else
      out! "<#{tag}#{attrs}>"
      data.each{|line| out! line}
      out! "</#{tag}>"
    end
  end
  private
  def attrs_to_s(attrs={})
    attrs.to_a.map{|k,v| v.nil? ? "" : " #{k}=\"#{v.to_s.xml_escape}\""}.sort.join
  end
end
