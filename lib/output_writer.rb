# frozen_string_literal: true

module ClaudeGardener
  module OutputWriter
    def write_output(name, value)
      output_file = ENV.fetch("GITHUB_OUTPUT", nil)
      if output_file
        if value.include?("\n")
          delimiter = "EOF_#{rand(1000000)}"
          File.open(output_file, "a") do |f|
            f.puts "#{name}<<#{delimiter}"
            f.puts value
            f.puts delimiter
          end
        else
          File.open(output_file, "a") { |f| f.puts "#{name}=#{value}" }
        end
      else
        puts "#{name}=#{value}"
      end
    end
  end
end
