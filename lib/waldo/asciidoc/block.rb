# Public: Methods for managing blocks of Asciidoc content in a section.
#
# Examples
#
#   block = Asciidoc::Block.new(:paragraph, ["`This` is a <test>"])
#   block.content
#   => ["<em>This</em> is a &lt;test&gt;"]
class Asciidoc::Block
  # Public: Get the Symbol context for this section block.
  attr_reader :context

  # Public: Get the Array of sub-blocks for this section block.
  attr_reader :blocks

  # Public: Get/Set the original Array content for this section block.
  attr_accessor :buffer

  # Public: Get/Set the String section anchor name.
  attr_accessor :anchor

  # Public: Get/Set the String block title.
  attr_accessor :title

  # Public: Get/Set the String block caption.
  attr_accessor :caption

  # Public: Initialize an Asciidoc::Block object.
  #
  # parent  - The parent Asciidoc Object.
  # context - The Symbol context name for the type of content.
  # buffer  - The Array buffer of source data.
  def initialize(parent, context, buffer=nil)
    @parent = parent
    @context = context
    @buffer = buffer

    @blocks = []
  end

  # Public: Get the Asciidoc::Document instance to which this Block belongs
  def document
    @parent.is_a?(Asciidoc::Document) ? @parent : @parent.document
  end

  # Public: Get the Asciidoc::Renderer instance being used for the ancestor
  # Asciidoc::Document instance.
  def renderer
    @parent.renderer
  end

  # Public: Get the rendered String content for this Block.  If the block
  # has child blocks, the content method should cause them to be
  # rendered and returned as content that can be included in the
  # parent block's template.
  def render
    Waldo.debug "Now attempting to render for #{context} my own bad #{self}"
    Waldo.debug "Parent is #{@parent}"
    Waldo.debug "Renderer is #{renderer}"
    renderer.render("section_#{context}", self)
  end

  # Public: Get an HTML-ified version of the source buffer, with special
  # Asciidoc characters and entities converted to their HTML equivalents.
  #
  # Examples
  #
  #   block = Asciidoc::Block.new(:paragraph, ['`This` is what happens when you <meet> a stranger in the <alps>!'])
  #   block.content
  #   => ["<em>This</em> is what happens when you &lt;meet&gt; a stranger in the &lt;alps&gt;!"]
  #
  # TODO:
  # * forced line breaks
  # * bold, mono
  # * double/single quotes
  # * super/sub script
  def content
    case @context
    when :dlist
      @buffer.map do |dt, dd|
        if !dt.anchor.nil? && !dt.anchor.empty?
          html_dt = "<a id=#{dt.anchor}></a>" + htmlify(dt.content)
        else
          html_dt = htmlify(dt.content)
        end
        if dd.content.empty?
          html_dd = ''
        else
          html_dd = "<p>#{htmlify(dd.content)}</p>"
        end
        html_dd += dd.blocks.map{|block| block.render}.join

        [html_dt, html_dd]
      end
    when :oblock, :quote
      blocks.map{|block| block.render}.join
    when :olist, :ulist, :colist
      @buffer.map do |li|
        htmlify(li.content) + li.blocks.map{|block| block.render}.join
      end
    when :listing
      @buffer.map{|l| CGI.escapeHTML(l).gsub(/(<\d+>)/,'<b>\1</b>')}.join
    when :literal
      htmlify( @buffer.join.gsub( '*', '{asterisk}' ).gsub( '\'', '{apostrophe}' ))
    when :verse
      htmlify( @buffer.map{ |l| l.strip }.join( "\n" ) )
    else
      htmlify( @buffer.map{ |l| l.lstrip }.join )
    end
  end

  private

  # Private: Return a String HTML version of the source string, with
  # Asciidoc characters converted and HTML entities escaped.
  #
  # string - The String source string in Asciidoc format.
  #
  # Examples
  #
  #   asciidoc_string = "Make 'this' <emphasized>"
  #   htmlify(asciidoc_string)
  #   => "Make <em>this</em> &lt;emphasized&gt;"
  def htmlify(string)
    unless string.nil?
      html = string.dup

      # Convert reference links to "link:" asciidoc for later HTMLification.
      # This ensures that eg. "<<some reference>>" is turned into a link but
      # "`<<<<<` and `>>>>>` are conflict markers" is not.  This is much
      # easier before the HTML is escaped and <> are turned into entities.
      html.gsub!( /(^|[^<])<<([^<>,]+)(,([^>]*))?>>/ ) { "#{$1}link:##{$2}[" + ($4.nil? ? document.references[$2] : $4).to_s + "]" }

      # Do the same with URLs
      html.gsub!( /(^|[^`])(https?:\/\/[^\[ ]+)(\[+[^\]]*\]+)?/ ) do
        pre = $1
        url = $2
        link = ( $3 || $2 ).gsub( /(^\[|\]$)/,'' )
        link = url if link.empty?

        "#{pre}link:#{url}[#{link}]"
      end

      html = CGI.escapeHTML(html)
      html.gsub!(Asciidoc::REGEXP[:biblio], '<a name="\1">[\1]</a>')
      html.gsub!(/``(.*?)''/m, '&ldquo;\1&rdquo;')
      html.gsub!(/`(.*?)'/m, '&lsquo;\1&rsquo;')
      html.gsub!(/`([^`]+)`/m) { "<tt>#{$1.gsub( '*', '{asterisk}' ).gsub( '\'', '{apostrophe}' )}</tt>" }
      html.gsub!(/([\s\W])#(.+?)#([\s\W])/, '\1\2\3')

      # "Unconstrained" quotes
      html.gsub!(/\_\_([^\_]+)\_\_/m, '<em>\1</em>')
      html.gsub!(/\*\*([^\*]+)\*\*/m, '<strong>\1</strong>')
      html.gsub!(/\+\+([^\+]+)\+\+/m, '<tt>\1</tt>')
      html.gsub!(/\^\^([^\^]+)\^\^/m, '<sup>\1</sup>')
      html.gsub!(/\~\~([^\~]+)\~\~/m, '<sub>\1</sub>')

      # "Constrained" quotes, which must be bounded by white space or
      # common punctuation characters
      html.gsub!(/([\s\W])\*([^\*]+)\*([\s\W])/m, '\1<strong>\2</strong>\3')
      html.gsub!(/([\s\W])'(.+?)'([\s\W])/m, '\1<em>\2</em>\3')
      html.gsub!(/([\s\W])_([^_]+)_([\s\W])/m, '\1<em>\2</em>\3')
      html.gsub!(/([\s\W])\+([^\+]+)\+([\s\W])/m, '\1<tt>\2</tt>\3')
      html.gsub!(/([\s\W])\^([^\^]+)\^([\s\W])/m, '\1<sup>\2</sup>\3')
      html.gsub!(/([\s\W])\~([^\~]+)\~([\s\W])/m, '\1<sub>\2</sub>\3')

      # Don't have lookbehind so have to capture and re-insert
      html.gsub!(/(^|[^\\])\{(\w[\w\-]+\w)\}/) do
        if self.document.defines.has_key?($2)
          # Substitute from user defines first
          $1 + self.document.defines[$2]
        elsif Asciidoc::INTRINSICS.has_key?($2)
          # Then do intrinsics
          $1 + Asciidoc::INTRINSICS[$2]
        else
          # leave everything else alone
          "#{$1}{#{$2}}"
        end
      end

      html.gsub!(/\\([\{\}\-])/, '\1')
      html.gsub!(/linkgit:([^\]]+)\[(\d+)\]/, '<a href="\1.html">\1(\2)</a>')
      html.gsub!(/link:([^\[]+)(\[+[^\]]*\]+)/ ) { "<a href=\"#{$1}\">#{$2.gsub( /(^\[|\]$)/,'' )}</a>" }
      html
    end
  end
  # end private
end
