require 'test_helper'


describe BashStrict::StrictSet do
  i_suck_and_my_tests_are_order_dependent!
  include BashStrict
  before do
    @short_e = "set -e"
    @short_eu = "set -eu"
    @long_opipe = "set -o pipefail"
    @long_complete = BashStrict::STRICT_SET
  end

  describe "shortcodes" do
    it "handles -e" do
      actual = BashStrict::StrictSet.new(@short_e).short_codes
      assert_equal [:e], actual
    end

    it "handles -eu" do
      actual = BashStrict::StrictSet.new(@short_eu).short_codes
      assert_equal [:e, :u], actual
    end

    it "handles -o pipefail" do
      actual = BashStrict::StrictSet.new(@long_opipe).long_codes
      assert_equal [:pipefail], actual
    end

    it "handles #{@long_complete}" do
      ss = BashStrict::StrictSet.new(@long_complete)
      assert_equal [:pipefail], ss.long_codes
      assert_equal [:C, :E, :e, :u], ss.short_codes
    end
  end
end

describe BashStrict do
  i_suck_and_my_tests_are_order_dependent!

  before do
    @bash_with_declarations = BashStrict.to_lines(<<EOF)
#!/usr/bin/env bash
set -CEeou pipefail
IFS=$'\n\t'
shopt -s extdebug

echo "hello"
EOF

    @bash_with_declarations_and_comment =  BashStrict.to_lines(<<EOF)
#!/usr/bin/env bash
#
# Usage: ....
# Commandline arguments
# Credit:
#
set -CEeou pipefail
IFS=$'\n\t'
shopt -s extdebug
.
.


echo "hello"
EOF

    @bash_file = <<EOF
#!/usr/bin/env bash
IFS=$'\n\t'
echo "hello"
EOF


    @bash_without_declarations = BashStrict.to_lines(<<EOF)
#!/usr/bin/env bash

echo "hello"
EOF

  end
  it "Version is present" do
    ::BashStrict::VERSION.wont_be_nil
  end

  it "leaves ruby files unaltered" do
    content = <<EOF
#!/usr/bin/env ruby

puts "hello"
EOF
    assert_equal content, BashStrict.lint(content)
  end

  it "doesn't " do
    content = <<EOF
#!/usr/bin/env bash

set -CEeuo pipefail
IFS=$'\n\t'
shopt -s extdebug

# Setup ruby dependencies
bundle install

# Setup Node.js
yarn
EOF

    int = BashStrict::Parser.call(content)
    actual = BashStrict::Parser.normalize(int)
    assert_equal(content, actual)
  end

  #it "alters bash files" do
  #  content = <<EOF
##!/usr/bin/env bash

#echo "hello"
#EOF
  #  refute_equal BashStrict.lint(content), content
  #end

  describe "supported?" do
    it "bash is supported" do
      assert_equal true, BashStrict.supported?(:bash)
    end
    it "ruby is not supported" do
      assert_equal false, BashStrict.supported?(:ruby)
    end
  end

  describe "shebang" do
    it "extracts simple bash" do
      content = ["#!/bin/bash"]
      assert_equal :bash, BashStrict.shebang(content)
    end

    it "extracts advanced bash" do
      content = ["#!/usr/bin/env bash"]
      assert_equal :bash, BashStrict.shebang(content)
    end

    it "extracts simple ruby" do
      content = ["#!/bin/ruby"]
      assert_equal :ruby, BashStrict.shebang(content)
    end
  end

  describe "finds `set` declaration" do
    it "for basic scenario at top of file" do
      assert_equal true, BashStrict.options_declaration?(@bash_with_declarations)
    end

    it "for basic scenario where absent" do
      assert_equal false, BashStrict.options_declaration?(@bash_without_declarations)
    end
  end

  describe "finds `IFS` declaration" do
    it "for basic scenario at top of file" do
      assert_equal true, BashStrict.ifs?(@bash_with_declarations)
    end

    it "for basic scenario where absent" do
      assert_equal false, BashStrict.ifs?(@bash_without_declarations)
    end

  end

  describe "finds extended debug statement" do
    it "is present" do
      assert_equal true, BashStrict.extdebug?(@bash_with_declarations)
    end
  end

  describe "first non comment line index" do
    it "finds index in simple scenario" do
      assert_equal 1, BashStrict.first_non_comment(@bash_with_declarations)
    end

    it "finds index in advanced scenario" do
      assert_equal 6, BashStrict.first_non_comment(@bash_with_declarations_and_comment)
    end
  end

  describe "split to lines" do
    it "handles IFS and embedded newline gracefully" do
      header = ["#!/usr/bin/env bash", "IFS=$'\n\t'", 'echo "hello"']
      assert_equal header, BashStrict.to_lines(@bash_file)
    end
  end

  describe "parses complex file" do
    it "correctly" do
      e = {:header=> {
        :shebang=>"#!/usr/bin/env bash",
        :comments=>["#", "# Usage: ....", "# Commandline arguments", "# Credit:", "#"],
        :non_comments=>[],
        :declarations=> {
          :strict=>["set -CEeou pipefail"],
          :ifs=>"IFS=$'\n\t'",
          :shopt=>[:extdebug]}
      },
      :body=>[".", ".", "", "", "echo \"hello\""]}
      actual = BashStrict::Parser.call(@bash_with_declarations_and_comment.join("\n"))
      assert_equal(e, actual)
    end

    it "recombines file without changes when starts perfect ;)" do
      expected = <<EOF
#!/usr/bin/env bash

set -CEeuo pipefail
IFS=$'\\n\\t'
shopt -s extdebug

echo "hello"
EOF

      int = BashStrict::Parser.call(expected)
      actual = BashStrict::Parser.normalize(int)
      assert_equal(expected, actual)
    end

    it "recombines complex that start well ;)" do
      expected = <<EOF
#!/usr/bin/env bash
# So many comments explaining usage

set -CEeuo pipefail
IFS=$'\\n\\t'
shopt -s extdebug

echo "hello"
EOF

      int = BashStrict::Parser.call(expected)
      actual = BashStrict::Parser.normalize(int)
      assert_equal(expected, actual)
    end

    it "recombines complex file with more perfection ;)" do
      original = <<EOF
#!/usr/bin/env bash
set -CEeuo pipefail
shopt -s extdebug
IFS=$'\n\t'
# So many comments explaining usage
# AAAAAAAAAA

echo "hello"
shopt -s extdebug
  echo "indentations"
printf "all the things"
EOF

      desired = <<EOF
#!/usr/bin/env bash
# So many comments explaining usage
# AAAAAAAAAA

set -CEeuo pipefail
IFS=$'\\n\\t'
shopt -s extdebug

echo "hello"
shopt -s extdebug
  echo "indentations"
printf "all the things"
EOF

      int = BashStrict::Parser.call(original)
      actual = BashStrict::Parser.normalize(int)
      assert_equal(desired, actual)
    end
  end
end
