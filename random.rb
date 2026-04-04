#!/usr/bin/env -S bundle exec ruby

require %(options_by_example)

require_relative "lib/image_ledger"

flags = OptionsByExample.read(DATA).parse(ARGV)

files = if flags.include_user?
  ImageLedger.new("data/downloaded_images.sqlite")
    .find_all_entries
    .select { |row| row["username"] == flags.get(:user) && row["path"].start_with?("images/") }
    .map { |row| row["path"] }
else
  Dir.glob("images/*").select { it =~ /(jpg|png)$/ }
end
grouped = files.group_by { |fname| File.basename(fname).split("_").first }
selection = grouped.values.sample(flags.get(:num)).map(&:sample)

selection.each { |fname| system("open", fname) }
puts selection

__END__
Open random files from the images folder.

Usage: random.rb [options]

Options:
  -n, --num NUM       Number of random files (default 10)
  -u, --user NAME     Only pick conversations downloaded by NAME
