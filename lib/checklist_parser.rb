# frozen_string_literal: true

module ClaudeGardener
  module ChecklistParser
    Item = Struct.new(:text, :checked, :claimed_by, :index, keyword_init: true)

    CHECKLIST_PATTERN = /^- \[([ xX])\] (.+)$/

    module_function

    def parse(body)
      return [] unless body

      items = []
      body.each_line.with_index do |line, index|
        match = line.match(CHECKLIST_PATTERN)
        next unless match

        checked = match[1] != " "
        text = match[2].strip
        claimed_by = extract_claim(text)

        items << Item.new(
          text: strip_claim(text),
          checked: checked,
          claimed_by: claimed_by,
          index: index
        )
      end
      items
    end

    def unclaimed_items(body)
      parse(body).reject { |item| item.checked || item.claimed_by }
    end

    def check_item(body, line_index:, note: nil)
      lines = body.lines
      line = lines[line_index]
      return body unless line&.match?(CHECKLIST_PATTERN)

      suffix = note ? " (#{note})" : ""
      lines[line_index] = line.sub(/^- \[[ xX]\]/, "- [x]").rstrip + suffix + "\n"
      lines.join
    end

    def claim_item(body, line_index:, pr_number:)
      lines = body.lines
      line = lines[line_index]
      return body unless line&.match?(CHECKLIST_PATTERN)

      lines[line_index] = line.rstrip + " (claimed by PR ##{pr_number})\n"
      lines.join
    end

    def add_item(body, text)
      "#{body.rstrip}\n- [ ] #{text}\n"
    end

    def extract_claim(text)
      match = text.match(/\(claimed by PR #(\d+)\)/)
      match ? match[1].to_i : nil
    end

    def strip_claim(text)
      text.sub(/\s*\(claimed by PR #\d+\)/, "").strip
    end
  end
end
