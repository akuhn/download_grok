#!/usr/bin/env -S bundle exec ruby

require %(set)
require %(options_by_example)

require_relative "lib/extensions"
require_relative "lib/image_ledger"

flags = OptionsByExample.read(DATA).parse(ARGV)
flags.expect_at_most_one_of :compare, :delete_conversation, :delete_image

ledger = ImageLedger.new("data/downloaded_images.sqlite")

if flags.include_delete_conversation?
  conversation_id = flags.get(:delete_conversation)
  matches = ledger.find_images_by_conversation_id(conversation_id)

  deleted_rows = ledger.delete_images_by_conversation_id(conversation_id)
  deleted_files = matches.map(&'path').count do |fname|
    File.exist?(fname) && File.delete(fname)
  end

  puts "Deleted conversation #{conversation_id}"
  puts "  #{deleted_rows} index entries deleted"
  puts "  #{deleted_files} files deleted"
  exit
end

if flags.include_delete_image?
  # Vararg flags aren't support yet, so we cheat a little bit
  names = [flags.get(:delete_image), *flags.get(:names)]

  names.each do |each|
    media_id = each[/\A\d{19}\z/] || each[/\d{19}_(\d{19})/, 1]
    raise "unknown media_id found: #{each}" unless media_id

    row = ledger.find_image_by_media_id(media_id)
    deleted_file = row && File.exist?(row["path"]) && File.delete(row["path"])
    marked_rows = ledger.mark_image_as_manual_delete_by_media_id(media_id)

    puts "Deleted image #{media_id}"
    puts "  source: #{each}"
    puts "  #{marked_rows} index entries marked as 'manual_delete'"
    puts "  #{deleted_file ? 1 : 0} files deleted"
  end

  exit
end

if flags.include_compare?
  indexed_entries = ledger.find_all_entries
  indexed_paths = indexed_entries.map(&'path').to_set

  roots = indexed_paths.map { it.split('/').first }
  roots = ["images", *roots].uniq

  disk_paths = roots.flat_map { |root|
    Dir.glob("#{root}/**/*").select { |path| File.file?(path) }
  }.to_set

  unindexed_entries = (disk_paths - indexed_paths).entries.sort
  missing = indexed_entries
    .reject { |row| %w[duplicate_delete manual_delete].include?(row["status"]) || File.exist?(row["path"]) }
    .uniq { |row| row["media_id"] }
    .sort_by { |row| row.values_at("conversation_id", "username", "media_id") }

  puts "Unindexed files: #{unindexed_entries.length}"
  unindexed_entries.each { |path| puts "  #{path}" }
  puts

  puts "Missing indexed files: #{missing.length}"
  missing.group_by { |row| row["conversation_id"].to_s }.each do |conversation_id, rows|
    puts "  https://x.com/i/grok?conversation=#{conversation_id}"
    rows.each { |row| puts "    https://ton.x.com/i/ton/data/grok-attachment/#{row["media_id"]}\t#{row["username"]}" }
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
  -c, --compare               Compare indexed paths against files on disk
  --delete-conversation ID    Delete files and delete all conversation index entries
  --delete-image ID           Delete files and mark index entries as manual_delete
