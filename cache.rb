require "sqlite3"

class Cache
  def initialize(path)
    @db = SQLite3::Database.new(path)

    @db.execute %{
      CREATE TABLE IF NOT EXISTS cache (
        key TEXT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        content BLOB
      )
    }
  end

  def fetch(key)
    row = @db.get_first_row(
      "SELECT content FROM cache WHERE key = ? ORDER BY timestamp DESC LIMIT 1",
      key
    )

    return row[0] if row

    raise "no block given" unless block_given?

    content = yield

    @db.execute(
      "INSERT INTO cache (key, content) VALUES (?, ?)",
      [key, content]
    )

    content
  end
end