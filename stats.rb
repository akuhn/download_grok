require %(sqlite3)
require %(options_by_example)

flags = OptionsByExample.read(DATA).parse(ARGV)

db = SQLite3::Database.new("data/downloaded_images.sqlite")
db.results_as_hash = true

rows = db.execute(%{
  SELECT conversation_id, username, path
  FROM images
  ORDER BY conversation_id, username, path
})
rows = rows.select { |row| row["username"] == flags.get(:user) } if flags.include_user?

files = rows.select { |row| File.file?(row["path"]) }
conversations = files
  .group_by { |row| row["conversation_id"].to_s }
  .map { |conversation_id, entries|
    sizes = entries.map { |row| File.size(row["path"]) }
    users = entries.map { |row| row["username"] }.uniq.sort
    [conversation_id, users, sizes]
  }
  .sort_by { |conversation_id, users, sizes| [sizes.sum, conversation_id, users.join(",")] }

conversations.each do |conversation_id, users, sizes|
  total_size = sizes.sum
  average_size = total_size.to_f / sizes.length

  puts "https://x.com/i/grok?conversation=#{conversation_id}"
  puts "  user: #{users.join(", ")}"
  puts "  images: #{sizes.length}"
  puts "  average_size: #{format("%.2f", average_size / 1024.0)} KB"
  puts "  total_size: #{format("%.2f", total_size / 1024.0 / 1024.0)} MB"
  puts
end

all_size = files.sum { |row| File.size(row["path"]) }
puts "Total size on disk: #{format("%.2f", all_size / 1024.0 / 1024.0)} MB"

__END__
Show size stats grouped by conversation.

Usage: stats.rb [options]

Options:
  -u, --user NAME     Only include rows downloaded by NAME
