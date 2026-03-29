require %(set)
require %(options_by_example)

require_relative "lib/image_ledger"

flags = OptionsByExample.read(DATA).parse(ARGV)
names = flags.get(:names)

ledger = ImageLedger.new("data/downloaded_images.sqlite")

if flags.include_compare?
  indexed_entries = ledger.find_all_entries
  indexed_paths = indexed_entries.map { |row| row["path"].to_s }.reject(&:empty?).to_set

  roots = indexed_paths.map { |path| path.split('/').first }.uniq
  roots << "images" if roots.empty? && Dir.exist?("images")

  disk_paths = roots.flat_map { |root|
    Dir.glob("#{root}/**/*", File::FNM_DOTMATCH)
      .reject { |path| path.end_with?("/.", "/..") }
      .select { |path| File.file?(path) }
      .reject { |path| File.basename(path).start_with?(".") }
  }.uniq.to_set

  unindexed = (disk_paths - indexed_paths).to_a.sort
  missing = indexed_entries
    .reject { |row| row["status"] == "duplicate_delete" }
    .reject { |row| row["path"].to_s.empty? || File.exist?(row["path"]) }
    .uniq { |row| row["media_id"] }
    .sort_by { |row| [row["conversation_id"].to_s, row["username"].to_s, row["media_id"].to_s] }

  puts "Unindexed files: #{unindexed.length}"
  unindexed.each { |path| puts "  #{path}" }
  puts
  puts "Missing indexed files: #{missing.length}"
  missing.group_by { |row| row["conversation_id"].to_s }.each do |conversation_id, rows|
    puts "  https://x.com/i/grok?conversation=#{conversation_id}"
    rows.each do |row|
      puts "    https://ton.x.com/i/ton/data/grok-attachment/#{row["media_id"]}\t#{row["username"]}"
    end
  end

  exit
end

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

Usage: info.rb [options] [names ...]

Options:
  -c, --compare    Compare indexed paths against files on disk
