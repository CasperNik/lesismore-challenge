module ApplicationHelper
  include ::Core::Helpers

  def link_to_page(name, opts = nil)
    opts = name if !opts
    opts[:name] = name if name.is_a?(String)
    opts[:name] ||= opts[:title]
    link_to(opts[:name], post_path(opts[:title]))
    #opts.inspect
  end

  def decoderay(text)
    regex = /<% coderay\((.+?)\) do [-]*%>(.+?)<% end [-]*%>/m

    text.gsub(regex) do
      opts, subtext = $1, $2

      opts = eval("{#{opts}}")
      #puts "------------------------ decoderay:"
      #p opts
      #puts "------------------------"
      CodeRay.scan(subtext, opts[:lang]).div(:line_numbers => :table,
        :tab_width => 2, :css => :class, :wrap => :div)
    end
  end
end
