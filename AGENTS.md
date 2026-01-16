## Coding style

Always include the # frozen_string_literal: true magic comment at the top of each ruby file.

Use `class << self` syntax for defining class methods. instead of `def self.method_name`.

All public methods should have YARD documentation. Include an empty comment line between the method description and the first YARD tag.

This project uses the standardrb style guide. Run `bundle exec standardrb --fix` to automatically fix style issues.

## Testing

Run the test suite with `bundle exec rspec`.

## Things you have learned

This list summarizes important things you have learned. When the user tells you that you have learned something new add it to this list. If the user tells you to learn something new, research it and then add it to this list. If the user tells you to forget something, remove it from this list.

- You have not learned anything yet. Replace this item with the first thing you learn.
