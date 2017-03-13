#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# Graphical user interface of Pandora
# RU: Графический интерфейс Пандоры
#
# This program is free software and distributed under the GNU GPLv2
# RU: Это свободное программное обеспечение распространяется под GNU GPLv2
# 2012 (c) Michael Galyuk
# RU: 2012 (c) Михаил Галюк

require 'fileutils'
require File.expand_path('../crypto.rb',  __FILE__)
require File.expand_path('../net.rb',  __FILE__)

module PandoraGtk

  # Version of GUI application
  # RU: Версия GUI приложения
  PandoraVersion  = '0.69'

  # GTK is cross platform graphical user interface
  # RU: Кроссплатформенный оконный интерфейс
  begin
    require 'gtk2'
    Gtk.init
  rescue Exception
    Kernel.abort("Gtk is not installed.\nInstall packet 'ruby-gtk'")
  end

  include PandoraUtils
  include PandoraModel

  # Middle width of num char in pixels
  # RU: Средняя ширина цифрового символа в пикселах
  def self.num_char_width
    @@num_char_width ||= nil
    if not @@num_char_width
      lab = Gtk::Label.new('0')
      lw,lh = lab.size_request
      @@num_char_width = lw
      @@num_char_width ||= 5
    end
    @@num_char_width
  end

  # Force set text of any Button (with stock)
  # RU: Силовая смена текста любой кнопки (со stock)
  def self.set_button_text(btn, text=nil)
    alig = btn.children[0]
    if alig.is_a? Gtk::Bin
      hbox = alig.child
      if (hbox.is_a? Gtk::Box) and (hbox.children.size>1)
        lab = hbox.children[1]
        if lab.is_a? Gtk::Label
          if text.nil?
            lab.destroy
          else
            lab.text = text
          end
        end
      end
    end
  end

  # Ctrl, Shift, Alt are pressed? (Array or Yes/No)
  # RU: Кнопки Ctrl, Shift, Alt нажаты? (Массив или Да/Нет)
  def self.is_ctrl_shift_alt?(ctrl=nil, shift=nil, alt=nil)
    screen, x, y, mask = Gdk::Display.default.pointer
    res = nil
    ctrl_prsd = ((mask & Gdk::Window::CONTROL_MASK.to_i) != 0)
    shift_prsd = ((mask & Gdk::Window::SHIFT_MASK.to_i) != 0)
    alt_prsd = ((mask & Gdk::Window::MOD1_MASK.to_i) != 0)
    if ctrl.nil? and shift.nil? and alt.nil?
      res = [ctrl_prsd, shift_prsd, alt_prsd]
    else
      res = ((ctrl and ctrl_prsd) or (shift and shift_prsd) or (alt and alt_prsd))
    end
    res
  end

  # Statusbar fields
  # RU: Поля в статусбаре
  SF_Log     = 0
  SF_FullScr = 1
  SF_Update  = 2
  SF_Lang    = 3
  SF_Auth    = 4
  SF_Listen  = 5
  SF_Hunt    = 6
  SF_Conn    = 7
  SF_Radar   = 8
  SF_Fisher  = 9
  SF_Search  = 10
  SF_Harvest = 11

  # Good and simle MessageDialog
  # RU: Хороший и простой MessageDialog
  class GoodMessageDialog < Gtk::MessageDialog

    def initialize(a_mes, a_title=nil, a_stock=nil, an_icon=nil)
      a_stock ||= Gtk::MessageDialog::INFO
      super($window, Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT, \
        a_stock, Gtk::MessageDialog::BUTTONS_OK_CANCEL, a_mes)
      a_title ||= 'Note'
      self.title = _(a_title)
      self.default_response = Gtk::Dialog::RESPONSE_OK
      an_icon ||= $window.icon if $window
      an_icon ||= main_icon = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'pandora.ico'))
      self.icon = an_icon
      self.signal_connect('key-press-event') do |widget, event|
        if [Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
          event.keyval) and event.state.control_mask? #w, W, ц, Ц
        then
          widget.response(Gtk::Dialog::RESPONSE_CANCEL)
          false
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
          event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
          Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
          and event.state.control_mask?) #q, Q, й, Й, x, X, ч, Ч
        then
          $window.do_menu_act('Quit')
          false
        else
          false
        end
      end
    end

    def run_and_do(do_if_ok=true)
      res = nil
      res = (self.run == Gtk::Dialog::RESPONSE_OK)
      if (res and do_if_ok) or ((not res) and (not do_if_ok))
        res = true
        yield if block_given?
      end
      self.destroy if not self.destroyed?
      res
    end

  end

  # Advanced dialog window
  # RU: Продвинутое окно диалога
  class AdvancedDialog < Gtk::Window #Gtk::Dialog
    attr_accessor :response, :window, :notebook, :vpaned, :viewport, :hbox, \
      :enter_like_tab, :enter_like_ok, :panelbox, :okbutton, :cancelbutton, \
      :def_widget, :main_sw

    # Create method
    # RU: Метод создания
    def initialize(*args)
      super(*args)
      @response = 0
      @window = self
      @enter_like_tab = false
      @enter_like_ok = true
      set_default_size(300, -1)

      window.transient_for = $window
      window.modal = true
      #window.skip_taskbar_hint = true
      window.window_position = Gtk::Window::POS_CENTER
      #window.type_hint = Gdk::Window::TYPE_HINT_DIALOG
      window.destroy_with_parent = true

      @vpaned = Gtk::VPaned.new
      vpaned.border_width = 2

      window.add(vpaned)
      #window.vbox.add(vpaned)

      @main_sw = Gtk::ScrolledWindow.new(nil, nil)
      sw = main_sw
      sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      @viewport = Gtk::Viewport.new(nil, nil)
      sw.add(viewport)

      @notebook = Gtk::Notebook.new
      @notebook.scrollable = true
      label_box1 = TabLabelBox.new(Gtk::Stock::PROPERTIES, _('Basic'))
      page = notebook.append_page(sw, label_box1)
      vpaned.pack1(notebook, true, true)

      @panelbox = Gtk::VBox.new
      @hbox = Gtk::HBox.new
      panelbox.pack_start(hbox, false, false, 0)

      vpaned.pack2(panelbox, false, true)

      bbox = Gtk::HBox.new
      bbox.border_width = 2
      bbox.spacing = 4

      @okbutton = Gtk::Button.new(Gtk::Stock::OK)
      okbutton.width_request = 110
      okbutton.signal_connect('clicked') do |*args|
        @response=2
      end
      bbox.pack_start(okbutton, false, false, 0)

      @cancelbutton = Gtk::Button.new(Gtk::Stock::CANCEL)
      cancelbutton.width_request = 110
      cancelbutton.signal_connect('clicked') do |*args|
        @response=1
      end
      bbox.pack_start(cancelbutton, false, false, 0)

      hbox.pack_start(bbox, true, false, 1.0)

      #self.signal_connect('response') do |widget, response|
      #  case response
      #    when Gtk::Dialog::RESPONSE_OK
      #      p "OK"
      #    when Gtk::Dialog::RESPONSE_CANCEL
      #      p "Cancel"
      #    when Gtk::Dialog::RESPONSE_CLOSE
      #      p "Close"
      #      dialog.destroy
      #  end
      #end

      window.signal_connect('delete-event') { |*args|
        @response=1
        false
      }
      window.signal_connect('destroy') { |*args| @response=1 }

      window.signal_connect('key-press-event') do |widget, event|
        if (event.keyval==Gdk::Keyval::GDK_Tab) and enter_like_tab  # Enter works like Tab
          event.hardware_keycode=23
          event.keyval=Gdk::Keyval::GDK_Tab
          window.signal_emit('key-press-event', event)
          true
        elsif
          [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
          and (event.state.control_mask? or (enter_like_ok and (not (self.focus.is_a? Gtk::TextView))))
        then
          okbutton.activate if okbutton.sensitive?
          true
        elsif (event.keyval==Gdk::Keyval::GDK_Escape) or \
          ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(event.keyval) and event.state.control_mask?) #w, W, ц, Ц
        then
          cancelbutton.activate
          false
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?(event.keyval) and event.state.mod1_mask?) or
          ([Gdk::Keyval::GDK_q, Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) and event.state.control_mask?) #q, Q, й, Й
        then
          $window.do_menu_act('Quit')
          @response=1
          false
        else
          false
        end
      end

    end

    # Show dialog in modal mode
    # RU: Показать диалог в модальном режиме
    def run2(in_thread=false)
      res = nil
      show_all
      if @def_widget
        #focus = @def_widget
        @def_widget.grab_focus
        self.present
        GLib::Timeout.add(200) do
          @def_widget.grab_focus if @def_widget and (not @def_widget.destroyed?)
          false
        end
      end

      while (not destroyed?) and (@response == 0) do
        if in_thread
          Thread.pass
        else
          Gtk.main_iteration
        end
        #sleep(0.001)
      end

      if not destroyed?
        if (@response > 1)
          yield(@response) if block_given?
          res = true
        end
        self.destroy
      end

      res
    end
  end

  # ToggleButton with safety "active" switching
  # RU: ToggleButton с безопасным переключением "active"
  class SafeToggleButton < Gtk::ToggleButton

    # Remember signal handler
    # RU: Запомнить обработчик сигнала
    def safe_signal_clicked
      @clicked_signal = self.signal_connect('clicked') do |*args|
        yield(*args) if block_given?
      end
    end

    # Set "active" property safety
    # RU: Безопасно установить свойство "active"
    def safe_set_active(an_active)
      if @clicked_signal
        self.signal_handler_block(@clicked_signal) do
          self.active = an_active
        end
      else
        self.active = an_active
      end
    end

  end

  # ToggleToolButton with safety "active" switching
  # RU: ToggleToolButton с безопасным переключением "active"
  class SafeToggleToolButton < Gtk::ToggleToolButton

    # Remember signal handler
    # RU: Запомнить обработчик сигнала
    def safe_signal_clicked
      @clicked_signal = self.signal_connect('clicked') do |*args|
        yield(*args) if block_given?
      end
    end

    # Set "active" property safety
    # RU: Безопасно установить свойство "active"
    def safe_set_active(an_active)
      if @clicked_signal
        self.signal_handler_block(@clicked_signal) do
          self.active = an_active
        end
      else
        self.active = an_active
      end
    end

  end

  # CheckButton with safety "active" switching
  # RU: CheckButton с безопасным переключением "active"
  class SafeCheckButton < Gtk::CheckButton

    # Remember signal handler
    # RU: Запомнить обработчик сигнала
    def safe_signal_clicked
      @clicked_signal = self.signal_connect('clicked') do |*args|
        yield(*args) if block_given?
      end
    end

    # Set "active" property safety
    # RU: Безопасно установить свойство "active"
    def safe_set_active(an_active)
      if @clicked_signal
        self.signal_handler_block(@clicked_signal) do
          self.active = an_active
        end
      end
    end
  end

  # Entry with allowed symbols of mask
  # RU: Поле ввода с допустимыми символами в маске
  class MaskEntry < Gtk::Entry
    attr_accessor :mask

    def initialize
      super
      signal_connect('key-press-event') do |widget, event|
        res = false
        if not key_event(widget, event)
          if (not event.state.control_mask?) and (event.keyval<60000) \
          and (mask.is_a? String) and (mask.size>0)
            res = (not mask.include?(event.keyval.chr))
          end
        end
        res
      end
      @mask = nil
      init_mask
      if mask and (mask.size>0)
        prefix = self.tooltip_text
        if prefix and (prefix != '')
          prefix << "\n"
        end
        prefix ||= ''
        self.tooltip_text = prefix+'['+mask+']'
      end
    end

    def init_mask
      #will reinit in child
    end

    def key_event(widget, event)
      false
    end
  end

  # Entry for integer
  # RU: Поле ввода целых чисел
  class IntegerEntry < MaskEntry
    def init_mask
      super
      @mask = '0123456789-'
      self.max_length = 20
      self.width_request = PandoraGtk.num_char_width*8+8
    end
  end

  # Entry for float
  # RU: Поле ввода дробных чисел
  class FloatEntry < IntegerEntry
    def init_mask
      super
      @mask += '.e'
      self.max_length = 35
      self.width_request = PandoraGtk.num_char_width*11+8
    end
  end

  # Entry for HEX
  # RU: Поле ввода шестнадцатеричных чисел
  class HexEntry < MaskEntry
    def init_mask
      super
      @mask = '0123456789abcdefABCDEF'
      self.width_request = PandoraGtk.num_char_width*45+8
    end
  end

  Base64chars = [('0'..'9').to_a, ('a'..'z').to_a, ('A'..'Z').to_a, '+/=-_*[]'].join

  # Entry for Base64
  # RU: Поле ввода Base64
  class Base64Entry < MaskEntry
    def init_mask
      super
      @mask = Base64chars
      self.width_request = PandoraGtk.num_char_width*64+8
    end
  end

  # Simple entry for date
  # RU: Простое поле ввода даты
  class DateEntrySimple < MaskEntry
    def init_mask
      super
      @mask = '0123456789.'
      self.max_length = 10
      self.tooltip_text = 'DD.MM.YYYY'
      self.width_request = PandoraGtk.num_char_width*self.max_length+8
    end
  end

  # Entry for date and time
  # RU: Поле ввода даты и времени
  class TimeEntrySimple < DateEntrySimple
    def init_mask
      super
      @mask = '0123456789:'
      self.max_length = 8
      self.tooltip_text = 'hh:mm:ss'
      self.width_request = PandoraGtk.num_char_width*self.max_length+8
    end
  end

  # Entry for date and time
  # RU: Поле ввода даты и времени
  class DateTimeEntry < DateEntrySimple
    def init_mask
      super
      @mask += ': '
      self.max_length = 19
      self.tooltip_text = 'DD.MM.YYYY hh:mm:ss'
      self.width_request = PandoraGtk.num_char_width*(self.max_length+1)+8
    end
  end

  # Entry with popup widget
  # RU: Поле с всплывающим виджетом
  class BtnEntry < Gtk::HBox
    attr_accessor :entry, :button, :close_on_enter, :modal

    def initialize(entry_class, stock=nil, tooltip=nil, amodal=nil, *args)
      amodal = false if amodal.nil?
      @modal = amodal
      super(*args)
      @close_on_enter = true
      @entry = entry_class.new
      stock ||= :list

      @init_yield_block = nil
      if block_given?
        @init_yield_block = Proc.new do |*args|
          yield(*args)
        end
      end

      if PandoraUtils.os_family=='windows'
        @button = GoodButton.new(stock, nil, nil) do
          do_on_click
        end
      else
        $window.register_stock(stock)
        @button = Gtk::Button.new(stock)
        PandoraGtk.set_button_text(@button)

        tooltip ||= stock.to_s.capitalize
        @button.tooltip_text = _(tooltip)
        @button.signal_connect('clicked') do |*args|
          do_on_click
        end
      end

      @button.can_focus = false

      @entry.instance_variable_set('@button', @button)

      #def @entry.key_event(widget, event)
      @entry.define_singleton_method('key_event') do |widget, event|
        res = ((event.keyval==32) or ((event.state.shift_mask? \
          or event.state.mod1_mask?) \
          and (event.keyval==65364)))  # Space, Shift+Down or Alt+Down
        if res
          if @button.is_a? GoodButton
            parent.do_on_click
          else
            @button.activate
          end
        end
        false
      end

      self.pack_start(entry, true, true, 0)
      align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
      align.add(@button)
      self.pack_start(align, false, false, 1)
      esize = entry.size_request
      h = esize[1]-2
      @button.set_size_request(h, h)
    end

    def do_on_click
      res = false
      @entry.grab_focus
      if @popwin and (not @popwin.destroyed?)
        @popwin.destroy
        @popwin = nil
      else
        @popwin = Gtk::Window.new #(Gtk::Window::POPUP)
        popwin = @popwin
        popwin.transient_for = $window if PandoraUtils.os_family == 'windows'
        popwin.modal = @modal
        popwin.decorated = false
        popwin.skip_taskbar_hint = true
        popwin.destroy_with_parent = true

        popwidget = get_popwidget
        popwin.add(popwidget)
        popwin.signal_connect('delete_event') { @popwin.destroy; @popwin=nil }

        popwin.signal_connect('focus-out-event') do |win, event|
          GLib::Timeout.add(100) do
            if not win.destroyed?
              @popwin.destroy
              @popwin = nil
            end
            false
          end
          false
        end

        popwin.signal_connect('key-press-event') do |widget, event|
          if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
            if @close_on_enter
              @popwin.destroy
              @popwin = nil
            end
            false
          elsif (event.keyval==Gdk::Keyval::GDK_Escape) or \
            ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
            event.keyval) and event.state.control_mask?) #w, W, ц, Ц
          then
            @popwin.destroy
            @popwin = nil
            false
          elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
            event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
            Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
            and event.state.control_mask?) #q, Q, й, Й
          then
            @popwin.destroy
            @popwin = nil
            $window.do_menu_act('Quit')
            false
          else
            false
          end
        end

        pos = @entry.window.origin
        all = @entry.allocation.to_a
        popwin.move(pos[0], pos[1]+all[3]+1)

        popwin.show_all
      end
      res
    end

    def get_popwidget   # Example widget
      wid = Gtk::Button.new('Here must be a popup widget')
      wid.signal_connect('clicked') do |*args|
        @entry.text = 'AValue'
        @popwin.destroy
        @popwin = nil
      end
      wid
    end

    def max_length=(maxlen)
      maxlen = 512 if maxlen<512
      entry.max_length = maxlen
    end

    def text=(text)
      entry.text = text
    end

    def text
      entry.text
    end

    def width_request=(wr)
      entry.set_width_request(wr)
    end

    def modify_text(*args)
      entry.modify_text(*args)
    end

    def size_request
      esize = entry.size_request
      res = button.size_request
      res[0] = esize[0]+1+res[0]
      res
    end
  end

  # Popup choose window
  # RU: Всплывающее окно выбора
  class PopWindow < Gtk::Window
    attr_accessor :root_vbox, :just_leaved, :on_click_btn

    def get_popwidget
      nil
    end

    def initialize(amodal=nil)
      super()

      @just_leaved = false

      self.transient_for = $window if PandoraUtils.os_family == 'windows'
      amodal = false if amodal.nil?
      self.modal = amodal
      self.decorated = false
      self.skip_taskbar_hint = true

      popwidget = get_popwidget
      self.add(popwidget) if popwidget
      self.signal_connect('delete_event') do
        destroy
      end

      self.signal_connect('focus-out-event') do |win, event|
        if not @just_leaved.nil?
          @just_leaved = true
          if not destroyed?
            hide
          end
          GLib::Timeout.add(500) do
            @just_leaved = false if not destroyed?
            false
          end
        end
        false
      end

      self.signal_connect('key-press-event') do |widget, event|
        if (event.keyval==Gdk::Keyval::GDK_Escape) or \
          ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
          event.keyval) and event.state.control_mask?) #w, W, ц, Ц
        then
          @just_leaved = nil
          hide
          false
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
          event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
          Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
          and event.state.control_mask?) #q, Q, й, Й
        then
          destroy
          $window.do_menu_act('Quit')
          false
        else
          false
        end
      end
    end

    def hide_popwin
      @just_leaved = nil
      self.hide
    end

  end

  # Smile choose window
  # RU: Окно выбора смайла
  class SmilePopWindow < PopWindow
    attr_accessor :preset, :poly_btn, :preset

    def initialize(apreset=nil, amodal=nil)
      apreset ||= 'vk'
      @preset = apreset
      super(amodal)
      self.signal_connect('key-press-event') do |widget, event|
        if (event.keyval==Gdk::Keyval::GDK_Tab)
          if preset=='qip'
            @vk_btn.do_on_click
          else
            @qip_btn.do_on_click
          end
          true
        elsif [Gdk::Keyval::GDK_b, Gdk::Keyval::GDK_B, 1737, 1769].include?(event.keyval)
          @poly_btn.set_active((not @poly_btn.active?))
          false
        else
          false
        end
      end
    end

    def get_popwidget
      if @root_vbox.nil? or @root_vbox.destroyed?
        @root_vbox = Gtk::VBox.new
        @smile_box = Gtk::Frame.new
        #@smile_box.shadow_type = Gtk::SHADOW_NONE
        hbox = Gtk::HBox.new
        $window.register_stock(:music, 'qip')
        @qip_btn = GoodButton.new(:music_qip, 'qip', -1) do |*args|
          if not @qip_btn.active?
            @qip_btn.set_active(true)
            @vk_btn.set_active(false)
            move_and_show('qip')
          end
        end
        hbox.pack_start(@qip_btn, true, true, 0)
        $window.register_stock(:ufo, 'vk')
        @vk_btn = GoodButton.new(:ufo_vk, 'vk', -1) do |*args|
          if not @vk_btn.active?
            @vk_btn.set_active(true)
            @qip_btn.set_active(false)
            move_and_show('vk')
          end
        end
        hbox.pack_start(@vk_btn, true, true, 0)
        $window.register_stock(:bomb, 'qip')
        @poly_btn = GoodButton.new(:bomb_qip, nil, false)
        @poly_btn.tooltip_text = _('Many smiles')
        hbox.pack_start(@poly_btn, false, false, 0)
        root_vbox.pack_start(hbox, false, true, 0)
        if preset=='vk'
          @vk_btn.set_active(true)
        else
          @qip_btn.set_active(true)
        end
        root_vbox.pack_start(@smile_box, true, true, 0)
      end
      root_vbox
    end

    def init_smiles_box(preset, smiles_parent, smile_btn)
      @@smile_btn = smile_btn if smile_btn
      @@smile_boxes ||= {}
      vbox = nil
      res = @@smile_boxes[preset]
      if res
        vbox = res[0]
        vbox = nil if vbox.destroyed?
      end
      if vbox
        resize(100, 100)
        #p '  vbox.parent='+vbox.parent.inspect
        if vbox.parent and (not vbox.parent.destroyed?)
          if (vbox.parent != smiles_parent)
            #p '  reparent'
            smiles_parent.remove(smiles_parent.child) if smiles_parent.child
            vbox.parent.remove(vbox)
            smiles_parent.add(vbox)
            vbox.reparent(smiles_parent)
          end
        else
          #p '  set_parent'
          smiles_parent.remove(smiles_parent.child) if smiles_parent.child
          vbox.parent = smiles_parent
        end
      else
        smiles_parent.remove(smiles_parent.child) if smiles_parent.child
        vbox = Gtk::VBox.new
        icon_params, icon_file_desc = $window.get_icon_file_params(preset)
        focus_btn = nil
        if icon_params and (icon_params.size>0)
          row = 0
          col = 0
          max_col = Math.sqrt(icon_params.size).round
          hbox = Gtk::HBox.new
          icon_params.each_with_index do |smile, i|
            if col>max_col
              vbox.pack_start(hbox, false, false, 0)
              hbox = Gtk::HBox.new
              col = 0
              row += 1
            end
            col += 1
            buf = $window.get_icon_buf(smile, preset)
            aimage = Gtk::Image.new(buf)
            btn = Gtk::ToolButton.new(aimage, smile)
            btn.set_can_focus(true)
            btn.tooltip_text = smile
            #btn.events = Gdk::Event::ALL_EVENTS_MASK
            focus_btn = btn if i==0
            btn.signal_connect('clicked') do |widget|
              clear_click = (not PandoraGtk.is_ctrl_shift_alt?(true, true))
              btn.grab_focus
              smile_btn = @@smile_btn
              smile_btn.on_click_btn.call(preset, widget.label)
              hide_popwin if clear_click and (not smile_btn.poly_btn.active?)
              false
            end
            btn.signal_connect('key-press-event') do |widget, event|
              res = false
              if [Gdk::Keyval::GDK_space, Gdk::Keyval::GDK_KP_Space].include?(event.keyval)
                smile_btn = @@smile_btn
                smile_btn.on_click_btn.call(preset, widget.label)
                res = true
              elsif [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
                smile_btn = @@smile_btn
                smile_btn.on_click_btn.call(preset, widget.label)
                hide_popwin
                res = true
              end
              res
            end
            btn.signal_connect('expose-event') do |widget, event|
              if widget.focus?   #STATE_PRELIGHT
                widget.style.paint_focus(widget.window, Gtk::STATE_NORMAL, \
                  event.area, widget, '', event.area.x+1, event.area.y+1, \
                  event.area.width-2, event.area.height-2)
              end
              false
            end
            hbox.pack_start(btn, true, true, 0)
          end
          vbox.pack_start(hbox, false, false, 0)
          vbox.show_all
        end
        smiles_parent.add(vbox)
        res = [vbox, focus_btn]
        @@smile_boxes[preset] = res
      end
      res
    end

    def move_and_show(apreset=nil, x=nil, y=nil, a_on_click_btn=nil)
      @preset = apreset if apreset
      @on_click_btn = a_on_click_btn if a_on_click_btn
      popwidget = get_popwidget
      vbox, focus_btn = init_smiles_box(@preset, @smile_box, self)
      popwidget.show_all
      pwh = popwidget.size_request
      resize(*pwh)

      if x and y
        @x = x
        @y = y
      end

      move(@x, @y-pwh[1])
      show_all
      present
      focus_btn.grab_focus if focus_btn
    end

  end

  # Smile choose box
  # RU: Поле выбора смайлов
  class SmileButton < Gtk::ToolButton
    attr_accessor :on_click_btn, :popwin

    def initialize(apreset=nil, *args)
      aimage = $window.get_preset_image('smile')
      super(aimage, _('smile'))
      self.tooltip_text = _('smile')
      apreset ||= 'vk'
      @preset = apreset
      @@popwin ||= nil

      @on_click_btn = Proc.new do |*args|
        yield(*args) if block_given?
      end

      signal_connect('clicked') do |*args|
        popwin = @@popwin
        if popwin and (not popwin.destroyed?) and (popwin.visible? or popwin.just_leaved)
          popwin.hide
        else
          if popwin.nil? or popwin.destroyed?
            @@popwin = SmilePopWindow.new(@preset, false)
            popwin = @@popwin
          end
          borig = self.window.origin
          brect = self.allocation.to_a
          x = brect[0]+borig[0]
          y = brect[1]+borig[1]-1
          popwin.move_and_show(nil, x, y, @on_click_btn)
          popwin.poly_btn.set_active(false)
        end
        popwin.just_leaved = false
        false
      end
    end

  end

  # Color box for calendar day
  # RU: Цветной бокс дня календаря
  class ColorDayBox < Gtk::EventBox
    attr_accessor :bg, :day_date

    def initialize(background=nil)
      super()
      @bg = background
      self.events = Gdk::Event::BUTTON_PRESS_MASK | Gdk::Event::POINTER_MOTION_MASK \
        | Gdk::Event::ENTER_NOTIFY_MASK | Gdk::Event::LEAVE_NOTIFY_MASK \
        | Gdk::Event::VISIBILITY_NOTIFY_MASK | Gdk::Event::FOCUS_CHANGE_MASK
      self.signal_connect('focus-in-event') do |widget, event|
        self.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#88CC88')) if day_date
        false
      end
      self.signal_connect('focus-out-event') do |widget, event|
        self.modify_bg(Gtk::STATE_NORMAL, @bg)
        false
      end
      self.signal_connect('button-press-event') do |widget, event|
        res = false
        if (event.button == 1) and widget.can_focus?
          widget.set_focus(true)
          yield(self) if block_given?
          res = true
        elsif (event.button == 3)
          popwin = self.parent.parent.parent
          if popwin.is_a? DatePopWindow
            popwin.show_month_menu(event.time)
            res = true
          end
        end
        res
      end
    end

    def bg=(background)
      @bg = background
      bgc = nil
      if not bg.nil?
        if bg.is_a? String
          bgc = Gdk::Color.parse(bg)
        elsif
          bgc = bg
        end
      end
      @bg = bgc
      self.modify_bg(Gtk::STATE_NORMAL, bgc)
    end

  end

  # Date choose window
  # RU: Окно выбора даты
  class DatePopWindow < PopWindow
    attr_accessor :date, :year, :month, :month_btn, :year_btn, :date_entry, \
      :holidays, :left_mon_btn, :right_mon_btn, :left_year_btn, :right_year_btn

    def initialize(adate=nil, amodal=nil)
      @@month_menu = nil
      @@year_menu  = nil
      @@year_mi = nil
      @@days_box = nil
      @date ||= adate
      @year_holidays = {}
      super(amodal)
      self.signal_connect('key-press-event') do |widget, event|
        if [32, Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
          if focus and (focus.is_a? ColorDayBox)
            event = Gdk::EventButton.new(Gdk::Event::BUTTON_PRESS)
            event.button = 1
            focus.signal_emit('button-press-event', event)
          end
          true
        elsif (event.keyval==Gdk::Keyval::GDK_Tab)
          false
        elsif (event.keyval>=65360) and (event.keyval<=65367)
          ctrl = (event.state.control_mask? or event.state.shift_mask?)
          if event.keyval==65360 or (ctrl and event.keyval==65361)
            left_mon_btn.clicked
          elsif event.keyval==65367 or (ctrl and event.keyval==65363)
            right_mon_btn.clicked
          elsif event.keyval==65365 or (ctrl and event.keyval==65362)
            left_year_btn.clicked
          elsif event.keyval==65366 or (ctrl and event.keyval==65364)
            right_year_btn.clicked
          end
          false
        else
          false
        end
      end
      self.signal_connect('scroll-event') do |widget, event|
        ctrl = (event.state.control_mask? or event.state.shift_mask?)
        if (event.direction==Gdk::EventScroll::UP) \
        or (event.direction==Gdk::EventScroll::LEFT)
          if ctrl
            left_year_btn.clicked
          else
            left_mon_btn.clicked
          end
        else
          if ctrl
            right_year_btn.clicked
          else
            right_mon_btn.clicked
          end
        end
        true
      end
    end

    def get_holidays(year)
      @holidays = @year_holidays[year]
      if not @holidays
        holidays_fn = File.join($pandora_lang_dir, 'holiday.'+$country+'.'+year.to_s+'.txt')
        f_exist = File.exist?(holidays_fn)
        if not f_exist
          year = 0
          @holidays = @year_holidays[year]
          if not @holidays
            holidays_fn = File.join($pandora_lang_dir, 'holiday.'+$country+'.0000.txt')
            f_exist = File.exist?(holidays_fn)
          end
        end
        if f_exist
          @holidays = {}
          month = nil
          set_line = nil
          IO.foreach(holidays_fn) do |line|
            if (line.is_a? String) and (line.size>0)
              if line[0]==':'
                month = line[1..-1].to_i
                set_line = 0
              elsif set_line and (set_line<2)
                set_line += 1
                day_list = line.split(',')
                day_list.each do |days|
                  i = days.index('-')
                  if i
                    d1 = days[0, i].to_i
                    d2 = days[i+1..-1].to_i
                    (d1..d2).each do |d|
                      holidays[month.to_s+'.'+d.to_s] = true
                    end
                  else
                    holidays[month.to_s+'.'+days.to_i.to_s] = set_line
                  end
                end
              end
            end
          end
          @year_holidays[year] = @holidays
        end
      end
      @holidays
    end

    def show_month_menu(time=nil)
      if not @@month_menu
        @@month_menu = Gtk::Menu.new
        time_now = Time.now
        12.times do |mon|
          mon_time = Time.gm(time_now.year, mon+1, 1)
          menuitem = Gtk::MenuItem.new(_(mon_time.strftime('%B')))
          menuitem.signal_connect('activate') do |widget|
            @month = mon+1
            init_days_box
          end
          @@month_menu.append(menuitem)
          @@month_menu.show_all
        end
      end
      time ||= 0
      @@month_menu.popup(nil, nil, 3, time) do |menu, x, y, push_in|
        @just_leaved = nil
        GLib::Timeout.add(500) do
          @just_leaved = false if not destroyed?
          false
        end
        borig = @month_btn.window.origin
        brect = @month_btn.allocation.to_a
        x = borig[0]+brect[0]
        y = borig[1]+brect[1]+brect[3]
        [x, y]
      end
    end

    def show_year_menu(time=nil)
      if not @@year_menu
        @@year_menu = Gtk::Menu.new
        time_now = Time.now
        ((time_now.year-55)..time_now.year).each do |year|
          menuitem = Gtk::MenuItem.new(year.to_s)
          menuitem.signal_connect('activate') do |widget|
            @year = year
            get_holidays(@year)
            init_days_box
          end
          @@year_menu.append(menuitem)
          @@year_mi = menuitem if @year == year
        end
        @@year_menu.show_all
      end
      @@year_menu.select_item(@@year_mi) if @@year_mi
      time ||= 0
      @@year_menu.popup(nil, nil, 3, time) do |menu, x, y, push_in|
        @just_leaved = nil
        GLib::Timeout.add(500) do
          @just_leaved = false if not destroyed?
          false
        end
        borig = @year_btn.window.origin
        brect = @year_btn.allocation.to_a
        x = borig[0]+brect[0]
        y = borig[1]+brect[1]+brect[3]
        [x, y]
      end
    end

    def get_popwidget
      if @root_vbox.nil? or @root_vbox.destroyed?
        @root_vbox = Gtk::VBox.new
        @days_frame = Gtk::Frame.new
        @days_frame.shadow_type = Gtk::SHADOW_IN

        cur_btn = Gtk::Button.new(_'Current time')
        cur_btn.signal_connect('clicked') do |widget|
          time_now = Time.now
          if (@month == time_now.month) and (@year == time_now.year)
            @date_entry.on_click_btn.call(time_now)
          else
            @month = time_now.month
            @year = time_now.year
            get_holidays(@year)
          end
          init_days_box
        end
        root_vbox.pack_start(cur_btn, false, false, 0)

        row = Gtk::HBox.new
        @left_mon_btn = Gtk::Button.new('<')
        left_mon_btn.signal_connect('clicked') do |widget|
          if @month>1
            @month -= 1
          else
            @year -= 1
            @month = 12
            get_holidays(@year)
          end
          init_days_box
        end
        row.pack_start(left_mon_btn, true, true, 0)
        @month_btn = Gtk::Button.new('month')
        month_btn.width_request = 90
        month_btn.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#FFFFFF'))
        month_btn.signal_connect('clicked') do |widget, event|
          show_month_menu
        end
        month_btn.signal_connect('scroll-event') do |widget, event|
          if (event.direction==Gdk::EventScroll::UP) \
          or (event.direction==Gdk::EventScroll::LEFT)
            left_mon_btn.clicked
          else
            right_mon_btn.clicked
          end
          true
        end
        row.pack_start(month_btn, true, true, 0)
        @right_mon_btn = Gtk::Button.new('>')
        right_mon_btn.signal_connect('clicked') do |widget|
          if @month<12
            @month += 1
          else
            @year += 1
            @month = 1
            get_holidays(@year)
          end
          init_days_box
        end
        row.pack_start(right_mon_btn, true, true, 0)

        @left_year_btn = Gtk::Button.new('<')
        left_year_btn.signal_connect('clicked') do |widget|
          @year -= 1
          get_holidays(@year)
          init_days_box
        end
        row.pack_start(left_year_btn, true, true, 0)
        @year_btn = Gtk::Button.new('year')
        year_btn.signal_connect('clicked') do |widget, event|
          show_year_menu
        end
        year_btn.signal_connect('scroll-event') do |widget, event|
          if (event.direction==Gdk::EventScroll::UP) \
          or (event.direction==Gdk::EventScroll::LEFT)
            left_year_btn.clicked
          else
            right_year_btn.clicked
          end
          true
        end
        row.pack_start(year_btn, true, true, 0)
        @right_year_btn = Gtk::Button.new('>')
        right_year_btn.signal_connect('clicked') do |widget|
          @year += 1
          get_holidays(@year)
          init_days_box
        end
        row.pack_start(right_year_btn, true, true, 0)

        root_vbox.pack_start(row, false, true, 0)
        root_vbox.pack_start(@days_frame, true, true, 0)
      end
      root_vbox
    end

    Sunday_Contries = ['US', 'JA', 'CA', 'IN', 'BR', 'AR', 'MX', 'IL', 'PH', \
      'PE', 'BO', 'EC', 'VE', 'ZA', 'CO', 'KR', 'TW', 'HN', 'NI', 'PA']
    Saturay_Contries = ['EG', 'LY', 'IR', 'AF', 'SY', 'DZ', 'SA', 'YE', 'IQ', 'JO']

    def init_days_box
      labs_parent = @days_frame
      if @@days_box
        evbox = @@days_box
        evbox = nil if evbox.destroyed?
      end
      @labs ||= []

      #p '---init_days_box: [date, month, year]='+[date, month, year].inspect
      time_now = Time.now
      month_d1 = Time.gm(@year, @month, 1)
      d1_wday = month_d1.wday
      start = nil
      if Sunday_Contries.include?($country)
        start = d1_wday
      elsif Saturay_Contries.include?($country)
        start = d1_wday+1
        start = 0 if d1_wday==6
      else
        d1_wday = 7 if d1_wday==0
        start = d1_wday-1
      end
      #start =+ 7 if start==0
      start_time = month_d1 - (start+1)*3600*24
      start_day = Time.gm(start_time.year, start_time.month, start_time.day)

      if evbox
        resize(100, 100)
        if evbox.parent and (not evbox.parent.destroyed?)
          if (evbox.parent != labs_parent)
            labs_parent.remove(labs_parent.child) if labs_parent.child
            evbox.parent.remove(evbox)
            labs_parent.add(evbox)
            evbox.reparent(labs_parent)
          end
        else
          labs_parent.remove(labs_parent.child) if labs_parent.child
          evbox.parent = labs_parent
        end
      else
        labs_parent.remove(labs_parent.child) if labs_parent.child

        evbox = ColorDayBox.new('#FFFFFF')
        evbox.can_focus = false
        @@days_box = evbox
        labs_parent.add(evbox)

        vbox = Gtk::VBox.new
        focus_btn = nil

        7.times do |week|
          row = Gtk::HBox.new
          row.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#FFFFFF'))
          vbox.pack_start(row, true, true, 1)
          7.times do |day|
            lab = Gtk::Label.new
            @labs[week*7+day] = lab
            lab.width_chars = 4
            lab.use_markup = true
            lab.justify = Gtk::JUSTIFY_CENTER

            lab_evbox = ColorDayBox.new do |lab_evbox|
              @date_entry.on_click_btn.call(lab_evbox.day_date)
            end
            lab_evbox.day_date = true
            lab_evbox.add(lab)
            row.pack_start(lab_evbox, true, true, 1)
          end
        end

        evbox.add(vbox)
        labs_parent.show_all
      end

      @month_btn.label = _(month_d1.strftime('%B'))
      @year_btn.label = month_d1.strftime('%Y')

      cal_day = start_day

      7.times do |week|
        7.times do |day|
          bg_type = nil
          curr_day = nil
          chsd_day = nil
          text = '0'
          if week==0
            #p '---[@year, @month, day+1]='+[@year, @month, day+1].inspect
            atime = start_day + (day+1)*3600*24
            text = _(atime.strftime('%a'))
            #p '+++++++ WEEKDAY='+text.inspect
            bg_type = :capt
          else
            cal_day += 3600*24
            text = (cal_day.day).to_s
            if cal_day.month == @month
              bg_type = :work
              wday = cal_day.wday
              bg_type = :rest if (wday==0) or (wday==6)
              if holidays and (set_line = holidays[@month.to_s+'.'+cal_day.day.to_s])
                if set_line==2
                  bg_type = :work
                else
                  bg_type = :holi
                end
              end
            end
            if (cal_day.day == time_now.day) and (cal_day.month == time_now.month) \
            and (cal_day.year == time_now.year)
              curr_day = true
            end
            if date and (cal_day.day == date.day) and (cal_day.month == date.month) \
            and (cal_day.year == date.year)
              chsd_day = true
            end
          end
          bg = nil
          if bg_type==:work
            bg = '#DDEEFF'
          elsif bg_type==:rest
            bg = '#5050A0'
          elsif bg_type==:holi
            bg = '#B05050'
          else
            bg = '#FFFFFF'
          end

          lab = @labs[week*7+day]
          if lab.use_markup?
            if bg_type==:capt
              lab.set_markup('<b>'+text+'</b>')
            else
              fg = nil
              if (bg_type==:rest) or (bg_type==:holi)
                fg = '#66FF66' if curr_day
                fg ||= '#EEEE44' if chsd_day
                fg ||= '#FFFFFF'
              else
                fg = '#00BB00' if curr_day
                fg ||= '#AAAA00' if chsd_day
              end
              text = '<b>'+text+'</b>' if chsd_day
              fg ||= '#000000'
              lab.set_markup('<span foreground="'+fg+'">'+text+'</span>')
            end
          else
            lab.text = text
          end
          lab.parent.day_date = cal_day
          lab_evbox = lab.parent
          lab_evbox.bg = bg
          lab_evbox.can_focus = (bg_type != :capt)
        end
      end

      [vbox, focus_btn]
    end

    def move_and_show(adate=nil, adate_entry=nil, x=nil, y=nil, a_on_click_btn=nil)
      @date = adate
      @date_entry = adate_entry if adate_entry
      if @date
        @month = date.month
        @year = date.year
      else
        time_now = Time.now
        @month = time_now.month
        @year = time_now.year
      end
      get_holidays(@year)
      @on_click_btn = a_on_click_btn if a_on_click_btn
      popwidget = get_popwidget
      vbox, focus_btn = init_days_box
      popwidget.show_all
      pwh = popwidget.size_request
      resize(*pwh)
      if x and y
        @x = x
        @y = y
      end
      move(@x, @y)
      show_all
      present
      month_btn.grab_focus
    end

  end

  # Entry for date with calendar button
  # RU: Поле ввода даты с кнопкой календаря
  class DateEntry < BtnEntry
    attr_accessor :on_click_btn, :popwin

    def update_mark(month, year, time_now=nil)
      #time_now ||= Time.now
      #@cal.clear_marks
      #@cal.mark_day(time_now.day) if ((time_now.month==month) and (time_now.year==year))
    end

    def initialize(amodal=nil, *args)
      super(MaskEntry, :date, 'Date', amodal, *args)
      @@popwin ||= nil
      @close_on_enter = false
      @entry.mask = '0123456789.'
      @entry.max_length = 10
      @entry.tooltip_text = 'DD.MM.YYYY'
      @entry.width_request = PandoraGtk.num_char_width*@entry.max_length+8
      @on_click_btn = Proc.new do |date|
        @entry.text = PandoraUtils.date_to_str(date)
        @@popwin.hide_popwin
      end
    end

    def do_on_click
      res = false
      @entry.grab_focus
      popwin = @@popwin
      if popwin and (not popwin.destroyed?) and (popwin.visible? or popwin.just_leaved) \
      and (popwin.date_entry==self)
        popwin.hide
      else
        date = PandoraUtils.str_to_date(@entry.text)
        if popwin.nil? or popwin.destroyed? or (popwin.modal? != @modal)
          @@popwin = DatePopWindow.new(date, @modal)
          popwin = @@popwin
        end
        borig = @entry.window.origin
        brect = @entry.allocation.to_a
        x = borig[0]
        y = borig[1]+brect[3]+1
        popwin.move_and_show(date, self, x, y, @on_click_btn)
      end
      popwin.just_leaved = false
      res
    end

  end

  # Entry for time
  # RU: Поле ввода времени
  class TimeEntry < BtnEntry
    attr_accessor :hh_spin, :mm_spin, :ss_spin

    def initialize(amodal=nil, *args)
      super(MaskEntry, :time, 'Time', amodal, *args)
      @entry.mask = '0123456789:'
      @entry.max_length = 8
      @entry.tooltip_text = 'hh:mm:ss'
      @entry.width_request = PandoraGtk.num_char_width*@entry.max_length+8
      @@time_his ||= nil
    end

    def get_time(update_spin=nil)
      res = nil
      time = PandoraUtils.str_to_date(@entry.text)
      if time
        vals = time.to_a
        res = [vals[2], vals[1], vals[0]]  #hh,mm,ss
      else
        res = [0, 0, 0]
      end
      if update_spin
        hh_spin.value = res[0] if hh_spin
        mm_spin.value = res[1] if mm_spin
        ss_spin.value = res[2] if ss_spin
      end
      res
    end

    def set_time(hh, mm=nil, ss=nil)
      hh0, mm0, ss0 = get_time
      hh ||= hh0
      mm ||= mm0
      ss ||= ss0
      shh = PandoraUtils.int_to_str_zero(hh, 2)
      smm = PandoraUtils.int_to_str_zero(mm, 2)
      sss = PandoraUtils.int_to_str_zero(ss, 2)
      @entry.text = shh + ':' + smm + ':' + sss
    end

    ColNumber = 2
    RowNumber = 4
    DefTimeHis = '09:00|14:15|17:30|20:45'.split('|')

    def get_popwidget
      if not @@time_his
        @@time_his = PandoraUtils.get_param('time_history')
        @@time_his ||= ''
        @@time_his = @@time_his.split('|')
        (@@time_his.size..ColNumber*RowNumber-1).each do |i|
          @@time_his << DefTimeHis[i % DefTimeHis.size]
        end
      end
      vbox = Gtk::VBox.new
      btn1 = Gtk::Button.new(_'Current time')
      btn1.signal_connect('clicked') do |widget|
        @entry.text = Time.now.strftime('%H:%M:%S')
        get_time(true)
      end
      vbox.pack_start(btn1, false, false, 0)

      i = 0
      RowNumber.times do |row|
        hbox = Gtk::HBox.new
        ColNumber.times do |col|
          time_str = @@time_his[row + col*RowNumber]
          if time_str
            btn = Gtk::Button.new(time_str)
            btn.signal_connect('clicked') do |widget|
              @entry.text = widget.label+':00'
              get_time(true)
            end
            hbox.pack_start(btn, true, true, 0)
          else
            break
          end
        end
        vbox.pack_start(hbox, false, false, 0)
      end

      hbox = Gtk::HBox.new

      adj = Gtk::Adjustment.new(0, 0, 23, 1, 5, 0)
      @hh_spin = Gtk::SpinButton.new(adj, 0, 0)
      hh_spin.max_length = 2
      hh_spin.numeric = true
      hh_spin.wrap = true
      hh_spin.signal_connect('value-changed') do |widget|
        set_time(widget.value_as_int)
      end
      hbox.pack_start(hh_spin, false, true, 0)

      adj = Gtk::Adjustment.new(0, 0, 59, 1, 5, 0)
      @mm_spin = Gtk::SpinButton.new(adj, 0, 0)
      mm_spin.max_length = 2
      mm_spin.numeric = true
      mm_spin.wrap = true
      mm_spin.signal_connect('value-changed') do |widget|
        set_time(nil, widget.value_as_int)
      end
      hbox.pack_start(mm_spin, false, true, 0)

      adj = Gtk::Adjustment.new(0, 0, 59, 1, 5, 0)
      @ss_spin = Gtk::SpinButton.new(adj, 0, 0)
      ss_spin.max_length = 2
      ss_spin.numeric = true
      ss_spin.wrap = true
      ss_spin.signal_connect('value-changed') do |widget|
        set_time(nil, nil, widget.value_as_int)
      end
      hbox.pack_start(ss_spin, false, true, 0)

      get_time(true)
      vbox.pack_start(hbox, false, false, 0)

      btn = Gtk::Button.new(Gtk::Stock::OK)
      btn.signal_connect('clicked') do |widget|
        new_time = @entry.text
        if new_time and @@time_his
          i = new_time.rindex(':')
          new_time = new_time[0, i] if i
          i = @@time_his.index(new_time)
          if (not i) or (i >= (@@time_his.size / 2))
            if i
              @@time_his.delete_at(i)
            else
              @@time_his.pop
            end
            @@time_his.unshift(new_time)
            PandoraUtils.set_param('time_history', @@time_his.join('|'))
          end
        end
        @popwin.destroy
        @popwin = nil
      end
      vbox.pack_start(btn, false, false, 0)

      hh_spin.grab_focus

      vbox
    end

  end

  # Entry for relation kind
  # RU: Поле ввода типа связи
  class ByteListEntry < BtnEntry

    def initialize(code_name_list, amodal=nil, *args)
      super(MaskEntry, :list, 'List', amodal, *args)
      @close_on_enter = false
      @code_name_list = code_name_list
      @entry.mask = '0123456789'
      @entry.max_length = 3
      @entry.tooltip_text = 'NNN'
      @entry.width_request = PandoraGtk.num_char_width*10+8
    end

    def get_popwidget
      store = Gtk::ListStore.new(Integer, String)
      @code_name_list.each do |kind,name|
        iter = store.append
        iter[0] = kind
        iter[1] = _(name)
      end

      @treeview = Gtk::TreeView.new(store)
      treeview = @treeview
      treeview.rules_hint = true
      treeview.search_column = 0
      treeview.border_width = 10
      #treeview.hover_selection = false
      #treeview.selection.mode = Gtk::SELECTION_BROWSE

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Code'), renderer, 'text' => 0)
      column.set_sort_column_id(0)
      treeview.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Description'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      treeview.append_column(column)

      treeview.signal_connect('row-activated') do |tree_view, path, column|
        path, column = tree_view.cursor
        if path
          store = tree_view.model
          iter = store.get_iter(path)
          if iter and iter[0]
            @entry.text = iter[0].to_s
            if not @popwin.destroyed?
              @popwin.destroy
              @popwin = nil
            end
          end
        end
        false
      end

      # Make choose only when click to selected
      #treeview.add_events(Gdk::Event::BUTTON_PRESS_MASK)
      #treeview.signal_connect('button-press-event') do |widget, event|
      #  @iter = widget.selection.selected if (event.button == 1)
      #  false
      #end
      #treeview.signal_connect('button-release-event') do |widget, event|
      #  if (event.button == 1) and @iter
      #    path, column = widget.cursor
      #    if path and (@iter.path == path)
      #      widget.signal_emit('row-activated', nil, nil)
      #    end
      #  end
      #  false
      #end

      treeview.signal_connect('event-after') do |widget, event|
        if event.kind_of?(Gdk::EventButton) and (event.button == 1)
          iter = widget.selection.selected
          if iter
            path, column = widget.cursor
            if path and (iter.path == path)
              widget.signal_emit('row-activated', nil, nil)
            end
          end
        end
        false
      end

      treeview.signal_connect('key-press-event') do |widget, event|
        if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
          widget.signal_emit('row-activated', nil, nil)
          true
        else
          false
        end
      end

      frame = Gtk::Frame.new
      frame.shadow_type = Gtk::SHADOW_OUT
      frame.add(treeview)

      treeview.can_default = true
      treeview.grab_focus

      frame
    end
  end

  # Dialog for panhash choose
  # RU: Диалог для выбора панхэша
  class PanhashDialog < AdvancedDialog
    attr_accessor :panclasses

    def initialize(apanclasses)
      @panclasses = apanclasses
      super(_('Choose object'))
      $window.register_stock(:panhash)
      iconset = Gtk::IconFactory.lookup_default('panhash')
      style = Gtk::Widget.default_style  #Gtk::Style.new
      anicon = iconset.render_icon(style, Gtk::Widget::TEXT_DIR_LTR, \
        Gtk::STATE_NORMAL, Gtk::IconSize::LARGE_TOOLBAR)
      self.icon = anicon

      self.skip_taskbar_hint = true
      self.set_default_size(600, 400)
      auto_create = true
      @panclasses.each_with_index do |panclass, i|
        title = _(PandoraUtils.get_name_or_names(panclass.name, true))
        self.main_sw.destroy if i==0
        #image = Gtk::Image.new(Gtk::Stock::INDEX, Gtk::IconSize::MENU)
        image = $window.get_panobject_image(panclass.ider, Gtk::IconSize::SMALL_TOOLBAR)
        label_box2 = TabLabelBox.new(image, title)
        pbox = PandoraGtk::PanobjScrolledWindow.new
        page = self.notebook.append_page(pbox, label_box2)
        auto_create = PandoraGtk.show_panobject_list(panclass, nil, pbox, auto_create)
      end
      self.notebook.page = 0
    end

    # Show dialog and send choosed panhash,sha1,md5 to yield block
    # RU: Показать диалог и послать панхэш,sha1,md5 в выбранный блок
    def choose_record(*add_fields)
      self.run2 do
        panhash = nil
        add_fields = nil if not ((add_fields.is_a? Array) and (add_fields.size>0))
        field_vals = nil
        pbox = self.notebook.get_nth_page(self.notebook.page)
        treeview = pbox.treeview
        if treeview.is_a? SubjTreeView
          path, column = treeview.cursor
          panobject = treeview.panobject
          if path and panobject
            store = treeview.model
            iter = store.get_iter(path)
            id = iter[0]
            fields = 'panhash'
            this_is_blob = (panobject.is_a? PandoraModel::Blob)
            fields << ','+add_fields.join(',') if add_fields
            sel = panobject.select('id='+id.to_s, false, fields)
            if sel and (sel.size>0)
              rec = sel[0]
              panhash = rec[0]
              field_vals = rec[1..-1] if add_fields
            end
          end
        end
        if block_given?
          if field_vals
            yield(panhash, *field_vals)
          else
            yield(panhash)
          end
        end
      end
    end

  end

  MaxPanhashTabs = 5

  # Entry for panhash
  # RU: Поле ввода панхэша
  class PanhashBox < BtnEntry
    attr_accessor :types, :panclasses

    def initialize(panhash_type, amodal=nil, *args)
      @panclasses = nil
      @types = panhash_type
      stock = nil
      if @types=='Panhash'
        @types = 'Panhash(Blob,Person,Community,City,Key)'
        stock = :panhash
      end
      set_classes
      title = nil
      if (panclasses.is_a? Array) and (panclasses.size>0) and (not @types.nil?)
        stock ||= $window.get_panobject_stock(panclasses[0].ider)
        panclasses.each do |panclass|
          if title
            title << ', '
          else
            title = ''
          end
          title << panclass.sname
        end
      end
      stock ||= :panhash
      stock = stock.to_sym
      title ||= 'Panhash'
      super(HexEntry, stock, title, amodal=nil, *args)
      @entry.max_length = 44
      @entry.width_request = PandoraGtk.num_char_width*(@entry.max_length+1)+8
    end

    def do_on_click
      @entry.grab_focus
      set_classes
      dialog = PanhashDialog.new(@panclasses)
      dialog.choose_record do |panhash|
        if PandoraUtils.panhash_nil?(panhash)
          @entry.text = ''
        else
          @entry.text = PandoraUtils.bytes_to_hex(panhash) if (panhash.is_a? String)
        end
      end
      true
    end

    # Define panobject class list
    # RU: Определить список классов панобъектов
    def set_classes
      if not @panclasses
        #p '=== types='+types.inspect
        @panclasses = []
        @types.strip!
        if (types.is_a? String) and (types.size>0)
          drop_prefix = 0
          if (@types[0, 10].downcase=='panhashes(')
            drop_prefix = 10
          elsif (@types[0, 8].downcase=='panhash(')
            drop_prefix = 8
          end
          if drop_prefix>0
            @types = @types[drop_prefix..-2]
            @types.strip!
            @types = @types.split(',')
            @types.each do |ptype|
              ptype.strip!
              if PandoraModel.const_defined? ptype
                @panclasses << PandoraModel.const_get(ptype)
              end
            end
          end
        end
        if @panclasses.size==0
          @types = nil
          kind_list = PandoraModel.get_kind_list
          kind_list.each do |rec|
            ptype = rec[1]
            ptype.strip!
            p '---ptype='+ptype.inspect
            if PandoraModel.const_defined? ptype
              @panclasses << PandoraModel.const_get(ptype)
            end
            if @panclasses.size>MaxPanhashTabs
              break
            end
          end
        end
        #p '====panclasses='+panclasses.inspect
      end
    end

  end

  # Good FileChooserDialog
  # RU: Правильный FileChooserDialog
  class GoodFileChooserDialog < Gtk::FileChooserDialog
    def initialize(file_name, open=true, filters=nil, parent_win=nil, title=nil)
      action = nil
      act_btn = nil
      stock_id = nil
      if open
        action = Gtk::FileChooser::ACTION_OPEN
        stock_id = Gtk::Stock::OPEN
        act_btn = [stock_id, Gtk::Dialog::RESPONSE_ACCEPT]
      else
        action = Gtk::FileChooser::ACTION_SAVE
        stock_id = Gtk::Stock::SAVE
        act_btn = [stock_id, Gtk::Dialog::RESPONSE_ACCEPT]
        title ||= 'Save to file'
      end
      title ||= 'Choose a file'
      parent_win ||= $window
      super(_(title), parent_win, action, 'gnome-vfs',
        [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL], act_btn)
      dialog = self
      dialog.transient_for = parent_win
      dialog.skip_taskbar_hint = true
      dialog.default_response = Gtk::Dialog::RESPONSE_ACCEPT
      #image = $window.get_preset_image('export')
      #iconset = image.icon_set
      iconset = Gtk::IconFactory.lookup_default(stock_id.to_s)
      style = Gtk::Widget.default_style  #Gtk::Style.new
      anicon = iconset.render_icon(style, Gtk::Widget::TEXT_DIR_LTR, \
        Gtk::STATE_NORMAL, Gtk::IconSize::LARGE_TOOLBAR)
      dialog.icon = anicon
      dialog.add_shortcut_folder($pandora_files_dir)

      dialog.signal_connect('key-press-event') do |widget, event|
        if [Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
          event.keyval) and event.state.control_mask? #w, W, ц, Ц
        then
          dialog.response(Gtk::Dialog::RESPONSE_CANCEL)
          false
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
          event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
          Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
          and event.state.control_mask?) #q, Q, й, Й
        then
          dialog.destroy
          $window.do_menu_act('Quit')
          false
        else
          false
        end
      end

      filter = Gtk::FileFilter.new
      filter.name = _('All files')+' (*.*)'
      filter.add_pattern('*.*')
      dialog.add_filter(filter)

      if open
        if file_name.nil? or (file_name=='')
          dialog.current_folder = $pandora_files_dir
        else
          dialog.filename = file_name
        end
        scr = Gdk::Screen.default
        if (scr.height > 500)
          frame = Gtk::Frame.new
          frame.shadow_type = Gtk::SHADOW_IN
          align = Gtk::Alignment.new(0.5, 0.5, 0, 0)
          align.add(frame)
          image = Gtk::Image.new
          frame.add(image)
          align.show_all

          dialog.preview_widget = align
          dialog.use_preview_label = false
          dialog.signal_connect('update-preview') do
            fn = dialog.preview_filename
            ext = nil
            ext = File.extname(fn) if fn
            if ext and (['.jpg','.gif','.png'].include? ext.downcase)
              begin
                pixbuf = Gdk::Pixbuf.new(fn, 128, 128)
                image.pixbuf = pixbuf
                dialog.preview_widget_active = true
              rescue
                dialog.preview_widget_active = false
              end
            else
              dialog.preview_widget_active = false
            end
          end
        end
      else #save
        if File.exist?(file_name)
          dialog.filename = file_name
        else
          dialog.current_name = File.basename(file_name) if file_name
          dialog.current_folder = $pandora_files_dir
        end
        dialog.signal_connect('notify::filter') do |widget, param|
          aname = dialog.filter.name
          i = aname.index('*.')
          ext = nil
          ext = aname[i+2..-2] if i
          if ext
            i = ext.index('*.')
            ext = ext[0..i-2] if i
          end
          if ext.nil? or (ext != '*')
            ext ||= ''
            fn = PandoraUtils.change_file_ext(dialog.filename, ext)
            dialog.current_name = File.basename(fn) if fn
          end
        end
      end
    end
  end

  # Entry for filename
  # RU: Поле выбора имени файла
  class FilenameBox < BtnEntry
    attr_accessor :window

    def initialize(parent, amodal=nil, *args)
      super(Gtk::Entry, Gtk::Stock::OPEN, 'File', amodal, *args)
      @window = parent
      @entry.width_request = PandoraGtk.num_char_width*64+8
    end

    def do_on_click
      @entry.grab_focus
      fn = PandoraUtils.absolute_path(@entry.text)
      dialog = GoodFileChooserDialog.new(fn, true, nil, @window)

      filter = Gtk::FileFilter.new
      filter.name = _('Pictures')+' (*.png,*.jpg,*.gif)'
      filter.add_pattern('*.png')
      filter.add_pattern('*.jpg')
      filter.add_pattern('*.jpeg')
      filter.add_pattern('*.gif')
      dialog.add_filter(filter)

      filter = Gtk::FileFilter.new
      filter.name = _('Sounds')+' (*.mp3,*.wav)'
      filter.add_pattern('*.mp3')
      filter.add_pattern('*.wav')
      dialog.add_filter(filter)

      if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
        filename0 = @entry.text
        @entry.text = PandoraUtils.relative_path(dialog.filename)
        if @init_yield_block
          @init_yield_block.call(@entry.text, @entry, @button, filename0)
        end
      end
      dialog.destroy if not dialog.destroyed?
      true
    end

    def width_request=(wr)
      s = button.size_request
      h = s[0]+1
      wr -= h
      wr = 24 if wr<24
      entry.set_width_request(wr)
    end

  end

  # Entry for coordinate
  # RU: Поле ввода координаты
  class CoordEntry < FloatEntry
    def init_mask
      super
      @mask += 'EsNn SwW\'"`′″,'
      self.max_length = 35
    end
  end

  # Entry for coordinates
  # RU: Поле ввода координат
  class CoordBox < BtnEntry # Gtk::HBox
    attr_accessor :latitude, :longitude
    CoordWidth = 110

    def initialize(amodal=nil, hide_btn=nil)
      super(Gtk::HBox, :coord, 'Coordinates', amodal)
      @latitude   = CoordEntry.new
      latitude.tooltip_text = _('Latitude')+': 60.716, 60 43\', 60.43\'00"N'+"\n["+latitude.mask+']'
      @longitude  = CoordEntry.new
      longitude.tooltip_text = _('Longitude')+': -114.9, W114 54\' 0", 114.9W'+"\n["+longitude.mask+']'
      latitude.width_request = CoordWidth
      longitude.width_request = CoordWidth
      entry.pack_start(latitude, false, false, 0)
      @entry.pack_start(longitude, false, false, 1)
      if hide_btn
        @button.destroy
        @button = nil
      end
    end

    def do_on_click
      @latitude.grab_focus
      dialog = PanhashDialog.new([PandoraModel::City])
      dialog.choose_record('coord') do |panhash,coord|
        if coord
          geo_coord = PandoraUtils.coil_coord_to_geo_coord(coord)
          if geo_coord.is_a? Array
            latitude.text = geo_coord[0].to_s
            longitude.text = geo_coord[1].to_s
          end
        end
      end
      true
    end

    def max_length=(maxlen)
      btn_width = 0
      btn_width = @button.allocation.width if @button
      ml = (maxlen-btn_width) / 2
      latitude.max_length = ml
      longitude.max_length = ml
    end

    def text=(text)
      i = nil
      begin
        i = text.to_i if (text.is_a? String) and (text.size>0)
      rescue
        i = nil
      end
      if i
        coord = PandoraUtils.coil_coord_to_geo_coord(i)
      else
        coord = ['', '']
      end
      latitude.text = coord[0].to_s
      longitude.text = coord[1].to_s
    end

    def text
      res = PandoraUtils.geo_coord_to_coil_coord(latitude.text, longitude.text).to_s
    end

    def width_request=(wr)
      w = (wr+10) / 2
      latitude.set_width_request(w)
      longitude.set_width_request(w)
    end

    def modify_text(*args)
      latitude.modify_text(*args)
      longitude.modify_text(*args)
    end

    def size_request
      size1 = latitude.size_request
      res = longitude.size_request
      res[0] = size1[0]+1+res[0]
      res
    end
  end

  # Entry for date and time
  # RU: Поле ввода даты и времени
  class DateTimeBox < Gtk::HBox
    attr_accessor :date, :time

    def initialize(amodal=nil)
      super()
      @date   = DateEntry.new(amodal)
      @time   = TimeEntry.new(amodal)
      #date.width_request = CoordWidth
      #time.width_request = CoordWidth
      self.pack_start(date, false, false, 0)
      self.pack_start(time, false, false, 1)
    end

    def max_length=(maxlen)
      ml = maxlen / 2
      date.max_length = ml
      time.max_length = ml
    end

    def text=(text)
      date_str = nil
      time_str = nil
      if (text.is_a? String) and (text.size>0)
        i = text.index(' ')
        i ||= text.size
        date_str = text[0, i]
        time_str = text[i+1..-1]
      end
      date_str ||= ''
      time_str ||= ''
      date.text = date_str
      time.text = time_str
    end

    def text
      res = date.text + ' ' + time.text
    end

    def width_request=(wr)
      w = wr / 2
      date.set_width_request(w+10)
      time.set_width_request(w)
    end

    def modify_text(*args)
      date.modify_text(*args)
      time.modify_text(*args)
    end

    def size_request
      size1 = date.size_request
      res = time.size_request
      res[0] = size1[0]+1+res[0]
      res
    end
  end

  MaxOnePlaceViewSec = 60

  # Extended TextView
  # RU: Расширенный TextView
  class ExtTextView < Gtk::TextView
    attr_accessor :need_to_end, :middle_time, :middle_value, :go_to_end

    def initialize
      super
      self.receives_default = true
      signal_connect('key-press-event') do |widget, event|
        res = false
        if (event.keyval == Gdk::Keyval::GDK_F9)
          set_readonly(self.editable?)
          res = true
        end
        res
      end

      @go_to_end = false

      self.signal_connect('size-allocate') do |widget, step, arg2|
        if @go_to_end
          @go_to_end = false
          widget.parent.vadjustment.value = \
          widget.parent.vadjustment.upper - widget.parent.vadjustment.page_size
        end
        false
      end

    end

    def set_readonly(value=true)
      PandoraGtk.set_readonly(self, value, false)
    end

    # Do before addition
    # RU: Выполнить перед добавлением
    def before_addition(cur_time=nil, vadj_value=nil)
      cur_time ||= Time.now
      vadj_value ||= self.parent.vadjustment.value
      @need_to_end = ((vadj_value + self.parent.vadjustment.page_size) == self.parent.vadjustment.upper)
      if not @need_to_end
        if @middle_time and @middle_value and (@middle_value == vadj_value)
          if ((cur_time.to_i - @middle_time.to_i) > MaxOnePlaceViewSec)
            @need_to_end = true
            @middle_time = nil
          end
        else
          @middle_time = cur_time
          @middle_value = vadj_value
        end
      end
      @need_to_end
    end

    # Do after addition
    # RU: Выполнить после добавления
    def after_addition(go_end=nil)
      go_end ||= @need_to_end
      if go_end
        @go_to_end = true
        adj = self.parent.vadjustment
        adj.value = adj.upper - adj.page_size
        #scroll_to_iter(buffer.end_iter, 0, true, 0.0, 1.0)
        #mark = buffer.create_mark(nil, buffer.end_iter, false)
        #scroll_to_mark(mark, 0, true, 0.0, 1.0)
        #tv.scroll_to_mark(buf.get_mark('insert'), 0.0, true, 0.0, 1.0)
        #buffer.delete_mark(mark)
      end
      go_end
    end
  end

  class ScalePixbufLoader < Gdk::PixbufLoader
    attr_accessor :scale, :width, :height, :scaled_pixbuf, :set_dest, :renew_thread

    def initialize(ascale=nil, awidth=nil, aheight=nil, *args)
      super(*args)
      @scale = 100
      @width  = nil
      @height = nil
      @scaled_pixbuf = nil
      set_scale(ascale, awidth, aheight)
    end

    def set_scale(ascale=nil, awidth=nil, aheight=nil)
      ascale ||= 100
      if (@scale != ascale) or (@width != awidth) or (@height = aheight)
        @scale = ascale
        @width  = awidth
        @height = aheight
        renew_scaled_pixbuf
      end
    end

    def renew_scaled_pixbuf(redraw_wiget=nil)
      apixbuf = self.pixbuf
      if apixbuf and ((@scale != 100) or @width or @height)
        if not @renew_thread
          @renew_thread = Thread.new do
            #sleep(0.01)
            @renew_thread = nil
            apixbuf = self.pixbuf
            awidth  = apixbuf.width
            aheight = apixbuf.height

            scale_x = nil
            scale_y = nil
            if @width or @height
              p scale_x = @width.fdiv(awidth) if @width
              p scale_y = @height.fdiv(aheight) if @height
              new_scale = nil
              if scale_x and (scale_x<1.0)
                new_scale = scale_x
              end
              if scale_y and ((scale_x and scale_x<1.0 and scale_y.abs<scale_x.abs) \
              or ((not scale_x) and scale_y<1.0))
                new_scale = scale_y
              end
              if new_scale
                new_scale = new_scale.abs
              else
                new_scale = 1.0
              end
              scale_x = scale_y = new_scale
            end
            #p '      SCALE [@scale, @width, @height, awidth, aheight, scale_x, scale_y]='+\
            #  [@scale, @width, @height, awidth, aheight, scale_x, scale_y].inspect
            if not scale_x
              scale_x = @scale.fdiv(100)
              scale_y = scale_x
            end
            p dest_width  = awidth*scale_x
            p dest_height = aheight*scale_y
            if @scaled_pixbuf
              @scaled_pixbuf.scale!(apixbuf, 0, 0, dest_width, dest_height, 0, 0, scale_x, scale_y)
            else
              @scaled_pixbuf = apixbuf.scale(dest_width, dest_height)
            end
            set_dest.call(@scaled_pixbuf) if set_dest
            redraw_wiget.queue_draw if redraw_wiget and (not redraw_wiget.destroyed?)
          end
        end
      else
        @scaled_pixbuf = apixbuf
        redraw_wiget.queue_draw if redraw_wiget and (not redraw_wiget.destroyed?)
      end
      @scaled_pixbuf
    end

  end

  ReadImagePortionSize = 1024*1024 # 1Mb

  # Start loading image from file
  # RU: Запускает загрузку картинки в файл
  def self.start_image_loading(filename, pixbuf_parent=nil, scale=nil, width=nil, height=nil)
    res = nil
    p '--start_image_loading  [filename, pixbuf_parent, scale, width, height]='+\
      [filename, pixbuf_parent, scale, width, height].inspect
    filename = PandoraUtils.absolute_path(filename)
    if File.exist?(filename)
      if (scale.nil? or (scale==100)) and width.nil? and height.nil?
        begin
          res = Gdk::Pixbuf.new(filename)
          if not pixbuf_parent
            res = Gtk::Image.new(res)
          end
        rescue => err
          if not pixbuf_parent
            err_text = _('Image loading error1')+":\n"+Utf8String.new(err.message)
            label = Gtk::Label.new(err_text)
            res = label
          end
        end
      else
        begin
          file_stream = File.open(filename, 'rb')
          res = Gtk::Image.new if not pixbuf_parent
          #sleep(0.01)
          scale ||= 100
          read_thread = Thread.new do
            pixbuf_loader = ScalePixbufLoader.new(scale, width, height)
            pixbuf_loader.signal_connect('area_prepared') do |loader|
              loader.set_dest = Proc.new do |apixbuf|
                if pixbuf_parent
                  res = apixbuf
                else
                  res.pixbuf = apixbuf if (not res.destroyed?)
                end
              end
              pixbuf = loader.pixbuf
              pixbuf.fill!(0xAAAAAAFF)
              loader.renew_scaled_pixbuf(res)
              loader.set_dest.call(loader.scaled_pixbuf)
            end
            pixbuf_loader.signal_connect('area_updated') do |loader|
              upd_wid = res
              upd_wid = pixbuf_parent if pixbuf_parent
              loader.renew_scaled_pixbuf(upd_wid)
              if pixbuf_parent
                #res = loader.pixbuf
              else
                #res.pixbuf = loader.pixbuf if (not res.destroyed?)
              end
            end
            while file_stream
              buf = file_stream.read(ReadImagePortionSize)
              if buf
                pixbuf_loader.write(buf)
                if file_stream.eof?
                  pixbuf_loader.close
                  pixbuf_loader = nil
                  file_stream.close
                  file_stream = nil
                end
                sleep(0.005)
                #sleep(1)
              else
                pixbuf_loader.close
                pixbuf_loader = nil
                file_stream.close
                file_stream = nil
              end
            end
          end
          while pixbuf_parent and read_thread.alive?
            sleep(0.01)
          end
        rescue => err
          if not pixbuf_parent
            err_text = _('Image loading error2')+":\n"+Utf8String.new(err.message)
            label = Gtk::Label.new(err_text)
            res = label
          end
        end
      end
    end
    res
  end

  class LinkTag < Gtk::TextTag
    attr_accessor :link
  end

  $font_desc = nil

  # Window for view body (text or blob)
  # RU: Окно просмотра тела (текста или блоба)
  class SuperTextView < ExtTextView
    #attr_accessor :format

    def format
      res = nil
      sw = parent
      if (sw.is_a? BodyScrolledWindow)
        res = sw.format
      end
      res ||= 'bbcode'
      res
    end

    def initialize(left_border=nil, *args)
      super(*args)
      self.wrap_mode = Gtk::TextTag::WRAP_WORD

      @hovering = false

      buf = self.buffer
      buf.create_tag('bold', 'weight' => Pango::FontDescription::WEIGHT_BOLD)
      buf.create_tag('italic', 'style' => Pango::FontDescription::STYLE_ITALIC)
      buf.create_tag('strike', 'strikethrough' => true)
      buf.create_tag('undline', 'underline' => Pango::AttrUnderline::SINGLE)
      buf.create_tag('dundline', 'underline' => Pango::AttrUnderline::DOUBLE)
      buf.create_tag('link', 'foreground' => 'blue', \
        'underline' => Pango::AttrUnderline::SINGLE)
      buf.create_tag('linked', 'foreground' => 'navy', \
        'underline' => Pango::AttrUnderline::SINGLE)
      buf.create_tag('left', 'justification' => Gtk::JUSTIFY_LEFT)
      buf.create_tag('center', 'justification' => Gtk::JUSTIFY_CENTER)
      buf.create_tag('right', 'justification' => Gtk::JUSTIFY_RIGHT)
      buf.create_tag('fill', 'justification' => Gtk::JUSTIFY_FILL)
      buf.create_tag('h1', 'weight' => Pango::FontDescription::WEIGHT_BOLD, \
        'size' => 24 * Pango::SCALE, 'justification' => Gtk::JUSTIFY_CENTER)
      buf.create_tag('h2', 'weight' => Pango::FontDescription::WEIGHT_BOLD, \
        'size' => 21 * Pango::SCALE, 'justification' => Gtk::JUSTIFY_CENTER)
      buf.create_tag('h3', 'weight' => Pango::FontDescription::WEIGHT_BOLD, \
        'size' => 18 * Pango::SCALE)
      buf.create_tag('h4', 'weight' => Pango::FontDescription::WEIGHT_BOLD, \
        'size' => 15 * Pango::SCALE)
      buf.create_tag('h5', 'weight' => Pango::FontDescription::WEIGHT_BOLD, \
        'style' => Pango::FontDescription::STYLE_ITALIC, 'size' => 12 * Pango::SCALE)
      buf.create_tag('h6', 'style' => Pango::FontDescription::STYLE_ITALIC, \
        'size' => 12 * Pango::SCALE)
      buf.create_tag('red', 'foreground' => 'red')
      buf.create_tag('green', 'foreground' => 'green')
      buf.create_tag('blue', 'foreground' => 'blue')
      buf.create_tag('navy', 'foreground' => 'navy')
      buf.create_tag('yellow', 'foreground' => 'yellow')
      buf.create_tag('magenta', 'foreground' => 'magenta')
      buf.create_tag('cyan', 'foreground' => 'cyan')
      buf.create_tag('lime', 'foreground' =>   '#00FF00')
      buf.create_tag('maroon', 'foreground' => 'maroon')
      buf.create_tag('olive', 'foreground' =>  '#808000')
      buf.create_tag('purple', 'foreground' => 'purple')
      buf.create_tag('teal', 'foreground' =>   '#008080')
      buf.create_tag('gray', 'foreground' => 'gray')
      buf.create_tag('silver', 'foreground' =>   '#C0C0C0')
      buf.create_tag('mono', 'family' => 'monospace', 'background' => '#EFEFEF')
      buf.create_tag('sup', 'rise' => 7 * Pango::SCALE, 'size' => 9 * Pango::SCALE)
      buf.create_tag('sub', 'rise' => -7 * Pango::SCALE, 'size' => 9 * Pango::SCALE)
      buf.create_tag('small', 'scale' => Pango::AttrScale::XX_SMALL)
      buf.create_tag('large', 'scale' => Pango::AttrScale::X_LARGE)
      buf.create_tag('quote', 'left_margin' => 20, 'background' => '#EFEFEF', \
        'style' => Pango::FontDescription::STYLE_ITALIC)

      signal_connect('key-press-event') do |widget, event|
        res = false
        case event.keyval
          when Gdk::Keyval::GDK_b, Gdk::Keyval::GDK_B, 1737, 1769
            if event.state.control_mask?
              set_tag('bold')
              res = true
            end
          when Gdk::Keyval::GDK_i, Gdk::Keyval::GDK_I, 1755, 1787
            if event.state.control_mask?
              set_tag('italic')
              res = true
            end
          when Gdk::Keyval::GDK_u, Gdk::Keyval::GDK_U, 1735, 1767
            if event.state.control_mask?
              set_tag('undline')
              res = true
            end
          when Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter
            if event.state.control_mask?
              res = true
            end
        end
        res
      end

      set_border_window_size(Gtk::TextView::WINDOW_LEFT, left_border) if left_border

      signal_connect('event-after') do |tv, event|
        if event.kind_of?(Gdk::EventButton) \
        and (event.event_type == Gdk::Event::BUTTON_PRESS) and (event.button == 1)
          buf = tv.buffer
          # we shouldn't follow a link if the user has selected something
          range = buf.selection_bounds
          if range and (range[0].offset == range[1].offset)
            x, y = tv.window_to_buffer_coords(Gtk::TextView::WINDOW_TEXT, \
              event.x, event.y)
            iter = tv.get_iter_at_location(x, y)
            follow_if_link(iter)
          end
        end
        false
      end

      signal_connect('motion-notify-event') do |tv, event|
        x, y = tv.window_to_buffer_coords(Gtk::TextView::WINDOW_TEXT, \
          event.x, event.y)
        set_cursor_if_appropriate(tv, x, y)
        tv.window.pointer
        false
      end

      signal_connect('visibility-notify-event') do |tv, event|
        window, wx, wy = tv.window.pointer
        bx, by = tv.window_to_buffer_coords(Gtk::TextView::WINDOW_TEXT, wx, wy)
        set_cursor_if_appropriate(tv, bx, by)
        false
      end

      self.has_tooltip = true
      signal_connect('query-tooltip') do |textview, x, y, keyboard_tip, tooltip|
        res = false
        iter = nil
        if keyboard_tip
          iter = textview.buffer.get_iter_at_offset(textview.buffer.cursor_position)
        else
          bx, by = textview.window_to_buffer_coords(Gtk::TextView::WINDOW_TEXT, x, y)
          iter, trailing = textview.get_iter_at_position(bx, by)
        end
        pixbuf = iter.pixbuf   #.has_tag?(tag)  .char = 0xFFFC
        if pixbuf
          alt = pixbuf.tooltip
          if (alt.is_a? String) and (alt.size>0)
            tooltip.text = alt if ((not textview.destroyed?) and (not tooltip.destroyed?))
            res = true
          end
        else
          tags = iter.tags
          link_tag = tags.find { |tag| (tag.is_a? LinkTag) }
          if link_tag
            tooltip.text = link_tag.link if not textview.destroyed?
            res = true
          end
        end
        res
      end
    end

    def scrollwin
      res = self.parent
      res = res.parent if not res.is_a? Gtk::ScrolledWindow
      res
    end

    def set_cursor_if_appropriate(tv, x, y)
      iter = tv.get_iter_at_location(x, y)
      hovering = false
      tags = iter.tags
      tags.each do |tag|
        if tag.is_a? LinkTag
          hovering = true
          break
        end
      end
      if hovering != @hovering
        @hovering = hovering
        window = tv.get_window(Gtk::TextView::WINDOW_TEXT)
        if @hovering
          window.cursor = $window.hand_cursor
        else
          window.cursor = $window.regular_cursor
        end
      end
    end

    def follow_if_link(iter)
      tags = iter.tags
      tags.each do |tag|
        if tag.is_a? LinkTag
          link = tag.link
          if (link.is_a? String) and (link.size>0)
            res = PandoraUtils.parse_url(link, 'http')
            if res
              proto, obj_type, way = res
              if (proto == 'pandora') or (proto == 'sha1') or (proto == 'md5')
                #PandoraGtk.internal_open(proto, obj_type, way)
              else
                url = way
                url = proto+'://'+way if proto and proto=='http'
                puts 'Go to link: ['+url+']'
                PandoraUtils.external_open(url)
              end
            end
          end
        end
      end
    end

    def get_lines(tv, first_y, last_y, y_coords, numbers, with_height=false)
      # Get iter at first y
      iter, top = tv.get_line_at_y(first_y)
      # For each iter, get its location and add it to the arrays.
      # Stop when we pass last_y
      line = iter.line
      count = 0
      size = 0
      while (line < tv.buffer.line_count)
        #iter = tv.buffer.get_iter_at_line(line)
        y, height = tv.get_line_yrange(iter)
        if with_height
          y_coords << [y, height]
        else
          y_coords << y
        end
        line += 1
        numbers << line
        count += 1
        break if (y + height) >= last_y
        iter.forward_line
      end
      count
    end

    BBCODES = ['B', 'I', 'U', 'S', 'EM', 'STRIKE', 'STRONG', 'D', 'BR', \
      'FONT', 'SIZE', 'COLOR', 'COLOUR', 'STYLE', 'BACK', 'BACKGROUND', 'BG', \
      'FORE', 'FOREGROUND', 'FG', 'SPAN', 'DIV', 'P', \
      'RED', 'GREEN', 'BLUE', 'NAVY', 'YELLOW', 'MAGENTA', 'CYAN', \
      'LIME', 'AQUA', 'MAROON', 'OLIVE', 'PURPLE', 'TEAL', 'GRAY', 'SILVER', \
      'URL', 'A', 'HREF', 'LINK', 'ANCHOR', 'QUOTE', 'BLOCKQUOTE', 'LIST', \
      'CUT', 'SPOILER', 'CODE', 'INLINE', \
      'BOX', 'PROPERTY', 'EDIT', 'ENTRY', 'INPUT', \
      'BUTTON', 'SPIN', 'INTEGER', 'HEX', 'REAL', 'FLOAT', 'DATE', \
      'TIME', 'DATETIME', 'COORD', 'FILENAME', 'BASE64', 'PANHASH', 'BYTELIST', \
      'PRE', 'SOURCE', 'MONO', 'MONOSPACE', \
      'IMG', 'IMAGE', 'SMILE', 'EMOT', 'VIDEO', 'AUDIO', 'FILE', 'SUB', 'SUP', \
      'ABBR', 'ACRONYM', 'HR', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', \
      'LEFT', 'CENTER', 'RIGHT', 'FILL', 'IMAGES', 'SLIDE', 'SLIDESHOW', \
      'TABLE', 'TR', 'TD', 'TH', \
      'SMALL', 'LITTLE', 'X-SMALL', 'XX-SMALL', 'LARGE', 'BIG', 'X-LARGE', 'XX-LARGE']

    # Insert taget string to buffer
    # RU: Вставить тегированный текст в буфер
    def insert_taged_str_to_buffer(str, dest_buf, aformat=nil)

      def shift_coms(shift)
        @open_coms.each do |ocf|
          ocf[1] += shift
        end
      end

      def remove_quotes(str)
        if str.is_a?(String) and (str.size>1) \
        and ((str[0]=='"' and str[-1]=='"') or (str[0]=="'" and str[-1]=="'"))
          str = str[1..-2]
          str.strip! if str
        end
        str
      end

      def get_tag_param(params, type=:string, retutn_tail=false)
        res = nil
        getted = nil
        if (params.is_a? String) and (params.size>0)
          ei = params.index('=')
          es = params.index(' ')
          if ei.nil? or (es and es<ei)
            res = params
            res = params[0, es] if ei
            if res
              getted = res.size
              res = res.strip
              res = remove_quotes(res)
              if res and (type==:number)
                begin
                  res.gsub!(/[^0-9\.]/, '')
                  res = res.to_i
                rescue
                  res = nil
                end
              end
            end
          end
        end
        if retutn_tail
          tail = nil
          if getted
            tail = params[getted..-1]
          else
            tail = params
          end
          res = [res, tail]
        end
        res
      end

      def detect_params(params, tagtype=:string)
        res = {}
        tag, params = get_tag_param(params, tagtype, true)
        res['tag'] = tag if tag
        while (params.is_a? String) and (params.size>0)
          params.strip
          n = nil
          v = nil
          i = params.index('=')
          if i and (i>0)
            n = params[0, i]
            params = params[i+1..-1]
            params.strip if params
            i = params.size
            j = params.index(' ')
            k = params.index('"', 1)
            if (i>0) and (params[0]=='"') and k
              v = params[0..k]
              params = params[k+1..-1]
            elsif j
              v = params[0, j]
              params = params[j+1..-1]
            else
              v = params
              params = ''
            end
          else
            params = ''
          end
          if n
            n = n.strip.downcase
            res[n] = remove_quotes(v.strip) if v and (v.size>0)
          end
        end
        p 'detect_params[params, res]='+[params, res].inspect
        res
      end

      def correct_color(str)
        if str.is_a?(String) and (str.size==6) and PandoraUtils.hex?(str)
          str = '#'+str
        end
        str
      end

      i = children.size
      while i>0
        i -= 1
        child = children[i]
        child.destroy if child and (not child.destroyed?)
      end

      aformat ||= 'auto'
      unless ['markdown', 'bbcode', 'html', 'ruby', 'plain'].include?(aformat)
        aformat = 'bbcode' #if aformat=='auto' #need autodetect here
      end
      #p 'str='+str
      case aformat
        when 'markdown'
          i = 0
          while i<str.size
            j = str.index('*')
            if j
              dest_buf.insert(dest_buf.end_iter, str[0, j])
              str = str[j+1..-1]
              j = str.index('*')
              if j
                tag_name = str[0..j-1]
                img_buf = $window.get_icon_buf(tag_name)
                dest_buf.insert(dest_buf.end_iter, img_buf) if img_buf
                str = str[j+1..-1]
              end
            else
              dest_buf.insert(dest_buf.end_iter, str)
              i = str.size
            end
          end
        when 'bbcode', 'html'
          open_coms = Array.new
          @open_coms = open_coms
          open_brek = '['
          close_brek = ']'
          if aformat=='html'
            open_brek = '<'
            close_brek = '>'
          end
          strict_close_tag = nil
          i1 = nil
          i = 0
          ss = str.size
          while i<ss
            c = str[i]
            if c==open_brek
              i1 = i
              i += 1
            elsif i1 and (c==close_brek)
              com = str[i1+1, i-i1-1]
              p 'bbcode com='+com
              if com and (com.size>0)
                comu = nil
                close = (com[0] == '/')
                show_text = true
                if close or (com[-1] == '/')
                  # -- close bbcode
                  params = nil
                  tv_tag = nil
                  if close
                    comu = com[1..-1]
                  else
                    com = com[0..-2]
                    j = 0
                    cs = com.size
                    j +=1 while (j<cs) and (not ' ='.index(com[j]))
                    comu = nil
                    params = nil
                    if (j<cs)
                      params = com[j+1..-1].strip
                      comu = com[0, j]
                    else
                      comu = com
                    end
                  end
                  comu = comu.strip.upcase if comu
                  p '===closetag  [comu,params]='+[comu,params].inspect
                  p1 = dest_buf.end_iter.offset
                  p2 = p1
                  if ((strict_close_tag.nil? and BBCODES.include?(comu)) \
                  or ((not strict_close_tag.nil?) and (comu==strict_close_tag)))
                    strict_close_tag = nil
                    k = open_coms.index{ |ocf| ocf[0]==comu }
                    if k or (not close)
                      if k
                        rec = open_coms[k]
                        open_coms.delete_at(k)
                        k = rec[1]
                        params = rec[2]
                      else
                        k = 0
                      end
                      #p '[comu, dest_buf.text]='+[comu, dest_buf.text].inspect
                      p p1 -= k
                      case comu
                        when 'B', 'STRONG'
                          tv_tag = 'bold'
                        when 'I', 'EM'
                          tv_tag = 'italic'
                        when 'S', 'STRIKE'
                          tv_tag = 'strike'
                        when 'U'
                          tv_tag = 'undline'
                        when 'D'
                          tv_tag = 'dundline'
                        when 'BR', 'P'
                          dest_buf.insert(dest_buf.end_iter, "\n")
                          shift_coms(1)
                        when 'URL', 'A', 'HREF', 'LINK'
                          tv_tag = 'link'
                          #insert_link(buffer, iter, 'Go back', 1)
                          params = str[0, i1] unless params and (params.size>0)
                          params = get_tag_param(params) if params and (params.size>0)
                          if params and (params.size>0)
                            trunc_md5 = Digest::MD5.digest(params)[0, 10]
                            link_id = 'link'+PandoraUtils.bytes_to_hex(trunc_md5)
                            link_tag = dest_buf.tag_table.lookup(link_id)
                            #p '--[link_id, link_tag, params]='+[link_id, link_tag, params].inspect
                            if link_tag
                              tv_tag = link_tag.name
                            else
                              link_tag = LinkTag.new(link_id)
                              if link_tag
                                dest_buf.tag_table.add(link_tag)
                                link_tag.foreground = 'blue'
                                link_tag.underline = Pango::AttrUnderline::SINGLE
                                link_tag.link = params
                                tv_tag = link_id
                              end
                            end
                          end
                        when 'ANCHOR'
                          tv_tag = nil
                        when 'QUOTE', 'BLOCKQUOTE'
                          tv_tag = 'quote'
                        when 'LIST'
                          tv_tag = 'quote'
                        when 'CUT', 'SPOILER'
                          capt = params
                          capt ||= _('Expand')
                          expander = Gtk::Expander.new(capt)
                          etv = Gtk::TextView.new
                          etv.buffer.text = str[0, i1]
                          show_text = false
                          expander.add(etv)
                          iter = dest_buf.end_iter
                          anchor = dest_buf.create_child_anchor(iter)
                          #p 'CUT [body_child, expander, anchor]='+
                          #  [body_child, expander, anchor].inspect
                          add_child_at_anchor(expander, anchor)
                          shift_coms(1)
                          expander.show_all
                        when 'CODE', 'INLINE', 'PRE', 'SOURCE', 'MONO', 'MONOSPACE'
                          tv_tag = 'mono'
                        when 'IMG', 'IMAGE', 'SMILE', 'EMOT'
                          params = str[0, i1] unless params and (params.size>0)
                          p 'IMG params='+params.inspect
                          params = get_tag_param(params) if params and (params.size>0)
                          if params and (params.size>0)
                            img_buf = $window.get_icon_buf(params)
                            if img_buf
                              show_text = false
                              dest_buf.insert(dest_buf.end_iter, img_buf)
                              shift_coms(1)
                            end
                          end
                        when 'IMAGES', 'SLIDE', 'SLIDESHOW'
                          tv_tag = nil
                        when 'VIDEO', 'AUDIO', 'FILE', 'IMAGES', 'SLIDE', 'SLIDESHOW'
                          tv_tag = nil
                        when 'ABBR', 'ACRONYM'
                          tv_tag = nil
                        when 'HR'
                          count = get_tag_param(params, :number)
                          count = 50 unless count.is_a? Numeric and (count>0)
                          dest_buf.insert(dest_buf.end_iter, ' '*count)
                          shift_coms(count)
                          p2 += count
                          tv_tag = 'undline'
                        when 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'LEFT', 'CENTER', \
                        'RIGHT', 'FILL', 'SUB', 'SUP', 'RED', 'GREEN', 'BLUE', \
                        'NAVY', 'YELLOW', 'MAGENTA', 'CYAN', 'LIME', 'AQUA', \
                        'MAROON', 'OLIVE', 'PURPLE', 'TEAL', 'GRAY', 'SILVER'
                          comu = 'CYAN' if comu=='AQUA'
                          tv_tag = comu.downcase
                        when 'FONT', 'STYLE', 'SIZE', \
                          'FG', 'FORE', 'FOREGROUND', 'COLOR', 'COLOUR', \
                          'BG', 'BACK', 'BACKGROUND'

                          fg = nil
                          bg = nil
                          sz = nil
                          js = nil #left, right...
                          fam = nil
                          wt = nil #bold
                          st = nil #italic...

                          case comu
                            when 'FG', 'FORE', 'FOREGROUND', 'COLOR', 'COLOUR'
                              fg = get_tag_param(params)
                            when 'BG', 'BACK', 'BACKGROUND'
                              bg = get_tag_param(params)
                            else
                              sz = get_tag_param(params, :number)
                              if not sz
                                param_hash = detect_params(params)
                                sz = param_hash['size']
                                sz ||= param_hash['sz']
                                fg = param_hash['color']
                                fg ||= param_hash['colour']
                                fg ||= param_hash['fg']
                                fg ||= param_hash['fore']
                                fg ||= param_hash['foreground']
                                bg = param_hash['bg']
                                bg ||= param_hash['back']
                                bg ||= param_hash['background']
                                js = param_hash['js']
                                js ||= param_hash['justify']
                                js ||= param_hash['justification']
                                js ||= param_hash['align']
                                fam = param_hash['fam']
                                fam ||= param_hash['family']
                                fam ||= param_hash['font']
                                fam ||= param_hash['name']
                                wt = param_hash['wt']
                                wt ||= param_hash['weight']
                                wt ||= param_hash['bold']
                                st = param_hash['st']
                                st ||= param_hash['style']
                                st ||= param_hash['italic']
                              end
                            #end-case-when
                          end

                          fg = correct_color(fg)
                          bg = correct_color(bg)

                          tag_params = {}

                          tag_name = 'font'
                          if fam and (fam.is_a? String) and (fam.size>0)
                            fam_st = fam.upcase
                            fam_st.gsub!(' ', '_')
                            tag_name << '_'+fam_st
                            tag_params['family'] = fam
                          end
                          if fg
                            tag_name << '_'+fg
                            tag_params['foreground'] = fg
                          end
                          if bg
                            tag_name << '_bg'+bg
                            tag_params['background'] = bg
                          end
                          if sz
                            sz.gsub!(/[^0-9\.]/, '') if sz.is_a? String
                            tag_name << '_sz'+sz.to_s
                            tag_params['size'] = sz.to_i * Pango::SCALE
                          end
                          if wt
                            tag_name << '_wt'+wt.to_s
                            tag_params['weight'] = wt.to_i
                          end
                          if st
                            tag_name << '_st'+st.to_s
                            tag_params['style'] = st.to_i
                          end
                          if js
                            js = js.upcase
                            jsv = nil
                            if js=='LEFT'
                              jsv = Gtk::JUSTIFY_LEFT
                            elsif js=='RIGHT'
                              jsv = Gtk::JUSTIFY_RIGHT
                            elsif js=='CENTER'
                              jsv = Gtk::JUSTIFY_CENTER
                            elsif js=='FILL'
                              jsv = Gtk::JUSTIFY_FILL
                            end
                            if jsv
                              tag_name << '_js'+js
                              tag_params['justification'] = jsv
                            end
                          end

                          text_tag = dest_buf.tag_table.lookup(tag_name)
                          p '[tag_name, tag_params]='+[tag_name, tag_params].inspect
                          if text_tag
                            tv_tag = text_tag.name
                          elsif tag_params.size != {}
                            if dest_buf.create_tag(tag_name, tag_params)
                              tv_tag = tag_name
                            end
                          end
                        when 'SPAN', 'DIV',
                          tv_tag = 'mono'
                        when 'TABLE', 'TR', 'TD', 'TH'
                          tv_tag = 'mono'
                        when 'SMALL', 'LITTLE', 'X-SMALL', 'XX-SMALL'
                          tv_tag = 'small'
                        when 'LARGE', 'BIG', 'X-LARGE', 'XX-LARGE'
                          tv_tag = 'large'
                        #end-case-when
                      end
                    else
                      comu = nil
                    end
                  else
                    p 'NO process'
                    comu = nil
                  end
                  if show_text
                    dest_buf.insert(dest_buf.end_iter, str[0, i1])
                    shift_coms(i1)
                    p2 += i1
                  end
                  if tv_tag
                    p 'apply_tag [tv_tag,p1,p2]='+[tv_tag,p1,p2].inspect
                    dest_buf.apply_tag(tv_tag, \
                      dest_buf.get_iter_at_offset(p1), \
                      dest_buf.get_iter_at_offset(p2))
                  end
                else
                  # -- open bbcode
                  dest_buf.insert(dest_buf.end_iter, str[0, i1])
                  shift_coms(i1)
                  j = 0
                  cs = com.size
                  j +=1 while (j<cs) and (not ' ='.index(com[j]))
                  comu = nil
                  params = nil
                  if (j<cs)
                    params = com[j+1..-1].strip
                    comu = com[0, j]
                  else
                    comu = com
                  end
                  comu = comu.strip.upcase
                  p '---opentag  [comu,params]='+[comu,params].inspect
                  if strict_close_tag.nil? and BBCODES.include?(comu)
                    k = open_coms.find{ |ocf| ocf[0]==comu }
                    p 'opentag k='+k.inspect
                    if k
                      comu = nil
                    else
                      strict_close_tag = comu if comu=='CODE'
                      case comu
                        when 'BR', 'P'
                          dest_buf.insert(dest_buf.end_iter, "\n")
                          shift_coms(1)
                        when 'HR'
                          p1 = dest_buf.end_iter.offset
                          count = get_tag_param(params, :number)
                          count = 50 if not (count.is_a? Numeric and (count>0))
                          dest_buf.insert(dest_buf.end_iter, ' '*count)
                          shift_coms(count)
                          dest_buf.apply_tag('undline',
                            dest_buf.get_iter_at_offset(p1), dest_buf.end_iter)
                        else
                          if params and (params.size>0)
                            case comu
                              when 'IMG', 'IMAGE', 'EMOT', 'SMILE'
                                def_proto = nil
                                def_proto = 'smile' if (comu=='EMOT') or (comu=='SMILE')
                                comu = nil
                                param_hash = detect_params(params)
                                #src = get_tag_param(params)
                                src = param_hash['tag']
                                src ||= param_hash['src']
                                src ||= param_hash['link']
                                src ||= param_hash['url']
                                alt = param_hash['alt']
                                alt ||= param_hash['tooltip']
                                alt ||= param_hash['popup']
                                alt ||= param_hash['name']
                                title = param_hash['title']
                                title ||= param_hash['caption']
                                title ||= param_hash['name']
                                pixbuf = PandoraModel.get_image_from_url(src, \
                                  true, self, def_proto)
                                if pixbuf
                                  iter = dest_buf.end_iter
                                  if pixbuf.is_a? Gdk::Pixbuf
                                    alt ||= src
                                    PandoraUtils.set_obj_property(pixbuf, 'tooltip', alt)
                                    dest_buf.insert(iter, pixbuf)
                                    #anchor = dest_buf.create_child_anchor(iter)
                                    #img = Gtk::Image.new(img_res)
                                    #body_child.add_child_at_anchor(img, anchor)
                                    #img.show_all
                                    shift_coms(1)
                                    show_text = false
                                    if (title.is_a? String) and (title.size>0)
                                      title = "\n" + title
                                      dest_buf.insert(dest_buf.end_iter, title, 'italic')
                                      shift_coms(title.size)
                                    end
                                  else
                                    errtxt ||= _('Unknown error')
                                    dest_buf.insert(iter, errtxt)
                                    shift_coms(errtxt.size)
                                  end
                                  #anchor = dest_buf.create_child_anchor(iter)
                                  #p 'IMG [wid, anchor]='+[wid, anchor].inspect
                                  #body_child.add_child_at_anchor(wid, anchor)
                                  #wid.show_all
                                end
                              when 'BOX', 'PROPERTY', 'EDIT', 'ENTRY', 'INPUT', \
                              'SPIN', 'INTEGER', 'HEX', 'REAL', 'FLOAT', 'DATE', \
                              'TIME', 'DATETIME', 'COORD', 'FILENAME', 'BASE64', \
                              'PANHASH', 'BYTELIST', 'BUTTON'
                                #p '--BOX['+comu+'] param_hash='+param_hash.inspect
                                param_hash = detect_params(params)
                                name = param_hash['tag']
                                name ||= param_hash['name']
                                name ||= _('Noname')
                                width = param_hash['width']
                                size = param_hash['size']
                                values = param_hash['values']
                                values ||= param_hash['value']
                                values = values.split(',') if values
                                default = param_hash['default']
                                default ||= values[0] if values
                                values ||= default
                                type = param_hash['type']
                                kind = param_hash['kind']
                                type ||= comu
                                comu = nil
                                show_text = false
                                type.upcase!
                                if (type=='ENTRY') or (type=='INPUT')
                                  type = 'EDIT'
                                elsif (type=='FLOAT')
                                  type = 'REAL'
                                elsif (type=='DATETIME')
                                  type = 'TIME'
                                elsif not ['EDIT', 'SPIN', 'INTEGER', 'HEX', 'REAL', \
                                'DATE', 'TIME', 'COORD', 'FILENAME', 'BASE64', \
                                'PANHASH', 'BUTTON', 'LIST'].include?(type)
                                  type = 'LIST'
                                end

                                dest_buf.insert(dest_buf.end_iter, name, 'bold')
                                dest_buf.insert(dest_buf.end_iter, ': ')
                                shift_coms(name.size+2)

                                widget = nil
                                if type=='EDIT'
                                  widget = Gtk::Entry.new
                                  widget.text = default if default
                                elsif type=='SPIN'
                                  if values
                                    values.sort!
                                    min = values[0]
                                    max = values[-1]
                                  else
                                    min = 0.0
                                    max = 100.0
                                  end
                                  default ||= 0.0
                                  widget = Gtk::SpinButton.new(min.to_f, max.to_f, 1.0)
                                  widget.value = default.to_f
                                elsif type=='INTEGER'
                                  widget = IntegerEntry.new
                                  widget.text = default if default
                                elsif type=='HEX'
                                  widget = HexEntry.new
                                  widget.text = default if default
                                elsif type=='REAL'
                                  widget = FloatEntry.new
                                  widget.text = default if default
                                elsif type=='TIME'
                                  widget = DateTimeBox.new
                                  if default
                                    if default.downcase=='current'
                                      default = PandoraUtils.time_to_dialog_str(Time.now)
                                    end
                                    widget.text = default
                                  end
                                elsif type=='DATE'
                                  widget = DateEntry.new
                                  if default
                                    if default.downcase=='current'
                                      default = PandoraUtils.date_to_str(Time.now)
                                    end
                                    widget.text = default
                                  end
                                elsif type=='COORD'
                                  widget = CoordBox.new
                                  widget.text = default if default
                                elsif type=='FILENAME'
                                  widget = FilenameBox.new(window)
                                  widget.text = default if default
                                elsif type=='BASE64'
                                  widget = Base64Entry.new
                                  widget.text = default if default
                                elsif type=='PANHASH'
                                  kind ||= 'Blob,Person,Community,City'
                                  widget = PanhashBox.new('Panhash('+kind+')')
                                  widget.text = default if default
                                elsif type=='LIST'
                                  widget = ByteListEntry.new(PandoraModel::RelationNames)
                                  widget.text = default if default
                                else #'BUTTON'
                                  default ||= name
                                  widget = Gtk::Button.new(_(default))
                                end
                                if width or size
                                  width = width.to_i if width
                                  width ||= PandoraGtk.num_char_width*size.to_i+8
                                  if widget.is_a? Gtk::Widget
                                    widget.width_request = width
                                  elsif widget.is_a? PandoraGtk::BtnEntry
                                    widget.entry.width_request = width
                                  end
                                end
                                iter = dest_buf.end_iter
                                anchor = dest_buf.create_child_anchor(iter)
                                add_child_at_anchor(widget, anchor)
                                shift_coms(1)
                                widget.show_all
                              #end-case-when
                            end
                          end
                          open_coms << [comu, 0, params] if comu
                        #end-case-when
                      end
                    end
                  else
                    comu = nil
                  end
                end
                if (not comu) and show_text
                  dest_buf.insert(dest_buf.end_iter, open_brek+com+close_brek)
                  shift_coms(com.size+2)
                end
              else
                dest_buf.insert(dest_buf.end_iter, str[0, i1])
                shift_coms(i1)
              end
              str = str[i+1..-1]
              i = 0
              ss = str.size
              i1 = nil
            else
              i += 1
            end
          end
          dest_buf.insert(dest_buf.end_iter, str)
        else
          dest_buf.text = str
        #end-case-when
      end
    end

    def set_tag(tag, params=nil, defval=nil, aformat=nil)
      bounds = buffer.selection_bounds
      ltext = rtext = ''
      aformat ||= format
      case aformat
        when 'bbcode', 'html'
          noclose = (tag and (tag[-1]=='/'))
          tag = tag[0..-2] if noclose
          t = ''
          case tag
            when 'bold'
              t = 'b'
            when 'italic'
              t = 'i'
            when 'strike'
              t = 's'
            when 'undline'
              t = 'u'
            else
              t = tag
            #end-case-when
          end
          open_brek = '['
          close_brek = ']'
          if aformat=='html'
            open_brek = '<'
            close_brek = '>'
          end
          if params.is_a? String
            params = '='+params
          elsif params.is_a? Hash
            all = ''
            params.each do |k,v|
              all << ' '
              all << k.to_s + '="' + v.to_s + '"'
            end
            params = all
          else
            params = ''
          end
          ltext = open_brek+t+params+close_brek
          rtext = open_brek+'/'+t+close_brek if not noclose
        when 'markdown'
          case tag
            when 'bold'
              ltext = rtext = '*'
            when 'italic'
              ltext = rtext = '/'
            when 'strike'
              ltext = rtext = '-'
            when 'undline'
              ltext = rtext = '_'
          end
      end
      lpos = bounds[0].offset
      rpos = bounds[1].offset
      if (lpos==rpos) and (defval.is_a? String)
        buffer.insert(buffer.get_iter_at_offset(lpos), defval)
        rpos += defval.size
      end
      if ltext != ''
        buffer.insert(buffer.get_iter_at_offset(lpos), ltext)
        lpos += ltext.length
        rpos += ltext.length
      end
      if rtext != ''
        buffer.insert(buffer.get_iter_at_offset(rpos), rtext)
      end
      buffer.move_mark('selection_bound', buffer.get_iter_at_offset(lpos))
      buffer.move_mark('insert', buffer.get_iter_at_offset(rpos))
    end

  end

  # Editor TextView
  # RU: TextView редактора
  class EditorTextView < SuperTextView
    attr_accessor :view_border, :raw_border

    def set_left_border_width(left_border=nil)
      if (not left_border) or (left_border<0)
        add_nums = 0
        add_nums = -left_border if left_border and (left_border<0)
        num_count = nil
        line_count = buffer.line_count
        num_count = (Math.log10(line_count).truncate+1) if line_count
        num_count = 1 if (num_count.nil? or (num_count<1))
        if add_nums>0
          if (num_count+add_nums)>5
            num_count += 1
          else
            num_count += add_nums
          end
        end
        left_border = PandoraGtk.num_char_width*num_count+8
      end
      set_border_window_size(Gtk::TextView::WINDOW_LEFT, left_border)
    end

    def initialize(aview_border=nil, araw_border=nil)
      @view_border = aview_border
      @raw_border = araw_border
      super(aview_border)
      $font_desc ||= Pango::FontDescription.new('Monospace 11')
      signal_connect('expose-event') do |widget, event|
        tv = widget
        type = nil
        event_win = nil
        begin
          left_win = tv.get_window(Gtk::TextView::WINDOW_LEFT)
          #right_win = tv.get_window(Gtk::TextView::WINDOW_RIGHT)
          event_win = event.window
        rescue Exception
          event_win = nil
        end
        if event_win and left_win and (event_win == left_win)
          type = Gtk::TextView::WINDOW_LEFT
          target = left_win
          sw = tv.scrollwin
          view_mode = true
          view_mode = sw.view_mode if sw and (sw.is_a? BodyScrolledWindow)
          if not view_mode
            first_y = event.area.y
            last_y = first_y + event.area.height
            x, first_y = tv.window_to_buffer_coords(type, 0, first_y)
            x, last_y = tv.window_to_buffer_coords(type, 0, last_y)
            numbers = []
            pixels = []
            count = get_lines(tv, first_y, last_y, pixels, numbers)
            # Draw fully internationalized numbers!
            layout = widget.create_pango_layout
            count.times do |i|
              x, pos = tv.buffer_to_window_coords(type, 0, pixels[i])
              str = numbers[i].to_s
              layout.text = str
              widget.style.paint_layout(target, widget.state, false,
                nil, widget, nil, 2, pos, layout)
            end
          end
        end
        false
      end
    end
  end

  class ChatTextView < SuperTextView
    attr_accessor :mes_ids, :numbers, :pixels, :send_btn, :edit_box, \
      :crypt_btn, :sign_btn, :smile_btn

    def initialize(*args)
      @@save_buf ||= $window.get_icon_scale_buf('save', 'pan', 14)
      @@gogo_buf ||= $window.get_icon_scale_buf('gogo', 'pan', 14)
      @@recv_buf ||= $window.get_icon_scale_buf('recv', 'pan', 14)
      @@crypt_buf ||= $window.get_icon_scale_buf('crypt', 'pan', 14)
      @@sign_buf ||= $window.get_icon_scale_buf('sign', 'pan', 14)
      #@@nosign_buf ||= $window.get_icon_scale_buf('nosign', 'pan', 14)
      @@fail_buf ||= $window.get_preset_icon(Gtk::Stock::DIALOG_WARNING, nil, 14)

      super(*args)
      @mes_ids = Array.new
      @numbers = Array.new
      @pixels = Array.new
      @mes_model = PandoraUtils.get_model('Message')
      @sign_model = PandoraUtils.get_model('Sign')

      signal_connect('expose-event') do |widget, event|
        type = nil
        event_win = nil
        begin
          left_win = widget.get_window(Gtk::TextView::WINDOW_LEFT)
          event_win = event.window
        rescue Exception
          event_win = nil
        end
        if event_win and left_win and (event_win == left_win)
          type = Gtk::TextView::WINDOW_LEFT
          first_y = event.area.y
          last_y = first_y + event.area.height
          x, first_y = widget.window_to_buffer_coords(type, 0, first_y)
          x, last_y = widget.window_to_buffer_coords(type, 0, last_y)
          pixels.clear
          numbers.clear
          count = get_lines(widget, first_y, last_y, pixels, numbers, true)
          cr = left_win.create_cairo_context

          count.times do |i|
            y1, h1 = pixels[i]
            x, y = widget.buffer_to_window_coords(type, 0, y1)
            line = numbers[i]
            attr = 1
            id = mes_ids[line]
            if id
              flds = 'state, panstate, panhash'
              sel = @mes_model.select({:id=>id}, false, flds, nil, 1)
              if sel and (sel.size > 0)
                state = sel[0][0]
                panstate = sel[0][1]
                if state
                  if state==0
                    cr.set_source_pixbuf(@@save_buf, 0, y+h1-@@save_buf.height)
                    cr.paint
                  elsif state==1
                    cr.set_source_pixbuf(@@gogo_buf, 0, y+h1-@@gogo_buf.height)
                    cr.paint
                  elsif state==2
                    cr.set_source_pixbuf(@@recv_buf, 0, y+h1-@@recv_buf.height)
                    cr.paint
                  end
                end
                if panstate
                  if (panstate & PandoraModel::PSF_Crypted) > 0
                    cr.set_source_pixbuf(@@crypt_buf, 18, y+h1-@@crypt_buf.height)
                    cr.paint
                  end
                  if (panstate & PandoraModel::PSF_Verified) > 0
                    panhash = sel[0][2]
                    sel = @sign_model.select({:obj_hash=>panhash}, false, 'id', nil, 1)
                    if sel and (sel.size > 0)
                      cr.set_source_pixbuf(@@sign_buf, 35, y+h1-@@sign_buf.height)
                    else
                      cr.set_source_pixbuf(@@fail_buf, 35, y+h1-@@fail_buf.height)
                    end
                    cr.paint
                  end
                end
              end
            end
          end
        end
        false
      end
    end

    # Update status icon border if visible lines contain id or ids
    # RU: Обновляет бордюр с иконками статуса, если видимые строки содержат ids
    def update_lines_with_id(ids=nil, redraw_before=true)
      self.queue_draw if redraw_before
      need_redraw = nil
      if ids
        if ids.is_a? Array
          ids.each do |id|
            line = mes_ids.index(id)
            if line and numbers.include?(line)
              need_redraw = true
              break
            end
          end
        else
          line = mes_ids.index(ids)
          need_redraw = true if line and numbers.include?(line)
        end
      else
        need_redraw = true
      end
      if need_redraw
        left_win = self.get_window(Gtk::TextView::WINDOW_LEFT)
        left_win.invalidate(left_win.frame_extents, true)
      end
    end

  end

  # Trust change Scale
  # RU: Шкала для изменения доверия
  class TrustScale < ColorDayBox
    attr_accessor :scale

    def colorize
      if sensitive?
        val = scale.value
        trust = (val*127).round
        r = 0
        g = 0
        b = 0
        if trust==0
          b = 40000
        else
          mul = ((trust.fdiv(127))*45000).round
          if trust>0
            g = mul+20000
          else
            r = -mul+20000
          end
        end
        color = Gdk::Color.new(r, g, b)
        #scale.modify_fg(Gtk::STATE_NORMAL, color)
        self.bg = color
        prefix = ''
        prefix = _(@tooltip_prefix) + ': ' if @tooltip_prefix
        scale.tooltip_text = prefix+val.to_s
      else
        #modify_fg(Gtk::STATE_NORMAL, nil)
        self.bg = nil
        scale.tooltip_text = ''
      end
    end

    def initialize(bg=nil, tooltip_prefix=nil, avalue=nil)
      super(bg)
      @tooltip_prefix = tooltip_prefix
      adjustment = Gtk::Adjustment.new(0, -1.0, 1.0, 0.1, 0.3, 0.0)
      @scale = Gtk::HScale.new(adjustment)
      scale.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#000000'))
      scale.set_size_request(100, -1)
      scale.value_pos = Gtk::POS_RIGHT
      scale.digits = 1
      scale.draw_value = true
      scale.signal_connect('value-changed') do |widget|
        colorize
      end
      self.signal_connect('notify::sensitive') do |widget, param|
        colorize
      end
      scale.signal_connect('scroll-event') do |widget, event|
        res = (not (event.state.control_mask? or event.state.shift_mask?))
        if (event.direction==Gdk::EventScroll::UP) \
        or (event.direction==Gdk::EventScroll::LEFT)
          widget.value = (widget.value-0.1).round(1) if res
        else
          widget.value = (widget.value+0.1).round(1) if res
        end
        res
      end
      scale.value = avalue if avalue
      self.add(scale)
      colorize
    end
  end

  # Tab box for notebook with image and close button
  # RU: Бокс закладки для блокнота с картинкой и кнопкой
  class TabLabelBox < Gtk::HBox
    attr_accessor :image, :label, :stock

    def set_stock(astock)
      p @stock = astock
      #$window.register_stock(stock)
      an_image = $window.get_preset_image(stock, Gtk::IconSize::SMALL_TOOLBAR, nil)
      if (@image.is_a? Gtk::Image) and @image.icon_set
        @image.icon_set = an_image.icon_set
      else
        @image = an_image
      end
    end

    def initialize(an_image, title, child=nil, *args)
      args ||= [false, 0]
      super(*args)
      @image = an_image
      @image ||= :person
      if ((image.is_a? Symbol) or (image.is_a? String))
        set_stock(image)
      end
      @image.set_padding(2, 0)
      self.pack_start(image, false, false, 0) if image
      @label = Gtk::Label.new(title)
      self.pack_start(label, false, false, 0)
      if child
        btn = Gtk::Button.new
        btn.relief = Gtk::RELIEF_NONE
        btn.focus_on_click = false
        style = btn.modifier_style
        style.xthickness = 0
        style.ythickness = 0
        btn.modify_style(style)
        wim,him = Gtk::IconSize.lookup(Gtk::IconSize::MENU)
        btn.set_size_request(wim+2,him+2)
        btn.signal_connect('clicked') do |*args|
          yield if block_given?
          ind = $window.notebook.children.index(child)
          $window.notebook.remove_page(ind) if ind
          self.destroy if not self.destroyed?
          child.destroy if not child.destroyed?
        end
        close_image = Gtk::Image.new(Gtk::Stock::CLOSE, Gtk::IconSize::MENU)
        btn.add(close_image)
        align = Gtk::Alignment.new(1.0, 0.5, 0.0, 0.0)
        align.add(btn)
        self.pack_start(align, false, false, 0)
      end
      self.spacing = 3
      self.show_all
    end
  end

  # Window for view body (text or blob)
  # RU: Окно просмотра тела (текста или блоба)
  class BodyScrolledWindow < Gtk::ScrolledWindow
    include PandoraUtils

    attr_accessor :field, :link_name, :body_child, :format, :raw_buffer, :view_buffer, \
      :view_mode, :color_mode, :fields, :property_box, :toolbar, :edit_btn

    def parent_win
      res = parent.parent.parent
    end

    def get_fld_value_by_id(id)
      res = nil
      fld = fields.detect{ |f| (f[FI_Id].to_s == id) }
      res = fld[FI_Value] if fld.is_a? Array
      res
    end

    def fill_body
      if field
        link_name = field[FI_Widget].text
        link_name.chomp! if link_name
        link_name = PandoraUtils.absolute_path(link_name)
        bodywin = self
        bodywid = self.child
        if (not bodywid) or (link_name != bodywin.link_name)
          @last_sw = child
          if bodywid
            bodywid.destroy if (not bodywid.destroyed?)
            bodywid = nil
            #field[FI_Widget2] = nil
          end
          if link_name and (link_name != '')
            if File.exist?(link_name)
              ext = File.extname(link_name)
              ext_dc = ext.downcase
              if ext
                if (['.jpg','.gif','.png'].include? ext_dc)
                  scale = nil
                  #!!!img_width  = bodywin.parent.allocation.width-14
                  #!!!img_height = bodywin.parent.allocation.height
                  img_width  = bodywin.allocation.width-14
                  img_height = bodywin.allocation.height
                  image = PandoraGtk.start_image_loading(link_name, nil, scale)
                    #img_width, img_height)
                  bodywid = image
                  bodywin.link_name = link_name
                elsif (['.txt','.rb','.xml','.py','.csv','.sh'].include? ext_dc)
                  if ext_dc=='.rb'
                    @format = 'ruby'
                  end
                  p 'Read file: '+link_name
                  File.open(link_name, 'r') do |file|
                    field[FI_Value] = file.read
                  end
                else
                  ext = nil
                end
              end
              if not ext
                field[FI_Value] = '@'+link_name
              end
            else
              err_text = _('File does not exist')+":\n"+link_name
              label = Gtk::Label.new(err_text)
              bodywid = label
            end
          else
            link_name = nil
          end

          bodywid ||= PandoraGtk::EditorTextView.new(0, nil)

          if not bodywin.child
            if bodywid.is_a? PandoraGtk::SuperTextView
              begin
                bodywin.add(bodywid)
              rescue Exception
                bodywin.add_with_viewport(bodywid)
              end
            else
              bodywin.add_with_viewport(bodywid)
            end
            fmt = get_fld_value_by_id('type')
            bodywin.format = fmt.downcase if fmt.is_a? String
          end
          bodywin.body_child = bodywid
          if bodywid.is_a? Gtk::TextView
            bodywin.init_view_buf(bodywin.body_child.buffer)
            atext = field[FI_Value].to_s
            bodywin.init_raw_buf(atext)
            if atext and (atext.size==0)
              bodywin.view_mode = false
            end
            bodywin.set_buffers
            #toolbar.show
          else
            #toolbar2.show
          end
          bodywin.show_all
        end
      end
    end

    def initialize(aproperty_box, afields, *args)
      @@page_setup ||= nil
      super(*args)
      @property_box = aproperty_box
      @format = nil
      @view_mode = true
      @color_mode = true
      @fields = afields
    end

    def init_view_buf(buf)
      if (not @view_buffer) and buf
        @view_buffer = buf
      end
    end

    def init_raw_buf(text=nil)
      if (not @raw_buffer)
        buf ||= Gtk::TextBuffer.new
        @raw_buffer = buf
        buf.text = text if text
        buf.create_tag('string', {'foreground' => '#00f000'})
        buf.create_tag('symbol', {'foreground' => '#008020'})
        buf.create_tag('comment', {'foreground' => '#8080e0'})
        buf.create_tag('keyword', {'foreground' => '#ffffff', \
          'weight' => Pango::FontDescription::WEIGHT_BOLD})
        buf.create_tag('keyword2', {'foreground' => '#ffffff'})
        buf.create_tag('function', {'foreground' => '#f12111'})
        buf.create_tag('number', {'foreground' => '#f050e0'})
        buf.create_tag('hexadec', {'foreground' => '#e070e7'})
        buf.create_tag('constant', {'foreground' => '#60eedd'})
        buf.create_tag('big_constant', {'foreground' => '#d080e0'})
        buf.create_tag('identifer', {'foreground' => '#ffff33'})
        buf.create_tag('global', {'foreground' => '#ffa500'})
        buf.create_tag('instvar', {'foreground' => '#ff85a2'})
        buf.create_tag('classvar', {'foreground' => '#ff79ec'})
        buf.create_tag('operator', {'foreground' => '#ffffff'})
        buf.create_tag('class', {'foreground' => '#ff1100', \
          'weight' => Pango::FontDescription::WEIGHT_BOLD})
        buf.create_tag('module', {'foreground' => '#1111ff', \
          'weight' => Pango::FontDescription::WEIGHT_BOLD})
        buf.create_tag('regex', {'foreground' => '#105090'})

        buf.signal_connect('changed') do |buf|  #modified-changed
          mark = buf.get_mark('insert')
          iter = buf.get_iter_at_mark(mark)
          line1 = iter.line
          set_tags(buf, line1, line1, true)
          false
        end

        buf.signal_connect('insert-text') do |buf, iter, text, len|
          $view_buffer_off1 = iter.offset
          false
        end

        buf.signal_connect('paste-done') do |buf|
          if $view_buffer_off1
            line1 = buf.get_iter_at_offset($view_buffer_off1).line
            mark = buf.get_mark('insert')
            iter = buf.get_iter_at_mark(mark)
            line2 = iter.line
            $view_buffer_off1 = iter.offset
            set_tags(buf, line1, line2)
          end
          false
        end
      end
    end

    # Ruby key words
    # Ключевые слова Ruby
    RUBY_KEYWORDS = ('begin end module class def if then else elsif' \
      +' while unless do case when require yield rescue include').split
    RUBY_KEYWORDS2 = 'self nil true false not and or'.split

    # Call a code block with the text
    # RU: Вызвать блок кода по тексту
    def ruby_tag_line(str, index=0, mode=0)

      def ident_char?(c)
        ('a'..'z').include?(c) or ('A'..'Z').include?(c) or (c == '_')
      end

      def capt_char?(c)
        ('A'..'Z').include?(c) or ('0'..'9').include?(c) or (c == '_')
      end

      def word_char?(c)
        ('a'..'z').include?(c) or ('A'..'Z').include?(c) \
        or ('0'..'9').include?(c) or (c == '_')
      end

      def oper_char?(c)
        ".+,-=*^%()<>&[]!?~{}|/\\".include?(c)
      end

      def rewind_ident(str, i, ss, pc, prev_kw=nil)

        def check_func(prev_kw, c, i, ss, str)
          if (prev_kw=='def') and (c.nil? or (c=='.'))
            if not c.nil?
              yield(:operator, i, i+1)
              i += 1
            end
            i1 = i
            i += 1 while (i<ss) and ident_char?(str[i])
            i += 1 if (i<ss) and ('=?!'.include?(str[i]))
            i2 = i
            yield(:function, i1, i2)
          end
          i
        end

        kw = nil
        c = str[i]
        fc = c
        i1 = i
        i += 1
        big_cons = true
        while (i<ss)
          c = str[i]
          if ('a'..'z').include?(c)
            big_cons = false if big_cons
          elsif not capt_char?(c)
            break
          end
          i += 1
        end
        #p 'rewind_ident(str, i1, i, ss, pc)='+[str, i1, i, ss, pc].inspect
        #i -= 1
        i2 = i
        if ('A'..'Z').include?(fc)
          if prev_kw=='class'
            yield(:class, i1, i2)
          elsif prev_kw=='module'
            yield(:module, i1, i2)
          else
            if big_cons
              if ['TRUE', 'FALSE'].include?(str[i1, i2-i1])
                yield(:keyword2, i1, i2)
              else
                yield(:big_constant, i1, i2)
              end
            else
              yield(:constant, i1, i2)
            end
            i = check_func(prev_kw, c, i, ss, str) do |tag, id1, id2|
              yield(tag, id1, id2)
            end
          end
        else
          if pc==':'
            yield(:symbol, i1-1, i2)
          elsif pc=='@'
            if (i1-2>0) and (str[i1-2]=='@')
              yield(:classvar, i1-2, i2)
            else
              yield(:instvar, i1-1, i2)
            end
          elsif pc=='$'
            yield(:global, i1-1, i2)
          else
            can_keyw = (((i1<=0) or " \t\n({}[]=|+&,".include?(str[i1-1])) \
              and ((i2>=ss) or " \t\n(){}[]=|+&,.".include?(str[i2])))
            s = str[i1, i2-i1]
            if can_keyw and RUBY_KEYWORDS.include?(s)
              yield(:keyword, i1, i2)
              kw = s
            elsif can_keyw and RUBY_KEYWORDS2.include?(s)
              yield(:keyword2, i1, i2)
              if (s=='self') and (prev_kw=='def')
                i = check_func(prev_kw, c, i, ss, str) do |tag, id1, id2|
                  yield(tag, id1, id2)
                end
              end
            else
              i += 1 if (i<ss) and ('?!'.include?(str[i]))
              if prev_kw=='def'
                if (i<ss) and (str[i]=='.')
                  yield(:identifer, i1, i)
                  i = check_func(prev_kw, c, i, ss, str) do |tag, id1, id2|
                    yield(tag, id1, id2)
                  end
                else
                  i = check_func(prev_kw, nil, i1, ss, str) do |tag, id1, id2|
                    yield(tag, id1, id2)
                  end
                end
              else
                yield(:identifer, i1, i)
              end
            end
          end
        end
        [i, kw]
      end

      ss = str.size
      if ss>0
        i = 0
        if (mode == 1)
          if (str[0,4] == '=end')
            mode = 0
            i = 4
            yield(:comment, index, index + i)
          else
            yield(:comment, index, index + ss)
          end
        elsif (mode == 0) and (str[0,6] == '=begin')
          mode = 1
          yield(:comment, index, index + ss)
        elsif (mode != 1)
          i += 1 while (i<ss) and ((str[i] == ' ') or (str[i] == "\t"))
          pc = ' '
          kw, kw2 = nil
          while (i<ss)
            c = str[i]
            if (c != ' ') and (c != "\t")
              if (c == '#')
                yield(:comment, index + i, index + ss)
                break
              elsif (c == "'") or (c == '"') or (c == '/')
                qc = c
                i1 = i
                i += 1
                if (i<ss)
                  c = str[i]
                  if c==qc
                    i += 1
                  else
                    pc = ' '
                    while (i<ss) and ((c != qc) or (pc == "\\") or (pc == qc))
                      if (pc=="\\")
                        pc = ' '
                      else
                        pc = c
                      end
                      c = str[i]
                      if (qc=='"') and (c=='{') and (pc=='#')
                        yield(:string, index + i1, index + i - 1)
                        yield(:operator, index + i - 1, index + i + 1)
                        i, kw2 = rewind_ident(str, i, ss, ' ') do |tag, id1, id2|
                          yield(tag, index + id1, index + id2)
                        end
                        i1 = i
                      end
                      i += 1
                    end
                  end
                end
                if (qc == '/')
                  i += 1 while (i<ss) and ('imxouesn'.include?(str[i]))
                  yield(:regex, index + i1, index + i)
                else
                  yield(:string, index + i1, index + i)
                end
              elsif ident_char?(c)
                i, kw = rewind_ident(str, i, ss, pc, kw) do |tag, id1, id2|
                  yield(tag, index + id1, index + id2)
                end
                pc = ' '
              elsif (c=='$') and (i+1<ss) and ('~'.include?(str[i+1]))
                i1 = i
                i += 2
                yield(:global, index + i1, index + i)
                pc = ' '
              elsif oper_char?(c) or ((pc==':') and (c==':'))
                i1 = i
                i1 -=1 if (i1>0) and (c==':')
                i += 1
                while (i<ss) and (oper_char?(str[i]) or (str[i]==':'))
                  i += 1
                end
                if i<ss
                  pc = ' '
                  c = str[i]
                end
                yield(:operator, index + i1, index + i)
              elsif ((c==':') or (c=='$')) and (i+1<ss) and (ident_char?(str[i+1]))
                i += 1
                pc = c
                i, kw2 = rewind_ident(str, i, ss, pc) do |tag, id1, id2|
                  yield(tag, index + id1, index + id2)
                end
                pc = ' '
              elsif ('0'..'9').include?(c)
                i1 = i
                i += 1
                if (i<ss) and ((str[i]=='x') or (str[i]=='X'))
                  i += 1
                  while (i<ss)
                    c = str[i]
                    break unless (('0'..'9').include?(c) or ('A'..'F').include?(c))
                    i += 1
                  end
                  yield(:hexadec, index + i1, index + i)
                else
                  while (i<ss)
                    c = str[i]
                    break unless (('0'..'9').include?(c) or (c=='.') or (c=='e'))
                    i += 1
                  end
                  if i<ss
                    i -= 1 if str[i-1]=='.'
                    pc = ' '
                  end
                  yield(:number, index + i1, index + i)
                end
              else
                #yield(:keyword, index + i, index + ss/2)
                #break
                pc = c
                i += 1
              end
            else
              pc = c
              i += 1
            end
          end
        end
      end
      mode
    end

    # Call a code block with the text
    # RU: Вызвать блок кода по тексту
    def bbcode_html_tag_line(str, index=0, mode=0, format='bbcode')
      open_brek = '['
      close_brek = ']'
      if format=='html'
        open_brek = '<'
        close_brek = '>'
      end
      d = 0
      ss = str.size
      while ss>0
        if mode>0
          # find close brek
          i = str.index(close_brek)
          #p 'close brek  [str,i,d]='+[str,i,d].inspect
          k = ss
          if i
            k = i
            yield(:operator, index + d + i , index + d + i + 1)
            i += 1
            mode = 0
          else
            i = ss
          end
          if k>0
            com = str[0, k]
            j = 0
            cs = com.size
            j +=1 while (j<cs) and (not ' ='.index(com[j]))
            comu = nil
            params = nil
            if (j<cs)
              params = com[j+1..-1].strip
              comu = com[0, j]
            else
              comu = com
            end
            if comu and (comu.size>0)
              if SuperTextView::BBCODES.include?(comu.upcase)
                yield(:big_constant, index + d, index + d + j)
              else
                yield(:constant, index + d, index + d + j)
              end
            end
            if j<cs
              yield(:comment, index + d + j + 1, index + d + k)
            end
          end
        else
          # find open brek
          i = str.index(open_brek)
          #p 'open brek  [str,i,d]='+[str,i,d].inspect
          if i
            yield(:operator, index + d + i , index + d + i + 1)
            i += 1
            mode = 1
            if (i<ss) and (str[i]=='/')
              yield(:operator, index + d + i, index + d + i+1)
              i += 1
              mode = 2
            end
          else
            i = ss
          end
        end
        d += i
        str = str[i..-1]
        ss = str.size
      end
      mode
    end

    # Set tags for line range of TextView
    # RU: Проставить теги для диапазона строк TextView
    def set_tags(buf, line1, line2, clean=nil)
      #p 'line1, line2, view_mode='+[line1, line2, view_mode].inspect
      if (not @view_mode) and @color_mode
        buf.begin_user_action do
          line = line1
          iter1 = buf.get_iter_at_line(line)
          iterN = nil
          mode = 0
          while line<=line2
            line += 1
            if line<buf.line_count
              iterN = buf.get_iter_at_line(line)
              iter2 = buf.get_iter_at_offset(iterN.offset-1)
            else
              iter2 = buf.end_iter
              line = line2+1
            end

            text = buf.get_text(iter1, iter2)
            offset1 = iter1.offset
            buf.remove_all_tags(iter1, iter2) if clean
            #buf.apply_tag('keyword', iter1, iter2)
            case @format
              when 'ruby'
                mode = ruby_tag_line(text, offset1, mode) do |tag, start, last|
                  buf.apply_tag(tag.to_s,
                    buf.get_iter_at_offset(start),
                    buf.get_iter_at_offset(last))
                end
              when 'bbcode', 'html'
                mode = bbcode_html_tag_line(text, offset1, mode, @format) do |tag, start, last|
                  buf.apply_tag(tag.to_s,
                    buf.get_iter_at_offset(start),
                    buf.get_iter_at_offset(last))
                end
              #end-case-when
            end
            #p mode
            iter1 = iterN if iterN
            #Gtk.main_iteration
          end
        end
      end
    end

    # Set buffers
    # RU: Задать буферы
    def set_buffers
      tv = body_child
      if tv and (tv.is_a? Gtk::TextView)
        tv.hide
        text_changed = false
        @format ||= 'auto'
        unless ['markdown', 'bbcode', 'html', 'ruby', 'plain'].include?(@format)
          @format = 'bbcode' #if aformat=='auto' #need autodetect here
        end
        @tv_style ||= tv.modifier_style
        if view_mode
          tv.modify_style(@tv_style)
          tv.modify_font(nil)
          tv.hide
          view_buffer.text = ''
          tv.buffer = view_buffer
          tv.insert_taged_str_to_buffer(raw_buffer.text, view_buffer, @format)
          tv.set_left_border_width(tv.view_border)
          tv.show
          tv.editable = false
        else
          tv.modify_font($font_desc)
          tv.modify_base(Gtk::STATE_NORMAL, Gdk::Color.parse('#000000'))
          tv.modify_text(Gtk::STATE_NORMAL, Gdk::Color.parse('#ffff33'))
          tv.modify_cursor(Gdk::Color.parse('#ff1111'), Gdk::Color.parse('#ff1111'))
          tv.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#A0A0A0'))
          tv.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#000000'))
          tv.hide
          #convert_buffer(view_buffer.text, raw_buffer, false, @format)
          tv.buffer = raw_buffer
          left_bord = tv.raw_border
          left_bord ||= -3
          tv.set_left_border_width(left_bord)
          tv.show
          tv.editable = true
          raw_buffer.remove_all_tags(raw_buffer.start_iter, raw_buffer.end_iter)
          set_tags(raw_buffer, 0, raw_buffer.line_count)
        end
        fmt_btn = property_box.format_btn
        fmt_btn.label = format if (fmt_btn and (fmt_btn.label != format))
        tv.show
        tv.grab_focus
      end
    end

    # Set tag for selection
    # RU: Задать тэг для выделенного
    def insert_tag(tag, params=nil, defval=nil)
      tv = body_child
      if tag and (tv.is_a? Gtk::TextView)
        edit_btn.active = true if edit_btn if view_mode
        tv.set_tag(tag, params, defval, format)
      end
    end

    Data = Struct.new(:font_size, :lines_per_page, :lines, :n_pages)
    HEADER_HEIGHT = 10 * 72 / 25.4
    HEADER_GAP = 3 * 72 / 25.4

    def set_page_setup
      if not @@page_setup
        @@page_setup = Gtk::PageSetup.new
        paper_size = Gtk::PaperSize.new(Gtk::PaperSize.default)
        @@page_setup.paper_size_and_default_margins = paper_size
      end
      @@page_setup = Gtk::PrintOperation::run_page_setup_dialog($window, @@page_setup)
    end

    def run_print_operation(preview=false)
      begin
        operation = Gtk::PrintOperation.new
        operation.default_page_setup = @@page_setup if @@page_setup

        operation.use_full_page = false
        operation.unit = Gtk::PaperSize::UNIT_POINTS
        operation.show_progress = true
        data = Data.new
        data.font_size = 12.0

        operation.signal_connect('begin-print') do |_operation, context|
          on_begin_print(_operation, context, data)
        end
        operation.signal_connect('draw-page') do |_operation, context, page_number|
          on_draw_page(_operation, context, page_number, data)
        end
        if preview
          operation.run(Gtk::PrintOperation::ACTION_PREVIEW, $window)
        else
          operation.run(Gtk::PrintOperation::ACTION_PRINT_DIALOG, $window)
        end
      rescue
        PandoraGtk::GoodMessageDialog.new($!.message).run_and_do
      end
    end

    def on_begin_print(operation, context, data)
      height = context.height - HEADER_HEIGHT - HEADER_GAP
      data.lines_per_page = (height / data.font_size).floor
      p '[context.height, height, HEADER_HEIGHT, HEADER_GAP, data.lines_per_page]='+\
        [context.height, height, HEADER_HEIGHT, HEADER_GAP, data.lines_per_page].inspect
      tv = body_child
      data.lines = nil
      data.lines = tv.buffer if (tv.is_a? Gtk::TextView)
      if data.lines
        data.n_pages = (data.lines.line_count - 1) / data.lines_per_page + 1
      else
        data.n_pages = 1
      end
      operation.set_n_pages(data.n_pages)
    end

    def on_draw_page(operation, context, page_number, data)
      cr = context.cairo_context
      draw_header(cr, operation, context, page_number, data)
      draw_body(cr, operation, context, page_number, data)
    end

    def draw_header(cr, operation, context, page_number, data)
      width = context.width
      cr.rectangle(0, 0, width, HEADER_HEIGHT)
      cr.set_source_rgb(0.8, 0.8, 0.8)
      cr.fill_preserve
      cr.set_source_rgb(0, 0, 0)
      cr.line_width = 1
      cr.stroke
      layout = context.create_pango_layout
      layout.font_description = 'sans 14'
      layout.text = 'Pandora Print'
      text_width, text_height = layout.pixel_size
      if (text_width > width)
        layout.width = width
        layout.ellipsize = :start
        text_width, text_height = layout.pixel_size
      end
      y = (HEADER_HEIGHT - text_height) / 2
      cr.move_to((width - text_width) / 2, y)
      cr.show_pango_layout(layout)
      layout.text = "#{page_number + 1}/#{data.n_pages}"
      layout.width = -1
      text_width, text_height = layout.pixel_size
      cr.move_to(width - text_width - 4, y)
      cr.show_pango_layout(layout)
    end

    def draw_body(cr, operation, context, page_number, data)
      bw = self
      tv = bw.body_child
      if (not (tv.is_a? Gtk::TextView)) or bw.view_mode
        cm = Gdk::Colormap.system
        width = context.width
        height = context.height
        min_width = width
        min_width = tv.allocation.width if tv.allocation.width < min_width
        min_height = height - (HEADER_HEIGHT + HEADER_GAP)
        min_height = tv.allocation.height if tv.allocation.height < min_height
        pixbuf = Gdk::Pixbuf.from_drawable(cm, tv.window, 0, 0, min_width, \
          min_height)
        cr.set_source_color(Gdk::Color.new(65535, 65535, 65535))
        cr.gdk_rectangle(Gdk::Rectangle.new(0, HEADER_HEIGHT + HEADER_GAP, \
          context.width, height - (HEADER_HEIGHT + HEADER_GAP)))
        cr.fill

        cr.set_source_pixbuf(pixbuf, 0, HEADER_HEIGHT + HEADER_GAP)
        cr.paint
      else
        layout = context.create_pango_layout
        description = Pango::FontDescription.new('monosapce')
        description.size = data.font_size * Pango::SCALE
        layout.font_description = description

        cr.move_to(0, HEADER_HEIGHT + HEADER_GAP)
        buf = data.lines
        start_line = page_number * data.lines_per_page
        line = start_line
        iter1 = buf.get_iter_at_line(line)
        iterN = nil
        buf.begin_user_action do
          while (line<buf.line_count) and (line<start_line+data.lines_per_page)
            line += 1
            if line < buf.line_count
              iterN = buf.get_iter_at_line(line)
              iter2 = buf.get_iter_at_offset(iterN.offset-1)
            else
              iter2 = buf.end_iter
            end
            text = buf.get_text(iter1, iter2)
            text = (line.to_s+':').ljust(6, ' ')+text.to_s
            layout.text = text
            cr.show_pango_layout(layout)
            cr.rel_move_to(0, data.font_size)
            iter1 = iterN
          end
        end
      end
    end

  end

  SexList = [[1, _('man')], [0, _('woman')], [2, _('gay')], [3, _('trans')], [4, _('lesbo')]]

  # Dialog with enter fields
  # RU: Диалог с полями ввода
  class PropertyBox < Gtk::VBox
    include PandoraModel

    attr_accessor :panobject, :vbox, :fields, :text_fields, :statusbar, \
      :rate_label, :lang_entry, :last_sw, :rate_btn, :format_btn, \
      :last_width, :last_height, :notebook, :tree_view, :edit, \
      :keep_btn, :follow_btn, :vouch0, :vouch_btn, :vouch_scale, :public0, \
      :public_btn, :public_scale, :ignore_btn, :arch_btn, :panhash0, :obj_id,
      :panstate

    # Create fields dialog
    # RU: Создать форму с полями
    def initialize(apanobject, afields, apanhash0, an_id, an_edit=nil, anotebook=nil, \
    atree_view=nil, width_loss=nil, height_loss=nil)
      super()
      if apanobject.is_a? Integer
        kind = apanobject
        panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
        if panobjectclass
          apanobject = PandoraUtils.get_model(panobjectclass.ider)
        end
      end
      @panobject = apanobject
      @fields = afields
      @notebook = anotebook
      @tree_view = atree_view
      @panhash0 = apanhash0
      @obj_id = an_id
      @edit = an_edit

      @vbox = self

      return if afields.nil?

      #@statusbar = Gtk::Statusbar.new
      #PandoraGtk.set_statusbar_text(statusbar, '')
      #statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      #@rate_btn = Gtk::Button.new(_('Rate')+':')
      #rate_btn.relief = Gtk::RELIEF_NONE
      #statusbar.pack_start(rate_btn, false, false, 0)
      #panelbox.pack_start(statusbar, false, false, 0)

      # devide text fields in separate list
      @panstate = 0
      @text_fields = Array.new
      i = @fields.size
      while i>0 do
        i -= 1
        field = @fields[i]
        atext = field[FI_VFName]
        aview = field[FI_View]
        if (aview=='blob') or (aview=='text')
          bodywin = BodyScrolledWindow.new(self, @fields, nil, nil)
          bodywin.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
          bodywin.field = field
          field[FI_Widget2] = bodywin
          if notebook
            label_box = TabLabelBox.new(Gtk::Stock::DND, atext, nil)
            page = notebook.append_page(bodywin, label_box)
          end
          @text_fields << field
        end
        if (field[FI_Id]=='panstate')
          val = field[FI_Value]
          @panstate = val.to_i if (val and (val.size>0))
        end
      end

      self.signal_connect('key-press-event') do |widget, event|
        btn = nil
        case event.keyval
          when Gdk::Keyval::GDK_F5
            btn = PandoraGtk.find_tool_btn(toolbar, 'Edit')
        end
        if btn.is_a? Gtk::ToggleToolButton
          btn.active = (not btn.active?)
        elsif btn.is_a? Gtk::ToolButton
          btn.clicked
        end
        res = (not btn.nil?)
      end

      # create labels, remember them, calc middle char width
      texts_width = 0
      texts_chars = 0
      labels_width = 0
      max_label_height = 0
      @fields.each do |field|
        atext = field[FI_VFName]
        aview = field[FI_View]
        label = Gtk::Label.new(atext)
        label.tooltip_text = aview if aview and (aview.size>0)
        label.xalign = 0.0
        lw,lh = label.size_request
        field[FI_Label] = label
        field[FI_LabW] = lw
        field[FI_LabH] = lh
        texts_width += lw
        texts_chars += atext.length
        #texts_chars += atext.length
        labels_width += lw
        max_label_height = lh if max_label_height < lh
      end
      @middle_char_width = (texts_width.to_f*1.2 / texts_chars).round

      # max window size
      scr = Gdk::Screen.default
      width_loss = 40 if (width_loss.nil? or (width_loss<10))
      height_loss = 150 if (height_loss.nil? or (height_loss<10))
      @last_width, @last_height = [scr.width-width_loss-40, scr.height-height_loss-70]

      # compose first matrix, calc its geometry
      # create entries, set their widths/maxlen, remember them
      entries_width = 0
      max_entry_height = 0
      @def_widget = nil
      @fields.each do |field|
        #p 'field='+field.inspect
        max_size = 0
        fld_size = 0
        aview = field[FI_View]
        atype = field[FI_Type]
        entry = nil
        amodal = (not notebook.nil?)
        case aview
          when 'integer', 'byte', 'word'
            entry = IntegerEntry.new
          when 'hex'
            entry = HexEntry.new
          when 'real'
            entry = FloatEntry.new
          when 'time'
            entry = DateTimeEntry.new
          when 'datetime'
            entry = DateTimeBox.new(amodal)
          when 'date'
            entry = DateEntry.new(amodal)
          when 'coord'
            its_city = (panobject and (panobject.is_a? PandoraModel::City)) \
              or (kind==PandoraModel::PK_City)
            entry = CoordBox.new(amodal, its_city)
          when 'filename', 'blob'
            entry = FilenameBox.new(window, amodal) do |filename, entry, button, filename0|
              name_fld = @panobject.field_des('name')
              if (name_fld.is_a? Array) and (name_fld[FI_Widget].is_a? Gtk::Entry)
                name_ent = name_fld[FI_Widget]
                old_name = File.basename(filename0)
                old_name2 = File.basename(filename0, '.*')
                new_name = File.basename(filename)
                if (name_ent.text.size==0) or (name_ent.text==filename0) \
                or (name_ent.text==old_name) or (name_ent.text==old_name2)
                  name_ent.text = new_name
                end
              end
            end
          when 'base64'
            entry = Base64Entry.new
          when 'phash', 'panhash'
            if field[FI_Id]=='panhash'
              entry = HexEntry.new
              #entry.editable = false
            else
              entry = PanhashBox.new(atype, amodal)
            end
          when 'bytelist'
            if field[FI_Id]=='sex'
              entry = ByteListEntry.new(SexList, amodal)
            elsif field[FI_Id]=='kind'
              entry = ByteListEntry.new(PandoraModel::RelationNames, amodal)
            elsif field[FI_Id]=='mode'
              entry = ByteListEntry.new(PandoraModel::TaskModeNames, amodal)
            else
              entry = IntegerEntry.new
            end
          else
            entry = Gtk::Entry.new
        end
        @def_widget ||= entry
        begin
          def_size = 10
          case atype
            when 'Integer'
              def_size = 10
            when 'String'
              def_size = 32
            when 'Filename' , 'Blob', 'Text'
              def_size = 256
          end
          fld_size = field[FI_FSize].to_i if field[FI_FSize]
          max_size = field[FI_Size].to_i
          max_size = fld_size if (max_size==0)
          fld_size = def_size if (fld_size<=0)
          max_size = fld_size if (max_size<fld_size) and (max_size>0)
        rescue
          fld_size = def_size
        end
        #entry.width_chars = fld_size
        entry.max_length = max_size if max_size>0
        color = field[FI_Color]
        if color
          color = Gdk::Color.parse(color)
        else
          color = nil
        end
        #entry.modify_fg(Gtk::STATE_ACTIVE, color)
        entry.modify_text(Gtk::STATE_NORMAL, color)

        ew = fld_size*@middle_char_width
        ew = last_width if ew > last_width
        entry.width_request = ew if ((fld_size != 44) and (not (entry.is_a? PanhashBox)))
        ew,eh = entry.size_request
        #p 'Final [fld_size, max_size, ew]='+[fld_size, max_size, ew].inspect
        #p '[view, ew,eh]='+[aview, ew,eh].inspect
        field[FI_Widget] = entry
        field[FI_WidW] = ew
        field[FI_WidH] = eh
        entries_width += ew
        max_entry_height = eh if max_entry_height < eh
        text = field[FI_Value].to_s
        #if (atype=='Blob') or (atype=='Text')
        if (aview=='blob') or (aview=='text')
          entry.text = text[1..-1] if text and (text.size<1024) and (text[0]=='@')
        else
          entry.text = text
        end
      end

      # calc matrix sizes
      #field_matrix = Array.new
      mw, mh = 0, 0
      row = Array.new
      row_index = -1
      rw, rh = 0, 0
      orient = :up
      @fields.each_index do |index|
        field = @fields[index]
        if (index==0) or (field[FI_NewRow]==1)
          row_index += 1
          #field_matrix << row if row != []
          mw, mh = [mw, rw].max, mh+rh
          row = []
          rw, rh = 0, 0
        end

        if ! [:up, :down, :left, :right].include?(field[FI_LabOr]) then field[FI_LabOr]=orient; end
        orient = field[FI_LabOr]

        field_size = calc_field_size(field)
        rw, rh = rw+field_size[0], [rh, field_size[1]+1].max
        row << field
      end
      #field_matrix << row if row != []
      mw, mh = [mw, rw].max, mh+rh
      if (mw<=last_width) and (mh<=last_height) then
        @last_width, @last_height = mw+10, mh+10
      end

      #self.signal_connect('check-resize') do |widget|
      #self.signal_connect('configure-event') do |widget, event|
      #self.signal_connect('notify::position') do |widget, param|
      #self.signal_connect('expose-event') do |widget, param|
      #self.signal_connect('size-request') do |widget, requisition|
      self.signal_connect('size-allocate') do |widget, allocation|
        self.on_resize
        false
      end

      @old_field_matrix = []
    end

    def set_status_icons
      @panstate ||= 0
      if edit
        count, rate, querist_rate = PandoraCrypto.rate_of_panobj(panhash0)
        if rate_btn and rate.is_a? Float
          rate_btn.label = _('Rate')+': '+rate.round(2).to_s
        #dialog.rate_label.text = rate.to_s
        end

        if vouch_btn
          trust = nil
          trust_or_num = PandoraCrypto.trust_to_panobj(panhash0)
          #p '====trust_or_num='+[panhash0, trust_or_num].inspect
          trust = trust_or_num if (trust_or_num.is_a? Float)
          vouch_btn.safe_set_active((trust_or_num != nil))
          #vouch_btn.inconsistent = (trust_or_num.is_a? Integer)
          vouch_scale.sensitive = (trust != nil)
          #dialog.trust_scale.signal_emit('value-changed')
          trust ||= 0.0
          vouch_scale.scale.value = trust
        end

        keep_btn.safe_set_active((PandoraModel::PSF_Support & panstate)>0) if keep_btn
        arch_btn.safe_set_active((PandoraModel::PSF_Archive & panstate)>0) if arch_btn

        if public_btn
          pub_level = PandoraModel.act_relation(nil, panhash0, RK_MinPublic, :check)
          public_btn.safe_set_active(pub_level)
          public_scale.sensitive = pub_level
          if pub_level
            #p '====pub_level='+pub_level.inspect
            #public_btn.inconsistent = (pub_level == nil)
            public_scale.scale.value = (pub_level-RK_MinPublic-10)/10.0 if pub_level
          end
        end

        if follow_btn
          follow = PandoraModel.act_relation(nil, panhash0, RK_Follow, :check)
          follow_btn.safe_set_active(follow)
        end

        if ignore_btn
          ignore = PandoraModel.act_relation(nil, panhash0, RK_Ignore, :check)
          ignore_btn.safe_set_active(ignore)
        end

        lang_entry.active_text = lang.to_s if lang_entry
        #trust_lab = dialog.trust_btn.children[0]
        #trust_lab.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#777777')) if signed == 1
      else  #new or copy
        key = PandoraCrypto.current_key(false, false)
        key_inited = (key and key[PandoraCrypto::KV_Obj])
        keep_btn.safe_set_active(true) if keep_btn
        follow_btn.safe_set_active(key_inited) if follow_btn
        vouch_btn.safe_set_active(key_inited) if vouch_btn
        vouch_scale.sensitive = key_inited if vouch_scale
        if follow_btn and (not key_inited)
          follow_btn.sensitive = false
          vouch_btn.sensitive = false
          public_btn.sensitive = false
          ignore_btn.sensitive = false
        end
      end

      #!!!st_text = panobject.panhash_formula
      #!!!st_text = st_text + ' [#'+panobject.calc_panhash(sel[0], lang, \
      #  true, true)+']' if sel and sel.size>0
      #!!PandoraGtk.set_statusbar_text(dialog.statusbar, st_text)

      #if panobject.is_a? PandoraModel::Key
      #  mi = Gtk::MenuItem.new("Действия")
      #  menu = Gtk::MenuBar.new
      #  menu.append(mi)

      #  menu2 = Gtk::Menu.new
      #  menuitem = Gtk::MenuItem.new("Генерировать")
      #  menu2.append(menuitem)
      #  mi.submenu = menu2
      #  #p dialog.action_area
      #  dialog.hbox.pack_end(menu, false, false)
      #  #dialog.action_area.add(menu)
      #end

      titadd = nil
      if not edit
      #  titadd = _('edit')
      #else
        titadd = _('new')
      end
      #!!dialog.title += ' ('+titadd+')' if titadd and (titadd != '')
    end

    # Calculate field size
    # RU: Вычислить размер поля
    def calc_field_size(field)
      lw = field[FI_LabW]
      lh = field[FI_LabH]
      ew = field[FI_WidW]
      eh = field[FI_WidH]
      if (field[FI_LabOr]==:left) or (field[FI_LabOr]==:right)
        [lw+ew, [lh,eh].max]
      else
        field_size = [[lw,ew].max, lh+eh]
      end
    end

    # Calculate row size
    # RU: Вычислить размер ряда
    def calc_row_size(row)
      rw, rh = [0, 0]
      row.each do |fld|
        fs = calc_field_size(fld)
        rw, rh = rw+fs[0], [rh, fs[1]].max
      end
      [rw, rh]
    end

    # Event on resize window
    # RU: Событие при изменении размеров окна
    def on_resize(view_width=nil, view_height=nil, force=nil)
      view_width ||= parent.allocation.width
      view_height ||= parent.allocation.height
      if (((view_width != last_width) or (view_height != last_height) or force) \
      and (@pre_last_width.nil? or @pre_last_height.nil? \
      or ((view_width != @pre_last_width) and (view_height != @pre_last_height))))
        #p '----------RESIZE [view_width, view_height, last_width, last_height, parent]='+\
        #  [view_width, view_height, last_width, last_height, parent].inspect
        @pre_last_width, @pre_last_height = last_width, last_height
        @last_width, @last_height = view_width, view_height

        form_width = last_width-30
        form_height = last_height-65

        # create and fill field matrix to merge in form
        step = 1
        found = false
        while not found do
          fields = Array.new
          @fields.each do |field|
            fields << field.dup
          end

          field_matrix = Array.new
          mw, mh = 0, 0
          case step
            when 1  #normal compose. change "left" to "up" when doesn't fit to width
              row = Array.new
              row_index = -1
              rw, rh = 0, 0
              orient = :up
              fields.each_with_index do |field, index|
                if (index==0) or (field[FI_NewRow]==1)
                  row_index += 1
                  field_matrix << row if row != []
                  mw, mh = [mw, rw].max, mh+rh
                  #p [mh, form_height]
                  if (mh>form_height)
                    #step = 2
                    step = 5
                    break
                  end
                  row = Array.new
                  rw, rh = 0, 0
                end

                if (not [:up, :down, :left, :right].include?(field[FI_LabOr]))
                  field[FI_LabOr]=orient
                end
                orient = field[FI_LabOr]

                field_size = calc_field_size(field)
                rw, rh = rw+field_size[0], [rh, field_size[1]].max
                row << field

                if rw>form_width
                  col = row.size
                  while (col>0) and (rw>form_width)
                    col -= 1
                    fld = row[col]
                    if [:left, :right].include?(fld[FI_LabOr])
                      fld[FI_LabOr]=:up
                      rw, rh = calc_row_size(row)
                    end
                  end
                  if (rw>form_width)
                    #step = 3
                    step = 5
                    break
                  end
                end
              end
              field_matrix << row if row != []
              mw, mh = [mw, rw].max, mh+rh
              if (mh>form_height) or (mw>form_width)
                #step = 2
                step = 5
              end
              found = (step==1)
            when 2
              found = true
            when 3
              found = true
            when 5  #need to rebuild rows by width
              row = Array.new
              row_index = -1
              rw, rh = 0, 0
              orient = :up
              fields.each_with_index do |field, index|
                if ! [:up, :down, :left, :right].include?(field[FI_LabOr])
                  field[FI_LabOr] = orient
                end
                orient = field[FI_LabOr]
                field_size = calc_field_size(field)

                if (rw+field_size[0]>form_width)
                  row_index += 1
                  field_matrix << row if row != []
                  mw, mh = [mw, rw].max, mh+rh
                  #p [mh, form_height]
                  row = Array.new
                  rw, rh = 0, 0
                end

                row << field
                rw, rh = rw+field_size[0], [rh, field_size[1]].max

              end
              field_matrix << row if row != []
              mw, mh = [mw, rw].max, mh+rh
              found = true
            else
              found = true
          end
        end

        matrix_is_changed = @old_field_matrix.size != field_matrix.size
        if not matrix_is_changed
          field_matrix.each_index do |rindex|
            row = field_matrix[rindex]
            orow = @old_field_matrix[rindex]
            if row.size != orow.size
              matrix_is_changed = true
              break
            end
            row.each_index do |findex|
              field = row[findex]
              ofield = orow[findex]
              if (field[FI_LabOr] != ofield[FI_LabOr]) \
                or (field[FI_LabW] != ofield[FI_LabW]) \
                or (field[FI_LabH] != ofield[FI_LabH]) \
                or (field[FI_WidW] != ofield[FI_WidW]) \
                or (field[FI_WidH] != ofield[FI_WidH]) \
              then
                matrix_is_changed = true
                break
              end
            end
            if matrix_is_changed then break; end
          end
        end

        # compare matrix with previous
        if matrix_is_changed
          #p "----+++++redraw"
          @old_field_matrix = field_matrix

          #!!!@def_widget = focus if focus

          # delete sub-containers
          if @vbox.children.size>0
            @vbox.hide_all
            @vbox.child_visible = false
            @fields.each_index do |index|
              field = @fields[index]
              label = field[FI_Label]
              entry = field[FI_Widget]
              label.parent.remove(label)
              entry.parent.remove(entry)
            end
            @vbox.each do |child|
              child.destroy
            end
          end

          # show field matrix on form
          field_matrix.each do |row|
            row_hbox = Gtk::HBox.new
            row.each_index do |field_index|
              field = row[field_index]
              label = field[FI_Label]
              entry = field[FI_Widget]
              if (field[FI_LabOr]==nil) or (field[FI_LabOr]==:left)
                row_hbox.pack_start(label, false, false, 2)
                row_hbox.pack_start(entry, false, false, 2)
              elsif (field[FI_LabOr]==:right)
                row_hbox.pack_start(entry, false, false, 2)
                row_hbox.pack_start(label, false, false, 2)
              else
                field_vbox = Gtk::VBox.new
                if (field[FI_LabOr]==:down)
                  field_vbox.pack_start(entry, false, false, 2)
                  field_vbox.pack_start(label, false, false, 2)
                else
                  field_vbox.pack_start(label, false, false, 2)
                  field_vbox.pack_start(entry, false, false, 2)
                end
                row_hbox.pack_start(field_vbox, false, false, 2)
              end
            end
            @vbox.pack_start(row_hbox, false, false, 2)
          end
          @vbox.child_visible = true
          @vbox.show_all
          if (@def_widget and (not @def_widget.destroyed?))
            #focus = @def_widget
            @def_widget.grab_focus
          end
        end
      end
    end

    def accept_hash_flds(flds_hash, lang=nil, created0=nil)
      time_now = Time.now.to_i
      if (panobject.is_a? PandoraModel::Created)
        if created0 and flds_hash['created'] \
        and ((flds_hash['created'].to_i-created0.to_i).abs<=1)
          flds_hash['created'] = created0
        end
        #if not edit
          #flds_hash['created'] = time_now
          #creator = PandoraCrypto.current_user_or_key(true)
          #flds_hash['creator'] = creator
        #end
      end
      flds_hash['modified'] = time_now

      @panstate = flds_hash['panstate']
      panstate ||= 0
      if keep_btn and keep_btn.sensitive?
        if keep_btn.active?
          panstate = (panstate | PandoraModel::PSF_Support)
        else
          panstate = (panstate & (~ PandoraModel::PSF_Support))
        end
      end
      if arch_btn and arch_btn.sensitive?
        if arch_btn.active?
          panstate = (panstate | PandoraModel::PSF_Archive)
        else
          panstate = (panstate & (~ PandoraModel::PSF_Archive))
        end
      end
      flds_hash['panstate'] = panstate

      lang ||= 0
      if (panobject.is_a? PandoraModel::Key)
        lang = flds_hash['rights'].to_i
      elsif (panobject.is_a? PandoraModel::Currency)
        lang = 0
      end

      panhash = panobject.calc_panhash(flds_hash, lang)
      flds_hash['panhash'] = panhash

      if (panobject.is_a? PandoraModel::Key) and panhash0 \
      and (flds_hash['kind'].to_i == PandoraCrypto::KT_Priv) and edit
        flds_hash['panhash'] = panhash0
      end

      filter = nil
      filter = {:id=>obj_id.to_i} if (edit and obj_id)
      #filter = {:panhash=>panhash} if filter.nil?
      res = panobject.update(flds_hash, nil, filter, true)

      if res
        filter ||= { :panhash => panhash, :modified => time_now }
        sel = panobject.select(filter, true)
        if sel[0]
          #p 'panobject.namesvalues='+panobject.namesvalues.inspect
          #p 'panobject.matter_fields='+panobject.matter_fields.inspect

          if tree_view and (not tree_view.destroyed?)
            @obj_id = panobject.field_val('id', sel[0])  #panobject.namesvalues['id']
            @obj_id = obj_id.to_i
            #p 'id='+id.inspect
            #p 'id='+id.inspect
            ind = tree_view.sel.index { |row| row[0]==obj_id }
            #p 'ind='+ind.inspect
            store = tree_view.model
            if ind
              #p '---------CHANGE'
              sel[0].each_with_index do |c,i|
                tree_view.sel[ind][i] = c
              end
              iter[0] = obj_id
              store.row_changed(path, iter)
            else
              #p '---------INSERT'
              tree_view.sel << sel[0]
              iter = store.append
              iter[0] = obj_id
              tree_view.set_cursor(Gtk::TreePath.new(tree_view.sel.size-1), nil, false)
            end
          end

          if vouch_btn and vouch_btn.sensitive? and vouch_scale
            PandoraCrypto.unsign_panobject(panhash0, true) if panhash0
            if vouch_btn.active?
              trust = vouch_scale.scale.value
              trust = PandoraModel.transform_trust(trust, :float_to_int)
              PandoraCrypto.sign_panobject(panobject, trust)
            end
          end

          if follow_btn and follow_btn.sensitive?
            PandoraModel.act_relation(nil, panhash0, RK_Follow, :delete, \
              true, true) if panhash0
            if panhash0 and (panhash != panhash0)
              PandoraModel.act_relation(nil, panhash, RK_Follow, :delete, \
                true, true)
            end
            if follow_btn.active?
              PandoraModel.act_relation(nil, panhash, RK_Follow, :create, \
                true, true)
            end
          end

          if public_btn and public_btn.sensitive?
            PandoraModel.act_relation(nil, panhash0, RK_MinPublic, :delete, \
              true, true) if panhash0
            if panhash0 and (panhash != panhash0)
              PandoraModel.act_relation(nil, panhash, RK_MinPublic, :delete, \
                true, true)
            end
            if public_btn.active? and public_scale
              public_level = PandoraModel.trust2_to_pub235(public_scale.scale.value)
              p 'public_level='+public_level.inspect
              PandoraModel.act_relation(nil, panhash, public_level, :create, \
                true, true)
            end
          end

          if ignore_btn and ignore_btn.sensitive?
            PandoraModel.act_relation(nil, panhash, RK_Ignore, :delete, \
              true, true)
            PandoraModel.act_relation(nil, panhash, RK_Ignore, :create, \
              true, true) if ignore_btn.active?
          end

        end
      end
    end

    def save_fields_with_flags(created0=nil, row=nil)
      # view_fields to raw_fields and hash
      flds_hash = {}
      file_way = nil
      file_way_exist = nil
      row ||= fields
      fields.each do |field|
        type = field[FI_Type]
        view = field[FI_View]
        entry = field[FI_Widget]
        val = entry.text

        if ((panobject.kind==PK_Relation) and val \
        and ((field[FI_Id]=='first') or (field[FI_Id]=='second')))
          PandoraModel.del_image_from_cache(val, true)
        elsif (panobject.kind==PK_Parameter) and (field[FI_Id]=='value')
          par_type = panobject.field_val('type', row)
          setting = panobject.field_val('setting', row)
          ps = PandoraUtils.decode_param_setting(setting)
          view = ps['view']
          view ||= PandoraUtils.pantype_to_view(par_type)
        elsif file_way
          p 'file_way2='+file_way.inspect
          if (field[FI_Id]=='type')
            val = PandoraUtils.detect_file_type(file_way) if (not val) or (val.size==0)
          elsif (field[FI_Id]=='sha1')
            if file_way_exist
              sha1 = Digest::SHA1.file(file_way)
              val = sha1.hexdigest
            else
              val = nil
            end
          elsif (field[FI_Id]=='md5')
            if file_way_exist
              md5 = Digest::MD5.file(file_way)
              val = md5.hexdigest
            else
              val = nil
            end
          elsif (field[FI_Id]=='size')
            val = File.size?(file_way)
          end
        end
        p 'fld, val, type, view='+[field[FI_Id], val, type, view].inspect
        val = PandoraUtils.view_to_val(val, type, view)
        if (view=='blob') or (view=='text')
          if val and (val.size>0)
            file_way = PandoraUtils.absolute_path(val)
            file_way_exist = File.exist?(file_way)
            p 'file_way1='+file_way.inspect
            val = '@'+val
            flds_hash[field[FI_Id]] = val
            field[FI_Value] = val
            #p '----TEXT ENTR!!!!!!!!!!!'
          end
        else
          flds_hash[field[FI_Id]] = val
          field[FI_Value] = val
        end
      end

      # add text and blob fields
      text_fields.each do |field|
        entry = field[FI_Widget]
        if entry.text == ''
          textview = field[FI_Widget2].child
          body_win = nil
          body_win = textview.parent if textview and (not textview.destroyed?)
          text = nil
          if body_win and (not body_win.destroyed?) \
          and (body_win.is_a? PandoraGtk::BodyScrolledWindow) and body_win.raw_buffer
            #text = textview.buffer.text
            text = body_win.raw_buffer.text
            if text and (text.size>0)
              #p '===TEXT BUF!!!!!!!!!!!'
              field[FI_Value] = text
              flds_hash[field[FI_Id]] = text
              type_fld = panobject.field_des('type')
              flds_hash['type'] = body_win.property_box.format_btn.label.upcase if type_fld
            else
              text = nil
            end
          end
          text ||= field[FI_Value]
          text ||= ''
          sha1_fld = panobject.field_des('sha1')
          flds_hash['sha1'] = Digest::SHA1.digest(text) if sha1_fld
          md5_fld = panobject.field_des('md5')
          flds_hash['md5'] = Digest::MD5.digest(text) if md5_fld
          size_fld = panobject.field_des('size')
          flds_hash['size'] = text.size if size_fld
        end
      end

      # language detect
      lg = nil
      begin
        lg = PandoraModel.text_to_lang(@lang_entry.entry.text)
      rescue
      end
      lang = lg if lg
      lang = 5 if (not lang.is_a? Integer) or (lang<0) or (lang>255)

      self.accept_hash_flds(flds_hash, lang, created0)
    end

  end

  # Dialog with enter fields
  # RU: Диалог с полями ввода
  class FieldsDialog < AdvancedDialog
    attr_accessor :property_box

    def get_bodywin(page_num=nil)
      res = nil
      page_num ||= notebook.page
      child = notebook.get_nth_page(page_num)
      res = child if (child.is_a? BodyScrolledWindow)
      res
    end

    # Create fields dialog
    # RU: Создать форму с полями
    def initialize(apanobject, tree_view, afields, panhash0, obj_id, edit, *args)
      super(*args)
      width_loss = 36
      height_loss = 134
      @property_box = PropertyBox.new(apanobject, afields, panhash0, obj_id, \
        edit, self.notebook, tree_view, width_loss, height_loss)
      viewport.add(@property_box)
      #self.signal_connect('configure-event') do |widget, event|
      #  property_box.on_resize_window(event.width, event.height)
      #  false
      #end
      self.set_default_size(property_box.last_width+width_loss, \
        property_box.last_height+height_loss)
      #property_box.window_width = property_box.window_height = 0
      viewport.show_all

      @last_sw = nil
      notebook.signal_connect('switch-page') do |widget, page, page_num|
        @last_sw = nil if (page_num == 0) and @last_sw
        if page_num==0
          hbox.show
        else
          bodywin = get_bodywin(page_num)
          p 'bodywin='+bodywin.inspect
          if bodywin
            hbox.hide
            bodywin.fill_body
          end
        end
      end

    end

  end

  $you_color = 'red'
  $dude_color = 'blue'
  $tab_color = 'blue'
  $sys_color = 'purple'
  $read_time = 1.5
  $last_page = nil

  # DrawingArea for video output
  # RU: DrawingArea для вывода видео
  class ViewDrawingArea < Gtk::DrawingArea
    attr_accessor :expose_event, :dialog

    def initialize(adialog, *args)
      super(*args)
      @dialog = adialog
      #set_size_request(100, 100)
      #@expose_event = signal_connect('expose-event') do
      #  alloc = self.allocation
      #  self.window.draw_arc(self.style.fg_gc(self.state), true, \
      #    0, 0, alloc.width, alloc.height, 0, 64 * 360)
      #end
    end

    # Set expose event handler
    # RU: Устанавливает обработчик события expose
    def set_expose_event(value, width=nil)
      signal_handler_disconnect(@expose_event) if @expose_event
      @expose_event = value
      if value.nil?
        if self==dialog.area_recv
          dialog.hide_recv_area
        else
          dialog.hide_send_area
        end
      else
        if self==dialog.area_recv
          dialog.show_recv_area(width)
        else
          dialog.show_send_area(width)
        end
      end
    end
  end

  # Add button to toolbar
  # RU: Добавить кнопку на панель инструментов
  def self.add_tool_btn(toolbar, stock=nil, title=nil, toggle=nil)
    btn = nil
    padd = 1
    if stock.is_a? Gtk::Widget
      btn = stock
    else
      stock = stock.to_sym if stock.is_a? String
      $window.register_stock(stock) if stock
      if toggle.nil?
        if stock.nil?
          btn = Gtk::SeparatorToolItem.new
          title = nil
          padd = 0
        else
          btn = Gtk::ToolButton.new(stock)
          btn.signal_connect('clicked') do |*args|
            yield(*args) if block_given?
          end
        end
      elsif toggle.is_a? Integer
        if stock
          btn = Gtk::MenuToolButton.new(stock)
        else
          btn = Gtk::MenuToolButton.new(nil, title)
          title = nil
        end
        btn.signal_connect('clicked') do |*args|
          yield(*args) if block_given?
        end
      else
        btn = SafeToggleToolButton.new(stock)
        btn.safe_signal_clicked do |*args|
          yield(*args) if block_given?
        end
        btn.safe_set_active(toggle) if toggle
      end
      if title
        title, keyb = title.split('|')
        if keyb
          keyb = ' '+keyb
        else
          keyb = ''
        end
        lang_title = _(title)
        lang_title.gsub!('_', '')
        btn.tooltip_text = lang_title + keyb
        btn.label = title
      elsif stock
        stock_info = Gtk::Stock.lookup(stock)
        if (stock_info.is_a? Array) and (stock_info.size>0)
          label = stock_info[1]
          if label
            label.gsub!('_', '')
            btn.tooltip_text = label
          end
        end
      end
    end
    #p '[toolbar, stock, title, toggle]='+[toolbar, stock, title, toggle].inspect
    if toolbar.is_a? Gtk::Toolbar
      toolbar.add(btn)
    else
      if btn.is_a? Gtk::Toolbar
        toolbar.pack_start(btn, true, true, padd)
      else
        toolbar.pack_start(btn, false, false, padd)
      end
    end
    btn
  end

  class CabViewport < Gtk::Viewport
    attr_accessor :def_widget

    def grab_def_widget
      if @def_widget and (not @def_widget.destroyed?)
        @def_widget.grab_focus
        #self.present
        GLib::Timeout.add(200) do
          @def_widget.grab_focus if @def_widget and (not @def_widget.destroyed?)
          false
        end
      end
    end

    def initialize(*args)
      super(*args)
      #self.signal_connect('show') do |window, event|
      #  grab_def_widget
      #  false
      #end
    end

  end

  CSI_Persons = 0
  CSI_Keys    = 1
  CSI_Nodes   = 2
  CSI_PersonRecs = 3

  CPI_Property  = 0
  CPI_Profile   = 1
  CPI_Opinions  = 2
  CPI_Relations = 3
  CPI_Signs     = 4
  CPI_Chat      = 5
  CPI_Dialog    = 6
  CPI_Editor    = 7

  CPI_Sub       = 1
  CPI_Last_Sub  = 4
  CPI_Last      = 7

  CabPageInfo = [[Gtk::Stock::PROPERTIES, 'Basic'], \
    [Gtk::Stock::HOME, 'Profile'], \
    [:opinion, 'Opinions'], \
    [:relation, 'Relations'], \
    [:sign, 'Signs'], \
    [:chat, 'Chat'], \
    [:dialog, 'Dialog'], \
    [:editor, 'Editor']]

  # Tab view of person
  TV_Name    = 0   # Name only
  TV_Family  = 1   # Family only
  TV_NameFam   = 2   # Name and family
  TV_NameN   = 3   # Name with number

  # Panobject cabinet page
  # RU: Страница кабинета панобъекта
  class CabinetBox < Gtk::VBox
    attr_accessor :room_id, :online_btn, :mic_btn, :webcam_btn, \
      :dlg_talkview, :chat_talkview, :area_send, :area_recv, :recv_media_pipeline, \
      :appsrcs, :session, :ximagesink, \
      :read_thread, :recv_media_queue, :has_unread, :person_name, :captcha_entry, \
      :sender_box, :toolbar_box, :captcha_enter, :edit_sw, :main_hpaned, \
      :send_hpaned, :cab_notebook, :opt_btns, :cab_panhash, :session, \
      :bodywin, :fields, :obj_id, :edit, :property_box, :kind, :label_box, \
      :active_page, :dlg_stock, :its_blob

    include PandoraGtk

    CL_Online = 0
    CL_Name   = 1

    def show_recv_area(width=nil)
      if area_recv.allocation.width <= 24
        width ||= 320
        main_hpaned.position = width
      end
    end

    def hide_recv_area
      main_hpaned.position = 0 if (main_hpaned and (not main_hpaned.destroyed?))
    end

    def show_send_area(width=nil)
      if area_send.allocation.width <= 24
        width ||= 120
        send_hpaned.position = width
      end
    end

    def hide_send_area
      send_hpaned.position = 0 if (send_hpaned and (not send_hpaned.destroyed?))
    end

    def init_captcha_entry(pixbuf, length=nil, symbols=nil, clue=nil, node_text=nil)
      if not @captcha_entry
        @captcha_label = Gtk::Label.new(_('Enter text from picture'))
        label = @captcha_label
        label.set_alignment(0.5, 1.0)
        @sender_box.pack_start(label, true, true, 2)

        @captcha_entry = PandoraGtk::MaskEntry.new

        len = 0
        begin
          len = length.to_i if length
        rescue
        end
        captcha_entry.max_length = len
        if symbols
          mask = symbols.downcase+symbols.upcase
          captcha_entry.mask = mask
        end

        res = area_recv.signal_connect('expose-event') do |widget, event|
          x = widget.allocation.width
          y = widget.allocation.height
          x = (x - pixbuf.width) / 2
          y = (y - pixbuf.height) / 2
          x = 0 if x<0
          y = 0 if y<0
          cr = widget.window.create_cairo_context
          cr.set_source_pixbuf(pixbuf, x, y)
          cr.paint
          true
        end
        area_recv.set_expose_event(res, pixbuf.width+20)

        captcha_entry.signal_connect('key-press-event') do |widget, event|
          if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
            text = captcha_entry.text
            if text.size>0
              @captcha_enter = captcha_entry.text
              captcha_entry.text = ''
              del_captcha_entry
            end
            true
          elsif (Gdk::Keyval::GDK_Escape==event.keyval)
            @captcha_enter = false
            del_captcha_entry
            false
          else
            false
          end
        end
        PandoraGtk.hack_enter_bug(captcha_entry)

        ew = 150
        if len>0
          str = label.text
          label.text = 'W'*(len+1)
          ew,lh = label.size_request
          label.text = str
        end

        captcha_entry.width_request = ew
        @captcha_align = Gtk::Alignment.new(0.5, 0, 0.0, 0.0)
        @captcha_align.add(captcha_entry)
        @sender_box.pack_start(@captcha_align, true, true, 2)
        @edit_sw.hide
        #@toolbar_box.hide
        @captcha_label.show
        @captcha_align.show_all

        area_recv.queue_draw

        Thread.pass
        sleep 0.02
        if dlg_talkview and (not dlg_talkview.destroyed?)
          dlg_talkview.after_addition(true)
          dlg_talkview.show_all
        end
        PandoraGtk.hack_grab_focus(@captcha_entry)
      end
    end

    def del_captcha_entry
      if @captcha_entry and (not self.destroyed?)
        @captcha_align.destroy
        @captcha_align = nil
        @captcha_entry = nil
        @captcha_label.destroy
        @captcha_label = nil
        #@toolbar_box.show
        @edit_sw.show_all
        area_recv.set_expose_event(nil)
        area_recv.queue_draw
        Thread.pass
        if dlg_talkview and (not dlg_talkview.destroyed?)
          dlg_talkview.after_addition(true)
          dlg_talkview.grab_focus
        end
      end
    end

    def hide_toolbar_btns(page=nil)
      @add_toolbar_btns.each do |btns|
        if btns.is_a? Array
          btns.each do |btn|
            btn.hide
          end
        end
      end
    end

    def show_toolbar_btns(page=nil)
      btns = @add_toolbar_btns[page]
      if btns.is_a? Array
        btns.each do |btn|
          btn.show_all
        end
      end
    end

    def add_btn_to_toolbar(stock=nil, title=nil, toggle=nil, page=nil)
      btns = nil
      if page.is_a? Array
        btns = page
      elsif page.is_a? FalseClass
        btns = nil
      else
        page ||= @active_page
        btns = @add_toolbar_btns[page]
        if not (btns.is_a? Array)
          btns = Array.new
          @add_toolbar_btns[page] = btns
        end
      end
      btn = PandoraGtk.add_tool_btn(toolbar_box, stock, title, toggle) do |*args|
        yield(*args) if block_given?
      end
      btns << btn if (not btns.nil?)
      btn
    end

    def fill_property_toolbar(pb)
      pb.keep_btn = add_btn_to_toolbar(:keep, 'Keep', false) do |btn|
        if ((not btn.destroyed?) and btn.active? \
        and (not PandoraGtk.is_ctrl_shift_alt?(true, true)))
          pb.ignore_btn.safe_set_active(false)
        end
      end

      pb.arch_btn = add_btn_to_toolbar(:arch, 'Shelve', false)

      pb.follow_btn = add_btn_to_toolbar(:follow, 'Follow', false) do |btn|
        if ((not btn.destroyed?) and btn.active? \
        and (not PandoraGtk.is_ctrl_shift_alt?(true, true)))
          pb.keep_btn.safe_set_active(true)
          pb.arch_btn.safe_set_active(false)
          pb.ignore_btn.safe_set_active(false)
        end
      end

      pb.vouch0 = 0.4
      pb.vouch_btn = add_btn_to_toolbar(:sign, 'Vouch|(Ctrl+G)', false) do |btn|
        if not btn.destroyed?
          pb.vouch_scale.sensitive = btn.active?
          if btn.active?
            if (not PandoraGtk.is_ctrl_shift_alt?(true, true))
              pb.keep_btn.safe_set_active(true)
              pb.arch_btn.safe_set_active(false)
              pb.ignore_btn.safe_set_active(false) if pb.vouch_scale.scale.value>0
            end
            pb.vouch0 ||= 0.4
            pb.vouch_scale.scale.value = pb.vouch0
          else
            pb.vouch0 = pb.vouch_scale.scale.value
          end
        end
      end
      pb.vouch_scale = TrustScale.new(nil, 'Vouch', pb.vouch0)
      pb.vouch_scale.sensitive = pb.vouch_btn.active?
      add_btn_to_toolbar(pb.vouch_scale)

      pb.public0 = 0.0
      pb.public_btn = add_btn_to_toolbar(:public, 'Public', false) do |btn|
        if not btn.destroyed?
          pb.public_scale.sensitive = btn.active?
          if btn.active?
            if (not PandoraGtk.is_ctrl_shift_alt?(true, true))
              pb.keep_btn.safe_set_active(true)
              pb.follow_btn.safe_set_active(true)
              pb.vouch_btn.active = true
              pb.arch_btn.safe_set_active(false)
              pb.ignore_btn.safe_set_active(false)
            end
            pb.public0 ||= 0.0
            pb.public_scale.scale.value = pb.public0
          else
            pb.public0 = pb.public_scale.scale.value
          end
        end
      end
      pb.public_scale = TrustScale.new(nil, 'Publish from level and higher', pb.public0)
      pb.public_scale.sensitive = pb.public_btn.active?
      add_btn_to_toolbar(pb.public_scale)

      pb.ignore_btn = add_btn_to_toolbar(:ignore, 'Ignore', false) do |btn|
        if ((not btn.destroyed?) and btn.active? \
        and (not PandoraGtk.is_ctrl_shift_alt?(true, true)))
          pb.keep_btn.safe_set_active(false)
          pb.follow_btn.safe_set_active(false)
          pb.public_btn.active = false
          if pb.vouch_btn.active? and (pb.vouch_scale.scale.value>0)
            pb.vouch_scale.scale.value = 0
          end
          pb.arch_btn.safe_set_active(true)
        end
      end

      add_btn_to_toolbar

      add_btn_to_toolbar(Gtk::Stock::SAVE) do |btn|
        pb.save_fields_with_flags
      end
      add_btn_to_toolbar(Gtk::Stock::OK) do |btn|
        pb.save_fields_with_flags
        self.destroy
      end

      #add_btn_to_toolbar(Gtk::Stock::CANCEL) do |btn|
      #  self.destroy
      #end

    end

    def fill_dlg_toolbar(page, talkview, chat_mode=false)
      crypt_btn = add_btn_to_toolbar(:crypt, 'Encrypt|(Ctrl+K)', false) if (page==CPI_Dialog)

      sign_scale = nil
      sign_btn = add_btn_to_toolbar(:sign, 'Vouch|(Ctrl+G)', false) do |widget|
        sign_scale.sensitive = widget.active? if not widget.destroyed?
      end
      sign_scale = TrustScale.new(nil, 'Vouch', 1.0)
      sign_scale.sensitive = sign_btn.active?
      add_btn_to_toolbar(sign_scale)

      if not chat_mode
        require_sign_btn = add_btn_to_toolbar(:require, 'Require sign', false)

        add_btn_to_toolbar

        is_online = (@session != nil)
        @online_btn = add_btn_to_toolbar(Gtk::Stock::CONNECT, 'Online', is_online) \
        do |widget|
          p 'widget.active?='+widget.active?.inspect
          if widget.active? #and (not widget.inconsistent?)
            persons, keys, nodes = PandoraGtk.extract_from_panhash(cab_panhash)
            if nodes and (nodes.size>0)
              nodes.each do |nodehash|
                $window.pool.init_session(nil, nodehash, 0, self, nil, \
                  persons, keys, nil, PandoraNet::CM_Captcha)
              end
            elsif persons
              persons.each do |person|
                $window.pool.init_session(nil, nil, 0, self, nil, \
                  person, keys, nil, PandoraNet::CM_Captcha)
              end
            end
          else
            widget.safe_set_active(false)
            $window.pool.stop_session(nil, cab_panhash, \
              nil, false, self.session)
          end
        end

        @webcam_btn = add_btn_to_toolbar(:webcam, 'Webcam', false) do |widget|
          if widget.active?
            if init_video_sender(true)
              online_btn.active = true
            end
          else
            init_video_sender(false, true)
            init_video_sender(false)
          end
        end

        @mic_btn = add_btn_to_toolbar(:mic, 'Mic', false) do |widget|
          if widget.active?
            if init_audio_sender(true)
              online_btn.active = true
            end
          else
            init_audio_sender(false, true)
            init_audio_sender(false)
          end
        end

        record_btn = add_btn_to_toolbar(Gtk::Stock::MEDIA_RECORD, 'Record', false) do |widget|
          if widget.active?
            #start record video and audio
            sleep(0.5)
            widget.safe_set_active(false)
          else
            #stop record, save the file and add a link to edit_box
          end
        end
      end

      add_btn_to_toolbar

      def_smiles = PandoraUtils.get_param('def_smiles')
      smile_btn = SmileButton.new(def_smiles) do |preset, label|
        smile_img = '[emot='+preset+'/'+label+']'
        text = talkview.edit_box.buffer.text
        smile_img = ' '+smile_img if (text.size>0) and (text[-1] != ' ')
        talkview.edit_box.buffer.insert_at_cursor(smile_img)
      end
      smile_btn.tooltip_text = _('Smile')+' (Alt+Down)'
      add_btn_to_toolbar(smile_btn)

      if page==CPI_Dialog
        game_btn = add_btn_to_toolbar(:game, 'Game')
        game_btn = add_btn_to_toolbar(:box, 'Box')
        add_btn_to_toolbar
      end

      send_btn = add_btn_to_toolbar(:send, 'Send') do |widget|
        mes = talkview.edit_box.buffer.text
        if mes != ''
          sign_trust = nil
          sign_trust = sign_scale.scale.value if sign_btn.active?
          crypt = nil
          crypt = crypt_btn.active? if crypt_btn
          if send_mes(mes, crypt, sign_trust, chat_mode)
            talkview.edit_box.buffer.text = ''
          end
        end
        false
      end
      send_btn.sensitive = false
      talkview.crypt_btn = crypt_btn
      talkview.sign_btn = sign_btn
      talkview.smile_btn = smile_btn
      talkview.send_btn = send_btn
    end

    # Add menu item
    # RU: Добавляет пункт меню
    def add_menu_item(btn, menu, stock, text=nil)
      mi = nil
      if stock.is_a? String
        mi = Gtk::MenuItem.new(stock)
      else
        $window.register_stock(stock)
        mi = Gtk::ImageMenuItem.new(stock)
        mi.label = _(text) if text
      end
      menu.append(mi)
      mi.signal_connect('activate') do |mi|
        yield(mi) if block_given?
      end
    end

    # Fill editor toolbar
    # RU: Заполнить панель редактора
    def fill_edit_toolbar
      bodywin = nil
      bodywid = nil
      pb = property_box
      first_body_fld = property_box.text_fields[0]
      if first_body_fld
        bodywin = first_body_fld[FI_Widget2]
        bodywid = bodywin.child
      end

      btn = add_btn_to_toolbar(Gtk::Stock::EDIT, 'Edit', false) do |btn|
        bodywin.view_mode = (not btn.active?)
        bodywin.set_buffers
      end
      bodywin.edit_btn = btn if bodywin

      btn = add_btn_to_toolbar(nil, 'auto', 0)
      pb.format_btn = btn
      menu = Gtk::Menu.new
      btn.menu = menu
      ['auto', 'plain', 'markdown', 'bbcode', 'wiki', 'html', 'ruby', \
      'python', 'xml'].each do |title|
        add_menu_item(btn, menu, title) do |mi|
          btn.label = mi.label
          bodywin.format = mi.label.to_s
          bodywin.set_buffers
        end
      end
      menu.show_all

      add_btn_to_toolbar

      toolbar = Gtk::Toolbar.new
      toolbar.show_arrow = true
      toolbar.toolbar_style = Gtk::Toolbar::Style::ICONS

      bodywin.toolbar = toolbar if bodywin

      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::BOLD) do
        bodywin.insert_tag('bold')
      end

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::ITALIC, nil, 0) do
        bodywin.insert_tag('italic')
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, Gtk::Stock::UNDERLINE) do
        insert_tag('undline')
      end
      add_menu_item(btn, menu, Gtk::Stock::STRIKETHROUGH) do
        bodywin.insert_tag('strike')
      end
      add_menu_item(btn, menu, Gtk::Stock::UNDERLINE) do
        bodywin.insert_tag('d')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Sub') do
        bodywin.insert_tag('sub')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Sup') do
        bodywin.insert_tag('sup')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Small') do
        bodywin.insert_tag('small')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Large') do
        bodywin.insert_tag('large')
      end
      menu.show_all

      @selected_color = 'red'
      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::SELECT_COLOR, nil, 0) do
        bodywin.insert_tag('color', @selected_color)
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, Gtk::Stock::SELECT_COLOR) do
        shift_or_ctrl = PandoraGtk.is_ctrl_shift_alt?(true, true)
        dialog = Gtk::ColorSelectionDialog.new
        dialog.set_transient_for(self)
        colorsel = dialog.colorsel
        color = Gdk::Color.parse(@selected_color)
        colorsel.set_previous_color(color)
        colorsel.set_current_color(color)
        colorsel.set_has_palette(true)
        if dialog.run == Gtk::Dialog::RESPONSE_OK
          color = colorsel.current_color
          if shift_or_ctrl
            @selected_color = color.to_s
          else
            @selected_color = PandoraUtils.color_to_str(color)
          end
          bodywin.insert_tag('color', @selected_color)
        end
        dialog.destroy
      end
      @selected_font = 'Sans 10'
      add_menu_item(btn, menu, Gtk::Stock::SELECT_FONT) do
        dialog = Gtk::FontSelectionDialog.new
        dialog.font_name = @selected_font
        #dialog.preview_text = 'P2P folk network Pandora'
        if dialog.run == Gtk::Dialog::RESPONSE_OK
          @selected_font = dialog.font_name
          desc = Pango::FontDescription.new(@selected_font)
          params = {'family'=>desc.family, 'size'=>desc.size/Pango::SCALE}
          params['style']='1' if desc.style==Pango::FontDescription::STYLE_OBLIQUE
          params['style']='2' if desc.style==Pango::FontDescription::STYLE_ITALIC
          params['weight']='600' if desc.weight==Pango::FontDescription::WEIGHT_BOLD
          bodywin.insert_tag('font', params)
        end
        dialog.destroy
      end
      menu.show_all

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_CENTER, nil, 0) do
        bodywin.insert_tag('center')
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, Gtk::Stock::JUSTIFY_RIGHT) do
        bodywin.insert_tag('right')
      end
      add_menu_item(btn, menu, Gtk::Stock::JUSTIFY_FILL) do
        bodywin.insert_tag('fill')
      end
      add_menu_item(btn, menu, Gtk::Stock::JUSTIFY_LEFT) do
        bodywin.insert_tag('left')
      end
      menu.show_all

      PandoraGtk.add_tool_btn(toolbar, :image, 'Image') do
        dialog = PandoraGtk::PanhashDialog.new([PandoraModel::Blob])
        dialog.choose_record('sha1','md5','name') do |panhash,sha1,md5,name|
          params = ''
          if (name.is_a? String) and (name.size>0)
            params << ' alt="'+name+'" title="'+name+'"'
          end
          if (sha1.is_a? String) and (sha1.size>0)
            bodywin.insert_tag('img/', 'sha1://'+PandoraUtils.bytes_to_hex(sha1)+params)
          elsif panhash.is_a? String
            bodywin.insert_tag('img/', 'pandora://'+PandoraUtils.bytes_to_hex(panhash)+params)
          end
        end
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::JUMP_TO, 'Link') do
        bodywin.insert_tag('link', 'http://priroda.su', 'Priroda.SU')
      end

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::INDENT, 'h1', 0) do
        bodywin.insert_tag('h1')
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, Gtk::Stock::INDENT, 'h2') do
        bodywin.insert_tag('h2')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDENT, 'h3') do
        bodywin.insert_tag('h3')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDENT, 'h4') do
        bodywin.insert_tag('h4')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDENT, 'h5') do
        bodywin.insert_tag('h5')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDENT, 'h6') do
        bodywin.insert_tag('h6')
      end
      menu.show_all

      btn = PandoraGtk.add_tool_btn(toolbar, :code, 'Code', 0) do
        bodywin.insert_tag('code', 'ruby')
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, :quote, 'Quote') do
        bodywin.insert_tag('quote')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Cut') do
        bodywin.insert_tag('cut', _('Expand'))
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'HR') do
        bodywin.insert_tag('hr/', '150')
      end
      add_menu_item(btn, menu, :table, 'Table') do
        bodywin.insert_tag('table')
      end
      menu.append(Gtk::SeparatorMenuItem.new)
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Edit') do
        bodywin.insert_tag('edit/', 'Edit value="Text" size="40"')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Spin') do
        bodywin.insert_tag('spin/', 'Spin values="42,48,52" default="48"')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Integer') do
        bodywin.insert_tag('integer/', 'Integer value="42" width="70"')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Hex') do
        bodywin.insert_tag('hex/', 'Hex value="01a5ff" size="20"')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Real') do
        bodywin.insert_tag('real/', 'Real value="0.55"')
      end
      add_menu_item(btn, menu, :date, 'Date') do
        bodywin.insert_tag('date/', 'Date value="current"')
      end
      add_menu_item(btn, menu, :time, 'Time') do
        bodywin.insert_tag('time/', 'Time value="current"')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Coord') do
        bodywin.insert_tag('coord/', 'Coord')
      end
      add_menu_item(btn, menu, Gtk::Stock::OPEN, 'Filename') do
        bodywin.insert_tag('filename/', 'Filename value="./picture1.jpg"')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Base64') do
        bodywin.insert_tag('base64/', 'Base64 value="SGVsbG8=" size="30"')
      end
      add_menu_item(btn, menu, :panhash, 'Panhash') do
        bodywin.insert_tag('panhash/', 'Panhash kind="Person,Community,Blob"')
      end
      add_menu_item(btn, menu, :list, 'Bytelist') do
        bodywin.insert_tag('bytelist/', 'List values="red, green, blue"')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Button') do
        bodywin.insert_tag('button/', 'Button value="Order"')
      end
      menu.show_all

      PandoraGtk.add_tool_btn(toolbar)

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::FIND, nil, 0) do
        #find
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, Gtk::Stock::FIND_AND_REPLACE) do
        #replace
      end
      menu.show_all

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::PRINT_PREVIEW, nil, 0) do
        bodywin.run_print_operation(true)
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, Gtk::Stock::PRINT) do
        bodywin.run_print_operation
      end
      add_menu_item(btn, menu, Gtk::Stock::PAGE_SETUP) do
        bodywin.set_page_setup
      end
      menu.show_all

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::UNDO, nil, 0) do
        #do undo
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, Gtk::Stock::REDO) do
        #redo
      end
      add_menu_item(btn, menu, Gtk::Stock::COPY) do
        #copy
      end
      add_menu_item(btn, menu, Gtk::Stock::CUT) do
        #cut
      end
      add_menu_item(btn, menu, Gtk::Stock::PASTE) do
        #paste
      end
      menu.show_all

      PandoraGtk.add_tool_btn(toolbar, :tags, 'Color tags', true) do |btn|
        bodywin.color_mode = btn.active?
        bodywin.set_buffers
      end

      PandoraGtk.add_tool_btn(toolbar)

      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::SAVE) do
        pb.save_fields_with_flags
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::OK) do
        pb.save_fields_with_flags
        self.destroy
      end

      toolbar.show_all
      add_btn_to_toolbar(toolbar)
    end

    def fill_view_toolbar
      add_btn_to_toolbar(Gtk::Stock::ADD, 'Add')
      add_btn_to_toolbar(Gtk::Stock::DELETE, 'Delete')
      add_btn_to_toolbar(Gtk::Stock::OK, 'Ok') { |*args| @response=2 }
      add_btn_to_toolbar(Gtk::Stock::CANCEL, 'Cancel') { |*args| @response=1 }
      @zoom_100 = add_btn_to_toolbar(Gtk::Stock::ZOOM_100, 'Show 1:1', true) do
        @zoom_fit.safe_set_active(false)
        true
      end
      @zoom_fit = add_btn_to_toolbar(Gtk::Stock::ZOOM_FIT, 'Zoom to fit', false) do
        @zoom_100.safe_set_active(false)
        true
      end
      add_btn_to_toolbar(Gtk::Stock::ZOOM_IN, 'Zoom in') do
        @zoom_fit.safe_set_active(false)
        @zoom_100.safe_set_active(false)
        true
      end
      add_btn_to_toolbar(Gtk::Stock::ZOOM_OUT, 'Zoom out') do
        @zoom_fit.safe_set_active(false)
        @zoom_100.safe_set_active(false)
        true
      end
    end

    def grab_def_widget
      page = cab_notebook.page
      container = cab_notebook.get_nth_page(page)
      container.grab_def_widget if container.is_a? CabViewport
    end

    def show_page(page=CPI_Dialog, tab_signal=nil)
      p '---show_page [page, tab_signal]='+[page, tab_signal].inspect
      page = CPI_Chat if ((page == CPI_Dialog) and (kind != PandoraModel::PK_Person))
      hide_toolbar_btns
      opt_btns.each do |opt_btn|
        opt_btn.safe_set_active(false) if (opt_btn.is_a?(SafeToggleToolButton))
      end
      cab_notebook.page = page if not tab_signal
      container = cab_notebook.get_nth_page(page)
      sub_btn = opt_btns[CPI_Sub]
      sub_stock = CabPageInfo[CPI_Sub][0]
      stock_id = CabPageInfo[page][0]
      if label_box.stock
        if page==CPI_Property
          label_box.set_stock(opt_btns[page].stock_id)
        else
          label_box.set_stock(stock_id)
        end
      end
      if page<=CPI_Sub
        opt_btns[page].safe_set_active(true)
        sub_btn.stock_id = sub_stock if (sub_btn.stock_id != sub_stock)
      elsif page>CPI_Last_Sub
        opt_btns[page-CPI_Last_Sub+CPI_Sub+1].safe_set_active(true)
        sub_btn.stock_id = sub_stock if (sub_btn.stock_id != sub_stock)
      else
        sub_btn.safe_set_active(true)
        sub_btn.stock_id = stock_id
      end
      prev_page = @active_page
      @active_page = page
      need_init = true
      if container
        container = container.child if page==CPI_Property
        need_init = false if (container.children.size>0)
      end
      if need_init
        case page
          when CPI_Property
            @property_box ||= PropertyBox.new(kind, @fields, cab_panhash, obj_id, edit)
            fill_property_toolbar(property_box)
            property_box.set_status_icons
            #property_box.window_width = property_box.window_height = 0
            p [self.allocation.width, self.allocation.height]
            #property_box.on_resize_window(self.allocation.width, self.allocation.height)
            #property_box.on_resize_window(container.allocation.width, container.allocation.height)
            #container.signal_connect('configure-event') do |widget, event|
            #  property_box.on_resize_window(event.width, event.height)
            #  false
            #end
            container.add(property_box)
          when CPI_Profile
            short_name = ''

            hpaned = Gtk::HPaned.new
            hpaned.border_width = 2

            list_sw = Gtk::ScrolledWindow.new(nil, nil)
            list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
            list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

            list_store = Gtk::ListStore.new(String)

            user_iter = list_store.append
            user_iter[0] = _('Info')
            user_iter = list_store.append
            user_iter[0] = _('Feed')

            # create tree view
            list_tree = Gtk::TreeView.new(list_store)
            list_tree.headers_visible = false
            #list_tree.rules_hint = true
            #list_tree.search_column = CL_Name

            renderer = Gtk::CellRendererText.new
            column = Gtk::TreeViewColumn.new(_('Menu'), renderer, 'text' => 0)
            column.set_sort_column_id(0)
            list_tree.append_column(column)

            list_tree.signal_connect('row_activated') do |tree_view, path, column|
              # download and go to record
            end
            list_tree.set_cursor(Gtk::TreePath.new(0), nil, false)
            list_sw.add(list_tree)

            left_box = Gtk::VBox.new

            dlg_pixbuf = PandoraModel.get_avatar_icon(cab_panhash, self, its_blob, 150)
            #buf = PandoraModel.scale_buf_to_size(buf, icon_size, center)
            dlg_image = nil
            dlg_image = Gtk::Image.new(dlg_pixbuf) if dlg_pixbuf
            #dlg_image ||= $window.get_preset_image('dialog')
            dlg_image ||= dlg_stock
            dlg_image ||= Gtk::Stock::MEDIA_PLAY
            if not (dlg_image.is_a? Gtk::Image)
              dlg_image = $window.get_preset_image(dlg_image, Gtk::IconSize::LARGE_TOOLBAR, nil)
            end
            dlg_image.height_request = 60 if not dlg_image.pixbuf
            dlg_image.tooltip_text = _('Set avatar')
            dlg_image.signal_connect('realize') do |widget, event|
              awindow = widget.window
              awindow.cursor = $window.hand_cursor if awindow
              false
            end
            event_box = Gtk::EventBox.new.add(dlg_image)
            event_box.events = Gdk::Event::BUTTON_PRESS_MASK
            event_box.signal_connect('button_press_event') do |widget, event|
              dialog = PandoraGtk::PanhashDialog.new([PandoraModel::Blob])
              dialog.choose_record do |img_panhash|
                PandoraModel.act_relation(img_panhash, cab_panhash, RK_AvatarFor, \
                  :delete, false)
                PandoraModel.act_relation(img_panhash, cab_panhash, RK_AvatarFor, \
                  :create, false)
                dlg_pixbuf = PandoraModel.get_avatar_icon(cab_panhash, self, its_blob, 150)
                if dlg_pixbuf
                  dlg_image.height_request = -1
                  dlg_image.pixbuf = dlg_pixbuf
                end
              end
            end

            left_box.pack_start(event_box, false, false, 0)
            left_box.pack_start(list_sw, true, true, 0)

            feed = PandoraGtk::ChatTextView.new

            hpaned.pack1(left_box, false, true)
            hpaned.pack2(feed, true, true)
            list_sw.show_all
            container.def_widget = list_tree

            fill_view_toolbar
            container.add(hpaned)
          when CPI_Editor
            #@bodywin = BodyScrolledWindow.new(@fields, nil, nil)
            #bodywin.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
            @property_box ||= PropertyBox.new(kind, @fields, cab_panhash, obj_id, edit)
            fill_edit_toolbar
            if property_box.text_fields.size>0
              p property_box.text_fields
              first_body_fld = property_box.text_fields[0]
              if first_body_fld
                bodywin = first_body_fld[FI_Widget2]
                bodywin.fill_body
                container.add(bodywin)
                bodywin.edit_btn.safe_set_active((not bodywin.view_mode)) if bodywin.edit_btn
              end
            end
          when CPI_Dialog, CPI_Chat
            listsend_vpaned = Gtk::VPaned.new

            @area_recv = ViewDrawingArea.new(self)
            area_recv.set_size_request(0, -1)
            area_recv.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#707070'))

            res = area_recv.signal_connect('expose-event') do |*args|
              #p 'area_recv '+area_recv.window.xid.inspect
              false
            end

            atalkview = PandoraGtk::ChatTextView.new(54)
            if page==CPI_Chat
              @chat_talkview = atalkview
            else
              @dlg_talkview = atalkview
            end
            atalkview.set_readonly(true)
            atalkview.set_size_request(200, 200)
            atalkview.wrap_mode = Gtk::TextTag::WRAP_WORD

            atalkview.buffer.create_tag('you', 'foreground' => $you_color)
            atalkview.buffer.create_tag('dude', 'foreground' => $dude_color)
            atalkview.buffer.create_tag('you_bold', 'foreground' => $you_color, \
              'weight' => Pango::FontDescription::WEIGHT_BOLD)
            atalkview.buffer.create_tag('dude_bold', 'foreground' => $dude_color,  \
              'weight' => Pango::FontDescription::WEIGHT_BOLD)
            atalkview.buffer.create_tag('sys', 'foreground' => $sys_color, \
              'style' => Pango::FontDescription::STYLE_ITALIC)
            atalkview.buffer.create_tag('sys_bold', 'foreground' => $sys_color,  \
              'weight' => Pango::FontDescription::WEIGHT_BOLD)

            talksw = Gtk::ScrolledWindow.new(nil, nil)
            talksw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
            talksw.add(atalkview)

            edit_box = PandoraGtk::SuperTextView.new
            atalkview.edit_box = edit_box
            edit_box.wrap_mode = Gtk::TextTag::WRAP_WORD
            edit_box.set_size_request(200, 70)

            @edit_sw = Gtk::ScrolledWindow.new(nil, nil)
            edit_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
            edit_sw.add(edit_box)

            edit_box.grab_focus

            edit_box.buffer.signal_connect('changed') do |buf|
              atalkview.send_btn.sensitive = (buf.text != '')
              false
            end

            edit_box.signal_connect('key-press-event') do |widget, event|
              res = false
              if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
              and (not event.state.control_mask?) and (not event.state.shift_mask?) \
              and (not event.state.mod1_mask?)
                atalkview.send_btn.clicked
                res = true
              elsif (Gdk::Keyval::GDK_Escape==event.keyval)
                edit_box.buffer.text = ''
              elsif ((event.state.shift_mask? or event.state.mod1_mask?) \
              and (event.keyval==65364))  # Shift+Down or Alt+Down
                atalkview.smile_btn.clicked
                res = true
              elsif ([Gdk::Keyval::GDK_k, Gdk::Keyval::GDK_K, 1740, 1772].include?(event.keyval) \
              and event.state.control_mask?) #k, K, л, Л
                if atalkview.crypt_btn and (not atalkview.crypt_btn.destroyed?)
                  atalkview.crypt_btn.active = (not atalkview.crypt_btn.active?)
                  res = true
                end
              elsif ([Gdk::Keyval::GDK_g, Gdk::Keyval::GDK_G, 1744, 1776].include?(event.keyval) \
              and event.state.control_mask?) #g, G, п, П
                if atalkview.sign_btn and (not atalkview.sign_btn.destroyed?)
                  atalkview.sign_btn.active = (not atalkview.sign_btn.active?)
                  res = true
                end
              end
              res
            end

            @send_hpaned = Gtk::HPaned.new
            @area_send = ViewDrawingArea.new(self)
            #area_send.set_size_request(120, 90)
            area_send.set_size_request(0, -1)
            area_send.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#707070'))
            send_hpaned.pack1(area_send, false, true)

            @sender_box = Gtk::VBox.new
            sender_box.pack_start(edit_sw, true, true, 0)

            send_hpaned.pack2(sender_box, true, true)

            list_sw = Gtk::ScrolledWindow.new(nil, nil)
            list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
            list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)
            #list_sw.visible = false

            list_store = Gtk::ListStore.new(TrueClass, String)
            #targets[CSI_Persons].each do |person|
            #  user_iter = list_store.append
            #  user_iter[CL_Name] = PandoraUtils.bytes_to_hex(person)
            #end

            # create tree view
            list_tree = Gtk::TreeView.new(list_store)
            list_tree.rules_hint = true
            list_tree.search_column = CL_Name

            # column for fixed toggles
            renderer = Gtk::CellRendererToggle.new
            renderer.signal_connect('toggled') do |cell, path_str|
              path = Gtk::TreePath.new(path_str)
              iter = list_store.get_iter(path)
              fixed = iter[CL_Online]
              p 'fixed='+fixed.inspect
              fixed ^= 1
              iter[CL_Online] = fixed
            end

            tit_image = Gtk::Image.new(Gtk::Stock::CONNECT, Gtk::IconSize::MENU)
            #tit_image.set_padding(2, 0)
            tit_image.show_all

            column = Gtk::TreeViewColumn.new('', renderer, 'active' => CL_Online)
            column.widget = tit_image

            # set this column to a fixed sizing (of 50 pixels)
            #column.sizing = Gtk::TreeViewColumn::FIXED
            #column.fixed_width = 50
            list_tree.append_column(column)

            # column for description
            renderer = Gtk::CellRendererText.new

            column = Gtk::TreeViewColumn.new(_('Nodes'), renderer, 'text' => CL_Name)
            column.set_sort_column_id(CL_Name)
            list_tree.append_column(column)

            list_sw.add(list_tree)

            list_hpaned = Gtk::HPaned.new
            list_hpaned.pack1(list_sw, true, true)
            list_hpaned.pack2(talksw, true, true)
            #motion-notify-event  #leave-notify-event  enter-notify-event
            #list_hpaned.signal_connect('notify::position') do |widget, param|
            #  if list_hpaned.position <= 1
            #    list_tree.set_size_request(0, -1)
            #    list_sw.set_size_request(0, -1)
            #  end
            #end
            list_hpaned.position = 1
            list_hpaned.position = 0

            area_send.add_events(Gdk::Event::BUTTON_PRESS_MASK)
            area_send.signal_connect('button-press-event') do |widget, event|
              if list_hpaned.position <= 1
                list_sw.width_request = 150 if list_sw.width_request <= 1
                list_hpaned.position = list_sw.width_request
              else
                list_sw.width_request = list_sw.allocation.width
                list_hpaned.position = 0
              end
            end

            area_send.signal_connect('visibility_notify_event') do |widget, event_visibility|
              case event_visibility.state
                when Gdk::EventVisibility::UNOBSCURED, Gdk::EventVisibility::PARTIAL
                  init_video_sender(true, true) if not area_send.destroyed?
                when Gdk::EventVisibility::FULLY_OBSCURED
                  init_video_sender(false, true, false) if not area_send.destroyed?
              end
            end

            area_send.signal_connect('destroy') do |*args|
              init_video_sender(false)
            end

            listsend_vpaned.pack1(list_hpaned, true, true)
            listsend_vpaned.pack2(send_hpaned, false, true)

            @main_hpaned = Gtk::HPaned.new
            main_hpaned.pack1(area_recv, false, true)
            main_hpaned.pack2(listsend_vpaned, true, true)

            area_recv.signal_connect('visibility_notify_event') do |widget, event_visibility|
              #p 'visibility_notify_event!!!  state='+event_visibility.state.inspect
              case event_visibility.state
                when Gdk::EventVisibility::UNOBSCURED, Gdk::EventVisibility::PARTIAL
                  init_video_receiver(true, true, false) if not area_recv.destroyed?
                when Gdk::EventVisibility::FULLY_OBSCURED
                  init_video_receiver(false, true) if not area_recv.destroyed?
              end
            end

            #area_recv.signal_connect('map') do |widget, event|
            #  p 'show!!!!'
            #  init_video_receiver(true, true, false) if not area_recv.destroyed?
            #end

            area_recv.signal_connect('destroy') do |*args|
              init_video_receiver(false, false)
            end

            chat_mode = ((page==CPI_Chat) or (kind != PandoraModel::PK_Person))
            fill_dlg_toolbar(page, atalkview, chat_mode)

            load_history($load_history_count, $sort_history_mode, chat_mode)
            container.add(main_hpaned)
            container.def_widget = edit_box
          when CPI_Opinions
            pbox = PandoraGtk::PanobjScrolledWindow.new
            panhash = PandoraUtils.bytes_to_hex(cab_panhash)
            PandoraGtk.show_panobject_list(PandoraModel::Message, nil, pbox, false, \
              'destination='+panhash)
            container.add(pbox)
          when CPI_Relations
            pbox = PandoraGtk::PanobjScrolledWindow.new
            panhash = PandoraUtils.bytes_to_hex(cab_panhash)
            PandoraGtk.show_panobject_list(PandoraModel::Relation, nil, pbox, false, \
              'first='+panhash+' OR second='+panhash)
            container.add(pbox)
          when CPI_Signs
            pbox = PandoraGtk::PanobjScrolledWindow.new
            panhash = PandoraUtils.bytes_to_hex(cab_panhash)
            PandoraGtk.show_panobject_list(PandoraModel::Sign, nil, pbox, false, \
              'obj_hash='+panhash)
            container.add(pbox)
        end
      else
        case page
          when CPI_Editor
            if (prev_page == @active_page) and property_box \
            and property_box.text_fields and (property_box.text_fields.size>0)
              first_body_fld = property_box.text_fields[0]
              if first_body_fld
                bodywin = first_body_fld[FI_Widget2]
                if bodywin.edit_btn
                  bodywin.edit_btn.active = (not bodywin.edit_btn.active?)
                end
              end
            end
        end
      end
      container.show_all
      show_toolbar_btns(page)
      grab_def_widget
    end

    # Create cabinet
    # RU: Создать кабинет
    def initialize(a_panhash, a_room_id, a_page=nil, a_fields=nil, an_id=nil, \
    an_edit=nil, a_session=nil)
      super(nil, nil)

      p '==Cabinet.new a_panhash='+PandoraUtils.bytes_to_hex(a_panhash)

      @cab_panhash = a_panhash
      @kind = PandoraUtils.kind_from_panhash(cab_panhash)
      @session = a_session
      @room_id = a_room_id
      @fields = a_fields
      @obj_id = an_id
      @edit = an_edit

      @has_unread = false
      @recv_media_queue = Array.new
      @recv_media_pipeline = Array.new
      @appsrcs = Array.new
      @add_toolbar_btns = Array.new

      #set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      #border_width = 0

      @dlg_stock = nil
      @its_blob = nil
      if cab_panhash
        kind = PandoraUtils.kind_from_panhash(cab_panhash)
        panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
        @its_blob = ((kind==PandoraModel::PK_Blob) \
          or (panobjectclass <= PandoraModel::Blob) \
          or panobjectclass.has_blob_fields?)
        @dlg_stock = $window.get_panobject_stock(panobjectclass.ider)
      end
      @dlg_stock ||= Gtk::Stock::PROPERTIES

      main_vbox = self #Gtk::VBox.new
      #add_with_viewport(main_vbox)

      @cab_notebook = Gtk::Notebook.new
      cab_notebook.show_tabs = false
      cab_notebook.show_border = false
      cab_notebook.border_width = 0
      @toolbar_box = Gtk::HBox.new #Toolbar.new HBox.new
      main_vbox.pack_start(cab_notebook, true, true, 0)

      @opt_btns = []
      btn_down = nil
      (CPI_Property..CPI_Last).each do |index|
        container = nil
        if index==CPI_Property
          stock = dlg_stock
          stock ||= CabPageInfo[index][0]
          text = CabPageInfo[index][1]
          container = Gtk::ScrolledWindow.new(nil, nil)
          container.shadow_type = Gtk::SHADOW_NONE
          container.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
          container.border_width = 0
          viewport = CabViewport.new(nil, nil)
          container.add(viewport)
        else
          stock = CabPageInfo[index][0]
          text = CabPageInfo[index][1]
          if index==CPI_Last_Sub+1
            btn_down.menu.show_all
            btn_down = nil
          end
          container = CabViewport.new(nil, nil)
        end
        text = _(text)
        page_box = TabLabelBox.new(stock, text)
        cab_notebook.append_page_menu(container, page_box)

        if not btn_down
          opt_btn = add_btn_to_toolbar(stock, text, false, opt_btns) do
            show_page(index)
          end
          if index==CPI_Sub
            btn_down = add_btn_to_toolbar(nil, nil, 0, opt_btns)
            btn_down.menu = Gtk::Menu.new
          end
        end
        if btn_down
          add_menu_item(btn_down, btn_down.menu, stock, text) do
            show_page(index)
          end
        end
      end
      cab_notebook.signal_connect('switch-page') do |widget, page, page_num|
        #container = widget.get_nth_page(page_num)
        #container.grab_def_widget if container.is_a? CabViewport
        #show_page(page_num, true)
        false
      end

      #toolbar_box.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      #toolbar_box.add(Gtk::SeparatorToolItem.new)
      add_btn_to_toolbar(nil, nil, nil, opt_btns)
      main_vbox.pack_start(toolbar_box, false, false, 0)

      dlg_pixbuf = PandoraModel.get_avatar_icon(cab_panhash, self, its_blob, \
        Gtk::IconSize.lookup(Gtk::IconSize::SMALL_TOOLBAR)[0])
      #buf = PandoraModel.scale_buf_to_size(buf, icon_size, center)
      dlg_image = nil
      dlg_image = Gtk::Image.new(dlg_pixbuf) if dlg_pixbuf
      #dlg_image ||= $window.get_preset_image('dialog')
      dlg_image ||= dlg_stock
      dlg_image ||= Gtk::Stock::MEDIA_PLAY
      @label_box = TabLabelBox.new(dlg_image, 'unknown', self) do
        area_send.destroy if area_send and (not area_send.destroyed?)
        area_recv.destroy if area_recv and (not area_recv.destroyed?)
        $window.pool.stop_session(nil, cab_panhash, nil, false, self.session)
      end

      page = $window.notebook.append_page(self, label_box)
      $window.notebook.set_tab_reorderable(self, true)

      construct_cab_title

      self.signal_connect('delete-event') do |*args|
        area_send.destroy if not area_send.destroyed?
        area_recv.destroy if not area_recv.destroyed?
      end

      show_all
      a_page ||= CPI_Dialog
      opt_btns[CPI_Sub+1].children[0].children[0].hide
      btn_offset = CPI_Last_Sub-CPI_Sub-1
      opt_btns[CPI_Editor-btn_offset].hide if (not its_blob)
      if (kind != PandoraModel::PK_Person)
        opt_btns[CPI_Dialog-btn_offset].hide
        a_page = CPI_Chat if a_page == CPI_Dialog
      end
      show_page(a_page)

      $window.notebook.page = $window.notebook.n_pages-1 if not @known_node
    end

    MaxTitleLen = 15

    # Construct room title
    # RU: Задаёт осмысленный заголовок окна
    def construct_cab_title(check_all=true, atitle_view=nil)

      def trunc_big_title(title)
        title.strip! if title
        if title.size>MaxTitleLen
          need_dots = (title[MaxTitleLen] != ' ')
          len = MaxTitleLen
          len -= 1 if need_dots
          need_dots = (title[len-1] != ' ')
          title = title[0, len].strip
          title << '..' if need_dots
        end
        title
      end

      res = 'unknown'
      if (kind==PandoraModel::PK_Person)
        title_view = atitle_view
        title_view ||= $window.title_view
        title_view ||= TV_Name
        res = ''
        aname, afamily = PandoraCrypto.name_and_family_of_person(nil, cab_panhash)
        #p '------------[aname, afamily, cab_panhash]='+[aname, afamily, cab_panhash, \
        #  PandoraUtils.bytes_to_hex(cab_panhash)].inspect
        addname = ''
        case title_view
          when TV_Name, TV_NameN
            if (aname.size==0)
              addname << afamily
            else
              addname << aname
            end
          when TV_Family
            if (afamily.size==0)
              addname << aname
            else
              addname << afamily
            end
          when TV_NameFam
            if (aname.size==0)
              addname << afamily
            else
              addname << aname #[0, 4]
              addname << ' '+afamily if afamily and (afamily.size>0)
            end
        end
        if (addname.size>0)
          res << ',' if (res.size>0)
          res << addname
        end
        res = 'unknown' if (res.size==0)
        res = trunc_big_title(res)
        tab_widget = $window.notebook.get_tab_label(self)
        tab_widget.label.text = res if tab_widget
        #p '$window.title_view, res='+[@$window.title_view, res].inspect
        if check_all
          title_view=TV_Name if (title_view==TV_NameN)
          has_conflict = true
          while has_conflict and (title_view < TV_NameN)
            has_conflict = false
            names = Array.new
            $window.notebook.children.each do |child|
              if (child.is_a? CabinetBox)
                tab_widget = $window.notebook.get_tab_label(child)
                if tab_widget
                  tit = tab_widget.label.text
                  if names.include? tit
                    has_conflict = true
                    break
                  else
                    names << tit
                  end
                end
              end
            end
            if has_conflict
              if (title_view < TV_NameN)
                title_view += 1
              end
              #p '@$window.title_view='+@$window.title_view.inspect
              names = Array.new
              $window.notebook.children.each do |child|
                if (child.is_a? CabinetBox)
                  sn = child.construct_cab_title(false, title_view)
                  if (title_view == TV_NameN)
                    names << sn
                    c = names.count(sn)
                    sn = sn+c.to_s if c>1
                    tab_widget = $window.notebook.get_tab_label(child)
                    tab_widget.label.text = sn if tab_widget
                  end
                end
              end
            end
          end
        end
      else
        panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
        if panobjectclass
          model = PandoraUtils.get_model(panobjectclass.ider)
          if model
            sel = model.select({'panhash'=>cab_panhash}, true, nil, nil, 1)
            res = model.record_info(MaxTitleLen+1, nil, nil, ' ')
            res = trunc_big_title(res)
            tab_widget = $window.notebook.get_tab_label(self)
            tab_widget.label.text = res if tab_widget
          end
        end
      end
      res
    end

    # Put message to dialog
    # RU: Добавляет сообщение в диалог
    def add_mes_to_view(mes, id, panstate=nil, to_end=nil, \
    key_or_panhash=nil, myname=nil, modified=nil, created=nil)
      if mes
        encrypted = ((panstate.is_a? Integer) \
          and ((panstate & PandoraModel::PSF_Crypted) > 0))
        chat_mode = ((panstate & PandoraModel::PSF_ChatMes) > 0)
        mes = PandoraCrypto.recrypt_mes(mes) if encrypted

        p '---add_mes_to_view [mes, id, pstate to_end, key_or_phash, myname, modif, created]=' + \
          [mes, id, panstate, to_end, key_or_panhash, myname, modified, created].inspect

        notice = false
        if not myname
          mykey = PandoraCrypto.current_key(false, false)
          myname = PandoraCrypto.short_name_of_person(mykey)
        end

        time_style = 'you'
        name_style = 'you_bold'
        user_name = nil
        if key_or_panhash
          if key_or_panhash.is_a? String
            user_name = PandoraCrypto.short_name_of_person(nil, key_or_panhash, 0, myname)
          else
            user_name = PandoraCrypto.short_name_of_person(key_or_panhash, nil, 0, myname)
          end
          time_style = 'dude'
          name_style = 'dude_bold'
          notice = (not to_end.is_a? FalseClass)
        else
          user_name = myname
        end
        user_name = 'noname' if (not user_name) or (user_name=='')

        time_now = Time.now
        created = time_now if (not modified) and (not created)

        time_str = ''
        time_str << PandoraUtils.time_to_dialog_str(created, time_now) if created
        if modified and ((not created) or ((modified.to_i-created.to_i).abs>30))
          time_str << ' ' if (time_str != '')
          time_str << '('+PandoraUtils.time_to_dialog_str(modified, time_now)+')'
        end

        talkview = @dlg_talkview
        talkview = @chat_talkview if chat_mode

        if talkview
          talkview.before_addition(time_now) if (not to_end.is_a? FalseClass)
          talkview.buffer.insert(talkview.buffer.end_iter, "\n") if (talkview.buffer.char_count>0)
          talkview.buffer.insert(talkview.buffer.end_iter, time_str+' ', time_style)
          talkview.buffer.insert(talkview.buffer.end_iter, user_name+':', name_style)

          line = talkview.buffer.line_count
          talkview.mes_ids[line] = id

          talkview.buffer.insert(talkview.buffer.end_iter, ' ')
          talkview.insert_taged_str_to_buffer(mes, talkview.buffer, 'bbcode')
          talkview.after_addition(to_end) if (not to_end.is_a? FalseClass)
          talkview.show_all
        end

        update_state(true) if notice
      end
    end

    # Load history of messages
    # RU: Подгрузить историю сообщений
    def load_history(max_message=6, sort_mode=0, chat_mode=false)
      p '---- load_history [max_message, sort_mode]='+[max_message, sort_mode].inspect
      talkview = @dlg_talkview
      talkview = @chat_talkview if chat_mode
      if talkview and max_message and (max_message>0)
        messages = []
        fields = 'creator, created, destination, state, text, panstate, modified, id'

        mypanhash = PandoraCrypto.current_user_or_key(true)
        myname = PandoraCrypto.short_name_of_person(nil, mypanhash)

        nil_create_time = false
        person = cab_panhash
        model = PandoraUtils.get_model('Message')
        max_message2 = max_message
        max_message2 = max_message * 2 if (person == mypanhash)
        chatbit = PandoraModel::PSF_ChatMes.to_s
        filter = [['destination=', person]]
        chat_filter = nil
        if chat_mode
          chat_filter = ['IFNULL(panstate,0)&'+chatbit+'>', 0]
        else
          filter << ['creator=', mypanhash]
          chat_filter = ['IFNULL(panstate,0)&'+chatbit+'=', 0]
        end
        filter << chat_filter if chat_filter
        sel = model.select(filter, false, fields, 'id DESC', max_message2)
        sel.reverse!
        if (person == mypanhash)
          i = sel.size-1
          while i>0 do
            i -= 1
            time, text, time_prev, text_prev = sel[i][1], sel[i][4], sel[i+1][1], sel[i+1][4]
            #p [time, text, time_prev, text_prev]
            if (not time) or (not time_prev)
              time, time_prev = sel[i][6], sel[i+1][6]
              nil_create_time = true
            end
            if (not text) or (time and text and time_prev and text_prev \
            and ((time-time_prev).abs<30) \
            and (AsciiString.new(text)==AsciiString.new(text_prev)))
              #p 'DEL '+[time, text, time_prev, text_prev].inspect
              sel.delete_at(i)
              i -= 1
            end
          end
        end
        messages += sel
        if (not chat_mode) and (person != mypanhash)
          filter = [['creator=', person], ['destination=', mypanhash]]
          filter << chat_filter if chat_filter
          sel = model.select(filter, false, fields, 'id DESC', max_message)
          messages += sel
        end
        if nil_create_time or (sort_mode==0) #sort by created
          messages.sort! do |a,b|
            res = (a[6]<=>b[6])
            res = (a[1]<=>b[1]) if (res==0) and (not nil_create_time)
            res
          end
        else   #sort by modified
          messages.sort! do |a,b|
            res = (a[1]<=>b[1])
            res = (a[6]<=>b[6]) if (res==0)
            res
          end
        end

        talkview.before_addition
        i = (messages.size-max_message)
        i = 0 if i<0
        while i<messages.size do
          message = messages[i]

          creator = message[0]
          created = message[1]
          mes = message[4]
          panstate = message[5]
          modified = message[6]
          id = message[7]

          key_or_panhash = nil
          key_or_panhash = creator if (creator != mypanhash)

          add_mes_to_view(mes, id, panstate, false, key_or_panhash, \
            myname, modified, created)

          i += 1
        end
        talkview.after_addition(true)
        talkview.show_all
        # Scroll because of the unknown gtk bug
        mark = talkview.buffer.create_mark(nil, talkview.buffer.end_iter, false)
        talkview.scroll_to_mark(mark, 0, true, 0.0, 1.0)
        talkview.buffer.delete_mark(mark)
      end
    end

    # Set session
    # RU: Задать сессию
    def set_session(session, online=true, keep=true)
      p '***---- set_session(session, online)='+[session.object_id, online].inspect
      @sessions ||= []
      if online
        @sessions << session if (not @sessions.include?(session))
        session.conn_mode = (session.conn_mode | PandoraNet::CM_Keep) if keep
      else
        @sessions.delete(session)
        session.conn_mode = (session.conn_mode & (~PandoraNet::CM_Keep)) if keep
        session.dialog = nil
      end
      active = (@sessions.size>0)
      online_btn.safe_set_active(active) if (online_btn and (not online_btn.destroyed?))
      if active
        #online_btn.inconsistent = false if (not online_btn.destroyed?)
      else
        mic_btn.active = false if (not mic_btn.destroyed?) and mic_btn.active?
        webcam_btn.active = false if (not webcam_btn.destroyed?) and webcam_btn.active?
        #mic_btn.safe_set_active(false) if (not mic_btn.destroyed?)
        #webcam_btn.safe_set_active(false) if (not webcam_btn.destroyed?)
      end
    end

    # Send message to node, before encrypt it if need
    # RU: Отправляет сообщение на узел, шифрует предварительно если надо
    def send_mes(text, crypt=nil, sign_trust=nil, chat_mode=false)
      res = false
      creator = PandoraCrypto.current_user_or_key(true)
      if creator
        if (not chat_mode) and (not online_btn.active?)
          online_btn.active = true
        end
        #Thread.pass
        time_now = Time.now.to_i
        state = 0
        panstate = 0
        crypt_text = text
        sign = (not sign_trust.nil?)
        panstate = (panstate | PandoraModel::PSF_ChatMes) if chat_mode
        if crypt or sign
          panstate = (panstate | PandoraModel::PSF_Support)
          keyhash = PandoraCrypto.current_user_or_key(false, false)
          if keyhash
            if crypt
              crypt_text = PandoraCrypto.recrypt_mes(text, keyhash)
              panstate = (panstate | PandoraModel::PSF_Crypted)
            end
            panstate = (panstate | PandoraModel::PSF_Verified) if sign
          else
            crypt = sign = false
          end
        end
        dest = cab_panhash
        values = {:destination=>dest, :text=>crypt_text, :state=>state, \
          :creator=>creator, :created=>time_now, :modified=>time_now, :panstate=>panstate}
        model = PandoraUtils.get_model('Message')
        panhash = model.calc_panhash(values)
        values[:panhash] = panhash
        res = model.update(values, nil, nil, sign)
        if res
          filter = {:panhash=>panhash, :created=>time_now}
          sel = model.select(filter, true, 'id', 'id DESC', 1)
          if sel and (sel.size>0)
            p 'send_mes sel='+sel.inspect
            if sign
              namesvalues = model.namesvalues
              namesvalues['text'] = text   #restore pure text for sign
              if not PandoraCrypto.sign_panobject(model, sign_trust)
                panstate = panstate & (~ PandoraModel::PSF_Verified)
                res = model.update(filter, nil, {:panstate=>panstate})
                PandoraUtils.log_message(LM_Warning, _('Cannot create sign')+' ['+text+']')
              end
            end
            id = sel[0][0]
            add_mes_to_view(crypt_text, id, panstate, true)
          else
            PandoraUtils.log_message(LM_Error, _('Cannot read message')+' ['+text+']')
          end
        else
          PandoraUtils.log_message(LM_Error, _('Cannot insert message')+' ['+text+']')
        end
        if chat_mode
          $window.pool.send_chat_messages
        else
          sessions = $window.pool.sessions_on_dialog(self)
          sessions.each do |session|
            session.conn_mode = (session.conn_mode | PandoraNet::CM_Keep)
            session.send_state = (session.send_state | PandoraNet::CSF_Message)
          end
        end
      end
      res
    end

    $statusicon = nil

    # Update tab color when received new data
    # RU: Обновляет цвет закладки при получении новых данных
    def update_state(received=true, curpage=nil)
      tab_widget = $window.notebook.get_tab_label(self)
      if tab_widget
        curpage ||= $window.notebook.get_nth_page($window.notebook.page)
        # interrupt reading thread (if exists)
        if $last_page and ($last_page.is_a? CabinetBox) \
        and $last_page.read_thread and (curpage != $last_page)
          $last_page.read_thread.exit
          $last_page.read_thread = nil
        end
        # set self dialog as unread
        if received
          @has_unread = true
          color = Gdk::Color.parse($tab_color)
          tab_widget.label.modify_fg(Gtk::STATE_NORMAL, color)
          tab_widget.label.modify_fg(Gtk::STATE_ACTIVE, color)
          $statusicon.set_message(_('Message')+' ['+tab_widget.label.text+']')
          PandoraUtils.play_mp3('message')
        end
        # run reading thread
        timer_setted = false
        if (not self.read_thread) and (curpage == self) and $window.visible? \
        and $window.has_toplevel_focus?
          #color = $window.modifier_style.text(Gtk::STATE_NORMAL)
          #curcolor = tab_widget.label.modifier_style.fg(Gtk::STATE_ACTIVE)
          if @has_unread #curcolor and (color != curcolor)
            timer_setted = true
            self.read_thread = Thread.new do
              sleep(0.3)
              if (not curpage.destroyed?) and curpage.dlg_talkview and \
              (not curpage.dlg_talkview.destroyed?) and curpage.dlg_talkview.edit_box \
              and (not curpage.dlg_talkview.edit_box.destroyed?)
                curpage.dlg_talkview.edit_box.grab_focus if curpage.dlg_talkview.edit_box.visible?
                curpage.dlg_talkview.after_addition(true)
              end
              if $window.visible? and $window.has_toplevel_focus?
                read_sec = $read_time-0.3
                if read_sec >= 0
                  sleep(read_sec)
                end
                if $window.visible? and $window.has_toplevel_focus?
                  if (not self.destroyed?) and (not tab_widget.destroyed?) \
                  and (not tab_widget.label.destroyed?)
                    @has_unread = false
                    tab_widget.label.modify_fg(Gtk::STATE_NORMAL, nil)
                    tab_widget.label.modify_fg(Gtk::STATE_ACTIVE, nil)
                    $statusicon.set_message(nil)
                  end
                end
              end
              self.read_thread = nil
            end
          end
        end
        # set focus to edit_box
        if curpage and (curpage.is_a? CabinetBox) #and curpage.edit_box
          curpage.grab_def_widget
        end
      end
    end

    # Parse Gstreamer string
    # RU: Распознаёт строку Gstreamer
    def parse_gst_string(text)
      elements = Array.new
      text.strip!
      elem = nil
      link = false
      i = 0
      while i<text.size
        j = 0
        while (i+j<text.size) \
        and (not ([' ', '=', "\\", '!', '/', 10.chr, 13.chr].include? text[i+j, 1]))
          j += 1
        end
        #p [i, j, text[i+j, 1], text[i, j]]
        word = nil
        param = nil
        val = nil
        if i+j<text.size
          sym = text[i+j, 1]
          if ['=', '/'].include? sym
            if sym=='='
              param = text[i, j]
              i += j
            end
            i += 1
            j = 0
            quotes = false
            while (i+j<text.size) and (quotes \
            or (not ([' ', "\\", '!', 10.chr, 13.chr].include? text[i+j, 1])))
              if quotes
                if text[i+j, 1]=='"'
                  quotes = false
                end
              elsif (j==0) and (text[i+j, 1]=='"')
                quotes = true
              end
              j += 1
            end
            sym = text[i+j, 1]
            val = text[i, j].strip
            val = val[1..-2] if val and (val.size>1) and (val[0]=='"') and (val[-1]=='"')
            val.strip!
            param.strip! if param
            if (not param) or (param=='')
              param = 'caps'
              if not elem
                word = 'capsfilter'
                elem = elements.size
                elements[elem] = [word, {}]
              end
            end
            #puts '++  [word, param, val]='+[word, param, val].inspect
          else
            word = text[i, j]
          end
          link = true if sym=='!'
        else
          word = text[i, j]
        end
        #p 'word='+word.inspect
        word.strip! if word
        #p '---[word, param, val]='+[word, param, val].inspect
        if param or val
          elements[elem][1][param] = val if elem and param and val
        elsif word and (word != '')
          elem = elements.size
          elements[elem] = [word, {}]
        end
        if link
          elements[elem][2] = true if elem
          elem = nil
          link = false
        end
        #p '===elements='+elements.inspect
        i += j+1
      end
      elements
    end

    # Append elements to pipeline
    # RU: Добавляет элементы в конвейер
    def append_elems_to_pipe(elements, pipeline, prev_elem=nil, prev_pad=nil, name_suff=nil)
      # create elements and add to pipeline
      #p '---- begin add&link elems='+elements.inspect
      elements.each do |elem_desc|
        factory = elem_desc[0]
        params = elem_desc[1]
        if factory and (factory != '')
          i = factory.index('.')
          if not i
            elemname = nil
            elemname = factory+name_suff if name_suff
            if $gst_old
              if ((factory=='videoconvert') or (factory=='autovideoconvert'))
                factory = 'ffmpegcolorspace'
              end
            elsif (factory=='ffmpegcolorspace')
              factory = 'videoconvert'
            end
            elem = Gst::ElementFactory.make(factory, elemname)
            if elem
              elem_desc[3] = elem
              if params.is_a? Hash
                params.each do |k, v|
                  v0 = elem.get_property(k)
                  #puts '[factory, elem, k, v]='+[factory, elem, v0, k, v].inspect
                  #v = v[1,-2] if v and (v.size>1) and (v[0]=='"') and (v[-1]=='"')
                  #puts 'v='+v.inspect
                  if (k=='caps') or (v0.is_a? Gst::Caps)
                    if $gst_old
                      v = Gst::Caps.parse(v)
                    else
                      v = Gst::Caps.from_string(v)
                    end
                  elsif (v0.is_a? Integer) or (v0.is_a? Float)
                    if v.index('.')
                      v = v.to_f
                    else
                      v = v.to_i
                    end
                  elsif (v0.is_a? TrueClass) or (v0.is_a? FalseClass)
                    v = ((v=='true') or (v=='1'))
                  end
                  #puts '[factory, elem, k, v]='+[factory, elem, v0, k, v].inspect
                  elem.set_property(k, v)
                  #p '----'
                  elem_desc[4] = v if k=='name'
                end
              end
              pipeline.add(elem) if pipeline
            else
              p 'Cannot create gstreamer element "'+factory+'"'
            end
          end
        end
      end
      # resolve names
      elements.each do |elem_desc|
        factory = elem_desc[0]
        link = elem_desc[2]
        if factory and (factory != '')
          #p '----'
          #p factory
          i = factory.index('.')
          if i
            name = factory[0,i]
            #p 'name='+name
            if name and (name != '')
              elem_desc = elements.find{ |ed| ed[4]==name }
              elem = elem_desc[3]
              if not elem
                p 'find by name in pipeline!!'
                p elem = pipeline.get_by_name(name)
              end
              elem[3] = elem if elem
              if elem
                pad = factory[i+1, -1]
                elem[5] = pad if pad and (pad != '')
              end
              #p 'elem[3]='+elem[3].inspect
            end
          end
        end
      end
      # link elements
      link1 = false
      elem1 = nil
      pad1  = nil
      if prev_elem
        link1 = true
        elem1 = prev_elem
        pad1  = prev_pad
      end
      elements.each_with_index do |elem_desc|
        link2 = elem_desc[2]
        elem2 = elem_desc[3]
        pad2  = elem_desc[5]
        if link1 and elem1 and elem2
          if pad1 or pad2
            pad1 ||= 'src'
            apad2 = pad2
            apad2 ||= 'sink'
            p 'pad elem1.pad1 >> elem2.pad2 - '+[elem1, pad1, elem2, apad2].inspect
            elem1.get_pad(pad1).link(elem2.get_pad(apad2))
          else
            #p 'elem1 >> elem2 - '+[elem1, elem2].inspect
            elem1 >> elem2
          end
        end
        link1 = link2
        elem1 = elem2
        pad1  = pad2
      end
      #p '===final add&link'
      [elem1, pad1]
    end

    # Append element to pipeline
    # RU: Добавляет элемент в конвейер
    def add_elem_to_pipe(str, pipeline, prev_elem=nil, prev_pad=nil, name_suff=nil)
      elements = parse_gst_string(str)
      elem, pad = append_elems_to_pipe(elements, pipeline, prev_elem, prev_pad, name_suff)
      [elem, pad]
    end

    # Link sink element to area of widget
    # RU: Прицепляет сливной элемент к области виджета
    def link_sink_to_area(sink, area, pipeline=nil)

      # Set handle of window
      # RU: Устанавливает дескриптор окна
      def set_xid(area, sink)
        if (not area.destroyed?) and area.window and sink \
        and (sink.class.method_defined? 'set_xwindow_id')
          win_id = nil
          if PandoraUtils.os_family=='windows'
            win_id = area.window.handle
          else
            win_id = area.window.xid
          end
          sink.set_property('force-aspect-ratio', true)
          sink.set_xwindow_id(win_id)
        end
      end

      res = nil
      if area and (not area.destroyed?)
        if (not area.window) and pipeline
          area.realize
          #Gtk.main_iteration
        end
        #p 'link_sink_to_area(sink, area, pipeline)='+[sink, area, pipeline].inspect
        set_xid(area, sink)
        if pipeline and (not pipeline.destroyed?)
          pipeline.bus.add_watch do |bus, message|
            if (message and message.structure and message.structure.name \
            and (message.structure.name == 'prepare-xwindow-id'))
              Gdk::Threads.synchronize do
                Gdk::Display.default.sync
                asink = message.src
                set_xid(area, asink)
              end
            end
            true
          end

          res = area.signal_connect('expose-event') do |*args|
            set_xid(area, sink)
          end
          area.set_expose_event(res)
        end
      end
      res
    end

    # Get video sender parameters
    # RU: Берёт параметры отправителя видео
    def get_video_sender_params(src_param = 'video_src_v4l2', \
      send_caps_param = 'video_send_caps_raw_320x240', send_tee_param = 'video_send_tee_def', \
      view1_param = 'video_view1_xv', can_encoder_param = 'video_can_encoder_vp8', \
      can_sink_param = 'video_can_sink_app')

      # getting from setup (will be feature)
      src         = PandoraUtils.get_param(src_param)
      send_caps   = PandoraUtils.get_param(send_caps_param)
      send_tee    = PandoraUtils.get_param(send_tee_param)
      view1       = PandoraUtils.get_param(view1_param)
      can_encoder = PandoraUtils.get_param(can_encoder_param)
      can_sink    = PandoraUtils.get_param(can_sink_param)

      # default param (temporary)
      #src = 'v4l2src decimate=3'
      #send_caps = 'video/x-raw-rgb,width=320,height=240'
      #send_tee = 'ffmpegcolorspace ! tee name=vidtee'
      #view1 = 'queue ! xvimagesink force-aspect-ratio=true'
      #can_encoder = 'vp8enc max-latency=0.5'
      #can_sink = 'appsink emit-signals=true'

      # extend src and its caps
      send_caps = 'capsfilter caps="'+send_caps+'"'

      [src, send_caps, send_tee, view1, can_encoder, can_sink]
    end

    $send_media_pipelines = {}
    $webcam_xvimagesink   = nil

    # Initialize video sender
    # RU: Инициализирует отправщика видео
    def init_video_sender(start=true, just_upd_area=false, init=true)
      video_pipeline = $send_media_pipelines['video']
      if not start
        if $webcam_xvimagesink and (PandoraUtils.elem_playing?($webcam_xvimagesink))
          $webcam_xvimagesink.pause
        end
        if just_upd_area
          area_send.set_expose_event(nil) if init
          tsw = PandoraGtk.find_another_active_sender(self)
          if $webcam_xvimagesink and (not $webcam_xvimagesink.destroyed?) and tsw \
          and tsw.area_send and tsw.area_send.window
            link_sink_to_area($webcam_xvimagesink, tsw.area_send)
            #$webcam_xvimagesink.xwindow_id = tsw.area_send.window.xid
          end
          #p '--LEAVE'
          area_send.queue_draw if area_send and (not area_send.destroyed?)
        else
          #$webcam_xvimagesink.xwindow_id = 0
          count = PandoraGtk.nil_send_ptrind_by_panhash(room_id)
          if video_pipeline and (count==0) and (not PandoraUtils::elem_stopped?(video_pipeline))
            video_pipeline.stop
            area_send.set_expose_event(nil)
            #p '==STOP!!'
          end
        end
        #Thread.pass
      elsif (not self.destroyed?) and webcam_btn and (not webcam_btn.destroyed?) and webcam_btn.active? \
      and area_send and (not area_send.destroyed?)
        if not video_pipeline
          begin
            Gst.init
            winos = (PandoraUtils.os_family == 'windows')
            video_pipeline = Gst::Pipeline.new('spipe_v')

            ##video_src = 'v4l2src decimate=3'
            ##video_src_caps = 'capsfilter caps="video/x-raw-rgb,width=320,height=240"'
            #video_src_caps = 'capsfilter caps="video/x-raw-yuv,width=320,height=240"'
            #video_src_caps = 'capsfilter caps="video/x-raw-yuv,width=320,height=240" ! videorate drop=10'
            #video_src_caps = 'capsfilter caps="video/x-raw-yuv, framerate=10/1, width=320, height=240"'
            #video_src_caps = 'capsfilter caps="width=320,height=240"'
            ##video_send_tee = 'ffmpegcolorspace ! tee name=vidtee'
            #video_send_tee = 'tee name=tee1'
            ##video_view1 = 'queue ! xvimagesink force-aspect-ratio=true'
            ##video_can_encoder = 'vp8enc max-latency=0.5'
            #video_can_encoder = 'vp8enc speed=2 max-latency=2 quality=5.0 max-keyframe-distance=3 threads=5'
            #video_can_encoder = 'ffmpegcolorspace ! videoscale ! theoraenc quality=16 ! queue'
            #video_can_encoder = 'jpegenc quality=80'
            #video_can_encoder = 'jpegenc'
            #video_can_encoder = 'mimenc'
            #video_can_encoder = 'mpeg2enc'
            #video_can_encoder = 'diracenc'
            #video_can_encoder = 'xvidenc'
            #video_can_encoder = 'ffenc_flashsv'
            #video_can_encoder = 'ffenc_flashsv2'
            #video_can_encoder = 'smokeenc keyframe=8 qmax=40'
            #video_can_encoder = 'theoraenc bitrate=128'
            #video_can_encoder = 'theoraenc ! oggmux'
            #video_can_encoder = videorate ! videoscale ! x264enc bitrate=256 byte-stream=true'
            #video_can_encoder = 'queue ! x264enc bitrate=96'
            #video_can_encoder = 'ffenc_h263'
            #video_can_encoder = 'h264enc'
            ##video_can_sink = 'appsink emit-signals=true'

            src_param = PandoraUtils.get_param('video_src')
            send_caps_param = PandoraUtils.get_param('video_send_caps')
            send_tee_param = 'video_send_tee_def'
            view1_param = PandoraUtils.get_param('video_view1')
            can_encoder_param = PandoraUtils.get_param('video_can_encoder')
            can_sink_param = 'video_can_sink_app'

            video_src, video_send_caps, video_send_tee, video_view1, video_can_encoder, video_can_sink \
              = get_video_sender_params(src_param, send_caps_param, send_tee_param, view1_param, \
                can_encoder_param, can_sink_param)
            p [src_param, send_caps_param, send_tee_param, view1_param, \
                can_encoder_param, can_sink_param]
            p [video_src, video_send_caps, video_send_tee, video_view1, video_can_encoder, video_can_sink]

            if winos
              video_src = PandoraUtils.get_param('video_src_win')
              video_src ||= 'dshowvideosrc'
              #video_src ||= 'videotestsrc'
              video_view1 = PandoraUtils.get_param('video_view1_win')
              video_view1 ||= 'queue ! directdrawsink'
              #video_view1 ||= 'queue ! d3dvideosink'
            end

            $webcam_xvimagesink = nil
            webcam, pad = add_elem_to_pipe(video_src, video_pipeline)
            if webcam
              capsfilter, pad = add_elem_to_pipe(video_send_caps, video_pipeline, webcam, pad)
              p 'capsfilter='+capsfilter.inspect
              tee, teepad = add_elem_to_pipe(video_send_tee, video_pipeline, capsfilter, pad)
              p 'tee='+tee.inspect
              encoder, pad = add_elem_to_pipe(video_can_encoder, video_pipeline, tee, teepad)
              p 'encoder='+encoder.inspect
              if encoder
                appsink, pad = add_elem_to_pipe(video_can_sink, video_pipeline, encoder, pad)
                p 'appsink='+appsink.inspect
                $webcam_xvimagesink, pad = add_elem_to_pipe(video_view1, video_pipeline, tee, teepad)
                p '$webcam_xvimagesink='+$webcam_xvimagesink.inspect
              end
            end

            if $webcam_xvimagesink
              $send_media_pipelines['video'] = video_pipeline
              $send_media_queues[1] ||= PandoraUtils::RoundQueue.new(true)
              #appsink.signal_connect('new-preroll') do |appsink|
              #appsink.signal_connect('new-sample') do |appsink|
              appsink.signal_connect('new-buffer') do |appsink|
                #p 'appsink new buf!!!'
                #buf = appsink.pull_preroll
                #buf = appsink.pull_sample
                buf = appsink.pull_buffer
                if buf
                  data = buf.data
                  $send_media_queues[1].add_block_to_queue(data, $media_buf_size)
                end
              end
            else
              video_pipeline.destroy if video_pipeline
            end
          rescue => err
            $send_media_pipelines['video'] = nil
            mes = 'Camera init exception'
            PandoraUtils.log_message(LM_Warning, _(mes))
            puts mes+': '+Utf8String.new(err.message)
            webcam_btn.active = false
          end
        end

        if video_pipeline
          if $webcam_xvimagesink and area_send #and area_send.window
            #$webcam_xvimagesink.xwindow_id = area_send.window.xid
            link_sink_to_area($webcam_xvimagesink, area_send)
          end
          if not just_upd_area
            #???
            video_pipeline.stop if (not PandoraUtils::elem_stopped?(video_pipeline))
            area_send.set_expose_event(nil)
          end
          #if not area_send.expose_event
            link_sink_to_area($webcam_xvimagesink, area_send, video_pipeline)
          #end
          #if $webcam_xvimagesink and area_send and area_send.window
          #  #$webcam_xvimagesink.xwindow_id = area_send.window.xid
          #  link_sink_to_area($webcam_xvimagesink, area_send)
          #end
          if just_upd_area
            video_pipeline.play if (not PandoraUtils.elem_playing?(video_pipeline))
          else
            ptrind = PandoraGtk.set_send_ptrind_by_panhash(room_id)
            count = PandoraGtk.nil_send_ptrind_by_panhash(nil)
            if count>0
              #Gtk.main_iteration
              #???
              p 'PLAAAAAAAAAAAAAAY 1'
              p PandoraUtils.elem_playing?(video_pipeline)
              video_pipeline.play if (not PandoraUtils.elem_playing?(video_pipeline))
              p 'PLAAAAAAAAAAAAAAY 2'
              #p '==*** PLAY'
            end
          end
          #if $webcam_xvimagesink and ($webcam_xvimagesink.get_state != Gst::STATE_PLAYING) \
          #and (video_pipeline.get_state == Gst::STATE_PLAYING)
          #  $webcam_xvimagesink.play
          #end
        end
      end
      video_pipeline
    end

    # Get video receiver parameters
    # RU: Берёт параметры приёмщика видео
    def get_video_receiver_params(can_src_param = 'video_can_src_app', \
      can_decoder_param = 'video_can_decoder_vp8', recv_tee_param = 'video_recv_tee_def', \
      view2_param = 'video_view2_x')

      # getting from setup (will be feature)
      can_src     = PandoraUtils.get_param(can_src_param)
      can_decoder = PandoraUtils.get_param(can_decoder_param)
      recv_tee    = PandoraUtils.get_param(recv_tee_param)
      view2       = PandoraUtils.get_param(view2_param)

      # default param (temporary)
      #can_src     = 'appsrc emit-signals=false'
      #can_decoder = 'vp8dec'
      #recv_tee    = 'ffmpegcolorspace ! tee'
      #view2       = 'ximagesink sync=false'

      [can_src, can_decoder, recv_tee, view2]
    end

    # Initialize video receiver
    # RU: Инициализирует приёмщика видео
    def init_video_receiver(start=true, can_play=true, init=true)
      p '--init_video_receiver [start, can_play, init]='+[start, can_play, init].inspect
      if not start
        if ximagesink and PandoraUtils.elem_playing?(ximagesink)
          if can_play
            ximagesink.pause
          else
            ximagesink.stop
          end
        end
        if (not can_play) or (not ximagesink)
          p 'Disconnect HANDLER !!!'
          area_recv.set_expose_event(nil)
        end
      elsif (not self.destroyed?) and area_recv and (not area_recv.destroyed?)
        if (not recv_media_pipeline[1]) and init
          begin
            Gst.init
            p 'init_video_receiver INIT'
            winos = (PandoraUtils.os_family == 'windows')
            @recv_media_queue[1] ||= PandoraUtils::RoundQueue.new
            dialog_id = '_v'+PandoraUtils.bytes_to_hex(room_id[-6..-1])
            @recv_media_pipeline[1] = Gst::Pipeline.new('rpipe'+dialog_id)
            vidpipe = @recv_media_pipeline[1]

            ##video_can_src = 'appsrc emit-signals=false'
            ##video_can_decoder = 'vp8dec'
            #video_can_decoder = 'xviddec'
            #video_can_decoder = 'ffdec_flashsv'
            #video_can_decoder = 'ffdec_flashsv2'
            #video_can_decoder = 'queue ! theoradec ! videoscale ! capsfilter caps="video/x-raw,width=320"'
            #video_can_decoder = 'jpegdec'
            #video_can_decoder = 'schrodec'
            #video_can_decoder = 'smokedec'
            #video_can_decoder = 'oggdemux ! theoradec'
            #video_can_decoder = 'theoradec'
            #! video/x-h264,width=176,height=144,framerate=25/1 ! ffdec_h264 ! videorate
            #video_can_decoder = 'x264dec'
            #video_can_decoder = 'mpeg2dec'
            #video_can_decoder = 'mimdec'
            ##video_recv_tee = 'ffmpegcolorspace ! tee'
            #video_recv_tee = 'tee'
            ##video_view2 = 'ximagesink sync=false'
            #video_view2 = 'queue ! xvimagesink force-aspect-ratio=true sync=false'

            can_src_param = 'video_can_src_app'
            can_decoder_param = PandoraUtils.get_param('video_can_decoder')
            recv_tee_param = 'video_recv_tee_def'
            view2_param = PandoraUtils.get_param('video_view2')

            video_can_src, video_can_decoder, video_recv_tee, video_view2 \
              = get_video_receiver_params(can_src_param, can_decoder_param, \
                recv_tee_param, view2_param)

            if winos
              video_view2 = PandoraUtils.get_param('video_view2_win')
              video_view2 ||= 'queue ! directdrawsink'
            end

            @appsrcs[1], pad = add_elem_to_pipe(video_can_src, vidpipe, nil, nil, dialog_id)
            decoder, pad = add_elem_to_pipe(video_can_decoder, vidpipe, appsrcs[1], pad, dialog_id)
            recv_tee, pad = add_elem_to_pipe(video_recv_tee, vidpipe, decoder, pad, dialog_id)
            @ximagesink, pad = add_elem_to_pipe(video_view2, vidpipe, recv_tee, pad, dialog_id)
          rescue => err
            @recv_media_pipeline[1] = nil
            mes = 'Video receiver init exception'
            PandoraUtils.log_message(LM_Warning, _(mes))
            puts mes+': '+Utf8String.new(err.message)
            webcam_btn.active = false
          end
        end

        if @ximagesink and init #and area_recv.window
          link_sink_to_area(@ximagesink, area_recv, recv_media_pipeline[1])
        end

        #p '[recv_media_pipeline[1], can_play]='+[recv_media_pipeline[1], can_play].inspect
        if recv_media_pipeline[1] and can_play and area_recv.window
          #if (not area_recv.expose_event) and
          if (not PandoraUtils.elem_playing?(recv_media_pipeline[1])) \
          or (not PandoraUtils.elem_playing?(ximagesink))
            #p 'PLAYYYYYYYYYYYYYYYYYY!!!!!!!!!! '
            #ximagesink.stop
            #recv_media_pipeline[1].stop
            ximagesink.play
            recv_media_pipeline[1].play
          end
        end
      end
    end

    # Get audio sender parameters
    # RU: Берёт параметры отправителя аудио
    def get_audio_sender_params(src_param = 'audio_src_alsa', \
      send_caps_param = 'audio_send_caps_8000', send_tee_param = 'audio_send_tee_def', \
      can_encoder_param = 'audio_can_encoder_vorbis', can_sink_param = 'audio_can_sink_app')

      # getting from setup (will be feature)
      src = PandoraUtils.get_param(src_param)
      send_caps = PandoraUtils.get_param(send_caps_param)
      send_tee = PandoraUtils.get_param(send_tee_param)
      can_encoder = PandoraUtils.get_param(can_encoder_param)
      can_sink = PandoraUtils.get_param(can_sink_param)

      # default param (temporary)
      #src = 'alsasrc device=hw:0'
      #send_caps = 'audio/x-raw-int,rate=8000,channels=1,depth=8,width=8'
      #send_tee = 'audioconvert ! tee name=audtee'
      #can_encoder = 'vorbisenc quality=0.0'
      #can_sink = 'appsink emit-signals=true'

      # extend src and its caps
      src = src + ' ! audioconvert ! audioresample'
      send_caps = 'capsfilter caps="'+send_caps+'"'

      [src, send_caps, send_tee, can_encoder, can_sink]
    end

    # Initialize audio sender
    # RU: Инициализирует отправителя аудио
    def init_audio_sender(start=true, just_upd_area=false)
      audio_pipeline = $send_media_pipelines['audio']
      #p 'init_audio_sender pipe='+audio_pipeline.inspect+'  btn='+mic_btn.active?.inspect
      if not start
        #count = PandoraGtk.nil_send_ptrind_by_panhash(room_id)
        #if audio_pipeline and (count==0) and (audio_pipeline.get_state != Gst::STATE_NULL)
        if audio_pipeline and (not PandoraUtils::elem_stopped?(audio_pipeline))
          audio_pipeline.stop
        end
      elsif (not self.destroyed?) and (not mic_btn.destroyed?) and mic_btn.active?
        if not audio_pipeline
          begin
            Gst.init
            winos = (PandoraUtils.os_family == 'windows')
            audio_pipeline = Gst::Pipeline.new('spipe_a')
            $send_media_pipelines['audio'] = audio_pipeline

            ##audio_src = 'alsasrc device=hw:0 ! audioconvert ! audioresample'
            #audio_src = 'autoaudiosrc'
            #audio_src = 'alsasrc'
            #audio_src = 'audiotestsrc'
            #audio_src = 'pulsesrc'
            ##audio_src_caps = 'capsfilter caps="audio/x-raw-int,rate=8000,channels=1,depth=8,width=8"'
            #audio_src_caps = 'queue ! capsfilter caps="audio/x-raw-int,rate=8000,depth=8"'
            #audio_src_caps = 'capsfilter caps="audio/x-raw-int,rate=8000,depth=8"'
            #audio_src_caps = 'capsfilter caps="audio/x-raw-int,endianness=1234,signed=true,width=16,depth=16,rate=22000,channels=1"'
            #audio_src_caps = 'queue'
            ##audio_send_tee = 'audioconvert ! tee name=audtee'
            #audio_can_encoder = 'vorbisenc'
            ##audio_can_encoder = 'vorbisenc quality=0.0'
            #audio_can_encoder = 'vorbisenc quality=0.0 bitrate=16000 managed=true' #8192
            #audio_can_encoder = 'vorbisenc quality=0.0 max-bitrate=32768' #32768  16384  65536
            #audio_can_encoder = 'mulawenc'
            #audio_can_encoder = 'lamemp3enc bitrate=8 encoding-engine-quality=speed fast-vbr=true'
            #audio_can_encoder = 'lamemp3enc bitrate=8 target=bitrate mono=true cbr=true'
            #audio_can_encoder = 'speexenc'
            #audio_can_encoder = 'voaacenc'
            #audio_can_encoder = 'faac'
            #audio_can_encoder = 'a52enc'
            #audio_can_encoder = 'voamrwbenc'
            #audio_can_encoder = 'adpcmenc'
            #audio_can_encoder = 'amrnbenc'
            #audio_can_encoder = 'flacenc'
            #audio_can_encoder = 'ffenc_nellymoser'
            #audio_can_encoder = 'speexenc vad=true vbr=true'
            #audio_can_encoder = 'speexenc vbr=1 dtx=1 nframes=4'
            #audio_can_encoder = 'opusenc'
            ##audio_can_sink = 'appsink emit-signals=true'

            src_param = PandoraUtils.get_param('audio_src')
            send_caps_param = PandoraUtils.get_param('audio_send_caps')
            send_tee_param = 'audio_send_tee_def'
            can_encoder_param = PandoraUtils.get_param('audio_can_encoder')
            can_sink_param = 'audio_can_sink_app'

            audio_src, audio_send_caps, audio_send_tee, audio_can_encoder, audio_can_sink  \
              = get_audio_sender_params(src_param, send_caps_param, send_tee_param, \
                can_encoder_param, can_sink_param)

            if winos
              audio_src = PandoraUtils.get_param('audio_src_win')
              audio_src ||= 'dshowaudiosrc'
            end

            micro, pad = add_elem_to_pipe(audio_src, audio_pipeline)
            capsfilter, pad = add_elem_to_pipe(audio_send_caps, audio_pipeline, micro, pad)
            tee, teepad = add_elem_to_pipe(audio_send_tee, audio_pipeline, capsfilter, pad)
            audenc, pad = add_elem_to_pipe(audio_can_encoder, audio_pipeline, tee, teepad)
            appsink, pad = add_elem_to_pipe(audio_can_sink, audio_pipeline, audenc, pad)

            $send_media_queues[0] ||= PandoraUtils::RoundQueue.new(true)
            appsink.signal_connect('new-buffer') do |appsink|
              buf = appsink.pull_buffer
              if buf
                #p 'GET AUDIO ['+buf.size.to_s+']'
                data = buf.data
                $send_media_queues[0].add_block_to_queue(data, $media_buf_size)
              end
            end
          rescue => err
            $send_media_pipelines['audio'] = nil
            mes = 'Microphone init exception'
            PandoraUtils.log_message(LM_Warning, _(mes))
            puts mes+': '+Utf8String.new(err.message)
            mic_btn.active = false
          end
        end

        if audio_pipeline
          ptrind = PandoraGtk.set_send_ptrind_by_panhash(room_id)
          count = PandoraGtk.nil_send_ptrind_by_panhash(nil)
          #p 'AAAAAAAAAAAAAAAAAAA count='+count.to_s
          if (count>0) and (not PandoraUtils::elem_playing?(audio_pipeline))
          #if (audio_pipeline.get_state != Gst::STATE_PLAYING)
            audio_pipeline.play
          end
        end
      end
      audio_pipeline
    end

    # Get audio receiver parameters
    # RU: Берёт параметры приёмщика аудио
    def get_audio_receiver_params(can_src_param = 'audio_can_src_app', \
      can_decoder_param = 'audio_can_decoder_vorbis', recv_tee_param = 'audio_recv_tee_def', \
      phones_param = 'audio_phones_auto')

      # getting from setup (will be feature)
      can_src     = PandoraUtils.get_param(can_src_param)
      can_decoder = PandoraUtils.get_param(can_decoder_param)
      recv_tee    = PandoraUtils.get_param(recv_tee_param)
      phones      = PandoraUtils.get_param(phones_param)

      # default param (temporary)
      #can_src = 'appsrc emit-signals=false'
      #can_decoder = 'vorbisdec'
      #recv_tee = 'audioconvert ! tee'
      #phones = 'autoaudiosink'

      [can_src, can_decoder, recv_tee, phones]
    end

    # Initialize audio receiver
    # RU: Инициализирует приёмщика аудио
    def init_audio_receiver(start=true, can_play=true, init=true)
      if not start
        if recv_media_pipeline[0] and (not PandoraUtils::elem_stopped?(recv_media_pipeline[0]))
          recv_media_pipeline[0].stop
        end
      elsif (not self.destroyed?)
        if (not recv_media_pipeline[0]) and init
          begin
            Gst.init
            winos = (PandoraUtils.os_family == 'windows')
            @recv_media_queue[0] ||= PandoraUtils::RoundQueue.new
            dialog_id = '_a'+PandoraUtils.bytes_to_hex(room_id[-6..-1])
            #p 'init_audio_receiver:  dialog_id='+dialog_id.inspect
            @recv_media_pipeline[0] = Gst::Pipeline.new('rpipe'+dialog_id)
            audpipe = @recv_media_pipeline[0]

            ##audio_can_src = 'appsrc emit-signals=false'
            #audio_can_src = 'appsrc'
            ##audio_can_decoder = 'vorbisdec'
            #audio_can_decoder = 'mulawdec'
            #audio_can_decoder = 'speexdec'
            #audio_can_decoder = 'decodebin'
            #audio_can_decoder = 'decodebin2'
            #audio_can_decoder = 'flump3dec'
            #audio_can_decoder = 'amrwbdec'
            #audio_can_decoder = 'adpcmdec'
            #audio_can_decoder = 'amrnbdec'
            #audio_can_decoder = 'voaacdec'
            #audio_can_decoder = 'faad'
            #audio_can_decoder = 'ffdec_nellymoser'
            #audio_can_decoder = 'flacdec'
            ##audio_recv_tee = 'audioconvert ! tee'
            #audio_phones = 'alsasink'
            ##audio_phones = 'autoaudiosink'
            #audio_phones = 'pulsesink'

            can_src_param = 'audio_can_src_app'
            can_decoder_param = PandoraUtils.get_param('audio_can_decoder')
            recv_tee_param = 'audio_recv_tee_def'
            phones_param = PandoraUtils.get_param('audio_phones')

            audio_can_src, audio_can_decoder, audio_recv_tee, audio_phones \
              = get_audio_receiver_params(can_src_param, can_decoder_param, recv_tee_param, phones_param)

            if winos
              audio_phones = PandoraUtils.get_param('audio_phones_win')
              audio_phones ||= 'autoaudiosink'
            end

            @appsrcs[0], pad = add_elem_to_pipe(audio_can_src, audpipe, nil, nil, dialog_id)
            auddec, pad = add_elem_to_pipe(audio_can_decoder, audpipe, appsrcs[0], pad, dialog_id)
            recv_tee, pad = add_elem_to_pipe(audio_recv_tee, audpipe, auddec, pad, dialog_id)
            audiosink, pad = add_elem_to_pipe(audio_phones, audpipe, recv_tee, pad, dialog_id)
          rescue => err
            @recv_media_pipeline[0] = nil
            mes = 'Audio receiver init exception'
            PandoraUtils.log_message(LM_Warning, _(mes))
            puts mes+': '+Utf8String.new(err.message)
            mic_btn.active = false
          end
          recv_media_pipeline[0].stop if recv_media_pipeline[0]  #this is a hack, else doesn't work!
        end
        if recv_media_pipeline[0] and can_play
          recv_media_pipeline[0].play if (not PandoraUtils::elem_playing?(recv_media_pipeline[0]))
        end
      end
    end
  end  #--class CabinetBox

  # Search panel
  # RU: Панель поиска
  class SearchBox < Gtk::VBox #Gtk::ScrolledWindow
    attr_accessor :text

    include PandoraGtk

    def show_all_reqs(reqs=nil)
      pool = $window.pool
      if reqs or (not @last_mass_ind) or (@last_mass_ind < pool.mass_ind)
        @list_store.clear
        reqs ||= pool.mass_records
        p '-----------reqs='+reqs.inspect
        reqs.each do |mr|
          if (mr.is_a? Array) and (mr[PandoraNet::MR_Kind] == PandoraNet::MK_Search)
            user_iter = @list_store.append
            user_iter[0] = mr[PandoraNet::MR_Index]
            user_iter[1] = Utf8String.new(mr[PandoraNet::MRS_Request])
            user_iter[2] = Utf8String.new(mr[PandoraNet::MRS_Kind])
            user_iter[3] = Utf8String.new(mr[PandoraNet::MRA_Answer].inspect)
          end
        end
        if reqs
          @last_mass_ind = nil
        else
          @last_mass_ind = pool.mass_ind
        end
      end
    end

    # Show search window
    # RU: Показать окно поиска
    def initialize(text=nil)
      super #(nil, nil)

      @text = nil

      #set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      #vbox = Gtk::VBox.new
      #vpaned = Gtk::VPaned.new
      vbox = self

      search_btn = Gtk::ToolButton.new(Gtk::Stock::FIND, _('Search'))
      search_btn.tooltip_text = _('Start searching')
      PandoraGtk.set_readonly(search_btn, true)

      stop_btn = Gtk::ToolButton.new(Gtk::Stock::STOP, _('Stop'))
      stop_btn.tooltip_text = _('Stop searching')
      PandoraGtk.set_readonly(stop_btn, true)

      prev_btn = Gtk::ToolButton.new(Gtk::Stock::GO_BACK, _('Previous'))
      prev_btn.tooltip_text = _('Previous search')
      PandoraGtk.set_readonly(prev_btn, true)

      next_btn = Gtk::ToolButton.new(Gtk::Stock::GO_FORWARD, _('Next'))
      next_btn.tooltip_text = _('Next search')
      PandoraGtk.set_readonly(next_btn, true)

      @list_store = Gtk::ListStore.new(Integer, String, String, String)

      search_entry = Gtk::Entry.new
      #PandoraGtk.hack_enter_bug(search_entry)
      search_entry.signal_connect('key-press-event') do |widget, event|
        res = false
        if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
          search_btn.clicked
          res = true
        elsif (Gdk::Keyval::GDK_Escape==event.keyval)
          stop_btn.clicked
          res = true
        end
        res
      end
      search_entry.signal_connect('changed') do |widget, event|
        empty = (search_entry.text.size==0)
        PandoraGtk.set_readonly(search_btn, empty)
        if empty
          show_all_reqs
        else
          if @last_mass_ind
            @list_store.clear
            @last_mass_ind = nil
          end
        end
        false
      end

      kind_entry = Gtk::Combo.new
      kind_list = PandoraModel.get_kind_list
      name_list = []
      name_list << 'auto'
      #name_list.concat( kind_list.collect{ |rec| rec[2] + ' ('+rec[0].to_s+'='+rec[1]+')' } )
      name_list.concat( kind_list.collect{ |rec| rec[1] } )
      kind_entry.set_popdown_strings(name_list)
      #kind_entry.entry.select_region(0, -1)

      #kind_entry = Gtk::ComboBox.new(true)
      #kind_entry.append_text('auto')
      #kind_entry.append_text('person')
      #kind_entry.append_text('file')
      #kind_entry.append_text('all')
      #kind_entry.active = 0
      #kind_entry.wrap_width = 3
      #kind_entry.has_frame = true

      kind_entry.set_size_request(100, -1)
      #p stop_btn.allocation.width
      #search_width = $window.allocation.width-kind_entry.allocation.width-stop_btn.allocation.width*4
      search_entry.set_size_request(150, -1)

      hbox = Gtk::HBox.new
      hbox.pack_start(kind_entry, false, false, 0)
      hbox.pack_start(search_btn, false, false, 0)
      hbox.pack_start(search_entry, true, true, 0)
      hbox.pack_start(stop_btn, false, false, 0)
      hbox.pack_start(prev_btn, false, false, 0)
      hbox.pack_start(next_btn, false, false, 0)

      toolbar_box = Gtk::HBox.new

      vbox.pack_start(hbox, false, true, 0)
      vbox.pack_start(toolbar_box, false, true, 0)

      #kind_btn = PandoraGtk::SafeToggleToolButton.new(Gtk::Stock::PROPERTIES)
      #kind_btn.tooltip_text = _('Change password')
      #kind_btn.safe_signal_clicked do |*args|
      #  #kind_btn.active?
      #end

      #Сделать горячие клавиши:
      #[CTRL + R], Ctrl + F5, Ctrl + Shift + R - Перезагрузить страницу
      #[CTRL + L] Выделить УРЛ страницы
      #[CTRL + N] Новое окно(не вкладка) - тоже что и Ctrl+T
      #[SHIFT + ESC] (Дипетчер задач) Возможно, список текущих соединений
      #[CTRL[+Alt] + 1] или [CTRL + 2] и т.д. - переключение между вкладками
      #Alt+ <- / -> - Вперед/Назад
      #Alt+Home - Домашняя страница (Профиль)
      #Открыть файл — Ctrl + O
      #Остановить — Esc
      #Сохранить страницу как — Ctrl + S
      #Найти далее — F3, Ctrl + G
      #Найти на этой странице — Ctrl + F
      #Отменить закрытие вкладки — Ctrl + Shift + T
      #Перейти к предыдущей вкладке — Ctrl + Page Up
      #Перейти к следующей вкладке — Ctrl + Page Down
      #Журнал посещений — Ctrl + H
      #Загрузки — Ctrl + J, Ctrl + Y
      #Закладки — Ctrl + B, Ctrl + I

      local_btn = SafeCheckButton.new(_('locally'), true)
      local_btn.safe_signal_clicked do |widget|
        search_btn.clicked if local_btn.active?
      end
      local_btn.safe_set_active(true)

      active_btn = SafeCheckButton.new(_('active only'), true)
      active_btn.safe_signal_clicked do |widget|
        search_btn.clicked if active_btn.active?
      end
      active_btn.safe_set_active(true)

      hunt_btn = SafeCheckButton.new(_('hunt!'), true)
      hunt_btn.safe_signal_clicked do |widget|
        search_btn.clicked if hunt_btn.active?
      end
      hunt_btn.safe_set_active(true)

      toolbar_box.pack_start(local_btn, false, false, 1)
      toolbar_box.pack_start(active_btn, false, false, 1)
      toolbar_box.pack_start(hunt_btn, false, false, 1)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)

      prev_btn.signal_connect('clicked') do |widget|
        PandoraGtk.set_readonly(next_btn, false)
        PandoraGtk.set_readonly(prev_btn, true)
        false
      end

      next_btn.signal_connect('clicked') do |widget|
        PandoraGtk.set_readonly(next_btn, true)
        PandoraGtk.set_readonly(prev_btn, false)
        false
      end

      search_btn.signal_connect('clicked') do |widget|
        request = search_entry.text
        search_entry.position = search_entry.position  # deselect
        if (request.size>0)
          kind = kind_entry.entry.text
          PandoraGtk.set_readonly(stop_btn, false)
          PandoraGtk.set_readonly(widget, true)
          #bases = kind
          #local_btn.active?  active_btn.active?  hunt_btn.active?
          if (kind=='Blob') and PandoraUtils.hex?(request)
            kind = PandoraModel::PK_BlobBody
            request = PandoraUtils.hex_to_bytes(request)
            p 'Search: Detect blob search  kind,sha1='+[kind,request].inspect
          end
          #reqs = $window.pool.add_search_request(request, kind, nil, nil, true)
          reqs = $window.pool.add_mass_record(PandoraNet::MK_Search, kind, request)
          show_all_reqs(reqs)
          PandoraGtk.set_readonly(stop_btn, true)
          PandoraGtk.set_readonly(widget, false)
          PandoraGtk.set_readonly(prev_btn, false)
          PandoraGtk.set_readonly(next_btn, true)
        end
        false
      end
      show_all_reqs

      stop_btn.signal_connect('clicked') do |widget|
        if @search_thread
          if @search_thread[:processing]
            @search_thread[:processing] = false
          else
            PandoraGtk.set_readonly(stop_btn, true)
            @search_thread.exit
            @search_thread = nil
          end
        else
          search_entry.select_region(0, search_entry.text.size)
        end
      end

      #search_btn.signal_connect('clicked') do |*args|
      #end

      # create tree view
      list_tree = Gtk::TreeView.new(@list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new('№', renderer, 'text' => 0)
      column.set_sort_column_id(0)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Request'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Kind'), renderer, 'text' => 2)
      column.set_sort_column_id(2)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Answer'), renderer, 'text' => 3)
      column.set_sort_column_id(3)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        # download and go to record
      end

      list_sw.add(list_tree)

      vbox.pack_start(list_sw, true, true, 0)
      list_sw.show_all

      PandoraGtk.hack_grab_focus(search_entry)
    end
  end

  # Profile panel
  # RU: Панель кабинета
  class ProfileScrollWin < Gtk::ScrolledWindow
    attr_accessor :person

    include PandoraGtk

    # Show profile window
    # RU: Показать окно профиля
    def initialize(a_person=nil)
      super(nil, nil)

      @person = a_person

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      #self.add_with_viewport(vpaned)
    end
  end

  # List of session
  # RU: Список сеансов
  class SessionScrollWin < Gtk::ScrolledWindow
    attr_accessor :update_btn

    include PandoraGtk

    # Show session window
    # RU: Показать окно сессий
    def initialize
      super(nil, nil)

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      vbox = Gtk::VBox.new
      hbox = Gtk::HBox.new

      title = _('Update')
      @update_btn = Gtk::ToolButton.new(Gtk::Stock::REFRESH, title)
      update_btn.tooltip_text = title
      update_btn.label = title

      hunted_btn = SafeCheckButton.new(_('hunted'), true)
      hunted_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      hunted_btn.safe_set_active(true)

      hunters_btn = SafeCheckButton.new(_('hunters'), true)
      hunters_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      hunters_btn.safe_set_active(true)

      fishers_btn = SafeCheckButton.new(_('fishers'), true)
      fishers_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      fishers_btn.safe_set_active(true)

      title = _('Delete')
      delete_btn = Gtk::ToolButton.new(Gtk::Stock::DELETE, title)
      delete_btn.tooltip_text = title
      delete_btn.label = title

      hbox.pack_start(hunted_btn, false, true, 0)
      hbox.pack_start(hunters_btn, false, true, 0)
      hbox.pack_start(fishers_btn, false, true, 0)
      hbox.pack_start(update_btn, false, true, 0)
      hbox.pack_start(delete_btn, false, true, 0)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

      list_store = Gtk::ListStore.new(String, String, String, String, Integer, Integer, \
        Integer, Integer, Integer)
      update_btn.signal_connect('clicked') do |*args|
        list_store.clear
        $window.pool.sessions.each do |session|
          hunter = session.hunter?
          if ((hunted_btn.active? and (not hunter)) \
          or (hunters_btn.active? and hunter) \
          or (fishers_btn.active? and session.active_hook))
            sess_iter = list_store.append
            sess_iter[0] = $window.pool.sessions.index(session).to_s
            sess_iter[1] = session.host_ip.to_s
            sess_iter[2] = session.port.to_s
            sess_iter[3] = PandoraUtils.bytes_to_hex(session.node_panhash)
            sess_iter[4] = session.conn_mode
            sess_iter[5] = session.conn_state
            sess_iter[6] = session.stage
            sess_iter[7] = session.read_state
            sess_iter[8] = session.send_state
          end

          #:host_name, :host_ip, :port, :proto, :node, :conn_mode, :conn_state,
          #:stage, :dialog, :send_thread, :read_thread, :socket, :read_state, :send_state,
          #:send_models, :recv_models, :sindex,
          #:read_queue, :send_queue, :confirm_queue, :params, :rcmd, :rcode, :rdata,
          #:scmd, :scode, :sbuf, :log_mes, :skey, :rkey, :s_encode, :r_encode, :media_send,
          #:node_id, :node_panhash, :entered_captcha, :captcha_sw, :fishes, :fishers
        end
      end

      # create tree view
      list_tree = Gtk::TreeView.new(list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new('№', renderer, 'text' => 0)
      column.set_sort_column_id(0)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Ip'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Port'), renderer, 'text' => 2)
      column.set_sort_column_id(2)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Node'), renderer, 'text' => 3)
      column.set_sort_column_id(3)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('conn_mode'), renderer, 'text' => 4)
      column.set_sort_column_id(4)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('conn_state'), renderer, 'text' => 5)
      column.set_sort_column_id(5)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('stage'), renderer, 'text' => 6)
      column.set_sort_column_id(6)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('read_state'), renderer, 'text' => 7)
      column.set_sort_column_id(7)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('send_state'), renderer, 'text' => 8)
      column.set_sort_column_id(8)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        # download and go to record
      end

      list_sw.add(list_tree)

      vbox.pack_start(hbox, false, true, 0)
      vbox.pack_start(list_sw, true, true, 0)
      list_sw.show_all

      self.add_with_viewport(vbox)
      update_btn.clicked

      list_tree.grab_focus
    end
  end

  # Creating menu item from its description
  # RU: Создание пункта меню по его описанию
  def self.create_menu_item(mi, treeview=nil)
    menuitem = nil
    if mi[0] == '-'
      menuitem = Gtk::SeparatorMenuItem.new
    else
      text = _(mi[2])
      #if (mi[4] == :check)
      #  menuitem = Gtk::CheckMenuItem.new(mi[2])
      #  label = menuitem.children[0]
      #  #label.set_text(mi[2], true)
      opts = nil
      stock = mi[1]
      stock, opts = PandoraGtk.detect_icon_opts(stock) if stock
      if stock and opts and opts.index('m')
        stock = stock.to_sym if stock.is_a? String
        $window.register_stock(stock, nil, text)
        menuitem = Gtk::ImageMenuItem.new(stock)
        label = menuitem.children[0]
        label.set_text(text, true)
      else
        menuitem = Gtk::MenuItem.new(text)
      end
      if menuitem
        if (not treeview) and mi[3]
          key, mod = Gtk::Accelerator.parse(mi[3])
          menuitem.add_accelerator('activate', $window.accel_group, key, \
            mod, Gtk::ACCEL_VISIBLE) if key
        end
        command = mi[0]
        if command and (command.size>0) and (command[0]=='>')
          command = command[1..-1]
          command = nil if command==''
        end
        #menuitem.name = mi[0]
        PandoraUtils.set_obj_property(menuitem, 'command', command)
        PandoraGtk.set_bold_to_menuitem(menuitem) if opts and opts.index('b')
        menuitem.signal_connect('activate') { |widget| $window.do_menu_act(widget, treeview) }
      end
    end
    menuitem
  end

  # List of fishes
  # RU: Список рыб
  class RadarScrollWin < Gtk::ScrolledWindow
    attr_accessor :update_btn

    include PandoraGtk

    MASS_KIND_ICONS = ['hunt', 'chat', 'request', 'fish']

    # Show fishes window
    # RU: Показать окно рыб
    def initialize
      super(nil, nil)

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      vbox = Gtk::VBox.new
      hbox = Gtk::HBox.new

      title = _('Update')
      @update_btn = Gtk::ToolButton.new(Gtk::Stock::REFRESH, title)
      update_btn.tooltip_text = title
      update_btn.label = title

      declared_btn = SafeCheckButton.new(_('declared'), true)
      declared_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      declared_btn.safe_set_active(true)

      lined_btn = SafeCheckButton.new(_('lined'), true)
      lined_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      lined_btn.safe_set_active(true)

      linked_btn = SafeCheckButton.new(_('linked'), true)
      linked_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      linked_btn.safe_set_active(true)

      failed_btn = SafeCheckButton.new(_('failed'), true)
      failed_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      #failed_btn.safe_set_active(true)

      title = _('Delete')
      delete_btn = Gtk::ToolButton.new(Gtk::Stock::DELETE, title)
      delete_btn.tooltip_text = title
      delete_btn.label = title

      hbox.pack_start(update_btn, false, true, 0)
      hbox.pack_start(declared_btn, false, true, 0)
      hbox.pack_start(lined_btn, false, true, 0)
      hbox.pack_start(linked_btn, false, true, 0)
      hbox.pack_start(failed_btn, false, true, 0)
      hbox.pack_start(delete_btn, false, true, 0)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_NONE
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

      #mass_ind, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]

      list_store = Gtk::ListStore.new(Integer, String, String, String, String, \
        Integer, Integer, Integer, String, String, Integer)

      update_btn.signal_connect('clicked') do |*args|
        list_store.clear
        if $window.pool
          $window.pool.mass_records.each do |mr|
            p '---mr:'
            p mr[0..6]
            anode = mr[PandoraNet::MR_Node]
            akey, abaseid, aperson = $window.pool.get_node_params(anode)
            if aperson or akey
              sess_iter = list_store.append
              akind = mr[PandoraNet::MR_Kind]
              anick = nil
              anick = '['+mr[PandoraNet::MRP_Nick]+']' if (akind == PandoraNet::MK_Presence)
              if anick.nil? and aperson
                anick = PandoraCrypto.short_name_of_person(nil, aperson, 1)
              end
              anick = akind.to_s if anick.nil?
              trust = mr[PandoraNet::MR_Trust]
              trust = 0 if not (trust.is_a? Integer)
              sess_iter[0] = akind
              sess_iter[1] = anick
              sess_iter[2] = PandoraUtils.bytes_to_hex(aperson)
              sess_iter[3] = PandoraUtils.bytes_to_hex(akey)
              sess_iter[4] = PandoraUtils.bytes_to_hex(abaseid)
              sess_iter[5] = trust
              sess_iter[6] = mr[PandoraNet::MR_Depth]
              sess_iter[7] = 0 #distance
              sess_iter[8] = PandoraUtils.bytes_to_hex(anode)
              sess_iter[9] = PandoraUtils.time_to_str(mr[PandoraNet::MR_CrtTime])
              sess_iter[10] = mr[PandoraNet::MR_Index]
            end
          end
        end
      end

      # create tree view
      list_tree = Gtk::TreeView.new(list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      #mass_ind, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]

      kind_pbs = []
      MASS_KIND_ICONS.each_with_index do |v, i|
        kind_pbs[i] = $window.get_icon_scale_buf(v, 'pan', 16)
      end

      kind_image = Gtk::Image.new(Gtk::Stock::CONNECT, Gtk::IconSize::MENU)
      kind_image.show_all
      renderer = Gtk::CellRendererPixbuf.new
      column = Gtk::TreeViewColumn.new('', renderer)
      column.widget = kind_image
      #column.set_sort_column_id(0)
      column.set_cell_data_func(renderer) do |tvc, renderer, model, iter|
        kind = nil
        kind = iter[0] if model.iter_is_valid?(iter) and iter and iter.path
        kind ||= 1
        if kind
          pixbuf = kind_pbs[kind-1]
          pixbuf = nil if pixbuf==false
          renderer.pixbuf = pixbuf
        end
      end
      column.fixed_width = 20
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Nick'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Person'), renderer, 'text' => 2)
      column.set_sort_column_id(2)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Key'), renderer, 'text' => 3)
      column.set_sort_column_id(3)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('BaseID'), renderer, 'text' => 4)
      column.set_sort_column_id(4)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Trust'), renderer, 'text' => 5)
      column.set_sort_column_id(5)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Depth'), renderer, 'text' => 6)
      column.set_sort_column_id(6)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Distance'), renderer, 'text' => 7)
      column.set_sort_column_id(7)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Node'), renderer, 'text' => 8)
      column.set_sort_column_id(8)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Time'), renderer, 'text' => 9)
      column.set_sort_column_id(9)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Index'), renderer, 'text' => 10)
      column.set_sort_column_id(10)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        PandoraGtk.act_panobject(list_tree, 'Dialog')
      end

      menu = Gtk::Menu.new
      menu.append(PandoraGtk.create_menu_item(['Dialog', 'dialog:mb', _('Dialog'), '<control>D'], list_tree))
      menu.append(PandoraGtk.create_menu_item(['Relation', :relation, _('Relate'), '<control>R'], list_tree))
      menu.show_all

      list_tree.add_events(Gdk::Event::BUTTON_PRESS_MASK)
      list_tree.signal_connect('button-press-event') do |widget, event|
        if (event.button == 3)
          menu.popup(nil, nil, event.button, event.time)
        end
      end

      list_tree.signal_connect('key-press-event') do |widget, event|
        res = true
        if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
          PandoraGtk.act_panobject(list_tree, 'Dialog')
        elsif event.state.control_mask?
          if [Gdk::Keyval::GDK_d, Gdk::Keyval::GDK_D, 1751, 1783].include?(event.keyval)
            PandoraGtk.act_panobject(list_tree, 'Dialog')
            #path, column = list_tree.cursor
            #if path
            #  iter = list_store.get_iter(path)
            #  person = nil
            #  person = iter[0] if iter
            #  person = PandoraUtils.hex_to_bytes(person)
            #  PandoraGtk.show_cabinet(person) if person
            #end
          else
            res = false
          end
        else
          res = false
        end
        res
      end

      list_sw.add(list_tree)
      #image = Gtk::Image.new(Gtk::Stock::GO_FORWARD, Gtk::IconSize::MENU)
      image = Gtk::Image.new(:radar, Gtk::IconSize::SMALL_TOOLBAR)
      image.set_padding(2, 0)
      #image1 = Gtk::Image.new(Gtk::Stock::ORIENTATION_PORTRAIT, Gtk::IconSize::MENU)
      #image1.set_padding(2, 2)
      #image2 = Gtk::Image.new(Gtk::Stock::NETWORK, Gtk::IconSize::MENU)
      #image2.set_padding(2, 2)
      image.show_all
      align = Gtk::Alignment.new(0.0, 0.5, 0.0, 0.0)
      btn_hbox = Gtk::HBox.new
      label = Gtk::Label.new(_('Radar'))
      btn_hbox.pack_start(image, false, false, 0)
      btn_hbox.pack_start(label, false, false, 2)

      close_image = Gtk::Image.new(Gtk::Stock::CLOSE, Gtk::IconSize::MENU)
      btn_hbox.pack_start(close_image, false, false, 2)

      btn = Gtk::Button.new
      btn.relief = Gtk::RELIEF_NONE
      btn.focus_on_click = false
      btn.signal_connect('clicked') do |*args|
        PandoraGtk.show_radar_panel
      end
      btn.add(btn_hbox)
      align.add(btn)
      #lab_hbox.pack_start(image, false, false, 0)
      #lab_hbox.pack_start(image2, false, false, 0)
      #lab_hbox.pack_start(align, false, false, 0)
      #vbox.pack_start(lab_hbox, false, false, 0)
      vbox.pack_start(align, false, false, 0)
      vbox.pack_start(hbox, false, false, 0)
      vbox.pack_start(list_sw, true, true, 0)
      vbox.show_all

      self.add_with_viewport(vbox)
      update_btn.clicked

      list_tree.grab_focus
    end
  end

  # List of fishers
  # RU: Список рыбаков
  class FisherScrollWin < Gtk::ScrolledWindow
    attr_accessor :update_btn

    include PandoraGtk

    # Show fishers window
    # RU: Показать окно рыбаков
    def initialize
      super(nil, nil)

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      vbox = Gtk::VBox.new
      hbox = Gtk::HBox.new

      title = _('Update')
      @update_btn = Gtk::ToolButton.new(Gtk::Stock::REFRESH, title)
      update_btn.tooltip_text = title
      update_btn.label = title

      title = _('Delete')
      delete_btn = Gtk::ToolButton.new(Gtk::Stock::DELETE, title)
      delete_btn.tooltip_text = title
      delete_btn.label = title

      hbox.pack_start(update_btn, false, true, 0)
      hbox.pack_start(delete_btn, false, true, 0)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

      #mass_ind, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]

      list_store = Gtk::ListStore.new(Integer, String, Integer, String, String, \
        String, String, String, String, String, String)

      update_btn.signal_connect('clicked') do |*args|
        list_store.clear
        $window.pool.mass_records.each do |mr|
          if mr
            sess_iter = list_store.append
            sess_iter[0] = mr[PandoraNet::MR_Kind]
            sess_iter[1] = PandoraUtils.bytes_to_hex(mr[PandoraNet::MR_Node])
            sess_iter[2] = mr[PandoraNet::MR_Index]
            sess_iter[3] = PandoraUtils.time_to_str(mr[PandoraNet::MR_CrtTime])
            sess_iter[4] = mr[PandoraNet::MR_Trust].inspect
            sess_iter[5] = mr[PandoraNet::MR_Depth].inspect
            sess_iter[6] = mr[PandoraNet::MR_Param1].inspect
            sess_iter[7] = mr[PandoraNet::MR_Param2].inspect
            sess_iter[8] = mr[PandoraNet::MR_Param3].inspect
            sess_iter[9] = mr[PandoraNet::MR_KeepNodes].inspect
            sess_iter[10] = mr[PandoraNet::MR_Requests].inspect
          end
        end
      end

      # create tree view
      list_tree = Gtk::TreeView.new(list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      #mass_ind, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Kind'), renderer, 'text' => 0)
      column.set_sort_column_id(0)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Node'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Index'), renderer, 'text' => 2)
      column.set_sort_column_id(2)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('CrtTime'), renderer, 'text' => 3)
      column.set_sort_column_id(3)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Trust'), renderer, 'text' => 4)
      column.set_sort_column_id(4)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Depth'), renderer, 'text' => 5)
      column.set_sort_column_id(5)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Param1'), renderer, 'text' => 6)
      column.set_sort_column_id(6)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Param2'), renderer, 'text' => 7)
      column.set_sort_column_id(7)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Param3'), renderer, 'text' => 8)
      column.set_sort_column_id(8)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('KeepNodes'), renderer, 'text' => 9)
      column.set_sort_column_id(9)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Requests'), renderer, 'text' => 10)
      column.set_sort_column_id(10)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        # download and go to record
      end

      list_sw.add(list_tree)

      vbox.pack_start(hbox, false, true, 0)
      vbox.pack_start(list_sw, true, true, 0)
      list_sw.show_all

      self.add_with_viewport(vbox)
      update_btn.clicked

      list_tree.grab_focus
    end
  end

  # Set readonly mode to widget
  # RU: Установить виджету режим только для чтения
  def self.set_readonly(widget, value=true, set_sensitive=true)
    value = (not value)
    widget.editable = value if widget.class.method_defined? 'editable?'
    widget.sensitive = value if set_sensitive and (widget.class.method_defined? 'sensitive?')
    #widget.can_focus = value
    #widget.has_focus = value if widget.class.method_defined? 'has_focus?'
    #widget.can_focus = (not value) if widget.class.method_defined? 'can_focus?'
  end

  # Correct bug with dissapear Enter press event
  # RU: Исправляет баг с исчезновением нажатия Enter
  def self.hack_enter_bug(enterbox)
    # because of bug - doesnt work Enter at 'key-press-event'
    enterbox.signal_connect('key-release-event') do |widget, event|
      if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
      and (not event.state.control_mask?) and (not event.state.shift_mask?) and (not event.state.mod1_mask?)
        widget.signal_emit('key-press-event', event)
        false
      end
    end
  end

  # Correct bug with non working focus set
  # RU: Исправляет баг с неработающей постановкой фокуса
  def self.hack_grab_focus(widget_to_focus)
    widget_to_focus.grab_focus
    Thread.new do
      sleep(0.2)
      if (not widget_to_focus.destroyed?)
        widget_to_focus.grab_focus
      end
    end
  end

  # Set statusbat text
  # RU: Задает текст статусной строки
  def self.set_statusbar_text(statusbar, text)
    statusbar.pop(0)
    statusbar.push(0, text)
  end

  def self.find_tool_btn(toolbar, title)
    res = nil
    if toolbar
      lang_title = _(title)
      i = 0
      while (i<toolbar.children.size) and (not res)
        ch = toolbar.children[i]
        if (((ch.is_a? Gtk::ToolButton) or (ch.is_a? Gtk::ToggleToolButton)) \
        and ((ch.label == title) or (ch.label == lang_title)))
          res = ch
          break
        end
        i += 1
      end
    end
    res
  end

  $update_lag = 30    #time lag (sec) for update after run the programm
  $download_thread = nil

  UPD_FileList = ['model/01-base.xml', 'model/02-forms.xml', 'pandora.sh', 'pandora.bat']
  UPD_FileList.concat(['model/03-language-'+$lang+'.xml', 'lang/'+$lang+'.txt']) if ($lang and ($lang != 'en'))

  # Check updated files and download them
  # RU: Проверить обновления и скачать их
  def self.start_updating(all_step=true)

    def self.connect_http_and_check_size(url, curr_size, step)
      time = nil
      http, host, path = PandoraNet.http_connect(url)
      if http
        new_size = PandoraNet.http_size_from_header(http, path, false)
        if not new_size
          sleep(0.5)
          new_size = PandoraNet.http_size_from_header(http, path, false)
        end
        if new_size
          PandoraUtils.set_param('last_check', Time.now)
          p 'Size diff: '+[new_size, curr_size].inspect
          if (new_size == curr_size)
            http = nil
            step = 254
            $window.set_status_field(SF_Update, 'Ok', false)
            PandoraUtils.set_param('last_update', Time.now)
          else
            time = Time.now.to_i
          end
        else
          http = nil
        end
      end
      if not http
        $window.set_status_field(SF_Update, 'Connection error')
        PandoraUtils.log_message(LM_Info, _('Cannot connect to repo to check update')+\
          ' '+[host, path].inspect)
      end
      [http, time, step, host, path]
    end

    def self.reconnect_if_need(http, time, url)
      http = PandoraNet.http_reconnect_if_need(http, time, url)
      if not http
        $window.set_status_field(SF_Update, 'Connection error')
        PandoraUtils.log_message(LM_Warning, _('Cannot reconnect to repo to update'))
      end
      http
    end

    # Update file
    # RU: Обновить файл
    def self.update_file(http, path, pfn, host='')
      res = false
      dir = File.dirname(pfn)
      FileUtils.mkdir_p(dir) unless Dir.exists?(dir)
      if Dir.exists?(dir)
        filebody = PandoraNet.http_get_body_from_path(http, path, host)
        if filebody and (filebody.size>0)
          begin
            File.open(pfn, 'wb+') do |file|
              file.write(filebody)
              res = true
              PandoraUtils.log_message(LM_Info, _('File updated')+': '+pfn)
            end
          rescue => err
            PandoraUtils.log_message(LM_Warning, _('Update error')+': '+Utf8String.new(err.message))
          end
        else
          PandoraUtils.log_message(LM_Warning, _('Empty downloaded body'))
        end
      else
        PandoraUtils.log_message(LM_Warning, _('Cannot create directory')+': '+dir)
      end
      res
    end

    if $download_thread and $download_thread.alive?
      $download_thread[:all_step] = all_step
      $download_thread.run if $download_thread.stop?
    else
      $download_thread = Thread.new do
        Thread.current[:all_step] = all_step
        downloaded = false
        $window.set_status_field(SF_Update, 'Need check')
        sleep($update_lag) if not Thread.current[:all_step]
        $window.set_status_field(SF_Update, 'Checking')

        main_script = File.join($pandora_app_dir, 'pandora.rb')
        curr_size = File.size?(main_script)
        if curr_size
          if File.stat(main_script).writable?
            update_zip = PandoraUtils.get_param('update_zip_first')
            update_zip = true if update_zip.nil?

            step = 0
            while (step<2) do
              step += 1
              if update_zip
                zip_local = File.join($pandora_base_dir, 'Pandora-master.zip')
                zip_exists = File.exist?(zip_local)
                p [zip_exists, zip_local]
                if not zip_exists
                  File.open(zip_local, 'wb+') do |file|
                    file.write('0')  #empty file
                  end
                  zip_exists = File.exist?(zip_local)
                end
                if zip_exists
                  zip_size = File.size?(zip_local)
                  if zip_size
                    if File.stat(zip_local).writable?
                      #zip_on_repo = 'https://codeload.github.com/Novator/Pandora/zip/master'
                      #dir_in_zip = 'Pandora-maste'
                      zip_url = 'https://bitbucket.org/robux/pandora/get/master.zip'
                      dir_in_zip = 'robux-pandora'
                      http, time, step, host, path = connect_http_and_check_size(zip_url, \
                        zip_size, step)
                      if http
                        PandoraUtils.log_message(LM_Info, _('Need update'))
                        $window.set_status_field(SF_Update, 'Need update')
                        Thread.stop
                        http = reconnect_if_need(http, time, zip_url)
                        if http
                          $window.set_status_field(SF_Update, 'Doing')
                          res = update_file(http, path, zip_local, host)
                          #res = true
                          if res
                            # Delete old arch paths
                            unzip_mask = File.join($pandora_base_dir, dir_in_zip+'*')
                            p unzip_paths = Dir.glob(unzip_mask, File::FNM_PATHNAME | File::FNM_CASEFOLD)
                            unzip_paths.each do |pathfilename|
                              p 'Remove dir: '+pathfilename
                              FileUtils.remove_dir(pathfilename) if File.directory?(pathfilename)
                            end
                            # Unzip arch
                            unzip_meth = 'lib'
                            res = PandoraUtils.unzip_via_lib(zip_local, $pandora_base_dir)
                            p 'unzip_file1 res='+res.inspect
                            if not res
                              PandoraUtils.log_message(LM_Trace, _('Was not unziped with method')+': lib')
                              unzip_meth = 'util'
                              res = PandoraUtils.unzip_via_util(zip_local, $pandora_base_dir)
                              p 'unzip_file2 res='+res.inspect
                              if not res
                                PandoraUtils.log_message(LM_Warning, _('Was not unziped with method')+': util')
                              end
                            end
                            # Copy files to work dir
                            if res
                              PandoraUtils.log_message(LM_Info, _('Arch is unzipped with method')+': '+unzip_meth)
                              #unzip_path = File.join($pandora_base_dir, 'Pandora-master')
                              unzip_path = nil
                              p 'unzip_mask='+unzip_mask.inspect
                              p unzip_paths = Dir.glob(unzip_mask, File::FNM_PATHNAME | File::FNM_CASEFOLD)
                              unzip_paths.each do |pathfilename|
                                if File.directory?(pathfilename)
                                  unzip_path = pathfilename
                                  break
                                end
                              end
                              if unzip_path and Dir.exist?(unzip_path)
                                begin
                                  p 'Copy '+unzip_path+' to '+$pandora_app_dir
                                  #FileUtils.copy_entry(unzip_path, $pandora_app_dir, true)
                                  FileUtils.cp_r(unzip_path+'/.', $pandora_app_dir)
                                  PandoraUtils.log_message(LM_Info, _('Files are updated'))
                                rescue => err
                                  res = false
                                  PandoraUtils.log_message(LM_Warning, _('Cannot copy files from zip arch')+': '+Utf8String.new(err.message))
                                end
                                # Remove used arch dir
                                begin
                                  FileUtils.remove_dir(unzip_path)
                                rescue => err
                                  PandoraUtils.log_message(LM_Warning, _('Cannot remove arch dir')+' ['+unzip_path+']: '+Utf8String.new(err.message))
                                end
                                step = 255 if res
                              else
                                PandoraUtils.log_message(LM_Warning, _('Unzipped directory does not exist'))
                              end
                            else
                              PandoraUtils.log_message(LM_Warning, _('Arch was not unzipped'))
                            end
                          else
                            PandoraUtils.log_message(LM_Warning, _('Cannot download arch'))
                          end
                        end
                      end
                    else
                      $window.set_status_field(SF_Update, 'Read only')
                      PandoraUtils.log_message(LM_Warning, _('Zip is unrewritable'))
                    end
                  else
                    $window.set_status_field(SF_Update, 'Size error')
                    PandoraUtils.log_message(LM_Warning, _('Zip size error'))
                  end
                end
                update_zip = false
              else   # update with https from sources
                url = 'https://raw.githubusercontent.com/Novator/Pandora/master/pandora.rb'
                http, time, step, host, path = connect_http_and_check_size(url, \
                  curr_size, step)
                if http
                  PandoraUtils.log_message(LM_Info, _('Need update'))
                  $window.set_status_field(SF_Update, 'Need update')
                  Thread.stop
                  http = reconnect_if_need(http, time, url)
                  if http
                    $window.set_status_field(SF_Update, 'Doing')
                    # updating pandora.rb
                    downloaded = update_file(http, path, main_script, host)
                    # updating other files
                    UPD_FileList.each do |fn|
                      pfn = File.join($pandora_app_dir, fn)
                      if File.exist?(pfn) and (not File.stat(pfn).writable?)
                        downloaded = false
                        PandoraUtils.log_message(LM_Warning, \
                          _('Not exist or read only')+': '+pfn)
                      else
                        downloaded = downloaded and \
                          update_file(http, '/Novator/Pandora/master/'+fn, pfn)
                      end
                    end
                    if downloaded
                      step = 255
                    else
                      PandoraUtils.log_message(LM_Warning, _('Direct download error'))
                    end
                  end
                end
                update_zip = true
              end
            end
            if step == 255
              PandoraUtils.set_param('last_update', Time.now)
              $window.set_status_field(SF_Update, 'Need restart')
              Thread.stop
              #Kernel.abort('Pandora is updated. Run it again')
              puts 'Pandora is updated. Restarting..'
              PandoraNet.start_or_stop_listen(false, true)
              PandoraNet.start_or_stop_hunt(false) if $hunter_thread
              $window.pool.close_all_session
              PandoraUtils.restart_app
            elsif step<250
              $window.set_status_field(SF_Update, 'Load error')
            end
          else
            $window.set_status_field(SF_Update, 'Read only')
          end
        else
          $window.set_status_field(SF_Update, 'Size error')
        end
        $download_thread = nil
      end
    end
  end

  # Get icon associated with panobject
  # RU: Взять иконку ассоциированную с панобъектом
  def self.get_panobject_icon(panobj)
    panobj_icon = nil
    if panobj
      ider = panobj
      ider = panobj.ider if (not panobj.is_a? String)
      image = nil
      image = $window.get_panobject_image(ider, Gtk::IconSize::DIALOG) if $window
      if image
        style = Gtk::Widget.default_style
        panobj_icon = image.icon_set.render_icon(style, Gtk::Widget::TEXT_DIR_LTR, \
          Gtk::STATE_NORMAL, Gtk::IconSize::DIALOG)
      end
    end
    panobj_icon
  end

  # Do action with selected record
  # RU: Выполнить действие над выделенной записью
  def self.act_panobject(tree_view, action)

    # Set delete dialog wigets (checkboxes and text)
    # RU: Задать виджеты диалога удаления (чекбоксы и текст)
    def self.set_del_dlg_wids(dialog, arch_cb, keep_cb, ignore_cb)
      text = nil
      if arch_cb and arch_cb.active?
        if keep_cb.active?
          text = _('Stay record in archive with "Keep" flag')
        else
          text = _('Move record to archive. Soon will be deleted by garbager')
        end
      elsif ignore_cb.active?
        text = _('Delete record physically')+'. '+\
          _('Also create Relation "Ignore"')
      else
        text = _('Delete record physically')
      end
      dialog.secondary_text = text if text
    end

    path = nil
    if tree_view.destroyed?
      new_act = false
    else
      path, column = tree_view.cursor
      new_act = (action == 'Create')
    end
    p 'path='+path.inspect
    if path or new_act
      panobject = nil
      if (tree_view.is_a? SubjTreeView)
        panobject = tree_view.panobject
      end
      #p 'panobject='+panobject.inspect
      store = tree_view.model
      iter = nil
      sel = nil
      id = nil
      panhash0 = nil
      lang = PandoraModel.text_to_lang($lang)
      panstate = 0
      created0 = nil
      creator0 = nil
      if path and (not new_act)
        iter = store.get_iter(path)
        if panobject  # SubjTreeView
          id = iter[0]
          sel = panobject.select('id='+id.to_s, true)
          panhash0 = panobject.namesvalues['panhash']
          panstate = panobject.namesvalues['panstate']
          panstate ||= 0
          if (panobject.is_a? PandoraModel::Created)
            created0 = panobject.namesvalues['created']
            creator0 = panobject.namesvalues['creator']
          end
        else  # RadarScrollWin
          panhash0 = PandoraUtils.hex_to_bytes(iter[2])
        end
        lang = panhash0[1].ord if panhash0 and (panhash0.size>1)
        lang ||= 0
      end

      if action=='Delete'
        if id and sel[0]
          ctrl_prsd, shift_prsd, alt_prsd = PandoraGtk.is_ctrl_shift_alt?
          keep_flag = (panstate and (panstate & PandoraModel::PSF_Support)>0)
          arch_flag = (panstate and (panstate & PandoraModel::PSF_Archive)>0)
          in_arch = tree_view.page_sw.arch_btn.active?
          ignore_mode = ((ctrl_prsd and shift_prsd) or (arch_flag and (not ctrl_prsd)))
          arch_mode = ((not ignore_mode) and (not ctrl_prsd))
          keep_mode = (arch_mode and (keep_flag or shift_prsd))
          delete_mode = PandoraUtils.get_param('delete_mode')
          do_del = true
          if arch_flag or ctrl_prsd or shift_prsd or in_arch \
          or (delete_mode==0)
            in_arch = (in_arch and arch_flag)
            info = panobject.record_info(80, nil, ': ')
            #panobject.show_panhash(panhash0) #.force_encoding('ASCII-8BIT') ASCII-8BIT
            dialog = PandoraGtk::GoodMessageDialog.new(info, 'Deletion', \
              Gtk::MessageDialog::QUESTION, get_panobject_icon(panobject))
            arch_cb = nil
            keep_cb = nil
            ignore_cb = nil
            dialog.signal_connect('key-press-event') do |widget, event|
              if (event.keyval==Gdk::Keyval::GDK_Delete)
                widget.response(Gtk::Dialog::RESPONSE_CANCEL)
              elsif [Gdk::Keyval::GDK_a, Gdk::Keyval::GDK_A, 1731, 1763].include?(\
              event.keyval) #a, A, ф, Ф
                arch_cb.active = (not arch_cb.active?) if arch_cb
              elsif [Gdk::Keyval::GDK_k, Gdk::Keyval::GDK_K, 1731, 1763].include?(\
              event.keyval) #k, K, л, Л
                keep_cb.active = (not keep_cb.active?) if keep_cb
              elsif [Gdk::Keyval::GDK_i, Gdk::Keyval::GDK_I, 1731, 1763].include?(\
              event.keyval) #i, I, ш, Ш
                ignore_cb.active = (not ignore_cb.active?) if ignore_cb
              else
                p event.keyval
              end
              false
            end
            # Set dialog size for prevent jumping
            hbox = dialog.vbox.children[0]
            hbox.set_size_request(500, 100) if hbox.is_a? Gtk::HBox
            # CheckBox adding
            if not in_arch
              arch_cb = SafeCheckButton.new(:arch)
              PandoraGtk.set_button_text(arch_cb, _('Move to archive'))
              arch_cb.active = arch_mode
              arch_cb.safe_signal_clicked do |widget|
                if in_arch
                  widget.safe_set_active(false)
                elsif not PandoraGtk.is_ctrl_shift_alt?(true, true)
                  widget.safe_set_active(true)
                end
                if widget.active?
                  ignore_cb.safe_set_active(false)
                else
                  keep_cb.safe_set_active(false)
                end
                set_del_dlg_wids(dialog, arch_cb, keep_cb, ignore_cb)
                false
              end
              dialog.vbox.pack_start(arch_cb, false, true, 0)

              $window.register_stock(:keep)
              keep_cb = SafeCheckButton.new(:keep)
              PandoraGtk.set_button_text(keep_cb, _('Keep in archive'))
              keep_cb.active = keep_mode
              keep_cb.safe_signal_clicked do |widget|
                widget.safe_set_active(false) if in_arch
                if widget.active?
                  arch_cb.safe_set_active(true) if not in_arch
                  ignore_cb.safe_set_active(false)
                end
                set_del_dlg_wids(dialog, arch_cb, keep_cb, ignore_cb)
                false
              end
              dialog.vbox.pack_start(keep_cb, false, true, 0)
            end

            $window.register_stock(:ignore)
            ignore_cb = SafeCheckButton.new(:ignore)
            ignore_cb.active = ignore_mode
            PandoraGtk.set_button_text(ignore_cb, _('Destroy and ignore'))
            ignore_cb.safe_signal_clicked do |widget|
              if widget.active?
                arch_cb.safe_set_active(false) if arch_cb
                keep_cb.safe_set_active(false) if keep_cb
              elsif not in_arch
                arch_cb.safe_set_active(true) if arch_cb
              end
              set_del_dlg_wids(dialog, arch_cb, keep_cb, ignore_cb)
              false
            end
            dialog.vbox.pack_start(ignore_cb, false, true, 0)

            set_del_dlg_wids(dialog, arch_cb, keep_cb, ignore_cb)
            dialog.vbox.show_all

            do_del = dialog.run_and_do do
              arch_mode = (arch_cb and arch_cb.active?)
              keep_mode = (keep_cb and keep_cb.active?)
              ignore_mode = ignore_cb.active?
            end
          end
          if do_del
            rm_from_tab = false
            if arch_mode
              p '[arch_mode, keep_mode]='+[arch_mode, keep_mode].inspect
              panstate = (panstate | PandoraModel::PSF_Archive)
              if keep_mode
                panstate = (panstate | PandoraModel::PSF_Support)
              else
                panstate = (panstate & (~PandoraModel::PSF_Support))
              end
              res = panobject.update({:panstate=>panstate}, nil, 'id='+id.to_s)
              if (not tree_view.page_sw.arch_btn.active?)
                rm_from_tab = true
              end
            else
              res = panobject.update(nil, nil, 'id='+id.to_s)
              PandoraModel.remove_all_relations(panhash0, true, true)
              PandoraModel.act_relation(nil, panhash0, RK_Ignore, :create, \
                true, true) if ignore_mode
              rm_from_tab = true
            end
            if rm_from_tab
              if (panobject.kind==PK_Relation)
                PandoraModel.del_image_from_cache(panobject.namesvalues['first'])
                PandoraModel.del_image_from_cache(panobject.namesvalues['second'])
              end
              tree_view.sel.delete_if {|row| row[0]==id }
              store.remove(iter)
              #iter.next!
              pt = path.indices[0]
              pt = tree_view.sel.size-1 if (pt > tree_view.sel.size-1)
              tree_view.set_cursor(Gtk::TreePath.new(pt), column, false) if (pt >= 0)
            end
          end
        end
      elsif panobject or (action=='Dialog') or (action=='Opinion') \
      or (action=='Chat') or (action=='Profile')
        # Edit or Insert

        edit = ((not new_act) and (action != 'Copy'))

        row = nil
        formfields = nil
        if panobject
          row = sel[0] if sel
          formfields = panobject.get_fields_as_view(row, edit)
        end

        if panhash0
          page = CPI_Property
          page = CPI_Profile if (action=='Profile')
          page = CPI_Chat if (action=='Chat')
          page = CPI_Dialog if (action=='Dialog')
          page = CPI_Opinions if (action=='Opinion')
          show_cabinet(panhash0, nil, nil, nil, nil, page, formfields, id, edit)
        else
          dialog = FieldsDialog.new(panobject, tree_view, formfields, panhash0, id, \
            edit, panobject.sname)
          dialog.icon = get_panobject_icon(panobject)

          #!!!dialog.lang_entry.entry.text = PandoraModel.lang_to_text(lang) if lang

          if edit
            count, rate, querist_rate = PandoraCrypto.rate_of_panobj(panhash0)
            #!!!dialog.rate_btn.label = _('Rate')+': '+rate.round(2).to_s if rate.is_a? Float
            trust = nil
            #p PandoraUtils.bytes_to_hex(panhash0)
            #p 'trust or num'
            trust_or_num = PandoraCrypto.trust_to_panobj(panhash0)
            trust = trust_or_num if (trust_or_num.is_a? Float)
            #!!!dialog.vouch_btn.active = (trust_or_num != nil)
            #!!!dialog.vouch_btn.inconsistent = (trust_or_num.is_a? Integer)
            #!!!dialog.trust_scale.sensitive = (trust != nil)
            #dialog.trust_scale.signal_emit('value-changed')
            trust ||= 0.0
            #!!!dialog.trust_scale.value = trust
            #dialog.rate_label.text = rate.to_s

            #!!!dialog.keep_btn.active = (PandoraModel::PSF_Support & panstate)>0

            #!!pub_level = PandoraModel.act_relation(nil, panhash0, RK_MinPublic, :check)
            #!!!dialog.public_btn.active = pub_level
            #!!!dialog.public_btn.inconsistent = (pub_level == nil)
            #!!!dialog.public_scale.value = (pub_level-RK_MinPublic-10)/10.0 if pub_level
            #!!!dialog.public_scale.sensitive = pub_level

            #!!follow = PandoraModel.act_relation(nil, panhash0, RK_Follow, :check)
            #!!!dialog.follow_btn.active = follow
            #!!!dialog.follow_btn.inconsistent = (follow == nil)

            #dialog.lang_entry.active_text = lang.to_s
            #trust_lab = dialog.trust_btn.children[0]
            #trust_lab.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#777777')) if signed == 1
          else  #new or copy
            key = PandoraCrypto.current_key(false, false)
            key_inited = (key and key[PandoraCrypto::KV_Obj])
            #!!!dialog.keep_btn.active = true
            #!!!dialog.follow_btn.active = key_inited
            #!!!dialog.vouch_btn.active = key_inited
            #!!!dialog.trust_scale.sensitive = key_inited
            #!!!if not key_inited
            #  dialog.follow_btn.inconsistent = true
            #  dialog.vouch_btn.inconsistent = true
            #  dialog.public_btn.inconsistent = true
            #end
            #!!!dialog.public_scale.sensitive = false
          end

          st_text = panobject.panhash_formula
          st_text = st_text + ' [#'+panobject.calc_panhash(row, lang, \
            true, true)+']' if sel and sel.size>0
          #!!!PandoraGtk.set_statusbar_text(dialog.statusbar, st_text)

          #if panobject.is_a? PandoraModel::Key
          #  mi = Gtk::MenuItem.new("Действия")
          #  menu = Gtk::MenuBar.new
          #  menu.append(mi)

          #  menu2 = Gtk::Menu.new
          #  menuitem = Gtk::MenuItem.new("Генерировать")
          #  menu2.append(menuitem)
          #  mi.submenu = menu2
          #  #p dialog.action_area
          #  dialog.hbox.pack_end(menu, false, false)
          #  #dialog.action_area.add(menu)
          #end

          titadd = nil
          if not edit
          #  titadd = _('edit')
          #else
            titadd = _('new')
          end
          dialog.title += ' ('+titadd+')' if titadd and (titadd != '')

          dialog.run2 do
            dialog.property_box.save_fields_with_flags(created0, row)
          end
        end
      end
    elsif action=='Dialog'
      PandoraGtk.show_panobject_list(PandoraModel::Person)
    end
  end

  # Grid for panobjects
  # RU: Таблица для объектов Пандоры
  class SubjTreeView < Gtk::TreeView
    attr_accessor :panobject, :sel, :notebook, :auto_create, :param_view_col, \
      :page_sw
  end

  # Column for SubjTreeView
  # RU: Колонка для SubjTreeView
  class SubjTreeViewColumn < Gtk::TreeViewColumn
    attr_accessor :tab_ind
  end

  # ScrolledWindow for panobjects
  # RU: ScrolledWindow для объектов Пандоры
  class PanobjScrolledWindow < Gtk::ScrolledWindow
    attr_accessor :update_btn, :auto_btn, :arch_btn, :treeview, :filter_box

    def initialize
      super(nil, nil)
    end

    def update_treeview
      panobject = treeview.panobject
      store = treeview.model
      Gdk::Threads.synchronize do
        Gdk::Display.default.sync
        $window.mutex.synchronize do
          path, column = treeview.cursor
          id0 = nil
          if path
            iter = store.get_iter(path)
            id0 = iter[0]
          end
          #store.clear
          panobject.class.modified = false if panobject.class.modified
          filter = nil
          filter = filter_box.compose_filter
          if (not arch_btn.active?)
            del_bit = PandoraModel::PSF_Archive
            del_fil = 'IFNULL(panstate,0)&'+del_bit.to_s+'=0'
            if filter.nil?
              filter = del_fil
            else
              filter[0] << ' AND '+del_fil
            end
          end
          p 'select filter[sql,values]='+filter.inspect
          sel = panobject.select(filter, false, nil, panobject.sort)
          if sel
            treeview.sel = sel
            treeview.param_view_col = nil
            if ((panobject.kind==PandoraModel::PK_Parameter) \
            or (panobject.kind==PandoraModel::PK_Message)) and sel[0]
              treeview.param_view_col = sel[0].size
            end
            iter0 = nil
            sel.each_with_index do |row,i|
              #iter = store.append
              iter = store.get_iter(Gtk::TreePath.new(i))
              iter ||= store.append
              #store.set_value(iter, column, value)
              id = row[0].to_i
              iter[0] = id
              iter0 = iter if id0 and id and (id == id0)
              if treeview.param_view_col
                view = nil
                if (panobject.kind==PandoraModel::PK_Parameter)
                  type = panobject.field_val('type', row)
                  setting = panobject.field_val('setting', row)
                  ps = PandoraUtils.decode_param_setting(setting)
                  view = ps['view']
                  view ||= PandoraUtils.pantype_to_view(type)
                else
                  panstate = panobject.field_val('panstate', row)
                  if (panstate.is_a? Integer) and ((panstate & PandoraModel::PSF_Crypted)>0)
                    view = 'hex'
                  end
                end
                row[treeview.param_view_col] = view
              end
            end
            i = sel.size
            iter = store.get_iter(Gtk::TreePath.new(i))
            while iter
              store.remove(iter)
              iter = store.get_iter(Gtk::TreePath.new(i))
            end
            if treeview.sel.size>0
              if (not path) or (not store.get_iter(path)) \
              or (not store.iter_is_valid?(store.get_iter(path)))
                path = iter0.path if iter0
                path ||= Gtk::TreePath.new(treeview.sel.size-1)
              end
              treeview.set_cursor(path, nil, false)
              treeview.scroll_to_cell(path, nil, false, 0.0, 0.0)
            end
          end
        end
        p 'treeview is updated: '+panobject.ider
        treeview.grab_focus
      end
    end

  end

  # Filter box: field, operation and value
  # RU: Группа фильтра: поле, операция и значение
  class FilterHBox < Gtk::HBox
    attr_accessor :filters, :field_com, :oper_com, :val_entry, :logic_com, \
      :del_btn, :add_btn, :page_sw

    # Remove itself
    # RU: Удалить себя
    def delete
      @add_btn = nil
      if @filters.size>1
        parent.remove(self)
        filters.delete(self)
        last = filters[filters.size-1]
        #p [last, last.add_btn, filters.size-1]
        last.add_btn_to
      else
        field_com.entry.text = ''
        while children.size>1
          child = children[children.size-1]
          remove(child)
          child.destroy
        end
        @add_btn.destroy if @add_btn
        @add_btn = nil
        @oper_com = nil
      end
      first = filters[0]
      page_sw.filter_box = first
      if first and first.logic_com
        first.remove(first.logic_com)
        first.logic_com = nil
      end
      page_sw.update_treeview
    end

    def add_btn_to
      #p '---add_btn_to [add_btn, @add_btn]='+[add_btn, @add_btn].inspect
      if add_btn.nil? and (children.size>2)
        @add_btn = Gtk::ToolButton.new(Gtk::Stock::ADD, _('Add'))
        add_btn.tooltip_text = _('Add a new filter')
        add_btn.signal_connect('clicked') do |*args|
          FilterHBox.new(filters, parent, page_sw)
        end
        pack_start(add_btn, false, true, 0)
        add_btn.show_all
      end
    end

    # Compose filter with sql-query and raw values
    # RU: Составить фильтр с sql-запросом и сырыми значениями
    def compose_filter
      sql = nil
      values = nil
      @filters.each do |fb|
        fld = fb.field_com.entry.text
        if fb.oper_com and fb.val_entry
          oper = fb.oper_com.entry.text
          if fld and oper
            logic = nil
            logic = fb.logic_com.entry.text if fb.logic_com
            if not sql
              sql = ''
            else
              sql << ' '
              logic = 'AND' if (logic.nil? or (logic != 'OR'))
            end
            sql << logic+' ' if logic and (logic.size>0)
            val = fb.val_entry.text
            panobject = page_sw.treeview.panobject
            tab_flds = panobject.tab_fields
            tab_ind = tab_flds.index{ |tf| tf[0] == fld }
            if tab_ind
              fdesc = panobject.tab_fields[tab_ind][PandoraUtils::TI_Desc]
              view = type = nil
              if fdesc
                view = fdesc[PandoraUtils::FI_View]
                type = fdesc[PandoraUtils::FI_Type]
                val = PandoraUtils.view_to_val(val, type, view)
              elsif fld=='id'
                val = val.to_i
              end
              p '[val, type, view]='+[val, type, view].inspect
              if view.nil? and val.is_a?(String) and (val.index('*') or val.index('?'))
                PandoraUtils.correct_aster_and_quest!(val)
                fb.oper_com.entry.text = '=' if (oper != '=')
                oper = ' LIKE '
              elsif (view.nil? and val.nil?) or (val.is_a?(String) and val.size==0)
                fld = 'IFNULL('+fld+",'')"
                oper << "''"
                val = nil
              elsif val.nil? and (oper=='=')
                oper = ' IS NULL'
                val = nil
              end
              values ||= Array.new
              sql << fld + oper
              if not val.nil?
                sql << '?'
                values << val
              end
            end
          end
        end
      end
      values.insert(0, sql) if values
      values
    end

    def set_filter_by_str(logic, afilter)
      res = nil
      p 'set_filter_by_str(logic, afilter)='+[logic, afilter].inspect
      len = 1
      i = afilter.index('=')
      i ||= afilter.index('>')
      i ||= afilter.index('<')
      if not i
        i = afilter.index('<>')
        len = 2
      end
      if i
        fname = afilter[0, i]
        oper = afilter[i, len]
        val = afilter[i+len..-1]
        field_com.entry.text = fname
        oper_com.entry.text = oper
        val_entry.text = val
        logic_com.entry.text = logic if logic and logic_com
        res = true
      end
      res
    end

    def set_fix_filter(fix_filter, logic=nil)
      #p '== set_fix_filter  fix_filter='+fix_filter
      if fix_filter
        i = fix_filter.index(' AND ')
        j = fix_filter.index(' OR ')
        i = j if (i.nil? or ((not j.nil?) and (j>i)))
        if i
          afilter = fix_filter[0, i]
          fix_filter = fix_filter[i+1..-1]
        else
          afilter = fix_filter
          fix_filter = nil
        end
        setted = set_filter_by_str(logic, afilter)
        #p '--set_fix_filter [logic, afilter, fix_filter]='+[logic, afilter, fix_filter].inspect
        if fix_filter
          i = fix_filter.index(' ')
          logic = nil
          if i and i<4
            logic = fix_filter[0, i]
            fix_filter = fix_filter[i+1..-1]
          end
          if setted
            add_btn_to
            FilterHBox.new(filters, parent, page_sw)
          end
          next_fb = @filters[@filters.size-1]
          next_fb.set_fix_filter(fix_filter, logic)
        end
      end
    end

    # Create new instance
    # RU: Создать новый экземпляр
    def initialize(a_filters, hbox, a_page_sw)

      def no_filter_frase
        res = '<'+_('filter')+'>'
      end

      super()
      @page_sw = a_page_sw
      @filters = a_filters
      filter_box = self
      panobject = page_sw.treeview.panobject
      tab_flds = panobject.tab_fields
      def_flds = panobject.def_fields
      #def_flds.each do |df|
      #id = df[FI_Id]
      #tab_ind = tab_flds.index{ |tf| tf[0] == id }
      #if tab_ind
      #  renderer = Gtk::CellRendererText.new
        #renderer.background = 'red'
        #renderer.editable = true
        #renderer.text = 'aaa'

      #  title = df[FI_VFName]
      if @filters.size>0
        @logic_com = Gtk::Combo.new
        logic_com.set_popdown_strings(['AND', 'OR'])
        logic_com.entry.text = 'AND'
        logic_com.set_size_request(64, -1)
        filter_box.pack_start(logic_com, false, true, 0)
        prev = @filters[@filters.size-1]
        if prev and prev.add_btn
          prev.remove(prev.add_btn)
          prev.add_btn = nil
        end
      end

      fields = Array.new
      fields << no_filter_frase
      fields << 'lang'
      fields.concat(tab_flds.collect{|tf| tf[0]})
      @field_com = Gtk::Combo.new
      field_com.set_popdown_strings(fields)
      field_com.set_size_request(110, -1)

      field_com.entry.signal_connect('changed') do |entry|
        if filter_box.children.size>2
          if (entry.text == no_filter_frase) or (entry.text == '')
            delete
          end
          false
        elsif (entry.text != no_filter_frase) and (entry.text != '')
          @oper_com = Gtk::Combo.new
          oper_com.set_popdown_strings(['=','<>','>','<'])
          oper_com.set_size_request(56, -1)
          oper_com.entry.signal_connect('activate') do |*args|
            @val_entry.grab_focus
          end
          filter_box.pack_start(oper_com, false, true, 0)

          @del_btn = Gtk::ToolButton.new(Gtk::Stock::DELETE, _('Delete'))
          del_btn.tooltip_text = _('Delete this filter')
          del_btn.signal_connect('clicked') do |*args|
            delete
          end
          filter_box.pack_start(del_btn, false, true, 0)

          @val_entry = Gtk::Entry.new
          val_entry.set_size_request(120, -1)
          filter_box.pack_start(val_entry, false, true, 0)
          val_entry.signal_connect('focus-out-event') do |widget, event|
            page_sw.update_treeview
            false
          end

          add_btn_to
          filter_box.show_all
        end
      end
      filter_box.pack_start(field_com, false, true, 0)

      filter_box.show_all
      hbox.pack_start(filter_box, false, true, 0)

      @filters << filter_box

      p '@filters='+@filters.inspect

      filter_box
    end
  end

  # Showing panobject list
  # RU: Показ списка панобъектов
  def self.show_panobject_list(panobject_class, widget=nil, page_sw=nil, \
  auto_create=false, fix_filter=nil)
    notebook = $window.notebook
    single = (page_sw == nil)
    if single
      notebook.children.each do |child|
        if (child.is_a? PanobjScrolledWindow) and (child.name==panobject_class.ider)
          notebook.page = notebook.children.index(child)
          #child.update_if_need
          return nil
        end
      end
    end
    panobject = panobject_class.new
    store = Gtk::ListStore.new(Integer)
    treeview = SubjTreeView.new(store)
    treeview.name = panobject.ider
    treeview.panobject = panobject

    tab_flds = panobject.tab_fields
    def_flds = panobject.def_fields

    its_blob = (panobject.is_a? PandoraModel::Blob)
    if its_blob or (panobject.is_a? PandoraModel::Person)
      renderer = Gtk::CellRendererPixbuf.new
      #renderer.pixbuf = $window.get_icon_buf('smile')
      column = SubjTreeViewColumn.new(_('View'), renderer)
      column.resizable = true
      column.reorderable = true
      column.clickable = true
      column.fixed_width = 45
      column.tab_ind = tab_flds.index{ |tf| tf[0] == 'panhash' }
      #p '//////////column.tab_ind='+column.tab_ind.inspect
      treeview.append_column(column)

      column.set_cell_data_func(renderer) do |tvc, renderer, model, iter|
        row = nil
        begin
          if model.iter_is_valid?(iter) and iter and iter.path
            row = tvc.tree_view.sel[iter.path.indices[0]]
          end
        rescue
          p 'rescue'
        end
        val = nil
        if row
          col = tvc.tab_ind
          val = row[col] if col
        end
        if val
          #p '[col, val]='+[col, val].inspect
          pixbuf = PandoraModel.get_avatar_icon(val, tvc.tree_view, its_blob, 45)
          pixbuf = nil if pixbuf==false
          renderer.pixbuf = pixbuf
        end
      end

    end

    def_flds.each do |df|
      id = df[FI_Id]
      tab_ind = tab_flds.index{ |tf| tf[0] == id }
      if tab_ind
        renderer = Gtk::CellRendererText.new
        #renderer.background = 'red'
        #renderer.editable = true
        #renderer.text = 'aaa'

        title = df[FI_VFName]
        title ||= v
        column = SubjTreeViewColumn.new(title, renderer )  #, {:text => i}

        #p v
        #p ind = panobject.def_fields.index_of {|f| f[0]==v }
        #p fld = panobject.def_fields[ind]

        column.tab_ind = tab_ind
        #column.sort_column_id = ind
        #p column.ind = i
        #p column.fld = fld
        #panhash_col = i if (v=='panhash')
        column.resizable = true
        column.reorderable = true
        column.clickable = true
        treeview.append_column(column)
        column.signal_connect('clicked') do |col|
          p 'sort clicked'
        end
        column.set_cell_data_func(renderer) do |tvc, renderer, model, iter|
          row = nil
          begin
            if model.iter_is_valid?(iter) and iter and iter.path
              row = tvc.tree_view.sel[iter.path.indices[0]]
            end
          rescue
          end
          color = 'black'
          val = nil
          if row
            col = tvc.tab_ind
            val = row[col]
          end
          if val
            panobject = tvc.tree_view.panobject
            fdesc = panobject.tab_fields[col][TI_Desc]
            if fdesc.is_a? Array
              view = nil
              if tvc.tree_view.param_view_col and ((fdesc[FI_Id]=='value') or (fdesc[FI_Id]=='text'))
                view = row[tvc.tree_view.param_view_col] if row
              else
                view = fdesc[FI_View]
              end
              val, color = PandoraUtils.val_to_view(val, nil, view, false)
            else
              val = val.to_s
            end
            val = val[0,46]
          end
          renderer.foreground = color
          val ||= ''
          renderer.text = val
        end
      else
        p 'Field ['+id.inspect+'] is not found in table ['+panobject.ider+']'
      end
    end

    treeview.signal_connect('row_activated') do |tree_view, path, column|
      dialog = page_sw.parent.parent.parent
      if dialog and (dialog.is_a? AdvancedDialog) and dialog.okbutton
        dialog.okbutton.activate
      else
        if (panobject.is_a? PandoraModel::Person)
          act_panobject(tree_view, 'Dialog')
        else
          act_panobject(tree_view, 'Edit')
        end
      end
    end

    list_sw = Gtk::ScrolledWindow.new(nil, nil)
    list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
    list_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    list_sw.border_width = 0
    list_sw.add(treeview)

    pbox = Gtk::VBox.new

    page_sw ||= PanobjScrolledWindow.new
    page_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    page_sw.border_width = 0
    page_sw.add_with_viewport(pbox)
    page_sw.children[0].shadow_type = Gtk::SHADOW_NONE # Gtk::SHADOW_ETCHED_IN

    page_sw.name = panobject.ider
    page_sw.treeview = treeview
    treeview.page_sw = page_sw

    hbox = Gtk::HBox.new

    PandoraGtk.add_tool_btn(hbox, Gtk::Stock::ADD, 'Create') do |widget|  #:NEW
      $window.do_menu_act('Create', treeview)
    end
    chat_stock = :chat
    chat_item = 'Chat'
    if (panobject.is_a? PandoraModel::Person)
      chat_stock = :dialog
      chat_item = 'Dialog'
    end
    if single
      PandoraGtk.add_tool_btn(hbox, chat_stock, chat_item) do |widget|
        $window.do_menu_act(chat_item, treeview)
      end
      PandoraGtk.add_tool_btn(hbox, :opinion, 'Opinions') do |widget|
        $window.do_menu_act('Opinion', treeview)
      end
    end
    page_sw.update_btn = PandoraGtk.add_tool_btn(hbox, Gtk::Stock::REFRESH, 'Update') do |widget|
      page_sw.update_treeview
    end
    page_sw.auto_btn = nil
    if single
      page_sw.auto_btn = PandoraGtk.add_tool_btn(hbox, :update, 'Auto update', true) do |widget|
        update_treeview_if_need(page_sw)
      end
    end
    page_sw.arch_btn = PandoraGtk.add_tool_btn(hbox, :arch, 'Show archived', false) do |widget|
      page_sw.update_btn.clicked
    end

    filters = Array.new
    page_sw.filter_box = FilterHBox.new(filters, hbox, page_sw)
    page_sw.filter_box.set_fix_filter(fix_filter) if fix_filter

    pbox.pack_start(hbox, false, true, 0)
    pbox.pack_start(list_sw, true, true, 0)

    page_sw.update_btn.clicked

    if auto_create and treeview.sel and (treeview.sel.size==0)
      treeview.auto_create = true
      treeview.signal_connect('map') do |widget, event|
        if treeview.auto_create
          act_panobject(treeview, 'Create')
          treeview.auto_create = false
        end
      end
      auto_create = false
    end

    edit_opt = ':m'
    dlg_opt = ':m'
    if single
      if (panobject.is_a? PandoraModel::Person)
        dlg_opt << 'b'
      else
        edit_opt << 'b'
      end
      image = $window.get_panobject_image(panobject_class.ider, Gtk::IconSize::SMALL_TOOLBAR)
      #p 'single: widget='+widget.inspect
      #if widget.is_a? Gtk::ImageMenuItem
      #  animage = widget.image
      #elsif widget.is_a? Gtk::ToolButton
      #  animage = widget.icon_widget
      #else
      #  animage = nil
      #end
      #image = nil
      #if animage
      #  if animage.stock
      #    image = Gtk::Image.new(animage.stock, Gtk::IconSize::MENU)
      #    image.set_padding(2, 0)
      #  else
      #    image = Gtk::Image.new(animage.icon_set, Gtk::IconSize::MENU)
      #    image.set_padding(2, 0)
      #  end
      #end
      image.set_padding(2, 0)

      label_box = TabLabelBox.new(image, panobject.pname, page_sw) do
        store.clear
        treeview.destroy
      end

      page = notebook.append_page(page_sw, label_box)
      notebook.set_tab_reorderable(page_sw, true)
      page_sw.show_all
      notebook.page = notebook.n_pages-1

      #pbox.update_if_need

      treeview.grab_focus
    end

    menu = Gtk::Menu.new
    menu.append(create_menu_item(['Create', Gtk::Stock::ADD, _('Create'), 'Insert'], treeview))  #:NEW
    menu.append(create_menu_item(['Edit', Gtk::Stock::EDIT.to_s+edit_opt, _('Edit'), 'Return'], treeview))
    menu.append(create_menu_item(['Delete', Gtk::Stock::DELETE, _('Delete'), 'Delete'], treeview))
    menu.append(create_menu_item(['Copy', Gtk::Stock::COPY, _('Copy'), '<control>Insert'], treeview))
    menu.append(create_menu_item(['-', nil, nil], treeview))
    menu.append(create_menu_item([chat_item, chat_stock.to_s+dlg_opt, _(chat_item), '<control>D'], treeview))
    menu.append(create_menu_item(['Relation', :relation, _('Relate'), '<control>R'], treeview))
    menu.append(create_menu_item(['Connect', Gtk::Stock::CONNECT, _('Connect'), '<control>N'], treeview))
    menu.append(create_menu_item(['-', nil, nil], treeview))
    menu.append(create_menu_item(['Convert', Gtk::Stock::CONVERT, _('Convert')], treeview))
    menu.append(create_menu_item(['Import', Gtk::Stock::OPEN, _('Import')], treeview))
    menu.append(create_menu_item(['Export', Gtk::Stock::SAVE, _('Export')], treeview))
    menu.show_all

    treeview.add_events(Gdk::Event::BUTTON_PRESS_MASK)
    treeview.signal_connect('button-press-event') do |widget, event|
      if (event.button == 3)
        menu.popup(nil, nil, event.button, event.time)
      end
    end

    treeview.signal_connect('key-press-event') do |widget, event|
      res = true
      if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
        act_panobject(treeview, 'Edit')
        #act_panobject(treeview, 'Dialog')
      elsif (event.keyval==Gdk::Keyval::GDK_Insert)
        if event.state.control_mask?
          act_panobject(treeview, 'Copy')
        else
          act_panobject(treeview, 'Create')
        end
      elsif (event.keyval==Gdk::Keyval::GDK_Delete)
        act_panobject(treeview, 'Delete')
      elsif event.state.control_mask?
        if [Gdk::Keyval::GDK_d, Gdk::Keyval::GDK_D, 1751, 1783].include?(event.keyval)
          act_panobject(treeview, 'Dialog')
        else
          res = false
        end
      else
        res = false
      end
      res
    end
    auto_create
  end

  # Update period for treeview tables
  # RU: Период обновления для таблиц
  TAB_UPD_PERIOD = 2   #second

  $treeview_thread = nil

  # Launch update thread for a table of the panobjbox
  # RU: Запускает поток обновления таблицы панобъекта
  def self.update_treeview_if_need(panobjbox=nil)
    if $treeview_thread
      $treeview_thread.exit if $treeview_thread.alive?
      $treeview_thread = nil
    end
    if (panobjbox.is_a? PanobjScrolledWindow) and panobjbox.auto_btn and panobjbox.auto_btn.active?
      $treeview_thread = Thread.new do
        while panobjbox and (not panobjbox.destroyed?) and panobjbox.treeview \
        and (not panobjbox.treeview.destroyed?) and $window.visible?
          #p 'update_treeview_if_need: '+panobjbox.treeview.panobject.ider
          if panobjbox.treeview.panobject.class.modified
            #p 'update_treeview_if_need: modif='+panobjbox.treeview.panobject.class.modified.inspect
            #panobjbox.update_btn.clicked
            panobjbox.update_treeview
          end
          sleep(TAB_UPD_PERIOD)
        end
        $treeview_thread = nil
      end
    end
  end

  $media_buf_size = 50
  $send_media_queues = []
  $send_media_rooms = {}

  # Take pointer index for sending by room
  # RU: Взять индекс указателя для отправки по id комнаты
  def self.set_send_ptrind_by_panhash(room_id)
    ptr = nil
    if room_id
      ptr = $send_media_rooms[room_id]
      if ptr
        ptr[0] = true
        ptr = ptr[1]
      else
        ptr = $send_media_rooms.size
        $send_media_rooms[room_id] = [true, ptr]
      end
    end
    ptr
  end

  # Check pointer index for sending by room
  # RU: Проверить индекс указателя для отправки по id комнаты
  def self.get_send_ptrind_by_panhash(room_id)
    ptr = nil
    if room_id
      set_ptr = $send_media_rooms[room_id]
      if set_ptr and set_ptr[0]
        ptr = set_ptr[1]
      end
    end
    ptr
  end

  # Clear pointer index for sending for room
  # RU: Сбросить индекс указателя для отправки для комнаты
  def self.nil_send_ptrind_by_panhash(room_id)
    if room_id
      ptr = $send_media_rooms[room_id]
      if ptr
        ptr[0] = false
      end
    end
    res = $send_media_rooms.count{ |panhas, ptr| ptr[0] }
  end

  $key_watch_lim   = 5
  $sign_watch_lim  = 5

  # Get person panhash by any panhash
  # RU: Получить панхэш персоны по произвольному панхэшу
  def self.extract_targets_from_panhash(targets, panhashes=nil)
    persons, keys, nodes = targets
    if panhashes
      panhashes = [panhashes] if panhashes.is_a? String
      #p '--extract_targets_from_panhash  targets='+targets.inspect
      panhashes.each do |panhash|
        if (panhash.is_a? String) and (panhash.bytesize>0)
          kind = PandoraUtils.kind_from_panhash(panhash)
          panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
          if panobjectclass
            if panobjectclass <= PandoraModel::Person
              persons << panhash
            elsif panobjectclass <= PandoraModel::Node
              nodes << panhash
            else
              if panobjectclass <= PandoraModel::Created
                model = PandoraUtils.get_model(panobjectclass.ider)
                filter = {:panhash=>panhash}
                sel = model.select(filter, false, 'creator')
                if sel and sel.size>0
                  sel.each do |row|
                    persons << row[0]
                  end
                end
              end
            end
          end
        end
      end
    end
    persons.uniq!
    persons.compact!
    if (keys.size == 0) and (nodes.size > 0)
      nodes.uniq!
      nodes.compact!
      model = PandoraUtils.get_model('Node')
      nodes.each do |node|
        sel = model.select({:panhash=>node}, false, 'key_hash')
        if sel and (sel.size>0)
          sel.each do |row|
            keys << row[0]
          end
        end
      end
    end
    keys.uniq!
    keys.compact!
    if (persons.size == 0) and (keys.size > 0)
      kmodel = PandoraUtils.get_model('Key')
      smodel = PandoraUtils.get_model('Sign')
      keys.each do |key|
        sel = kmodel.select({:panhash=>key}, false, 'creator', 'modified DESC', $key_watch_lim)
        if sel and (sel.size>0)
          sel.each do |row|
            persons << row[0]
          end
        end
        sel = smodel.select({:key_hash=>key}, false, 'creator', 'modified DESC', $sign_watch_lim)
        if sel and (sel.size>0)
          sel.each do |row|
            persons << row[0]
          end
        end
      end
      persons.uniq!
      persons.compact!
    end
    if nodes.size == 0
      model = PandoraUtils.get_model('Key')
      persons.each do |person|
        sel = model.select({:creator=>person}, false, 'panhash', 'modified DESC', $key_watch_lim)
        if sel and (sel.size>0)
          sel.each do |row|
            keys << row[0]
          end
        end
      end
      if keys.size == 0
        model = PandoraUtils.get_model('Sign')
        persons.each do |person|
          sel = model.select({:creator=>person}, false, 'key_hash', 'modified DESC', $sign_watch_lim)
          if sel and (sel.size>0)
            sel.each do |row|
              keys << row[0]
            end
          end
        end
      end
      keys.uniq!
      keys.compact!
      model = PandoraUtils.get_model('Node')
      keys.each do |key|
        sel = model.select({:key_hash=>key}, false, 'panhash')
        if sel and (sel.size>0)
          sel.each do |row|
            nodes << row[0]
          end
        end
      end
      #p '[keys, nodes]='+[keys, nodes].inspect
      #p 'targets3='+targets.inspect
    end
    nodes.uniq!
    nodes.compact!
    nodes.size
  end

  def self.extract_from_panhash(panhash, node_id=nil)
    targets = [[], [], []]
    persons, keys, nodes = targets
    #if nodehash and (panhashes.is_a? String)
    #  persons << panhashes
    #  nodes << nodehash
    #else
      extract_targets_from_panhash(targets, panhash)
    #end
    targets.each do |list|
      list.sort!
      list.uniq!
      list.compact!
    end
    p 'targets='+[targets].inspect

    target_exist = ((persons.size>0) or (nodes.size>0) or (keys.size>0))
    if (not target_exist) and node_id
      node_model = PandoraUtils.get_model('Node', models)
      sel = node_model.select({:id => node_id}, false, 'panhash, key_hash', nil, 1)
      if sel and (sel.size>0)
        sel.each do |row|
          nodes << row[0]
          keys  << row[1]
        end
        extract_targets_from_panhash(targets)
      end
    end
    targets
  end

  # Find active sender
  # RU: Найти активного отправителя
  def self.find_another_active_sender(not_this=nil)
    res = nil
    $window.notebook.children.each do |child|
      if (child != not_this) and (child.is_a? CabinetBox) \
      and child.webcam_btn and child.webcam_btn.active?
        return child
      end
    end
    res
  end

  # Get view parameters
  # RU: Взять параметры вида
  def self.get_view_params
    $load_history_count = PandoraUtils.get_param('load_history_count')
    $sort_history_mode = PandoraUtils.get_param('sort_history_mode')
  end

  # Get main parameters
  # RU: Взять основные параметры
  def self.get_main_params
    get_view_params
  end

  # About dialog hooks
  # RU: Обработчики диалога "О программе"
  Gtk::AboutDialog.set_url_hook do |about, link|
    PandoraUtils.external_open(link)
  end
  Gtk::AboutDialog.set_email_hook do |about, link|
    PandoraUtils.external_open(link)
  end

  # Calc hex md5 of Pandora files
  # RU: Вычисляет шестнадцатиричный md5 файлов Пандоры
  def self.pandora_md5_sum
    res = nil
    begin
      md5 = Digest::MD5.file(PandoraUtils.main_script)
      res = md5.digest
    rescue
    end
    ['crypto', 'gtk', 'model', 'net', 'utils'].each do |alib|
      begin
        md5 = Digest::MD5.file(File.join($pandora_lib_dir, alib+'.rb'))
        res2 = md5.digest
        i = 0
        res2.each_byte do |c|
          res[i] = (c ^ res[i].ord).chr
          i += 1
        end
      rescue
      end
    end
    if (res.is_a? String)
      res = PandoraUtils.bytes_to_hex(res)
    else
      res = 'fail'
    end
    res
  end

  # Show About dialog
  # RU: Показ окна "О программе"
  def self.show_about
    dlg = Gtk::AboutDialog.new
    dlg.transient_for = $window
    dlg.icon = $window.icon
    dlg.name = $window.title
    dlg.version = PandoraVersion + ' [' + pandora_md5_sum[0, 6] + ']'
    dlg.logo = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'pandora.png'))
    dlg.authors = ['© '+_('Michael Galyuk')+' <robux@mail.ru>']
    #dlg.documenters = dlg.authors
    #dlg.translator_credits = dlg.authors.join("\n")
    dlg.artists = ['© '+_('Rights to logo are owned by 21th Century Fox')]
    dlg.comments = _('P2P folk network')
    dlg.copyright = _('Free software')+' 2012, '+_('Michael Galyuk')
    begin
      file = File.open(File.join($pandora_app_dir, 'LICENSE.TXT'), 'r')
      gpl_text = '================='+_('Full text')+" LICENSE.TXT==================\n"+file.read
      file.close
    rescue
      gpl_text = _('Full text is in the file')+' LICENSE.TXT.'
    end
    dlg.license = _("Pandora is licensed under GNU GPLv2.\n"+
      "\nFundamentals:\n"+
      "- program code is open, distributed free and without warranty;\n"+
      "- author does not require you money, but demands respect authorship;\n"+
      "- you can change the code, sent to the authors for inclusion in the next release;\n"+
      "- your own release you must distribute with another name and only licensed under GPL;\n"+
      "- if you do not understand the GPL or disagree with it, you have to uninstall the program.\n\n")+gpl_text
    dlg.website = 'https://github.com/Novator/Pandora'
    dlg.program_name = dlg.name
    dlg.skip_taskbar_hint = true
    dlg.signal_connect('key-press-event') do |widget, event|
      if [Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
        event.keyval) and event.state.control_mask? #w, W, ц, Ц
      then
        widget.response(Gtk::Dialog::RESPONSE_CANCEL)
        false
      elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
        event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
        Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
        and event.state.control_mask?) #q, Q, й, Й
      then
        widget.destroy
        $window.do_menu_act('Quit')
        false
      else
        false
      end
    end
    dlg.run
    if not dlg.destroyed?
      dlg.destroy
      $window.present
    end
  end

  # Show capcha
  # RU: Показать капчу
  def self.show_captcha(captcha_buf=nil, clue_text=nil, conntype=nil, node=nil, \
  node_id=nil, models=nil, panhashes=nil, session=nil)
    res = nil
    sw = nil
    p '--recognize_captcha(captcha_buf.size, clue_text, node, node_id, models)='+\
      [captcha_buf.size, clue_text, node, node_id, models].inspect
    if captcha_buf
      sw = PandoraGtk.show_cabinet(panhashes, session, conntype, node_id, \
        models, CPI_Dialog)
      if sw
        clue_text ||= ''
        clue, length, symbols = clue_text.split('|')
        node_text = node
        pixbuf_loader = Gdk::PixbufLoader.new
        pixbuf_loader.last_write(captcha_buf)
        pixbuf = pixbuf_loader.pixbuf

        sw.init_captcha_entry(pixbuf, length, symbols, clue, node_text)

        sw.captcha_enter = true
        while (not sw.destroyed?) and (sw.captcha_enter.is_a? TrueClass)
          sleep(0.02)
          Thread.pass
        end
        p '===== sw.captcha_enter='+sw.captcha_enter.inspect
        if sw.destroyed?
          res = false
        else
          if (sw.captcha_enter.is_a? String)
            res = sw.captcha_enter.dup
          else
            res = sw.captcha_enter
          end
          sw.captcha_enter = nil
        end
      end

      #captcha_entry = PandoraGtk::MaskEntry.new
      #captcha_entry.max_length = len
      #if symbols
      #  mask = symbols.downcase+symbols.upcase
      #  captcha_entry.mask = mask
      #end
    end
    [res, sw]
  end

  # Show panobject cabinet
  # RU: Показать кабинет панобъекта
  def self.show_cabinet(panhash, session=nil, conntype=nil, \
  node_id=nil, models=nil, page=nil, fields=nil, obj_id=nil, edit=nil)
    sw = nil

    p '---show_cabinet(panhash, session.id, conntype, node_id, models, page, fields, obj_id, edit)=' \
      +[panhash, session.object_id, conntype, node_id, models, page, fields, obj_id, edit].inspect

    room_id = AsciiString.new(PandoraUtils.fill_zeros_from_right(panhash, \
      PandoraModel::PanhashSize)).dup if panhash
    #room_id ||= session.object_id if session

    if conntype.nil? or (conntype==PandoraNet::ST_Hunter)
      creator = PandoraCrypto.current_user_or_key(true)
      #room_id[-1] = (room_id[-1].ord ^ 1).chr if panhash==creator
    end
    p 'room_id='+room_id.inspect
    $window.notebook.children.each do |child|
      if ((child.is_a? CabinetBox) and ((child.room_id==room_id) \
      or (session and (child.session==session))))
        #child.targets = targets
        #child.online_btn.safe_set_active(nodehash != nil)
        #child.online_btn.inconsistent = false
        $window.notebook.page = $window.notebook.children.index(child) if conntype.nil?
        sw = child
        sw.show_page(page) if page
        break
      end
    end
    sw ||= CabinetBox.new(panhash, room_id, page, fields, obj_id, edit, session)
    sw
  end

  # Showing search panel
  # RU: Показать панель поиска
  def self.show_search_panel(text=nil)
    sw = SearchBox.new(text)

    image = Gtk::Image.new(Gtk::Stock::FIND, Gtk::IconSize::SMALL_TOOLBAR)
    image.set_padding(2, 0)

    label_box = TabLabelBox.new(image, _('Search'), sw) do
      #store.clear
      #treeview.destroy
      #sw.destroy
    end

    page = $window.notebook.append_page(sw, label_box)
    $window.notebook.set_tab_reorderable(sw, true)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Show profile panel
  # RU: Показать панель профиля
  def self.show_profile_panel(a_person=nil)
    a_person0 = a_person
    a_person ||= PandoraCrypto.current_user_or_key(true, true)

    return if not a_person

    $window.notebook.children.each do |child|
      if (child.is_a? ProfileScrollWin) and (child.person == a_person)
        $window.notebook.page = $window.notebook.children.index(child)
        return
      end
    end

    page = $window.notebook.append_page(sw, label_box)
    $window.notebook.set_tab_reorderable(sw, true)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Show session list
  # RU: Показать список сеансов
  def self.show_session_panel
    $window.notebook.children.each do |child|
      if (child.is_a? SessionScrollWin)
        $window.notebook.page = $window.notebook.children.index(child)
        child.update_btn.clicked
        return
      end
    end
    sw = SessionScrollWin.new

    image = Gtk::Image.new(:session, Gtk::IconSize::SMALL_TOOLBAR)
    image.set_padding(2, 0)
    label_box = TabLabelBox.new(image, _('Sessions'), sw) do
      #sw.destroy
    end
    page = $window.notebook.append_page(sw, label_box)
    $window.notebook.set_tab_reorderable(sw, true)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Show neighbor list
  # RU: Показать список соседей
  def self.show_radar_panel
    hpaned = $window.radar_hpaned
    radar_sw = $window.radar_sw
    if radar_sw.allocation.width <= 24 #hpaned.position <= 20
      radar_sw.width_request = 200 if radar_sw.width_request <= 24
      hpaned.position = hpaned.max_position-radar_sw.width_request
      radar_sw.update_btn.clicked
    else
      radar_sw.width_request = radar_sw.allocation.width
      hpaned.position = hpaned.max_position
    end
    $window.correct_fish_btn_state
    #$window.notebook.children.each do |child|
    #  if (child.is_a? RadarScrollWin)
    #    $window.notebook.page = $window.notebook.children.index(child)
    #    child.update_btn.clicked
    #    return
    #  end
    #end
    #sw = RadarScrollWin.new

    #image = Gtk::Image.new(Gtk::Stock::JUSTIFY_LEFT, Gtk::IconSize::MENU)
    #image.set_padding(2, 0)
    #label_box = TabLabelBox.new(image, _('Fishes'), sw, false, 0) do
    #  #sw.destroy
    #end
    #page = $window.notebook.append_page(sw, label_box)
    #sw.show_all
    #$window.notebook.page = $window.notebook.n_pages-1
  end

  # Switch full screen mode
  # RU: Переключить режим полного экрана
  def self.full_screen_switch
    need_show = (not $window.menubar.visible?)
    $window.menubar.visible = need_show
    $window.toolbar.visible = need_show
    $window.notebook.show_tabs = need_show
    $window.log_sw.visible = need_show
    $window.radar_sw.visible = need_show
    @last_cur_page_toolbar ||= nil
    if @last_cur_page_toolbar and (not @last_cur_page_toolbar.destroyed?)
      if need_show and (not @last_cur_page_toolbar.visible?)
        @last_cur_page_toolbar.visible = true
      end
      @last_cur_page_toolbar = nil
    end
    page = $window.notebook.page
    if (page >= 0)
      cur_page = $window.notebook.get_nth_page(page)
      if (cur_page.is_a? PandoraGtk::CabinetBox) and cur_page.toolbar_box
        if need_show
          cur_page.toolbar_box.visible = true if (not cur_page.toolbar_box.visible?)
        elsif PandoraGtk.is_ctrl_shift_alt?(true) and cur_page.toolbar_box.visible?
          cur_page.toolbar_box.visible = false
          @last_cur_page_toolbar = cur_page.toolbar_box
        end
      end
    end
    $window.set_status_field(PandoraGtk::SF_FullScr, nil, nil, (not need_show))
  end

  # Show log bar
  # RU: Показать log бар
  def self.show_log_bar(new_size=nil)
    vpaned = $window.log_vpaned
    log_sw = $window.log_sw
    if new_size and (new_size>=0) or (new_size.nil? \
    and (log_sw.allocation.height <= 24)) #hpaned.position <= 20
      if new_size and (new_size>=24)
        log_sw.height_request = new_size if (new_size>log_sw.height_request)
      else
        log_sw.height_request = log_sw.allocation.height if log_sw.allocation.height>24
        log_sw.height_request = 200 if (log_sw.height_request <= 24)
      end
      vpaned.position = vpaned.max_position-log_sw.height_request
    else
      log_sw.height_request = log_sw.allocation.height
      vpaned.position = vpaned.max_position
    end
    $window.correct_log_btn_state
  end

  # Show fisher list
  # RU: Показать список рыбаков
  def self.show_fisher_panel
    $window.notebook.children.each do |child|
      if (child.is_a? FisherScrollWin)
        $window.notebook.page = $window.notebook.children.index(child)
        child.update_btn.clicked
        return
      end
    end
    sw = FisherScrollWin.new

    image = Gtk::Image.new(:fish, Gtk::IconSize::SMALL_TOOLBAR)
    image.set_padding(2, 0)
    label_box = TabLabelBox.new(image, _('Fishers'), sw) do
      #sw.destroy
    end
    page = $window.notebook.append_page(sw, label_box)
    $window.notebook.set_tab_reorderable(sw, true)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Set bold weight of MenuItem
  # RU: Ставит жирный шрифт у MenuItem
  def self.set_bold_to_menuitem(menuitem)
    label = menuitem.children[0]
    if (label.is_a? Gtk::Label)
      text = label.text
      if text and (not text.include?('<b>'))
        label.use_markup = true
        label.set_markup('<b>'+text+'</b>') if label.use_markup?
      end
    end
  end

  # Status icon
  # RU: Иконка в трее
  class PandoraStatusIcon < Gtk::StatusIcon
    attr_accessor :main_icon, :play_sounds, :online, :hide_on_minimize, :message

    # Create status icon
    # RU: Создает иконку в трее
    def initialize(a_update_win_icon=false, a_flash_on_new=true, \
    a_flash_interval=0, a_play_sounds=true, a_hide_on_minimize=true)
      super()

      @online = false
      @main_icon = nil
      if $window.icon
        @main_icon = $window.icon
      else
        @main_icon = $window.render_icon(Gtk::Stock::HOME, Gtk::IconSize::LARGE_TOOLBAR)
      end
      @base_icon = @main_icon

      @online_icon = nil
      begin
        @online_icon = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'online.ico'))
      rescue Exception
      end
      if not @online_icon
        @online_icon = $window.render_icon(Gtk::Stock::INFO, Gtk::IconSize::LARGE_TOOLBAR)
      end

      begin
        @message_icon = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'message.ico'))
      rescue Exception
      end
      if not @message_icon
        @message_icon = $window.render_icon(Gtk::Stock::MEDIA_PLAY, Gtk::IconSize::LARGE_TOOLBAR)
      end

      @update_win_icon = a_update_win_icon
      @flash_on_new = a_flash_on_new
      @flash_interval = (a_flash_interval.to_f*1000).round
      @flash_interval = 800 if (@flash_interval<100)
      @play_sounds = a_play_sounds
      @hide_on_minimize = a_hide_on_minimize

      @message = nil
      @flash = false
      @flash_status = 0
      update_icon

      atitle = $window.title
      set_title(atitle)
      set_tooltip(atitle)

      #set_blinking(true)
      signal_connect('activate') do
        icon_activated
      end

      signal_connect('popup-menu') do |widget, button, activate_time|
        @menu ||= create_menu
        @menu.popup(nil, nil, button, activate_time)
      end
    end

    # Create and show popup menu
    # RU: Создает и показывает всплывающее меню
    def create_menu
      menu = Gtk::Menu.new

      checkmenuitem = Gtk::CheckMenuItem.new(_('Flash on new'))
      checkmenuitem.active = @flash_on_new
      checkmenuitem.signal_connect('activate') do |w|
        @flash_on_new = w.active?
        set_message(@message)
      end
      menu.append(checkmenuitem)

      checkmenuitem = Gtk::CheckMenuItem.new(_('Update window icon'))
      checkmenuitem.active = @update_win_icon
      checkmenuitem.signal_connect('activate') do |w|
        @update_win_icon = w.active?
        $window.icon = @base_icon
      end
      menu.append(checkmenuitem)

      checkmenuitem = Gtk::CheckMenuItem.new(_('Play sounds'))
      checkmenuitem.active = @play_sounds
      checkmenuitem.signal_connect('activate') do |w|
        @play_sounds = w.active?
      end
      menu.append(checkmenuitem)

      checkmenuitem = Gtk::CheckMenuItem.new(_('Hide on minimize'))
      checkmenuitem.active = @hide_on_minimize
      checkmenuitem.signal_connect('activate') do |w|
        @hide_on_minimize = w.active?
      end
      menu.append(checkmenuitem)

      menuitem = Gtk::ImageMenuItem.new(Gtk::Stock::PROPERTIES)
      alabel = menuitem.children[0]
      alabel.set_text(_('All parameters')+'..', true)
      menuitem.signal_connect('activate') do |w|
        icon_activated(false, true)
        PandoraGtk.show_panobject_list(PandoraModel::Parameter, nil, nil, true)
      end
      menu.append(menuitem)

      menuitem = Gtk::SeparatorMenuItem.new
      menu.append(menuitem)

      menuitem = Gtk::MenuItem.new(_('Show/Hide'))
      PandoraGtk.set_bold_to_menuitem(menuitem)
      menuitem.signal_connect('activate') do |w|
        icon_activated(false)
      end
      menu.append(menuitem)

      menuitem = Gtk::ImageMenuItem.new(Gtk::Stock::QUIT)
      alabel = menuitem.children[0]
      alabel.set_text(_('_Quit'), true)
      menuitem.signal_connect('activate') do |w|
        self.set_visible(false)
        $window.destroy
      end
      menu.append(menuitem)

      menu.show_all
      menu
    end

    # Set status "online"
    # RU: Задаёт статус "онлайн"
    def set_online(state=nil)
      base_icon0 = @base_icon
      if state
        @base_icon = @online_icon
      elsif state==false
        @base_icon = @main_icon
      end
      update_icon
    end

    # Set status "message comes"
    # RU: Задаёт статус "есть сообщение"
    def set_message(message=nil)
      if (message.is_a? String) and (message.size>0)
        @message = message
        set_tooltip(message)
        set_flash(@flash_on_new)
      else
        @message = nil
        set_tooltip($window.title)
        set_flash(false)
      end
    end

    # Set flash mode
    # RU: Задаёт мигание
    def set_flash(flash=true)
      @flash = flash
      if flash
        @flash_status = 1
        if not @timer
          timeout_func
        end
      else
        @flash_status = 0
      end
      update_icon
    end

    # Update icon
    # RU: Обновляет иконку
    def update_icon
      stat_icon = nil
      if @message and ((not @flash) or (@flash_status==1))
        stat_icon = @message_icon
      else
        stat_icon = @base_icon
      end
      self.pixbuf = stat_icon if (self.pixbuf != stat_icon)
      if @update_win_icon
        $window.icon = stat_icon if $window.visible? and ($window.icon != stat_icon)
      else
        $window.icon = @main_icon if ($window.icon != @main_icon)
      end
    end

    # Set timer on a flash step
    # RU: Ставит таймер на шаг мигания
    def timeout_func
      @timer = GLib::Timeout.add(@flash_interval) do
        next_step = true
        if @flash_status == 0
          @flash_status = 1
        else
          @flash_status = 0
          next_step = false if not @flash
        end
        update_icon
        @timer = nil if not next_step
        next_step
      end
    end

    # Action on icon click
    # RU: Действия при нажатии на иконку
    def icon_activated(top_sens=true, force_show=false)
      #$window.skip_taskbar_hint = false
      if $window.visible? and (not force_show)
        if (not top_sens) or ($window.has_toplevel_focus? or (PandoraUtils.os_family=='windows'))
          $window.hide
        else
          $window.do_menu_act('Activate')
        end
      else
        $window.do_menu_act('Activate')
        update_icon if @update_win_icon
        if @message and (not force_show)
          page = $window.notebook.page
          if (page >= 0)
            cur_page = $window.notebook.get_nth_page(page)
            if cur_page.is_a? PandoraGtk::CabinetBox
              cur_page.update_state(false, cur_page)
            end
          else
            set_message(nil) if ($window.notebook.n_pages == 0)
          end
        end
      end
    end
  end  #--PandoraStatusIcon

  def self.detect_icon_opts(stock)
    res = stock
    opts = 'mt'
    if res.is_a? String
      i = res.index(':')
      if i
        opts = res[i+1..-1]
        res = res[0, i]
        res = nil if res==''
      end
    end
    [res, opts]
  end

  $status_font = nil

  def self.status_font
    if $status_font.nil?
      style = Gtk::Widget.default_style
      font = style.font_desc
      fs = font.size
      fs = fs * Pango::SCALE_SMALL if fs
      font.size = fs if fs
      $status_font = font
    end
    $status_font
  end

  class GoodButton < Gtk::Frame
    attr_accessor :hbox, :image, :label, :active, :group_set

    def initialize(astock, atitle=nil, atoggle=nil, atooltip=nil)
      super()
      self.tooltip_text = atooltip if atooltip
      @group_set = nil
      if atoggle.is_a? Integer
        @group_set = atoggle
        atoggle = (atoggle>0)
      end
      @hbox = Gtk::HBox.new
      #align = Gtk::Alignment.new(0.5, 0.5, 0, 0)
      #align.add(@image)

      @proc_on_click = Proc.new do |*args|
        yield(*args) if block_given?
      end

      @im_evbox = Gtk::EventBox.new
      #@im_evbox.border_width = 2
      @im_evbox.events = Gdk::Event::BUTTON_PRESS_MASK | Gdk::Event::POINTER_MOTION_MASK \
        | Gdk::Event::ENTER_NOTIFY_MASK | Gdk::Event::LEAVE_NOTIFY_MASK \
        | Gdk::Event::VISIBILITY_NOTIFY_MASK
      @lab_evbox = Gtk::EventBox.new
      #@lab_evbox.border_width = 1
      @lab_evbox.events = Gdk::Event::BUTTON_PRESS_MASK | Gdk::Event::POINTER_MOTION_MASK \
        | Gdk::Event::ENTER_NOTIFY_MASK | Gdk::Event::LEAVE_NOTIFY_MASK \
        | Gdk::Event::VISIBILITY_NOTIFY_MASK

      set_image(astock)
      set_label(atitle)
      self.add(@hbox)

      set_active(atoggle)

      @enter_event = Proc.new do |body_child, event|
        self.shadow_type = Gtk::SHADOW_OUT if @active.nil?
        false
      end

      @leave_event = Proc.new do |body_child, event|
        self.shadow_type = Gtk::SHADOW_NONE if @active.nil?
        false
      end

      @press_event = Proc.new do |widget, event|
        if (event.button == 1)
          if @active.nil?
            self.shadow_type = Gtk::SHADOW_IN
          elsif @group_set.nil?
            @active = (not @active)
            set_active(@active)
          end
          do_on_click
        end
        false
      end

      @release_event = Proc.new do |widget, event|
        set_active(@active)
        false
      end

      @im_evbox.signal_connect('enter-notify-event') { |*args| @enter_event.call(*args) }
      @im_evbox.signal_connect('leave-notify-event') { |*args| @leave_event.call(*args) }
      @im_evbox.signal_connect('button-press-event') { |*args| @press_event.call(*args) }
      @im_evbox.signal_connect('button-release-event') { |*args| @release_event.call(*args) }

      @lab_evbox.signal_connect('enter-notify-event') { |*args| @enter_event.call(*args) }
      @lab_evbox.signal_connect('leave-notify-event') { |*args| @leave_event.call(*args) }
      @lab_evbox.signal_connect('button-press-event') { |*args| @press_event.call(*args) }
      @lab_evbox.signal_connect('button-release-event') { |*args| @release_event.call(*args) }
    end

    def do_on_click
      @proc_on_click.call
    end

    def active?
      @active
    end

    def set_active(toggle)
      @active = toggle
      if @active.nil?
        self.shadow_type = Gtk::SHADOW_NONE
      elsif @active
        self.shadow_type = Gtk::SHADOW_IN
        @im_evbox.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#C9C9C9'))
        @lab_evbox.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#C9C9C9'))
      else
        self.shadow_type = Gtk::SHADOW_OUT
        @im_evbox.modify_bg(Gtk::STATE_NORMAL, nil)
        @lab_evbox.modify_bg(Gtk::STATE_NORMAL, nil)
      end
    end

    def set_image(astock=nil)
      if @image
        @image.destroy
        @image = nil
      end
      if astock
        #$window.get_preset_iconset(astock)
        $window.register_stock(astock)
        @image = Gtk::Image.new(astock, Gtk::IconSize::MENU)
        @image.set_padding(2, 2)
        @image.set_alignment(0.5, 0.5)
        @im_evbox.add(@image)
        @hbox.pack_start(@im_evbox, true, true, 0)
      end
    end

    def set_label(atitle=nil)
      if atitle.nil?
        if @label
          @label.visible = false
          @label.text = ''
        end
      else
        if @label
          @label.text = atitle
          @label.visible = true if not @label.visible?
        else
          @label = Gtk::Label.new(atitle)
          @label.set_padding(2, 2)
          @label.set_alignment(0.0, 0.5)
          @label.modify_font(PandoraGtk.status_font)
          #p style = @label.style
          #p style = @label.modifier_style
          #p style = Gtk::Widget.default_style
          #p style.font_desc
          #p style.font_desc.size
          #p style.font_desc.family
          @lab_evbox.add(@label)
          @hbox.pack_start(@lab_evbox, true, true, 0)
        end
      end
    end
  end

  # Main window
  # RU: Главное окно
  class MainWindow < Gtk::Window
    attr_accessor :hunter_count, :listener_count, :fisher_count, :log_view, :notebook, \
      :pool, :focus_timer, :title_view, :do_on_start, :radar_hpaned, :task_offset, \
      :radar_sw, :log_vpaned, :log_sw, :accel_group, :node_reg_offset, :menubar, \
      :toolbar, :hand_cursor, :regular_cursor


    include PandoraUtils

    # Update status of connections
    # RU: Обновить состояние подключений
    def update_conn_status(conn, session_type, diff_count)
      #if session_type==0
      @hunter_count += diff_count
      #elsif session_type==1
      #  @listener_count += diff_count
      #else
      #  @fisher_count += diff_count
      #end
      set_status_field(SF_Conn, (hunter_count + listener_count + fisher_count).to_s)
      online = ((@hunter_count>0) or (@listener_count>0) or (@fisher_count>0))
      $statusicon.set_online(online)
    end

    $toggle_buttons = []

    # Change listener button state
    # RU: Изменить состояние кнопки слушателя
    def correct_lis_btn_state
      tool_btn = $toggle_buttons[PandoraGtk::SF_Listen]
      if tool_btn
        lis_act = PandoraNet.listen?
        tool_btn.safe_set_active(lis_act) if tool_btn.is_a? SafeToggleToolButton
      end
    end

    # Change hunter button state
    # RU: Изменить состояние кнопки охотника
    def correct_hunt_btn_state
      tool_btn = $toggle_buttons[PandoraGtk::SF_Hunt]
      #pushed = ((not $hunter_thread.nil?) and $hunter_thread[:active] \
      #  and (not $hunter_thread[:paused]))
      pushed = PandoraNet.is_hunting?
      #p 'correct_hunt_btn_state: pushed='+[tool_btn, pushed, $hunter_thread, \
      #  $hunter_thread[:active], $hunter_thread[:paused]].inspect
      tool_btn.safe_set_active(pushed) if tool_btn.is_a? SafeToggleToolButton
      $window.set_status_field(PandoraGtk::SF_Hunt, nil, nil, pushed)
    end

    # Change listener button state
    # RU: Изменить состояние кнопки слушателя
    def correct_fish_btn_state
      hpaned = $window.radar_hpaned
      #list_sw = hpaned.children[1]
      an_active = (hpaned.max_position - hpaned.position) > 24
      #(list_sw.allocation.width > 24)
      #($window.radar_hpaned.position > 24)
      $window.set_status_field(PandoraGtk::SF_Radar, nil, nil, an_active)
      #tool_btn = $toggle_buttons[PandoraGtk::SF_Radar]
      #if tool_btn
      #  hpaned = $window.radar_hpaned
      #  list_sw = hpaned.children[0]
      #  tool_btn.safe_set_active(hpaned.position > 24)
      #end
    end

    def correct_log_btn_state
      vpaned = $window.log_vpaned
      an_active = (vpaned.max_position - vpaned.position) > 24
      $window.set_status_field(PandoraGtk::SF_Log, nil, nil, an_active)
    end

    # Show notice status
    # RU: Показать уведомления в статусе
    #def show_notice(change=nil)
    #  if change
    #    PandoraGtk.show_panobject_list(PandoraModel::Parameter, nil, nil, true)
    #  end
    #  PandoraNet.get_notice_params
    #  notice = PandoraModel.transform_trust($notice_trust, :auto_to_float)
    #  notice = notice.round(1).to_s + '/'+$notice_depth.to_s
    #  set_status_field(PandoraGtk::SF_Notice, notice)
    #end

    $statusbar = nil
    $status_fields = []

    # Add field to statusbar
    # RU: Добавляет поле в статусбар
    def add_status_field(index, text, tooltip=nil, stock=nil, toggle=nil, separ_pos=nil)
      separ_pos ||= 1
      if (separ_pos & 1)>0
        $statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      end
      toggle_group = nil
      toggle_group = -1 if not toggle.nil?
      tooltip = _(tooltip) if tooltip
      btn = GoodButton.new(stock, text, toggle_group, tooltip) do |*args|
        yield(*args) if block_given?
      end
      btn.set_active(toggle) if not toggle.nil?
      $statusbar.pack_start(btn, false, false, 0)
      $status_fields[index] = btn
      if (separ_pos & 2)>0
        $statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      end
    end

    # Set properties of fiels in statusbar
    # RU: Задаёт свойства поля в статусбаре
    def set_status_field(index, text, enabled=nil, toggle=nil)
      fld = $status_fields[index]
      if fld
        if text
          str = _(text)
          str = _('Version') + ': ' + str if (index==SF_Update)
          fld.set_label(str)
        end
        fld.sensitive = enabled if (enabled != nil)
        if (toggle != nil)
          fld.set_active(toggle)
          btn = $toggle_buttons[index]
          btn.safe_set_active(toggle) if btn and (btn.is_a? SafeToggleToolButton)
        end
      end
    end

    # Get fiels of statusbar
    # RU: Возвращает поле статусбара
    def get_status_field(index)
      $status_fields[index]
    end

    def get_icon_file_params(preset)
      icon_params, icon_file_desc = nil
      smile_desc = PandoraUtils.get_param('icons_'+preset)
      if smile_desc
        icon_params = smile_desc.split('|')
        icon_file_desc = icon_params[0]
        icon_params.delete_at(0)
      end
      [icon_params, icon_file_desc]
    end

    # Return Pixbuf with icon picture
    # RU: Возвращает Pixbuf с изображением иконки
    def get_icon_buf(emot='smile', preset='qip')
      buf = nil
      if not preset
        @def_smiles ||= PandoraUtils.get_param('def_smiles')
        preset = @def_smiles
      end
      buf = @icon_bufs[preset][emot] if @icon_bufs and @icon_bufs[preset]
      icon_preset = nil
      if buf.nil?
        @icon_presets ||= Hash.new
        icon_preset = @icon_presets[preset]
        if icon_preset.nil?
          icon_params, icon_file_desc = get_icon_file_params(preset)
          if icon_params and icon_file_desc
            icon_file_params = icon_file_desc.split(':')
            icon_file_name = icon_file_params[0]
            numXs, numYs = icon_file_params[1].split('x')
            bord_s = icon_file_params[2]
            bord_s.delete!('p')
            padd_s = icon_file_params[3]
            padd_s.delete!('p')
            begin
              smile_fn = File.join($pandora_view_dir, icon_file_name)
              preset_buf = Gdk::Pixbuf.new(smile_fn)
              if preset_buf
                big_width = preset_buf.width
                big_height = preset_buf.height
                #p 'get_icon_buf [big_width, big_height]='+[big_width, big_height].inspect
                bord = bord_s.to_i
                padd = padd_s.to_i
                numX = numXs.to_i
                numY = numYs.to_i
                cellX = (big_width - 2*bord - (numX-1)*padd)/numX
                cellY = (big_height - 2*bord - (numY-1)*padd)/numY

                icon_preset = Hash.new
                icon_preset[:names]      = icon_params
                icon_preset[:big_width]  = big_width
                icon_preset[:big_height] = big_height
                icon_preset[:bord]       = bord
                icon_preset[:padd]       = padd
                icon_preset[:numX]       = numX
                icon_preset[:numY]       = numY
                icon_preset[:cellX]      = cellX
                icon_preset[:cellY]      = cellY
                icon_preset[:buf]        = preset_buf
                @icon_presets[preset] = icon_preset
              end
            rescue
              p 'Error while load smile file: ['+smile_fn+']'
            end
          end
        end
      end

      def transpix?(pix, bg)
        res = ((pix.size == 4) and (pix[-1] == 0.chr) or (pix == bg))
      end

      if buf.nil? and icon_preset
        index = icon_preset[:names].index(emot)
        if index.nil?
          if icon_preset[:def_index].nil?
            PandoraUtils.set_param('icons_'+preset, nil)
            icon_params, icon_file_desc = get_icon_file_params(preset)
            icon_preset[:names] = icon_params
            index = icon_preset[:names].index(emot)
            icon_preset[:def_index] = 0
          end
          index ||= icon_preset[:def_index]
        end
        if index
          big_width  = icon_preset[:big_width]
          big_height = icon_preset[:big_height]
          bord       = icon_preset[:bord]
          padd       = icon_preset[:padd]
          numX       = icon_preset[:numX]
          numY       = icon_preset[:numY]
          cellX      = icon_preset[:cellX]
          cellY      = icon_preset[:cellY]
          preset_buf = icon_preset[:buf]

          iY = index.div(numX)
          iX = index - (iY*numX)
          dX = bord + iX*(cellX+padd)
          dY = bord + iY*(cellY+padd)
          #p '[cellX, cellY, iX, iY, dX, dY]='+[cellX, cellY, iX, iY, dX, dY].inspect
          draft_buf = Gdk::Pixbuf.new(Gdk::Pixbuf::COLORSPACE_RGB, true, 8, cellX, cellY)
          preset_buf.copy_area(dX, dY, cellX, cellY, draft_buf, 0, 0)
          #draft_buf = Gdk::Pixbuf.new(preset_buf, 0, 0, 21, 24)

          pixs = AsciiString.new(draft_buf.pixels)
          pix_size = draft_buf.n_channels
          width = draft_buf.width
          height = draft_buf.height
          w = width * pix_size  #buf.rowstride
          #p '[pixs.bytesize, width, height, w]='+[pixs.bytesize, width, height, w].inspect

          bg = pixs[0, pix_size]   #top left pixel consider background

          # Find top border
          top = 0
          while (top<height)
            x = 0
            while (x<w) and transpix?(pixs[w*top+x, pix_size], bg)
              x += pix_size
            end
            if x<w
              break
            else
              top += 1
            end
          end

          # Find bottom border
          bottom = height-1
          while (bottom>top)
            x = 0
            while (x<w) and transpix?(pixs[w*bottom+x, pix_size], bg)
              x += pix_size
            end
            if x<w
              break
            else
              bottom -= 1
            end
          end

          # Find left border
          left = 0
          while (left<w)
            y = 0
            while (y<height) and transpix?(pixs[w*y+left, pix_size], bg)
              y += 1
            end
            if y<height
              break
            else
              left += pix_size
            end
          end

          # Find right border
          right = w - pix_size
          while (right>left)
            y = 0
            while (y<height) and transpix?(pixs[w*y+right, pix_size], bg)
              y += 1
            end
            if y<height
              break
            else
              right -= pix_size
            end
          end

          left = left/pix_size
          right = right/pix_size
          #p '====[top,bottom,left,right]='+[top,bottom,left,right].inspect

          width2 = right-left+1
          height2 = bottom-top+1
          #p '  ---[width2,height2]='+[width2,height2].inspect

          if (width2>0) and (height2>0) \
          and ((left>0) or (top>0) or (width2<width) or (height2<height))
            # Crop borders
            buf = Gdk::Pixbuf.new(Gdk::Pixbuf::COLORSPACE_RGB, true, 8, width2, height2)
            draft_buf.copy_area(left, top, width2, height2, buf, 0, 0)
          else
            buf = draft_buf
          end
          @icon_bufs ||= Hash.new
          @icon_bufs[preset] ||= Hash.new
          @icon_bufs[preset][emot] = buf
        else
          p 'No emotion ['+emot+'] in the preset ['+preset+']'
        end
      end
      buf
    end

    def get_icon_scale_buf(emot='smile', preset='pan', icon_size=16, center=true)
      buf = get_icon_buf(emot, preset)
      buf = PandoraModel.scale_buf_to_size(buf, icon_size, center)
    end

    $iconsets = {}

    # Return Image with defined icon size
    # RU: Возвращает Image с заданным размером иконки
    def get_preset_iconset(iname, preset='pan')
      ind = [iname.to_s, preset]
      res = $iconsets[ind]
      if res.nil?
        if (iname.is_a? Symbol)
          res = Gtk::IconFactory.lookup_default(iname.to_s)
          iname = iname.to_s if res.nil?
        end
        if res.nil? and preset
          buf = get_icon_buf(iname, preset)
          if buf
            width = buf.width
            height = buf.height
            if width==height
              qbuf = buf
            else
              asize = width
              asize = height if asize<height
              left = (asize - width)/2
              top  = (asize - height)/2
              qbuf = Gdk::Pixbuf.new(Gdk::Pixbuf::COLORSPACE_RGB, true, 8, asize, asize)
              qbuf.fill!(0xFFFFFF00)
              buf.copy_area(0, 0, width, height, qbuf, left, top)
            end
            res = Gtk::IconSet.new(qbuf)
          end
        end
        $iconsets[ind] = res if res
      end
      res
    end

    def get_preset_icon(iname, preset='pan', icon_size=nil)
      res = nil
      iconset = get_preset_iconset(iname, preset)
      if iconset
        icon_size ||= Gtk::IconSize::DIALOG
        if icon_size.is_a? Integer
          icon_name = Gtk::IconSize.get_name(icon_size)
          icon_name ||= 'SIZE'+icon_size.to_s
          icon_res = Gtk::IconSize.from_name(icon_name)
          if (not icon_res) or (icon_res==0)
            icon_size = Gtk::IconSize.register(icon_name, icon_size, icon_size)
          else
            icon_size = icon_res
          end
        end
        style = Gtk::Widget.default_style
        res = iconset.render_icon(style, Gtk::Widget::TEXT_DIR_LTR, \
          Gtk::STATE_NORMAL, icon_size)  #Gtk::IconSize::LARGE_TOOLBAR)
      end
      res
    end

    # Return Image with defined icon size
    # RU: Возвращает Image с заданным размером иконки
    def get_preset_image(iname, isize=Gtk::IconSize::MENU, preset='pan')
      image = nil
      isize ||= Gtk::IconSize::MENU
      #p 'get_preset_image  iname='+[iname, isize].inspect
      #if iname.is_a? String
        iconset = get_preset_iconset(iname, preset)
        image = Gtk::Image.new(iconset, isize)
      #else
      #  p image = Gtk::Image.new(iname, isize)
      #end
      image.set_alignment(0.5, 0.5)
      image
    end

    def get_panobject_stock(panobject_ider)
      res = panobject_ider
      mi = MENU_ITEMS.detect {|mi| mi[0]==res }
      if mi
        stock_opt = mi[1]
        stock, opts = PandoraGtk.detect_icon_opts(stock_opt)
        res = stock.to_sym if stock
      end
      res
    end

    def get_panobject_image(panobject_ider, isize=Gtk::IconSize::MENU, preset='pan')
      res = nil
      stock = get_panobject_stock(panobject_ider)
      res = get_preset_image(stock, isize, preset) if stock
      res
    end

    # Register new stock by name of image preset
    # RU: Регистрирует новый stock по имени пресета иконки
    def register_stock(stock=:person, preset=nil, name=nil)
      stock = stock.to_sym if stock.is_a? String
      stock_inf = nil
      preset ||= 'pan'
      suff = preset
      suff = '' if (preset=='pan' or (preset.nil?))
      reg_stock = stock.to_s
      if suff and (suff.size>0)
        reg_stock << '_'+suff.to_s
      end
      reg_stock = reg_stock.to_sym
      begin
        stock_inf = Gtk::Stock.lookup(reg_stock)
      rescue
      end
      if not stock_inf
        icon_set = get_preset_iconset(stock.to_s, preset)
        if icon_set
          name ||= '_'+stock.to_s.capitalize
          Gtk::Stock.add(reg_stock, name)
          @icon_factory.add(reg_stock.to_s, icon_set)
        end
      end
      stock_inf
    end

    # Export table to file
    # RU: Выгрузить таблицу в файл
    def export_table(panobject, filename=nil)

      ider = panobject.ider
      separ = '|'

      File.open(filename, 'w') do |file|
        file.puts('# Export table ['+ider+']')
        file.puts('# Code page: UTF-8')

        tab_flds = panobject.tab_fields
        #def_flds = panobject.def_fields
        #id = df[FI_Id]
        #tab_ind = tab_flds.index{ |tf| tf[0] == id }
        fields = tab_flds.collect{|tf| tf[0]}
        fields = fields.join('|')
        file.puts('# Fields: '+fields)

        sel = panobject.select(nil, false, nil, panobject.sort)
        sel.each do |row|
          line = ''
          row.each_with_index do |cell,i|
            line += separ if i>0
            if cell
              begin
                #line += '"' + cell.to_s + '"' if cell
                line += cell.to_s
              rescue
              end
            end
          end
          file.puts(Utf8String.new(line))
        end
      end

      PandoraUtils.log_message(LM_Info, _('Table exported')+': '+filename)
    end

    def mutex
      @mutex ||= Mutex.new
    end

    # Menu event handler
    # RU: Обработчик события меню
    def do_menu_act(command, treeview=nil)
      widget = nil
      if not (command.is_a? String)
        widget = command
        if widget.instance_variable_defined?('@command')
          command = widget.command
        else
          command = widget.name
        end
      end
      case command
        when 'Quit'
          PandoraNet.start_or_stop_listen(false, true)
          PandoraNet.start_or_stop_hunt(false) if $hunter_thread
          self.pool.close_all_session
          self.destroy
        when 'Activate'
          self.deiconify
          #self.visible = true if (not self.visible?)
          self.present
        when 'Hide'
          #self.iconify
          self.hide
        when 'About'
          PandoraGtk.show_about
        when 'Guide'
          guide_fn = File.join($pandora_doc_dir, 'guide.'+$lang+'.pdf')
          if not File.exist?(guide_fn)
            if ($lang == 'en')
              guide_fn = File.join($pandora_doc_dir, 'guide.en.odt')
            else
              guide_fn = File.join($pandora_doc_dir, 'guide.en.pdf')
            end
          end
          if guide_fn and File.exist?(guide_fn)
            PandoraUtils.external_open(guide_fn, 'open')
          else
            PandoraUtils.external_open($pandora_doc_dir, 'open')
          end
        when 'Readme'
          PandoraUtils.external_open(File.join($pandora_app_dir, 'README.TXT'), 'open')
        when 'DocPath'
          PandoraUtils.external_open($pandora_doc_dir, 'open')
        when 'Close'
          if notebook.page >= 0
            page = notebook.get_nth_page(notebook.page)
            tab = notebook.get_tab_label(page)
            close_btn = tab.children[tab.children.size-1].children[0]
            close_btn.clicked
          end
        when 'Create','Edit','Delete','Copy', 'Chat', 'Dialog', 'Opinion', \
        'Convert', 'Import', 'Export'
          p 'act_panobject()  treeview='+treeview.inspect
          if (not treeview) and (notebook.page >= 0)
            sw = notebook.get_nth_page(notebook.page)
            treeview = sw.children[0]
          end
          if treeview.is_a? Gtk::TreeView # SubjTreeView
            if command=='Convert'
              panobject = treeview.panobject
              panobject.update(nil, nil, nil)
              panobject.class.tab_fields(true)
            elsif command=='Import'
              p 'import'
            elsif command=='Export'
              panobject = treeview.panobject
              ider = panobject.ider
              filename = File.join($pandora_files_dir, ider+'.csv')

              dialog = GoodFileChooserDialog.new(filename, false, nil, $window)

              filter = Gtk::FileFilter.new
              filter.name = _('Text tables')+' (*.csv,*.txt)'
              filter.add_pattern('*.csv')
              filter.add_pattern('*.txt')
              dialog.add_filter(filter)

              dialog.filter = filter

              filter = Gtk::FileFilter.new
              filter.name = _('JavaScript Object Notation')+' (*.json)'
              filter.add_pattern('*.json')
              dialog.add_filter(filter)

              filter = Gtk::FileFilter.new
              filter.name = _('Pandora Simple Object Notation')+' (*.pson)'
              filter.add_pattern('*.pson')
              dialog.add_filter(filter)

              if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
                filename = dialog.filename
                export_table(panobject, filename)
              end
              dialog.destroy if not dialog.destroyed?
            else
              PandoraGtk.act_panobject(treeview, command)
            end
          end
        when 'Listen'
          PandoraNet.start_or_stop_listen
        when 'Hunt'
          continue = PandoraGtk.is_ctrl_shift_alt?(true, true)
          PandoraNet.start_or_stop_hunt(continue)
        when 'Authorize'
          key = PandoraCrypto.current_key(false, false)
          if key
            PandoraNet.start_or_stop_listen(false)
            PandoraNet.start_or_stop_hunt(false) if $hunter_thread
            self.pool.close_all_session
          end
          key = PandoraCrypto.current_key(true)
        when 'Wizard'
          PandoraGtk.show_log_bar(80)
        when 'Profile'
          current_user = PandoraCrypto.current_user_or_key(true, true)
          if current_user
            PandoraGtk.show_cabinet(current_user, nil, nil, nil, nil, CPI_Profile)
          end
        when 'Search'
          PandoraGtk.show_search_panel
        when 'Session'
          PandoraGtk.show_session_panel
        when 'Radar'
          PandoraGtk.show_radar_panel
        when 'FullScr'
          PandoraGtk.full_screen_switch
        when 'LogBar'
          PandoraGtk.show_log_bar
        when 'Fisher'
          PandoraGtk.show_fisher_panel
        else
          panobj_id = command
          if (panobj_id.is_a? String) and (panobj_id.size>0) \
          and (panobj_id[0].upcase==panobj_id[0]) and PandoraModel.const_defined?(panobj_id)
            panobject_class = PandoraModel.const_get(panobj_id)
            PandoraGtk.show_panobject_list(panobject_class, widget)
          else
            PandoraUtils.log_message(LM_Warning, _('Menu handler is not defined yet') + \
              ' "'+panobj_id+'"')
          end
      end
    end

    # Menu structure
    # RU: Структура меню
    MENU_ITEMS =
      [[nil, nil, '_World'],
      ['Person', 'person', 'People', '<control>E'], #Gtk::Stock::ORIENTATION_PORTRAIT
      ['Community', 'community:m', 'Communities'],
      ['Blob', 'blob', 'Files', '<control>J'], #Gtk::Stock::FILE Gtk::Stock::HARDDISK
      ['-', nil, '-'],
      ['City', 'city:m', 'Towns'],
      ['Street', 'street:m', 'Streets'],
      ['Address', 'address:m', 'Addresses'],
      ['Contact', 'contact:m', 'Contacts'],
      ['Country', 'country:m', 'States'],
      ['Language', 'lang:m', 'Languages'],
      ['Word', 'word', 'Words'], #Gtk::Stock::SPELL_CHECK
      ['Relation', 'relation:m', 'Relations'],
      ['-', nil, '-'],
      ['Task', 'task:m', 'Tasks'],
      ['Message', 'message:m', 'Messages'],
      [nil, nil, '_Business'],
      ['Advertisement', 'ad', 'Advertisements'],
      ['Order', 'order:m', 'Orders'],
      ['Deal', 'deal:m', 'Deals'],
      ['Transfer', 'transfer:m', 'Transfers'],
      ['Waybill', 'waybill:m', 'Waybills'],
      ['-', nil, '-'],
      ['Debenture', 'debenture:m', 'Debentures'],
      ['Deposit', 'deposit:m', 'Deposits'],
      ['Guarantee', 'guarantee:m', 'Guarantees'],
      ['Insurer', 'insurer:m', 'Insurers'],
      ['-', nil, '-'],
      ['Product', 'product:m', 'Products'],
      ['Service', 'service:m', 'Services'],
      ['Currency', 'currency:m', 'Currency'],
      ['Storage', 'storage:m', 'Storages'],
      ['Estimate', 'estimate:m', 'Estimates'],
      ['Contract', 'contract:m', 'Contracts'],
      ['Report', 'report:m', 'Reports'],
      [nil, nil, '_Region'],
      ['Law', 'law:m', 'Laws'],
      ['Resolution', 'resolution:m', 'Resolutions'],
      ['-', nil, '-'],
      ['Project', 'project', 'Projects'],
      ['Offense', 'offense:m', 'Offenses'],
      ['Punishment', 'punishment', 'Punishments'],
      ['-', nil, '-'],
      ['Contribution', 'contribution:m', 'Contributions'],
      ['Expenditure', 'expenditure:m', 'Expenditures'],
      ['-', nil, '-'],
      ['Resource', 'resource:m', 'Resources'],
      ['Delegation', 'delegation:m', 'Delegations'],
      ['Registry', 'registry:m', 'Registry'],
      [nil, nil, '_Node'],
      ['Parameter', Gtk::Stock::PROPERTIES, 'Parameters'],
      ['-', nil, '-'],
      ['Key', 'key', 'Keys'],   #Gtk::Stock::GOTO_BOTTOM
      ['Sign', 'sign:m', 'Signs'],
      ['Node', 'node', 'Nodes'],  #Gtk::Stock::NETWORK
      ['Request', 'request:m', 'Requests'],  #Gtk::Stock::SELECT_COLOR
      ['Block', 'block:m', 'Blocks'],
      ['Box', 'box:m', 'Boxes'],
      ['Event', 'event:m', 'Events'],
      ['-', nil, '-'],
      ['Authorize', :auth, 'Authorize', '<control>O', :check], #Gtk::Stock::DIALOG_AUTHENTICATION
      ['Listen', :listen, 'Listen', '<control>L', :check],  #Gtk::Stock::CONNECT
      ['Hunt', :hunt, 'Hunt', '<control>H', :check],   #Gtk::Stock::REFRESH
      ['Radar', :radar, 'Radar', '<control>R', :check],  #Gtk::Stock::GO_FORWARD
      ['Search', Gtk::Stock::FIND, 'Search', '<control>T'],
      ['>', nil, '_Wizards'],
      ['>Profile', Gtk::Stock::HOME, 'Profile'],
      ['>Exchange', 'exchange:m', 'Exchange'],
      ['>Session', 'session:m', 'Sessions', '<control>S'],   #Gtk::Stock::JUSTIFY_FILL
      ['>Fisher', 'fish:m', 'Fishers'],
      ['>Wizard', Gtk::Stock::PREFERENCES.to_s+':m', '_Wizards'],
      ['-', nil, '-'],
      ['>', nil, '_Help'],
      ['>Guide', Gtk::Stock::HELP.to_s+':m', 'Guide', 'F1'],
      ['>Readme', ':m', 'README.TXT'],
      ['>DocPath', Gtk::Stock::OPEN.to_s+':m', 'Documentation'],
      ['>About', Gtk::Stock::ABOUT, '_About'],
      ['Close', Gtk::Stock::CLOSE.to_s+':', '_Close', '<control>W'],
      ['Quit', Gtk::Stock::QUIT, '_Quit', '<control>Q']
      ]

    # Fill main menu
    # RU: Заполнить главное меню
    def fill_menubar(menubar)
      menu = nil
      sub_menu = nil
      MENU_ITEMS.each do |mi|
        command = mi[0]
        if command.nil? or menu.nil? or ((command.size==1) and (command[0]=='>'))
          menuitem = Gtk::MenuItem.new(_(mi[2]))
          if command and menu
            menu.append(menuitem)
            sub_menu = Gtk::Menu.new
            menuitem.set_submenu(sub_menu)
          else
            menubar.append(menuitem)
            menu = Gtk::Menu.new
            menuitem.set_submenu(menu)
            sub_menu = nil
          end
        else
          menuitem = PandoraGtk.create_menu_item(mi)
          if command and (command.size>1) and (command[0]=='>')
            if sub_menu
              sub_menu.append(menuitem)
            else
              menu.append(menuitem)
            end
          else
            menu.append(menuitem)
          end
        end
      end
    end

    # Fill toolbar
    # RU: Заполнить панель инструментов
    def fill_main_toolbar(toolbar)
      MENU_ITEMS.each do |mi|
        stock = mi[1]
        stock, opts = PandoraGtk.detect_icon_opts(stock)
        if stock and opts.index('t')
          command = mi[0]
          if command and (command.size>0) and (command[0]=='>')
            command = command[1..-1]
          end
          label = mi[2]
          if command and (command.size>1) and label and (label != '-')
            toggle = nil
            toggle = false if mi[4]
            btn = PandoraGtk.add_tool_btn(toolbar, stock, label, toggle) do |widget, *args|
              do_menu_act(widget)
            end
            btn.name = command
            if (toggle != nil)
              index = nil
              case command
                when 'Authorize'
                  index = SF_Auth
                when 'Listen'
                  index = SF_Listen
                when 'Hunt'
                  index = SF_Hunt
                when 'Radar'
                  index = SF_Radar
              end
              $toggle_buttons[index] = btn if index
            end
          end
        end
      end
    end

    $show_task_notif = true

    # Scheduler parameters (sec)
    # RU: Параметры планировщика (сек)
    CheckTaskPeriod  = 1*60   #5 min
    MassGarbStep   = 30     #30 sec
    CheckBaseStep    = 10     #10 sec
    CheckBasePeriod  = 60*60  #60 min
    # Size of bundle processed at one cycle
    # RU: Размер пачки, обрабатываемой за цикл
    HuntTrain         = 10     #nodes at a heat
    BaseGarbTrain     = 3      #records at a heat
    MassTrain       = 3      #request at a heat
    MassGarbTrain   = 30     #request at a heat

    # Initialize scheduler (tasks, hunter, base gabager, mem gabager)
    # RU: Инициировать планировщик (задачи, охотник, мусорщики баз и памяти)
    def init_scheduler(step=nil)
      step ||= 1.0
      p 'scheduler_step='+step.inspect
      if (not @scheduler) and step
        @scheduler_step = step
        @base_garbage_term = PandoraUtils.get_param('base_garbage_term')
        @base_purge_term = PandoraUtils.get_param('base_purge_term')
        @base_garbage_term ||= 5   #day
        @base_purge_term ||= 30    #day
        @base_garbage_term = (@base_garbage_term * 24*60*60).round   #sec
        @base_purge_term = (@base_purge_term * 24*60*60).round   #sec
        @shed_models ||= {}
        @task_offset = nil
        @task_model = nil
        @task_list = nil
        @task_dialog = nil
        @hunt_node_id = nil
        @mass_garb_offset = 0.0
        @mass_garb_ind = 0
        @base_garb_mode = :arch
        @base_garb_model = nil
        @base_garb_kind = 0
        @base_garb_offset = nil
        @panreg_period = PandoraUtils.get_param('panreg_period')
        if (not(@panreg_period.is_a? Numeric)) or (@panreg_period < 0)
          @panreg_period = 30
        end
        @panreg_period = @panreg_period*60
        @scheduler = Thread.new do
          sleep 1
          while @scheduler_step

            # Update pool time_now
            pool.time_now = Time.now.to_i

            # Task executer
            # RU: Запускальщик Заданий
            if (not @task_dialog) and ((not @task_offset) \
            or (@task_offset >= CheckTaskPeriod))
              @task_offset = 0.0
              user ||= PandoraCrypto.current_user_or_key(true, false)
              if user
                @task_model ||= PandoraUtils.get_model('Task', @shed_models)
                cur_time = Time.now.to_i
                filter = ["(executor=? OR IFNULL(executor,'')='' AND creator=?) AND mode>? AND time<=?", \
                  user, user, 0, cur_time]
                fields = 'id, time, mode, message'
                @task_list = @task_model.select(filter, false, fields, 'time ASC')
                Thread.pass
                if @task_list and (@task_list.size>0)
                  p 'TTTTTTTTTT @task_list='+@task_list.inspect

                  message = ''
                  store = nil
                  if $show_task_notif and $window.visible? \
                  and (PandoraUtils.os_family != 'windows')
                  #and $window.has_toplevel_focus?
                    store = Gtk::ListStore.new(String, String, String)
                  end
                  @task_list.each do |row|
                    time = Time.at(row[1]).strftime('%d.%m.%Y %H:%M:%S')
                    mode = row[2]
                    text = Utf8String.new(row[3])
                    if message.size>0
                      message += '; '
                    else
                      message += _('Tasks')+'> '
                    end
                    message +=  '"' + text + '" ('+time+')'
                    if store
                      iter = store.append
                      iter[0] = time
                      iter[1] = mode.to_s
                      iter[2] = text
                    end
                  end

                  PandoraUtils.log_message(LM_Warning, message)
                  PandoraUtils.play_mp3('message')
                  if $statusicon.message.nil?
                    $statusicon.set_message(message)
                    Thread.new do
                      sleep(10)
                      $statusicon.set_message(nil)
                    end
                  end

                  if store
                    Thread.new do
                      @task_dialog = PandoraGtk::AdvancedDialog.new(_('Tasks'))
                      dialog = @task_dialog
                      image = $window.get_preset_image('task')
                      iconset = image.icon_set
                      style = Gtk::Widget.default_style  #Gtk::Style.new
                      task_icon = iconset.render_icon(style, Gtk::Widget::TEXT_DIR_LTR, \
                        Gtk::STATE_NORMAL, Gtk::IconSize::LARGE_TOOLBAR)
                      dialog.icon = task_icon

                      dialog.set_default_size(500, 350)
                      vbox = Gtk::VBox.new
                      dialog.viewport.add(vbox)

                      treeview = Gtk::TreeView.new(store)
                      treeview.rules_hint = true
                      treeview.search_column = 0
                      treeview.border_width = 10

                      renderer = Gtk::CellRendererText.new
                      column = Gtk::TreeViewColumn.new(_('Time'), renderer, 'text' => 0)
                      column.set_sort_column_id(0)
                      treeview.append_column(column)

                      renderer = Gtk::CellRendererText.new
                      column = Gtk::TreeViewColumn.new(_('Mode'), renderer, 'text' => 1)
                      column.set_sort_column_id(1)
                      treeview.append_column(column)

                      renderer = Gtk::CellRendererText.new
                      column = Gtk::TreeViewColumn.new(_('Text'), renderer, 'text' => 2)
                      column.set_sort_column_id(2)
                      treeview.append_column(column)

                      vbox.pack_start(treeview, false, false, 2)

                      dialog.def_widget = treeview

                      dialog.run2(true) do
                        @task_list.each do |row|
                          id = row[0]
                          @task_model.update({:mode=>0}, nil, {:id=>id})
                        end
                      end
                      @task_dialog = nil
                    end
                  end
                  Thread.pass
                end
              end
            end
            @task_offset += @scheduler_step if @task_offset

            # Hunter
            if false #$window.hunt
              if not @hunt_node_id
                @hunt_node_id = 0
              end
              Thread.pass
              @hunt_node_id += HuntTrain
            end

            # Search robot
            # RU: Поисковый робот
            if (pool.found_ind <= pool.mass_ind) and false #OFFFFF !!!!!
              processed = MassTrain
              while (processed > 0) and (pool.found_ind <= pool.mass_ind)
                search_req = pool.mass_records[pool.found_ind]
                p '####  Search spider  [size, @found_ind, obj_id]='+[pool.mass_records.size, \
                  pool.found_ind, search_req.object_id].inspect
                if search_req and (not search_req[PandoraNet::SA_Answer])
                  req = search_req[PandoraNet::SR_Request..PandoraNet::SR_BaseId]
                  p 'search_req3='+req.inspect
                  answ = nil
                  if search_req[PandoraNet::SR_Kind]==PandoraModel::PK_BlobBody
                    sha1 = search_req[PandoraNet::SR_Request]
                    fn_fs = $window.pool.blob_exists?(sha1, @shed_models, true)
                    if fn_fs.is_a? Array
                      fn_fs[0] = PandoraUtils.relative_path(fn_fs[0])
                      answ = fn_fs
                    end
                  else
                    answ,kind = pool.search_in_local_bases(search_req[PandoraNet::SR_Request], \
                      search_req[PandoraNet::SR_Kind])
                  end
                  p 'SEARCH answ='+answ.inspect
                  if answ
                    search_req[PandoraNet::SA_Answer] = answ
                    answer_raw = PandoraUtils.rubyobj_to_pson([req, answ])
                    session = search_req[PandoraNet::SR_Session]
                    sessions = []
                    if pool.sessions.include?(session)
                      sessions << session
                    end
                    sessions.concat(pool.sessions_of_keybase(nil, \
                      search_req[PandoraNet::SR_BaseId]))
                    sessions.flatten!
                    sessions.uniq!
                    sessions.compact!
                    sessions.each do |sess|
                      if sess.active?
                        sess.add_send_segment(PandoraNet::EC_News, true, answer_raw, \
                          PandoraNet::ECC_News_Answer)
                      end
                    end
                  end
                  #p log_mes+'[to_person, to_key]='+[@to_person, @to_key].inspect
                  #if search_req and (search_req[SR_Session] != self) and (search_req[SR_BaseId] != @to_base_id)
                  processed -= 1
                else
                  processed = 0
                end
                pool.found_ind += 1
              end
            end

            # Mass record garbager
            # RU: Чистильщик массовых сообщений
            if false #!!!! (@mass_garb_offset >= MassGarbStep)
              @mass_garb_offset = 0.0
              cur_time = Time.now.to_i
              processed = MassGarbTrain
              while (processed > 0)
                if (@mass_garb_ind < pool.mass_records.size)
                  search_req = pool.mass_records[@mass_garb_ind]
                  if search_req
                    time = search_req[PandoraNet::MR_CrtTime]
                    if (not time.is_a? Integer) or (time+$search_live_time<cur_time)
                      pool.mass_records[@mass_garb_ind] = nil
                    end
                  end
                  @mass_garb_ind += 1
                  processed -= 1
                else
                  @mass_garb_ind = 0
                  processed = 0
                end
              end
              #pool.mass_records.compact!
            end
            @mass_garb_offset += @scheduler_step

            # Bases garbager
            # RU: Чистильшик баз
            if (not @base_garb_offset) \
            or ((@base_garb_offset >= CheckBaseStep) and @base_garb_kind<255) \
            or (@base_garb_offset >= CheckBasePeriod)
              #p '@base_garb_offset='+@base_garb_offset.inspect
              #p '@base_garb_kind='+@base_garb_kind.inspect
              @base_garb_kind = 0 if @base_garb_offset \
                and (@base_garb_offset >= CheckBasePeriod) and (@base_garb_kind >= 255)
              @base_garb_offset = 0.0
              train_tail = BaseGarbTrain
              while train_tail>0
                if (not @base_garb_model)
                  @base_garb_id = 0
                  while (@base_garb_kind<255) \
                  and (not @base_garb_model.is_a? PandoraModel::Panobject)
                    @base_garb_kind += 1
                    panobjectclass = PandoraModel.panobjectclass_by_kind(@base_garb_kind)
                    if panobjectclass
                      @base_garb_model = PandoraUtils.get_model(panobjectclass.ider, @shed_models)
                    end
                  end
                  if @base_garb_kind >= 255
                    if @base_garb_mode == :arch
                      @base_garb_mode = :purge
                      @base_garb_kind = 0
                    else
                      @base_garb_mode = :arch
                    end
                  end
                end

                if @base_garb_model
                  if @base_garb_mode == :arch
                    arch_time = Time.now.to_i - @base_garbage_term
                    filter = ['id>=? AND modified<? AND IFNULL(panstate,0)=0', \
                      @base_garb_id, arch_time]
                  else # :purge
                    purge_time = Time.now.to_i - @base_purge_term
                    filter = ['id>=? AND modified<? AND panstate>=?', @base_garb_id, \
                      purge_time, PandoraModel::PSF_Archive]
                  end
                  #p 'Base garbager [ider,mode,filt]: '+[@base_garb_model.ider, @base_garb_mode, filter].inspect
                  sel = @base_garb_model.select(filter, false, 'id', 'id ASC', train_tail)
                  #p 'base_garb_sel='+sel.inspect
                  if sel and (sel.size>0)
                    sel.each do |row|
                      id = row[0]
                      @base_garb_id = id
                      #p '@base_garb_id='+@base_garb_id.inspect
                      values = nil
                      if @base_garb_mode == :arch
                        # mark the record as deleted, else purge it
                        values = {:panstate=>PandoraModel::PSF_Archive}
                      end
                      @base_garb_model.update(values, nil, {:id=>id})
                    end
                    train_tail -= sel.size
                    @base_garb_id += 1
                  else
                    @base_garb_model = nil
                  end
                  Thread.pass
                else
                  train_tail = 0
                end
              end
            end
            @base_garb_offset += @scheduler_step if @base_garb_offset

            # GUI updater (list, traffic)

            # PanReg node registration
            # RU: Регистратор узлов PanReg
            if (@node_reg_offset.nil? or (@node_reg_offset >= @panreg_period))
              @node_reg_offset = 0.0
              PandoraNet.register_node_ips
            end
            @node_reg_offset += @scheduler_step if @node_reg_offset


            sleep(@scheduler_step)

            #p 'Next scheduler step'

            Thread.pass
          end
          @scheduler = nil
        end
      end
    end

    $pointoff = nil

    # Show main Gtk window
    # RU: Показать главное окно Gtk
    def initialize(*args)
      super(*args)
      $window = self
      @hunter_count = @listener_count = @fisher_count = @node_reg_offset = 0

      main_icon = nil
      begin
        main_icon = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'pandora.ico'))
      rescue Exception
      end
      if not main_icon
        main_icon = $window.render_icon(Gtk::Stock::HOME, Gtk::IconSize::LARGE_TOOLBAR)
      end
      if main_icon
        $window.icon = main_icon
        Gtk::Window.default_icon = $window.icon
      end

      @icon_factory = Gtk::IconFactory.new
      @icon_factory.add_default

      @hand_cursor = Gdk::Cursor.new(Gdk::Cursor::HAND2)
      @regular_cursor = Gdk::Cursor.new(Gdk::Cursor::XTERM)

      @accel_group = Gtk::AccelGroup.new
      $window.add_accel_group(accel_group)

      $window.register_stock(:save)

      @menubar = Gtk::MenuBar.new
      fill_menubar(menubar)

      @toolbar = Gtk::Toolbar.new
      toolbar.show_arrow = true
      toolbar.toolbar_style = Gtk::Toolbar::Style::ICONS
      fill_main_toolbar(toolbar)

      #frame = Gtk::Frame.new
      #frame.shadow_type = Gtk::SHADOW_IN
      #align = Gtk::Alignment.new(0.5, 0.5, 0, 0)
      #align.add(frame)
      #image = Gtk::Image.new
      #frame.add(image)

      @notebook = Gtk::Notebook.new
      notebook.show_border = false
      notebook.scrollable = true
      notebook.signal_connect('switch-page') do |widget, page, page_num|
        cur_page = notebook.get_nth_page(page_num)
        if $last_page and (cur_page != $last_page) \
        and ($last_page.is_a? PandoraGtk::CabinetBox)
          if $last_page.area_send and (not $last_page.area_send.destroyed?)
            $last_page.init_video_sender(false, true)
          end
          if $last_page.area_recv and (not $last_page.area_recv.destroyed?)
            $last_page.init_video_receiver(false)
          end
        end
        if cur_page.is_a? PandoraGtk::CabinetBox
          cur_page.update_state(false, cur_page)
          if cur_page.area_recv and (not cur_page.area_recv.destroyed?)
            cur_page.init_video_receiver(true, true, false)
          end
          if cur_page.area_send and (not cur_page.area_send.destroyed?)
            cur_page.init_video_sender(true, true)
          end
        end
        PandoraGtk.update_treeview_if_need(cur_page)
        $last_page = cur_page
      end

      @log_view = PandoraGtk::ExtTextView.new
      log_view.set_readonly(true)
      log_view.border_width = 0

      @log_sw = Gtk::ScrolledWindow.new(nil, nil)
      log_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      log_sw.shadow_type = Gtk::SHADOW_IN
      log_sw.add(log_view)
      log_sw.border_width = 0;
      log_sw.set_size_request(-1, 60)

      @radar_sw = RadarScrollWin.new
      radar_sw.set_size_request(0, -1)

      #note_sw = Gtk::ScrolledWindow.new(nil, nil)
      #note_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      #note_sw.border_width = 0
      #@viewport = Gtk::Viewport.new(nil, nil)
      #sw.add(viewport)

      @radar_hpaned = Gtk::HPaned.new
      #note_sw.add_with_viewport(notebook)
      #@radar_hpaned.pack1(note_sw, true, true)
      @radar_hpaned.pack1(notebook, true, true)
      @radar_hpaned.pack2(radar_sw, false, true)
      #@radar_hpaned.position = 1
      #p '****'+@radar_hpaned.allocation.width.inspect
      #@radar_hpaned.position = @radar_hpaned.max_position
      #@radar_hpaned.position = 0
      @radar_hpaned.signal_connect('notify::position') do |widget, param|
        $window.correct_fish_btn_state
      end

      @log_vpaned = Gtk::VPaned.new
      log_vpaned.border_width = 2
      log_vpaned.pack1(radar_hpaned, true, true)
      log_vpaned.pack2(log_sw, false, true)
      log_vpaned.signal_connect('notify::position') do |widget, param|
        $window.correct_log_btn_state
      end

      #@cvpaned = CaptchaHPaned.new(vpaned)
      #@cvpaned.position = cvpaned.max_position

      $statusbar = Gtk::HBox.new
      $statusbar.spacing = 1
      $statusbar.border_width = 0
      #$statusbar = Gtk::Statusbar.new
      #PandoraGtk.set_statusbar_text($statusbar, _('Base directory: ')+$pandora_base_dir)

      add_status_field(SF_Log, nil, 'Logbar', :log, false, 0) do
        do_menu_act('LogBar')
      end
      add_status_field(SF_FullScr, nil, 'Full screen', Gtk::Stock::FULLSCREEN, false, 0) do
        do_menu_act('FullScr')
      end

      path = $pandora_app_dir
      path = '..'+path[-40..-1] if path.size>40
      pathlabel = Gtk::Label.new(path)
      pathlabel.modify_font(PandoraGtk.status_font)
      pathlabel.justify = Gtk::JUSTIFY_LEFT
      pathlabel.set_padding(1, 1)
      pathlabel.set_alignment(0.0, 0.5)
      $statusbar.pack_start(pathlabel, true, true, 0)

      add_status_field(SF_Update, _('Version') + ': ' + _('Not checked'), 'Update') do
        PandoraGtk.start_updating(true)
      end
      add_status_field(SF_Lang, $lang, 'Language') do
        do_menu_act('Blob')
      end
      add_status_field(SF_Auth, _('Not logged'), 'Authorize', :auth, false) do
        do_menu_act('Authorize')          #Gtk::Stock::DIALOG_AUTHENTICATION
      end
      add_status_field(SF_Listen, '0', 'Listen', :listen, false) do
        do_menu_act('Listen')
      end
      add_status_field(SF_Hunt, '0', 'Hunting', :hunt, false) do
        do_menu_act('Hunt')
      end
      add_status_field(SF_Fisher, '0', 'Fishers', :fish) do
        do_menu_act('Fisher')
      end
      add_status_field(SF_Conn, '0', 'Sessions', :session) do
        do_menu_act('Session')
      end
      add_status_field(SF_Radar, '0', 'Radar', :radar, false) do
        do_menu_act('Radar')
      end
      add_status_field(SF_Harvest, '0', 'Files', :blob) do
        do_menu_act('Blob')
      end
      add_status_field(SF_Search, '0', 'Search', Gtk::Stock::FIND) do
        do_menu_act('Search')
      end
      resize_eb = Gtk::EventBox.new
      resize_eb.events = Gdk::Event::BUTTON_PRESS_MASK | Gdk::Event::POINTER_MOTION_MASK \
        | Gdk::Event::ENTER_NOTIFY_MASK | Gdk::Event::LEAVE_NOTIFY_MASK
      resize_eb.signal_connect('enter-notify-event') do |widget, param|
        window = widget.window
        window.cursor = Gdk::Cursor.new(Gdk::Cursor::BOTTOM_RIGHT_CORNER)
      end
      resize_eb.signal_connect('leave-notify-event') do |widget, param|
        window = widget.window
        window.cursor = nil #Gdk::Cursor.new(Gdk::Cursor::XTERM)
      end
      resize_eb.signal_connect('button-press-event') do |widget, event|
        if (event.button == 1)
          point = $window.window.pointer[1,2]
          wh = $window.window.geometry[2,2]
          $pointoff = [(wh[0]-point[0]), (wh[1]-point[1])]
          if $window.window.state == Gdk::EventWindowState::MAXIMIZED
            wbord = 6
            w, h = [(point[0]+$pointoff[0]-wbord), (point[1]+$pointoff[1]-wbord)]
            $window.move(0, 0)
            $window.set_default_size(w, h)
            $window.resize(w, h)
            $window.unmaximize
            $window.move(0, 0)
            $window.set_default_size(w, h)
            $window.resize(w, h)
          end
        end
        false
      end
      resize_eb.signal_connect('motion-notify-event') do |widget, event|
        if $pointoff
          point = $window.window.pointer[1,2]
          $window.resize((point[0]+$pointoff[0]), (point[1]+$pointoff[1]))
        end
        false
      end
      resize_eb.signal_connect('button-release-event') do |widget, event|
        if (event.button == 1) and $pointoff
          window = widget.window
          $pointoff = nil
        end
        false
      end
      $window.register_stock(:resize)
      resize_image = Gtk::Image.new(:resize, Gtk::IconSize::MENU)
      resize_image.set_padding(0, 0)
      resize_image.set_alignment(1.0, 1.0)
      resize_eb.add(resize_image)
      $statusbar.pack_start(resize_eb, false, false, 0)

      vbox = Gtk::VBox.new
      vbox.pack_start(menubar, false, false, 0)
      vbox.pack_start(toolbar, false, false, 0)
      #vbox.pack_start(cvpaned, true, true, 0)
      vbox.pack_start(log_vpaned, true, true, 0)
      stat_sw = Gtk::ScrolledWindow.new(nil, nil)
      stat_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_NEVER)
      stat_sw.border_width = 0
      iw, iy = Gtk::IconSize.lookup(Gtk::IconSize::MENU)
      stat_sw.height_request = iy+6
      #stat_sw.add_with_viewport($statusbar)
      stat_sw.add($statusbar)
      vbox.pack_start(stat_sw, false, false, 0)

      $window.add(vbox)

      update_win_icon = PandoraUtils.get_param('status_update_win_icon')
      flash_on_new = PandoraUtils.get_param('status_flash_on_new')
      flash_interval = PandoraUtils.get_param('status_flash_interval')
      play_sounds = PandoraUtils.get_param('play_sounds')
      hide_on_minimize = PandoraUtils.get_param('hide_on_minimize')
      hide_on_close = PandoraUtils.get_param('hide_on_close')
      mplayer = nil
      if PandoraUtils.os_family=='windows'
        mplayer = PandoraUtils.get_param('win_mp3_player')
      else
        mplayer = PandoraUtils.get_param('linux_mp3_player')
      end
      $mp3_player = mplayer if ((mplayer.is_a? String) and (mplayer.size>0))

      $statusicon = PandoraGtk::PandoraStatusIcon.new(update_win_icon, flash_on_new, \
        flash_interval, play_sounds, hide_on_minimize)

      $window.signal_connect('delete-event') do |*args|
        if hide_on_close
          $window.do_menu_act('Hide')
        else
          $window.do_menu_act('Quit')
        end
        true
      end

      $window.signal_connect('destroy') do |window|
        while (not $window.notebook.destroyed?) and ($window.notebook.children.count>0)
          $window.notebook.children[0].destroy if (not $window.notebook.children[0].destroyed?)
        end
        PandoraCrypto.reset_current_key
        $statusicon.visible = false if ($statusicon and (not $statusicon.destroyed?))
        $window = nil
        Gtk.main_quit
      end

      $window.signal_connect('key-press-event') do |widget, event|
        res = true
        if ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?(event.keyval) \
        and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, Gdk::Keyval::GDK_Q, \
        1738, 1770].include?(event.keyval) and event.state.control_mask?) #q, Q, й, Й
          $window.do_menu_act('Quit')
        elsif event.keyval == Gdk::Keyval::GDK_F5
          do_menu_act('Hunt')
        elsif event.state.shift_mask? \
        and (event.keyval == Gdk::Keyval::GDK_F11)
          PandoraGtk.full_screen_switch
        elsif event.state.control_mask?
          if [Gdk::Keyval::GDK_m, Gdk::Keyval::GDK_M, 1752, 1784].include?(event.keyval)
            $window.hide
          elsif ((Gdk::Keyval::GDK_0..Gdk::Keyval::GDK_9).include?(event.keyval) \
          or (event.keyval==Gdk::Keyval::GDK_Tab))
            num = $window.notebook.n_pages
            if num>0
              if (event.keyval==Gdk::Keyval::GDK_Tab)
                n = $window.notebook.page
                if n>=0
                  if event.state.shift_mask?
                    n -= 1
                  else
                    n += 1
                  end
                  if n<0
                    $window.notebook.page = num-1
                  elsif n>=num
                    $window.notebook.page = 0
                  else
                    $window.notebook.page = n
                  end
                end
              else
                n = (event.keyval - Gdk::Keyval::GDK_1)
                if (n>=0) and (n<num)
                  $window.notebook.page = n
                else
                  $window.notebook.page = num-1
                end
              end
            end
          elsif [Gdk::Keyval::GDK_h, Gdk::Keyval::GDK_H].include?(event.keyval)
            continue = (not event.state.shift_mask?)
            PandoraNet.start_or_stop_hunt(continue)
          elsif [Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(event.keyval)
            $window.do_menu_act('Close')
          elsif [Gdk::Keyval::GDK_d, Gdk::Keyval::GDK_D, 1751, 1783].include?(event.keyval)
            curpage = nil
            if $window.notebook.n_pages>0
              curpage = $window.notebook.get_nth_page($window.notebook.page)
            end
            if curpage.is_a? PandoraGtk::PanobjScrolledWindow
              res = false
            else
              res = PandoraGtk.show_panobject_list(PandoraModel::Person)
              res = (res != nil)
            end
          else
            res = false
          end
        else
          res = false
        end
        res
      end

      #$window.signal_connect('client-event') do |widget, event_client|
      #  p '[widget, event_client]='+[widget, event_client].inspect
      #end

      $window.signal_connect('window-state-event') do |widget, event_window_state|
        if (event_window_state.changed_mask == Gdk::EventWindowState::ICONIFIED) \
          and ((event_window_state.new_window_state & Gdk::EventWindowState::ICONIFIED)>0)
        then
          if notebook.page >= 0
            sw = notebook.get_nth_page(notebook.page)
            if (sw.is_a? CabinetBox) and (not sw.destroyed?)
              sw.init_video_sender(false, true) if sw.area_send and (not sw.area_send.destroyed?)
              sw.init_video_receiver(false) if sw.area_recv and (not sw.area_recv.destroyed?)
            end
          end
          if widget.visible? and widget.active? and $statusicon.hide_on_minimize
            $window.hide
            #$window.skip_taskbar_hint = true
          end
        end
      end

      PandoraGtk.get_main_params

      #$window.signal_connect('focus-out-event') do |window, event|
      #  p 'focus-out-event: ' + $window.has_toplevel_focus?.inspect
      #  false
      #end
      @do_on_start = PandoraUtils.get_param('do_on_start')
      @title_view = PandoraUtils.get_param('title_view')
      @title_view ||= TV_Name

      #$window.signal_connect('show') do |window, event|
      #  false
      #end

      @pool = PandoraNet::Pool.new($window)

      $window.set_default_size(640, 420)
      $window.maximize
      $window.show_all

      @radar_hpaned.position = @radar_hpaned.max_position
      @log_vpaned.position = @log_vpaned.max_position
      if $window.do_on_start and ($window.do_on_start > 0)
        dialog_timer = GLib::Timeout.add(400) do
          key = PandoraCrypto.current_key(false, true)
          if (($window.do_on_start & 2) != 0) and key
            PandoraNet.start_or_stop_listen(true)
          end
          if (($window.do_on_start & 4) != 0) and key and (not $hunter_thread)
            PandoraNet.start_or_stop_hunt(true, 2)
          end
          $window.do_on_start = 0
          false
        end
      end
      scheduler_step = PandoraUtils.get_param('scheduler_step')
      init_scheduler(scheduler_step)


      #------next must be after show main form ---->>>>

      $window.focus_timer = $window
      $window.signal_connect('focus-in-event') do |window, event|
        #p 'focus-in-event: ' + [$window.has_toplevel_focus?, \
        #  event, $window.visible?].inspect
        if $window.focus_timer
          $window.focus_timer = nil if ($window.focus_timer == $window)
        else
          if (PandoraUtils.os_family=='windows') and (not $window.visible?)
            $window.do_menu_act('Activate')
          end
          $window.focus_timer = GLib::Timeout.add(500) do
            if (not $window.nil?) and (not $window.destroyed?)
              #p 'read timer!!!' + $window.has_toplevel_focus?.inspect
              toplevel = ($window.has_toplevel_focus? or (PandoraUtils.os_family=='windows'))
              if toplevel and $window.visible?
                $window.notebook.children.each do |child|
                  if (child.is_a? CabinetBox) and (child.has_unread)
                    $window.notebook.page = $window.notebook.children.index(child)
                    break
                  end
                end
                curpage = $window.notebook.get_nth_page($window.notebook.page)
                if (curpage.is_a? PandoraGtk::CabinetBox) and toplevel
                  curpage.update_state(false, curpage)
                else
                  PandoraGtk.update_treeview_if_need(curpage)
                end
              end
              $window.focus_timer = nil
            end
            false
          end
        end
        false
      end

      check_update = PandoraUtils.get_param('check_update')
      if (check_update==1) or (check_update==true)
        last_check = PandoraUtils.get_param('last_check')
        last_check ||= 0
        last_update = PandoraUtils.get_param('last_update')
        last_update ||= 0
        check_interval = PandoraUtils.get_param('check_interval')
        if (not(check_interval.is_a? Numeric)) or (check_interval <= 0)
          check_interval = 1
        end
        update_period = PandoraUtils.get_param('update_period')
        if (not(update_period.is_a? Numeric)) or (update_period < 0)
          update_period = 1
        end
        time_now = Time.now.to_i
        ok_version = (time_now - last_update.to_i) < update_period*24*3600
        need_check = ((time_now - last_check.to_i) >= check_interval*24*3600)
        if ok_version
          set_status_field(SF_Update, 'Ok', need_check)
        elsif need_check
          PandoraGtk.start_updating(false)
        end
      end

      Gtk.main
    end

  end  #--MainWindow

end
