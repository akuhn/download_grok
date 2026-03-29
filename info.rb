require %(options_by_example)

require_relative "lib/image_ledger"

flags = OptionsByExample.read(DATA).parse(ARGV)
names = flags.get(:names)

ledger = ImageLedger.new("data/downloaded_images.sqlite")
matches = names.flat_map { |name| ledger.find_images_by_name(name) }
  .uniq { |row| row["media_id"] }
  .sort_by { |row| row["path"] }

matches.each do |row|
  media_id = row["media_id"]
  conversation_id = row["conversation_id"]
  puts "path: #{row["path"]}"
  puts "  username: #{row["username"]}"
  puts "  conversation_id: #{conversation_id}"
  puts "  media_id: #{media_id}"
  puts "  canonical_media_id: #{row["canonical_media_id"]}" if row["canonical_media_id"]
  puts "  source_url: https://ton.x.com/i/ton/data/grok-attachment/#{media_id}"
  puts "  conversation_url: https://x.com/i/grok?conversation=#{conversation_id}"
  puts "  status: #{row["status"]}"
  puts
end

puts "Found #{matches.length} match#{'es' if matches.length != 1}"

__END__
Show metadata about downloaded images.

Usage: info.rb names ...
