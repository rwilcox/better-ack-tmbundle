#!/usr/bin/env ruby -rcgi

class AckInProject::Search
  include AckInProject::Environment
  AckInProject::Environment.ghetto_include %w(escape), binding

  attr_accessor :plist, :current_file, :lines_matched, :files_matched, :use_mdfind
  
  def initialize(plist)
    self.plist = plist;
    self.lines_matched = self.files_matched = 0
    self.use_mdfind = false
  end
  
  def line_matched
    self.lines_matched = lines_matched + 1
  end
  
  def file_matched
    self.files_matched = files_matched + 1
  end
  
  def h(string)
    CGI.escapeHTML(string)
  end

  def section_start(file)
    self.current_file = file
    reset_stripe
    puts %Q|<tr><th colspan="2">#{current_file}<script>f();</script></th></tr>|
    puts %Q|<tbody class="matches">|
    file_matched()
  end
  
  def section_end
    if current_file
      puts %Q|<tr><td>&nbsp;</td><td>&nbsp;</td></tr>|
      puts %Q|</tbody>|
    end
    self.current_file = nil
  end
  
  def linked_content(line, content)
    href = ""
    if use_mdfind
      href = "txmt://open/?url=file://#{e_url current_file}&line=#{line}"
    else
      href = "txmt://open/?url=file://#{e_url file_in_search_directory(current_file)}&line=#{line}"
    end
    %Q|<pre><a href="#{href}">#{scrub(escape(content))}</a></pre>|
  end
  
  def content_line(line, content)
    puts %Q|<tr class="content#{stripe}"><td>#{line}<script>l();</script></td><td>#{linked_content(line, content)}</td></tr>|
    line_matched()
  end

  def context_line(line, content)
    puts %Q|<tr class="context#{stripe}"><td>#{line}</td><td>#{linked_content(line, content)}</td></tr>|
  end
  
  def context_break()
    reset_stripe
    puts %Q|<tr class="context break"><td>...</td><td>&nbsp;</td></tr>|
  end
  
  def stripe
    (@stripe = !@stripe) ? '' : ' stripe'
  end
  
  def reset_stripe
    @stripe = nil
  end
  
  def escape(content)
    CGI.escapeHTML(content)
  end

  def scrub(content)
    content.gsub(/\e\[\d+m\e\[K$/, '').
      gsub(/\e\[\d+;\d+m/, '<strong>').
      gsub(/\e\[\d+m/,'</strong>')
  end

  def prepare_search
    # TODO: bail if the search term is empty
    result = plist['result']
    
    options = %w(--group --color --flush)
    options << '-w' if result['matchWholeWords'] == 1
    options << '-i' if result['ignoreCase'] == 1
    options << '-Q' if result['literalMatch'] == 1
    options << '-C' if result['showContext'] == 1
    options << "--#{result['followSymLinks'] == 1 ? '' : 'no'}follow"
    options << "--#{result['loadAckRC'] == 1 ? '' : 'no'}env"

    options << '-G'
    options << "^(?#{folder_pattern})".inspect

    AckInProject.update_search_history result['returnArgument']
    AckInProject.update_pbfind result['returnArgument']
    if use_mdfind
      %{cd #{e_sh search_directory}; mdfind -onlyin -0 . "#{e_sh result['returnArgument']}" | xargs -0 #{e_sh ack} #{options.join(' ')} "#{e_sh result['returnArgument']}"}
      # we need -0 because we're dealing with files that could have spaces in their names. -0 says we should have NULL characters, instead of whitespace. On the other end, xargs understands that with ITS -0
      # WD-rpw 07-08-2010
    else
      %{cd #{e_sh search_directory}; #{e_sh ack} #{options.join(' ')} "#{e_sh result['returnArgument']}"}
    end
  end
  
  def folder_pattern
    @folder_pattern ||= escape_folder_pattern(get_folder_pattern)
  end
  
  def escape_folder_pattern pattern
    pattern.gsub('/', '\/')
  end
  
  def get_folder_pattern
    if tmproj_path = Dir["#{ENV['TM_PROJECT_DIRECTORY']}/*.tmproj"].first
      open(tmproj_path) do |io|
        OSX::PropertyList.load(io)["documents"][0]["regexFolderFilter"]
      end
    else
      '!.*/(\.[^/]*|CVS|_darcs|_MTN|\{arch\}|blib|.*~\.nib|.*\.(framework|app|pbproj|pbxproj|xcode(proj)?|bundle))$'
    end
  end
  
  def search
    # tell ack about potential .ackrc files in the project directory
    ENV['ACKRC'] = File.join(project_directory, '.ackrc')
    
    IO.popen(prepare_search) do |pipe|
      pipe.each do |line|
        case line
        when /^\s*$/
          section_end()
        when /^\e\[\d+;\d+m(.*)\e\[0m/
          section_start($1)
        when /^(\d+):(.*)$/
          content_line($1, $2)
        when /^(\d+)-(.*)$/
          context_line($1, $2)
        when /^--$/
          context_break
        end
        $stdout.flush
      end
      section_end()
    end
  end
end
