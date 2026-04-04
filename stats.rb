#!/usr/bin/env -S bundle exec ruby

require %(sqlite3)

db = SQLite3::Database.new("data/downloaded_images.sqlite")
db.results_as_hash = true

rows = db.execute(%{
  SELECT conversation_id, path
  FROM images
  ORDER BY conversation_id, path
})

files = rows.select { |row| File.file?(row["path"]) }
conversations = files
  .group_by { |row| row["conversation_id"].to_s }
  .map { |conversation_id, entries|
    sizes = entries.map { |row| File.size(row["path"]) }
    [conversation_id, sizes]
  }
  .sort_by { |conversation_id, sizes| [sizes.sum, conversation_id] }

conversations.each do |conversation_id, sizes|
  total_size = sizes.sum
  average_size = total_size.to_f / sizes.length

  puts "https://x.com/i/grok?conversation=#{conversation_id}"
  puts "  images: #{sizes.length}"
  puts "  average_size: #{format("%.2f", average_size / 1024.0)} KB"
  puts "  total_size: #{format("%.2f", total_size / 1024.0 / 1024.0)} MB"
  puts
end

all_size = files.sum { |row| File.size(row["path"]) }
puts "Total size on disk: #{format("%.2f", all_size / 1024.0 / 1024.0)} MB"
