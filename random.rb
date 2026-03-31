require %(options_by_example)

require_relative "lib/extensions"

flags = OptionsByExample.read(DATA).parse(ARGV)

files = Dir.glob("images/*").select { it =~ /(jpg|png)$/ }
grouped = files.group_by { |fname| fname.split("/").last.split("_").first }
selection = grouped.values.sample(flags.get(:num)).map(&:sample)

selection.each { |fname| system("open", fname) }
puts selection

__END__
Open random files from the images folder.

Usage: random.rb [options]

Options:
  -n, --num NUM       Number of random files (default 10)
