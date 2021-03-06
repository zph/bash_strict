require "bash_strict/version"
require 'strscan'

module BashStrict
  LANGUAGES_SUPPORTED = [:bash]
  SHEBANG = "#!/usr/bin/env bash"
  STRICT_SET = "set -CEeuo pipefail"
  EXT_DEBUG = "shopt -s extdebug"
  QUOTES = /['"]/
  EXT_DEBUG_REGEX = /^#{EXT_DEBUG}$/
  IFS = %Q(IFS=$'\\n\\t')
  IFS_REGEX = /^IFS=
               \$? # match in case the $'\n\t' syntax used
               #{QUOTES}
               (.*)
               #{QUOTES}
              $/xm

  PREFERRED_DECLARATION = {
    :strict => STRICT_SET,
    :shebang => SHEBANG,
    :ifs => IFS,
    :shopt => EXT_DEBUG,
  }

  EMPTY_DECLARATION = {
    :strict => [],
    :ifs => nil,
    :shopt => [],
  }

  class Parser
    class << self
      def normalize(data)
        shebang, strict, ifs, shopt = PREFERRED_DECLARATION.values_at(:shebang, :strict, :ifs, :shopt)
        comments = data[:header][:comments]
        body = data[:body]

        [shebang, comments, "", strict, ifs, shopt, "", body].flatten.join("\n") + "\n"
      end

      def parse_shopt(line)
        line.split(" ", 3).last.to_sym
      end

      SPECIAL_LINES = [
        /^#!/,
        /^#/,
        /^IFS/,
        EXT_DEBUG_REGEX,
        /^set -/,
        //,
      ]

      def special_line?(line)
        SPECIAL_LINES.find { |reg| !!line[reg] }
      end

      def call(content)
        file = {
          header: {},
          body: [],
        }

        header = {
          shebang: "",
          comments: [],
          non_comments: [],
          declarations: EMPTY_DECLARATION,
        }

        Thread.new do
          in_body = false
          s = StringScanner.new(content)

          # Read until we hit a non-comment, non-blank, non strict mode declaration
          while ! s.eos?
            # Handle the fact that IFS line includes \n that is not official line end
            if in_body
              file[:body] << s.rest.split("\n")
              file[:body].flatten!
              s.terminate
              next
            end

            line = s.scan_until(/\n/)

            if line.start_with?("IFS=$'\n")
              line += s.scan_until(/\n/)
            end

            line.chomp!

            case line
            when ""
            when /^#!/
              if header[:shebang].empty?
                header[:shebang] = line
              end
            when /^#/
              # IF next line is a special one, carry on, if not, we're into body
              if !special_line?(s.check_until(/\n/))
                file[:body] << line
                in_body = true
              else
                header[:comments] << line
              end
            when /^IFS/
              header[:declarations][:ifs] = line
            when EXT_DEBUG_REGEX
              opt = parse_shopt(line)
              if opt
                header[:declarations][:shopt] << opt
              end
            when /^set -/
              header[:declarations][:strict] << line
            else
              file[:body] << line
              in_body = true
            end
          end

          file[:header] = header
          file
        end.join

        file
      end
    end
  end

  class StrictSet
    def initialize(str)
      @raw = str
      @short_codes = []
      @long_codes = []
      parse(str)
    end

    def short_codes
      @short_codes
    end

    def long_codes
      @long_codes
    end

    def parse(str)
      short_codes = []
      long_codes = []
      s = StringScanner.new(str)

      while ! s.eos?
        word = s.scan_until(/\s+/)

        if word.nil?
          word = s.rest
          s.terminate
        end

        word.rstrip!

        case word
        when /^set/
        when /^-/
          short_codes += [word]
        when /\w+/
          long_codes += [word]
        end

        next if word.nil?
      end

      @short_codes = parse_short_codes(short_codes)
      @long_codes = parse_long_codes(long_codes)

      [@short_codes, @long_codes]
    end

    def parse_short_codes(str)
      result = str.map do |c|
        c.gsub(/[^A-Za-z]/, '')
         .each_char
         .to_a
         .map(&:to_sym)
      end.flatten
         .reject(&:empty?)
         .reject { |i| i == :o } # because this indicates longcodes
         .sort
         .uniq
    end

    def parse_long_codes(str)
      str.map(&:to_sym)
    end
  end

  class << self
    def supported?(language)
      LANGUAGES_SUPPORTED.include?(language)
    end

    def shebang(lines)
      interpreter, arg = lines[0].split(" ")
      if arg
        arg
      else
        interpreter.split("/").last
      end.to_sym
    end

    def lint(content)
      lines = to_lines(content)
      language = shebang(lines)
      return content unless supported?(language)

      content
    end

    def options_declaration?(lines)
      !lines.grep(/^set -/).empty?
    end

    def ifs?(lines)
      !!lines.join("\n").match(IFS_REGEX)
    end

    def extdebug?(lines)
      !lines.grep(EXT_DEBUG_REGEX).empty?
    end

    def first_non_comment(lines)
      lines.each_with_index do |line, index|
        if !line.start_with?("#")
          return index
        end
      end
    end

    def to_lines(content)
      lines = []
      s = StringScanner.new(content)
      while ! s.eos?
        line = s.scan_until(/\n/)

        # Handle the fact that IFS line includes \n that is not official line end
        if line.start_with?("IFS=$'\n")
          line += s.scan_until(/\n/)
        end
        line.chomp!
        lines << line

        # Handle case of missing final newline
        break if s.check_until(/\n/).nil?
      end

      lines
    end
  end
end
