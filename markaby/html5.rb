require 'markaby/builder'

module Markaby
  # All the tags and attributes from XHTML 1.0 Strict
  class HTML5
    class << self
      attr_accessor :tags, :tagset, :forms, :self_closing, :doctype
    end
    @doctype = [""]
    @tagset = {
      :html => AttrI18n + [:id],
      :head => AttrI18n + [:id],
      :title => AttrI18n + [:id],
      :base => [:href, :id],
      :meta => AttrI18n + [:id, :http, :name, :content, :scheme, 'http-equiv'.intern],
      :link => Attrs + [:charset, :href, :hreflang, :type, :rel, :rev, :media],
      :style => AttrI18n + [:id, :type, :media, :title, 'xml:space'.intern],
      :script => [:id, :charset, :type, :src, :defer, 'xml:space'.intern],
      :noscript => Attrs,
      :body => Attrs + [:onload, :onunload],
      :div => Attrs,
      :p => Attrs,
      :ul => Attrs,
      :ol => Attrs,
      :li => Attrs,
      :dl => Attrs,
      :dt => Attrs,
      :dd => Attrs,
      :address => Attrs,
      :hr => Attrs,
      :pre => Attrs + ['xml:space'.intern],
      :blockquote => Attrs + [:cite],
      :ins => Attrs + [:cite, :datetime],
      :del => Attrs + [:cite, :datetime],
      :a => Attrs + AttrFocus + [:charset, :type, :name, :href, :hreflang, :rel, :rev, :shape, :coords, :target],
      :span => Attrs,
      :bdo => AttrCore + AttrEvents + [:lang, 'xml:lang'.intern, :dir],
      :br => AttrCore,
      :em => Attrs,
      :strong => Attrs,
      :dfn => Attrs,
      :code => Attrs,
      :samp => Attrs,
      :kbd => Attrs,
      :var => Attrs,
      :cite => Attrs,
      :abbr => Attrs,
      :acronym => Attrs,
      :q => Attrs + [:cite],
      :sub => Attrs,
      :sup => Attrs,
      :tt => Attrs,
      :i => Attrs,
      :b => Attrs,
      :big => Attrs,
      :small => Attrs,
      :object => Attrs + [:declare, :classid, :codebase, :data, :type, :codetype, :archive, :standby, :height, :width, :usemap, :name, :tabindex],
      :param => [:id, :name, :value, :valuetype, :type],
      :img => Attrs + [:src, :alt, :longdesc, :height, :width, :usemap, :ismap],
      :map => AttrI18n + AttrEvents + [:id, :class, :style, :title, :name],
      :area => Attrs + AttrFocus + [:shape, :coords, :href, :nohref, :alt, :target],
      :form => Attrs + [:action, :method, :enctype, :onsubmit, :onreset, :accept, :accept, :name, :target],
      :label => Attrs + [:for, :accesskey, :onfocus, :onblur],
      :input => Attrs + AttrFocus + [:type, :name, :value, :checked, :disabled, :readonly, :size, :maxlength, :src, :alt, :usemap, :onselect, :onchange, :accept],
      :select => Attrs + [:name, :size, :multiple, :disabled, :tabindex, :onfocus, :onblur, :onchange],
      :optgroup => Attrs + [:disabled, :label],
      :option => Attrs + [:selected, :disabled, :label, :value],
      :textarea => Attrs + AttrFocus + [:name, :rows, :cols, :disabled, :readonly, :onselect, :onchange],
      :fieldset => Attrs,
      :legend => Attrs + [:accesskey],
      :button => Attrs + AttrFocus + [:name, :value, :type, :disabled],
      :table => Attrs + [:summary, :width, :border, :frame, :rules, :cellspacing, :cellpadding],
      :caption => Attrs,
      :colgroup => Attrs + AttrHAlign + AttrVAlign + [:span, :width],
      :col => Attrs + AttrHAlign + AttrVAlign + [:span, :width],
      :thead => Attrs + AttrHAlign + AttrVAlign,
      :tfoot => Attrs + AttrHAlign + AttrVAlign,
      :tbody => Attrs + AttrHAlign + AttrVAlign,
      :tr => Attrs + AttrHAlign + AttrVAlign,
      :th => Attrs + AttrHAlign + AttrVAlign + [:abbr, :axis, :headers, :scope, :rowspan, :colspan],
      :td => Attrs + AttrHAlign + AttrVAlign + [:abbr, :axis, :headers, :scope, :rowspan, :colspan],
      :iframe => AttrCore + [:longdesc, :name, :src, :frameborder, :marginwidth, :marginheight, :scrolling, :align, :height, :width],
			:header => Attrs,
      :h1 => Attrs,
      :h2 => Attrs,
      :h3 => Attrs,
      :h4 => Attrs,
      :h5 => Attrs,
      :h6 => Attrs
    }

    @tags = @tagset.keys
    @forms = @tags & FORM_TAGS
    @self_closing = @tags & SELF_CLOSING_TAGS
  end

	class Builder
    def html5(&block)
      instruct! if @output_xml_instruction
      declare!(:DOCTYPE, :html) 
      self.tagset = Markaby::HTML5
      html &block
    end

    HTML5.tags.each do |k|
      class_eval %{
        def #{k}(*args, &block)
          html_tag(#{k.inspect}, *args, &block)
        end
      }
    end


	end


end
